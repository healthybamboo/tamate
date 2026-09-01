import 'package:meta/meta.dart';

import 'memo_lock_state.dart';
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
    this.waitStartedAt,
    this.unlockedAt,
    this.openedAt = const [],
  });

  /// 保存データからメモを復元する。
  ///
  /// 解錠まわりのフィールドは後から足したものなので、無くても読めるようにしてある。
  factory Memo.fromJson(Map<String, dynamic> json) {
    final rule = json['unlockRule'];
    final waitStartedAt = json['waitStartedAt'];
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
      waitStartedAt: _parseDate(waitStartedAt),
      unlockedAt: _parseDate(unlockedAt),
      openedAt: _parseDates(json['openedAt']),
    );
  }

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// このメモの解錠条件。
  final UnlockRule unlockRule;

  /// 開こうとした時刻。null なら待機を始めていない。
  final DateTime? waitStartedAt;

  /// 本文が読める状態になった時刻の履歴。古い順。
  ///
  /// 閲覧可能時間の内側で画面を出入りしても増えない。再ロックされたあとに
  /// もう一度開けば1件増える。
  final List<DateTime> openedAt;

  /// これまでに開いた回数。
  int get openCount => openedAt.length;

  /// 解錠を検知した時刻。閲覧可能時間の起点。
  ///
  /// 解錠時刻が事前に分かるルールでは [UnlockRule.unlockAt] から導出できるため、
  /// 実際に使うのは解錠時刻を計算できないルールの場合。
  final DateTime? unlockedAt;

  /// 解錠される予定の時刻。待機していない、または計算できないルールなら null。
  DateTime? get scheduledUnlockAt {
    final startedAt = waitStartedAt;
    return startedAt == null ? null : unlockRule.unlockAt(startedAt);
  }

  /// [now] 時点での解錠状態。
  MemoLockState lockStateAt(DateTime now) {
    final openedAt = unlockedAt;
    if (openedAt != null) {
      // 解錠が成立している。あとは閲覧可能時間が残っているかどうか。
      return _readableStateAt(openedAt: openedAt, now: now);
    }

    final startedAt = waitStartedAt;
    if (startedAt == null) {
      return const MemoLocked();
    }

    switch (unlockRule.progressAt(startedAt: startedAt, now: now)) {
      case UnlockPending(:final remaining):
        return MemoWaiting(
          remaining: remaining,
          unlockAt: unlockRule.unlockAt(startedAt),
        );
      case UnlockSatisfied():
        // 解錠時刻が計算できるルールは、記録が無くても状態を導出できる。
        return _readableStateAt(
          openedAt: unlockRule.unlockAt(startedAt) ?? now,
          now: now,
        );
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

  /// [now] に開こうとした状態。前回の解錠の記録は捨てる。
  Memo startWaiting(DateTime now) => Memo(
        id: id,
        title: title,
        body: body,
        createdAt: createdAt,
        updatedAt: updatedAt,
        unlockRule: unlockRule,
        waitStartedAt: now,
        openedAt: openedAt,
      );

  /// 待機をやめてロック中に戻した状態。
  Memo cancelWaiting() => Memo(
        id: id,
        title: title,
        body: body,
        createdAt: createdAt,
        updatedAt: updatedAt,
        unlockRule: unlockRule,
        openedAt: openedAt,
      );

  /// 解錠を検知した時刻を記録した状態。開封の履歴にも1件残す。
  Memo markUnlocked(DateTime at) => Memo(
        id: id,
        title: title,
        body: body,
        createdAt: createdAt,
        updatedAt: updatedAt,
        unlockRule: unlockRule,
        waitStartedAt: waitStartedAt,
        unlockedAt: at,
        openedAt: [...openedAt, at],
      );

  /// 待機時間を [duration] に差し替えた状態。
  ///
  /// 作成後に待機時間を変えられるのは、開封回数に応じた提案から伸ばすときだけ。
  Memo withWaitDuration(Duration duration) => Memo(
        id: id,
        title: title,
        body: body,
        createdAt: createdAt,
        updatedAt: updatedAt,
        unlockRule: unlockRule.withWaitDuration(duration),
        waitStartedAt: waitStartedAt,
        unlockedAt: unlockedAt,
        openedAt: openedAt,
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
        waitStartedAt: waitStartedAt,
        unlockedAt: unlockedAt,
        openedAt: openedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'unlockRule': unlockRule.toJson(),
        'waitStartedAt': waitStartedAt?.toUtc().toIso8601String(),
        'unlockedAt': unlockedAt?.toUtc().toIso8601String(),
        'openedAt': [
          for (final at in openedAt) at.toUtc().toIso8601String(),
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
          other.waitStartedAt == waitStartedAt &&
          other.unlockedAt == unlockedAt &&
          _sameDates(other.openedAt, openedAt);

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
        waitStartedAt,
        unlockedAt,
        Object.hashAll(openedAt),
      );
}
