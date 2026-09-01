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
    return _sorted(memos);
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

    final unlockAt = _find(id)?.scheduledUnlockAt;
    if (unlockAt == null) {
      return;
    }
    await _notifications.requestPermission();
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

  /// 解錠コードを入力する。正しければ解錠して true を返す。
  ///
  /// 入力の失敗に回数制限は設けない。防ぎたいのは総当たりではなく、
  /// 「覚えているつもりだった」という記憶の方なので。
  Future<bool> submitPassCode(String id, String input) async {
    final now = _now;
    final memo = _find(id);
    if (memo == null || memo.lockStateAt(now) is! MemoAwaitingPassCode) {
      return false;
    }
    if (!memo.acceptsPassCode(input)) {
      return false;
    }

    await _mutate(
      (memos) =>
          memos.map((e) => e.id == id ? e.markUnlocked(now) : e).toList(),
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

  /// 解錠されたことを記録する。閲覧可能時間の起点になる。
  ///
  /// 解錠時刻が計算できるルールでは記録しなくても状態は導出できるが、
  /// 計算できないルール（パズルなど）ではここで残した時刻が起点になる。
  Future<void> settleUnlock(String id) async {
    final now = _now;
    final memo = _find(id);
    final startedAt = memo?.waitStartedAt;
    if (memo == null || startedAt == null || memo.unlockedAt != null) {
      return;
    }
    if (!memo.lockStateAt(now).canRead) {
      return;
    }

    final unlockedAt = memo.unlockRule.unlockAt(startedAt) ?? now;
    await _mutate(
      (memos) => memos
          .map((e) => e.id == id ? e.markUnlocked(unlockedAt) : e)
          .toList(),
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
    final current = state.valueOrNull ?? const <Memo>[];
    final next = _sorted(transform(current));
    state = AsyncData(next);
    await _repository.saveAll(next);
  }

  /// 再ロックされたメモの待機状態を落とす。
  ///
  /// 状態は時刻から導出しているので消さなくても表示は正しいが、
  /// 意味を失った待機開始時刻を残しておく理由もないので片付ける。
  List<Memo> _withRelockedCleared(List<Memo> memos, DateTime now) => memos
      .map((memo) => _isRelocked(memo, now) ? memo.cancelWaiting() : memo)
      .toList();

  /// 解錠されたあと、閲覧可能時間まで過ぎたか。待機中は false。
  bool _isRelocked(Memo memo, DateTime now) {
    final startedAt = memo.waitStartedAt;
    if (startedAt == null) {
      return false;
    }
    if (memo.unlockedAt != null) {
      // 解錠は成立済み。読める時間が残っているかどうかだけの問題。
      return !memo.lockStateAt(now).canRead;
    }
    final progress = memo.unlockRule.progressAt(startedAt: startedAt, now: now);
    return progress is UnlockSatisfied && !memo.lockStateAt(now).canRead;
  }

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
