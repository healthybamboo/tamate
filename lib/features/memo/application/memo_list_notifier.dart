import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/clock/clock.dart';
import '../../../core/notifications/notification_service.dart';
import '../data/memo_repository.dart';
import '../domain/memo.dart';
import '../domain/memo_lock_state.dart';
import '../domain/unlock_policy.dart';
import '../domain/unlock_rule.dart';

/// メモ一覧の状態を保持し、CRUD と解錠の操作を提供する。
class MemoListNotifier extends AsyncNotifier<List<Memo>> {
  static const Uuid _uuid = Uuid();

  MemoRepository get _repository => ref.read(memoRepositoryProvider);

  NotificationService get _notifications =>
      ref.read(notificationServiceProvider);

  DateTime get _now => ref.read(clockProvider).now();

  @override
  Future<List<Memo>> build() async {
    final memos = await _repository.fetchAll();
    // 前回アプリが落ちたときに進行中だった待機は、そのぶんを捨てて止める。
    // 落ちている間は待っていないので、経過に入れてはいけない。
    return _sorted([for (final memo in memos) memo.dropRunningWait()]);
  }

  /// 保存内容を読み直す。
  ///
  /// アプリ復帰時に呼ぶ。閲覧可能時間が過ぎたメモの待機状態はここで片付ける。
  Future<void> refresh() async {
    final stored = await _repository.fetchAll();
    final cleaned = _withRelockedCleared(stored, _now);
    state = AsyncData(_sorted(cleaned));
    if (!_sameMemos(stored, cleaned)) {
      await _repository.saveAll(cleaned);
    }
  }

  Future<void> add({
    required String title,
    required String body,
    UnlockRule unlockRule = UnlockRule.fallback,
  }) async {
    final now = _now;
    final memo = Memo(
      id: _uuid.v4(),
      title: title,
      body: body,
      createdAt: now,
      updatedAt: now,
      unlockRule: unlockRule,
    );
    await _mutate((memos) => [...memos, memo]);
  }

  /// 本文を書き換える。解錠中でなければ何もせず false を返す。
  Future<bool> edit({
    required String id,
    required String title,
    required String body,
  }) async {
    final memo = _find(id);
    if (memo == null || !memo.lockStateAt(_now).canRead) {
      return false;
    }

    await _mutate(
      (memos) => memos
          .map(
            (e) => e.id == id
                ? e.copyWith(title: title, body: body, updatedAt: _now)
                : e,
          )
          .toList(),
    );
    return true;
  }

  Future<void> delete(String id) async {
    await _notifications.cancelUnlock(id);
    await _mutate((memos) => memos.where((memo) => memo.id != id).toList());
  }

  /// 待機を始める。解錠予定時刻が分かるなら通知も予約する。
  Future<void> startWaiting(
    String id, {
    required UnlockNotificationContent notification,
  }) async {
    final now = _now;
    await _mutate(
      (memos) =>
          memos.map((e) => e.id == id ? e.startWaiting(now) : e).toList(),
    );

    // 待つメモだけが通知の対象。問いに答えるだけのメモで許可を求めても意味がない。
    if (_find(id)?.unlockRule.expectedWait != null) {
      await _notifications.requestPermission();
      await _scheduleUnlock(id, notification);
    }
  }

  /// 待機の計測を再開する。待機画面に戻ってきたときに呼ぶ。
  Future<void> resumeWaiting(
    String id, {
    required UnlockNotificationContent notification,
  }) async {
    final now = _now;
    final memo = _find(id);
    if (memo?.wait == null || (memo!.wait!.isRunning)) {
      return;
    }

    await _mutate(
      (memos) =>
          memos.map((e) => e.id == id ? e.resumeWaiting(now) : e).toList(),
    );
    await _scheduleUnlock(id, notification);
  }

  /// 待機の計測を止める。待機画面を離れたときに呼ぶ。
  ///
  /// 経過は残るので、戻ってくれば続きから進む。画面が捨てられる途中でも呼ばれるので、
  /// Provider から引くものは最初の await より前に済ませておく。
  Future<void> pauseWaiting(String id) async {
    final now = _now;
    final memo = _find(id);
    if (memo?.wait?.isRunning != true) {
      return;
    }
    final notifications = _notifications;

    await _mutate(
      (memos) =>
          memos.map((e) => e.id == id ? e.pauseWaiting(now) : e).toList(),
    );
    await notifications.cancelUnlock(id);
  }

  /// 進んでいる待機の解錠予定時刻に通知を予約する。
  Future<void> _scheduleUnlock(
    String id,
    UnlockNotificationContent notification,
  ) async {
    final unlockAt = _find(id)?.scheduledUnlockAt(_now);
    if (unlockAt == null) {
      return;
    }
    await _notifications.scheduleUnlock(
      memoId: id,
      unlockAt: unlockAt,
      content: notification,
    );
  }

