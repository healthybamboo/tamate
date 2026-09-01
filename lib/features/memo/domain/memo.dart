import 'package:meta/meta.dart';

import 'memo_lock_state.dart';
import 'memo_wait.dart';
import 'unlock_policy.dart';
import 'unlock_rule.dart';

/// メモ1件を表すドメインモデル。
///
/// 解錠状態そのものは持たず、[unlockRule] と [waitStartedAt] と現在時刻から
/// [lockStateAt] で導出する。アプリを閉じている間も時間は進むため、
/// 「今どうなっているか」を保存しない方が破綻しない。
@immutable
class Memo {
  const Memo({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.unlockRule = UnlockRule.fallback,
    this.wait,
    this.unlockedAt,
    this.openedAt = const [],
    this.declinedAt = const [],
  });

  /// 保存データからメモを復元する。
  ///
  /// 解錠まわりのフィールドは後から足したものなので、無くても読めるようにしてある。
  factory Memo.fromJson(Map<String, dynamic> json) {
    final rule = json['unlockRule'];
    final wait = json['wait'];
    final unlockedAt = json['unlockedAt'];

    return Memo(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      createdAt: _parseDate(json['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updatedAt']) ?? DateTime.now(),
      unlockRule: rule is Map<String, dynamic>
          ? UnlockRule.fromJson(rule)
          : UnlockRule.fallback,
      wait: wait is Map<String, dynamic> ? MemoWait.fromJson(wait) : null,
      unlockedAt: _parseDate(unlockedAt),
      openedAt: _parseDates(json['openedAt']),
      declinedAt: _parseDates(json['declinedAt']),
    );
  }

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// このメモの解錠条件。
  final UnlockRule unlockRule;

  /// 待機。null なら待機を始めていない。
  ///
  /// 続くのは待機画面を見ている間だけで、離れれば捨てる。詳細は `docs/spec.md` を参照。
  final MemoWait? wait;

  /// 本文が読める状態になった時刻の履歴。古い順。
  ///
  /// 閲覧可能時間の内側で画面を出入りしても増えない。再ロックされたあとに
  /// もう一度開けば1件増える。
  final List<DateTime> openedAt;

  /// これまでに開いた回数。
  int get openCount => openedAt.length;

  /// 問いに「いいえ」と答えて引き返した時刻の履歴。古い順。
  final List<DateTime> declinedAt;

  /// これまでに引き返した回数。
  int get declineCount => declinedAt.length;

  /// 解錠を検知した時刻。閲覧可能時間の起点。
  ///
  /// 解錠時刻が事前に分かるルールでは [UnlockRule.unlockAt] から導出できるため、
  /// 実際に使うのは解錠時刻を計算できないルールの場合。
  final DateTime? unlockedAt;

  /// [now] 時点での解錠状態。
  MemoLockState lockStateAt(DateTime now) {
    final openedAt = unlockedAt;
    if (openedAt != null) {
      // 解錠が成立している。あとは閲覧可能時間が残っているかどうか。
      return _readableStateAt(openedAt: openedAt, now: now);
    }

    final current = wait;
    if (current == null) {
      return const MemoLocked();
    }

    switch (unlockRule.progressFor(current.elapsedAt(now))) {
      case UnlockPending(:final remaining):
        return MemoWaiting(remaining: remaining);
      case UnlockNeedsAnswers(:final questions):
        return MemoAwaitingAnswers(questions: questions);
      case UnlockSatisfied():
        // 待機が終わった瞬間は画面を見ているはずなので、そのまま解錠にする。
        return _readableStateAt(openedAt: unlockedAt ?? now, now: now);
    }
  }

  /// [openedAt] に解錠したメモの、[now] 時点の状態。
  MemoLockState _readableStateAt({
    required DateTime openedAt,
    required DateTime now,
  }) {
    final relocksAt = openedAt.add(UnlockPolicy.openWindow);
    final remaining = relocksAt.difference(now);
    if (remaining <= Duration.zero) {
      return const MemoLocked();
    }
    return MemoUnlocked(remaining: remaining, relocksAt: relocksAt);
  }

  /// [now] から待機を始めた状態。前回の解錠の記録は捨てる。
  Memo startWaiting(DateTime now) => Memo(
        id: id,
        title: title,
        body: body,
        createdAt: createdAt,
        updatedAt: updatedAt,
        unlockRule: unlockRule,
        wait: MemoWait(now),
        openedAt: openedAt,
        declinedAt: declinedAt,
      );