  /// 待機をやめてロック中に戻す。計測はリセットされる。
  Future<void> cancelWaiting(String id) async {
    await _notifications.cancelUnlock(id);
    await _mutate(
      (memos) => memos.map((e) => e.id == id ? e.cancelWaiting() : e).toList(),
    );
  }

  /// 問いにすべて「はい」で答えたときに呼ぶ。解錠して記録を残す。
  Future<void> acceptAnswers(String id) async {
    final now = _now;
    final memo = _find(id);
    if (memo == null || memo.lockStateAt(now) is! MemoAwaitingAnswers) {
      return;
    }

    await _notifications.cancelUnlock(id);
    await _mutate(
      (memos) =>
          memos.map((e) => e.id == id ? e.markUnlocked(now) : e).toList(),
    );
  }

  /// 問いに「いいえ」と答えたときに呼ぶ。開かずにロック中へ戻す。
  ///
  /// 待機の経過も捨てる。答えを撤回して押し直す余地を残さないため。
  Future<void> declineAnswers(String id) async {
    final now = _now;
    final memo = _find(id);
    if (memo == null || memo.lockStateAt(now) is! MemoAwaitingAnswers) {
      return;
    }

    await _notifications.cancelUnlock(id);
    await _mutate(
      (memos) => memos.map((e) => e.id == id ? e.decline(now) : e).toList(),
    );
  }

  /// 問いを差し替える。解錠中のメモだけが対象。
  Future<bool> editQuestions(String id, List<String> questions) async {
    final memo = _find(id);
    if (memo == null || !memo.lockStateAt(_now).canRead) {
      return false;
    }

    await _mutate(
      (memos) => memos
          .map((e) => e.id == id ? e.withQuestions(questions) : e)
          .toList(),
    );
    return true;
  }

  /// 待機時間を1段階のばす。いちばん長いものなら何もせず null を返す。
  ///
  /// 作成後に待機時間を変えられるのは、開封回数に応じた提案からのこの経路だけ。
  Future<Duration?> extendWait(String id) async {
    final memo = _find(id);
    final current = memo?.unlockRule.expectedWait;
    if (memo == null || current == null) {
      return null;
    }
    final next = UnlockPolicy.nextWaitOption(current);
    if (next == null) {
      return null;
    }

    await _mutate(
      (memos) =>
          memos.map((e) => e.id == id ? e.withWaitDuration(next) : e).toList(),
    );
    return next;
  }

  /// 解錠されたことを記録する。閲覧可能時間の起点になり、開封の履歴にも残る。
  Future<void> settleUnlock(String id) async {
    final now = _now;
    final memo = _find(id);
    if (memo == null || memo.unlockedAt != null) {
      return;
    }
    if (!memo.lockStateAt(now).canRead) {
      return;
    }

    await _notifications.cancelUnlock(id);
    await _mutate(
      (memos) =>
          memos.map((e) => e.id == id ? e.markUnlocked(now) : e).toList(),
    );
  }

  Memo? _find(String id) {
    for (final memo in state.valueOrNull ?? const <Memo>[]) {
      if (memo.id == id) {
        return memo;
      }
    }
    return null;
  }

  /// 現在の一覧に [transform] を適用し、永続化まで行う。
  Future<void> _mutate(
    List<Memo> Function(List<Memo> current) transform,
  ) async {
    final repository = _repository;
    final current = state.valueOrNull ?? const <Memo>[];
    final next = _sorted(transform(current));
    state = AsyncData(next);
    await repository.saveAll(next);
  }

  /// 再ロックされたメモの待機状態を落とす。
  ///
  /// 状態は時刻から導出しているので消さなくても表示は正しいが、
  /// 意味を失った待機開始時刻を残しておく理由もないので片付ける。
  List<Memo> _withRelockedCleared(List<Memo> memos, DateTime now) => memos
      .map((memo) => _isRelocked(memo, now) ? memo.cancelWaiting() : memo)
      .toList();

  /// 解錠されたあと、閲覧可能時間まで過ぎたか。待機中は false。
  bool _isRelocked(Memo memo, DateTime now) =>
      memo.unlockedAt != null && !memo.lockStateAt(now).canRead;

  bool _sameMemos(List<Memo> a, List<Memo> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  /// 更新日時の新しい順。
  List<Memo> _sorted(List<Memo> memos) =>
      [...memos]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}

final memoListProvider =
    AsyncNotifierProvider<MemoListNotifier, List<Memo>>(MemoListNotifier.new);

/// 指定 ID のメモ。存在しなければ null。
final memoProvider = Provider.family<Memo?, String>((ref, id) {
  final memos = ref.watch(memoListProvider).valueOrNull;
  if (memos == null) {
    return null;
  }
  for (final memo in memos) {
    if (memo.id == id) {
      return memo;
    }
  }
  return null;
});