  /// 待機をやめてロック中に戻した状態。経過も解錠の記録も捨てる。
  Memo cancelWaiting() => Memo(
        id: id,
        title: title,
        body: body,
        createdAt: createdAt,
        updatedAt: updatedAt,
        unlockRule: unlockRule,
        openedAt: openedAt,
        declinedAt: declinedAt,
      );

  /// 問いに「いいえ」と答えて引き返した状態。
  ///
  /// 待機の経過も捨てる。答えを撤回して押し直す余地を残さないため。
  Memo decline(DateTime at) => Memo(
        id: id,
        title: title,
        body: body,
        createdAt: createdAt,
        updatedAt: updatedAt,
        unlockRule: unlockRule,
        openedAt: openedAt,
        declinedAt: [...declinedAt, at],
      );

  /// 待機だけを捨てた状態。解錠の記録は残す。
  ///
  /// アプリを起動し直したときに使う。閉じている間は待っていないが、
  /// 解錠して読めている時間まで取り上げる理由はない。
  Memo dropWait() => wait == null
      ? this
      : Memo(
          id: id,
          title: title,
          body: body,
          createdAt: createdAt,
          updatedAt: updatedAt,
          unlockRule: unlockRule,
          unlockedAt: unlockedAt,
          openedAt: openedAt,
          declinedAt: declinedAt,
        );

  /// 解錠のしかたを差し替えた状態。解錠中のメモだけが対象。
  Memo withUnlockRule(UnlockRule rule) => Memo(
        id: id,
        title: title,
        body: body,
        createdAt: createdAt,
        updatedAt: updatedAt,
        unlockRule: rule,
        wait: wait,
        unlockedAt: unlockedAt,
        openedAt: openedAt,
        declinedAt: declinedAt,
      );

  /// 解錠を検知した時刻を記録した状態。開封の履歴にも1件残す。
  ///
  /// 待機の経過はここで役目を終えるので捨てる。
  Memo markUnlocked(DateTime at) => Memo(
        id: id,
        title: title,
        body: body,
        createdAt: createdAt,
        updatedAt: updatedAt,
        unlockRule: unlockRule,
        unlockedAt: at,
        openedAt: [...openedAt, at],
        declinedAt: declinedAt,
      );

  /// 待機時間を [duration] に差し替えた状態。
  Memo withWaitDuration(Duration duration) => Memo(
        id: id,
        title: title,
        body: body,
        createdAt: createdAt,
        updatedAt: updatedAt,
        unlockRule: unlockRule.withWaitDuration(duration),
        wait: wait,
        unlockedAt: unlockedAt,
        openedAt: openedAt,
        declinedAt: declinedAt,
      );

  /// 本文まわりだけを書き換えた状態。解錠の状態は引き継ぐ。
  Memo copyWith({
    String? title,
    String? body,
    DateTime? updatedAt,
  }) =>
      Memo(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        unlockRule: unlockRule,
        wait: wait,
        unlockedAt: unlockedAt,
        openedAt: openedAt,
        declinedAt: declinedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'unlockRule': unlockRule.toJson(),
        'wait': wait?.toJson(),
        'unlockedAt': unlockedAt?.toUtc().toIso8601String(),
        'openedAt': [
          for (final at in openedAt) at.toUtc().toIso8601String(),
        ],
        'declinedAt': [
          for (final at in declinedAt) at.toUtc().toIso8601String(),
        ],
      };

  /// ISO8601 文字列の配列を [DateTime] の並びにする。読めない要素は捨てる。
  static List<DateTime> _parseDates(Object? value) {
    if (value is! List) {
      return const [];
    }
    return [
      for (final item in value)
        if (_parseDate(item) case final date?) date,
    ];
  }

  /// ISO8601 文字列を [DateTime] にする。読めない値は null。
  static DateTime? _parseDate(Object? value) {
    if (value is! String) {
      return null;
    }
    return DateTime.tryParse(value)?.toLocal();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Memo &&
          other.id == id &&
          other.title == title &&
          other.body == body &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          other.unlockRule == unlockRule &&
          other.wait == wait &&
          other.unlockedAt == unlockedAt &&
          _sameDates(other.openedAt, openedAt) &&
          _sameDates(other.declinedAt, declinedAt);

  static bool _sameDates(List<DateTime> a, List<DateTime> b) {
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

  @override
  int get hashCode => Object.hash(
        id,
        title,
        body,
        createdAt,
        updatedAt,
        unlockRule,
        wait,
        unlockedAt,
        Object.hashAll(openedAt),
        Object.hashAll(declinedAt),
      );
}
