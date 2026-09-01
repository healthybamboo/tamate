import 'package:meta/meta.dart';

import 'unlock_policy.dart';

/// 解錠条件の判定結果。
@immutable
sealed class UnlockProgress {
  const UnlockProgress();
}

/// 解錠条件を満たしている。
final class UnlockSatisfied extends UnlockProgress {
  const UnlockSatisfied();
}

/// まだ解錠条件を満たしていない。
///
/// [remaining] は残り時間。時間で測れないルールでは null になる。
final class UnlockPending extends UnlockProgress {
  const UnlockPending({this.remaining});

  final Duration? remaining;
}

/// メモを解錠するための条件。
///
/// 新しい仕掛け（パズル、場所、回数など）を足すときは、このクラスを継承した実装を
/// 1つ追加し、[UnlockRule.fromJson] に分岐を足す。時間の計算はすべてこの層に閉じ込め、
/// UI からは [progressAt] の結果だけを見る。
@immutable
abstract class UnlockRule {
  const UnlockRule();

  /// 保存データからルールを復元する。
  ///
  /// 未知の種別（将来のバージョンが書いたデータなど）は既定のルールとして読む。
  /// 読めないデータでクラッシュさせないため。
  factory UnlockRule.fromJson(Map<String, dynamic> json) =>
      switch (json['type']) {
        WaitDurationUnlockRule.typeName =>
          WaitDurationUnlockRule.fromJson(json),
        _ => fallback,
      };

  /// 解錠ルールが読み取れないときに使うルール。
  static const UnlockRule fallback =
      WaitDurationUnlockRule(UnlockPolicy.defaultWait);

  /// 保存時の識別子。
  String get type;

  /// [startedAt] に開こうとしたメモが、[now] 時点で解錠条件を満たしているか。
  UnlockProgress progressAt({
    required DateTime startedAt,
    required DateTime now,
  });

  /// 解錠される時刻。事前に分からないルールでは null を返す。
  ///
  /// 通知の予約に使う。
  DateTime? unlockAt(DateTime startedAt);

  /// 解錠までにかかる時間。時間で測れないルールでは null を返す。
  ///
  /// 「開くと10分待つことになります」という案内の表示に使う。
  Duration? get expectedWait;

  Map<String, dynamic> toJson();
}

/// 開こうとしてから一定時間待つルール。
final class WaitDurationUnlockRule extends UnlockRule {
  const WaitDurationUnlockRule(this.duration);

  factory WaitDurationUnlockRule.fromJson(Map<String, dynamic> json) {
    final seconds = json['seconds'];
    if (seconds is! int || seconds < 0) {
      return const WaitDurationUnlockRule(UnlockPolicy.defaultWait);
    }
    return WaitDurationUnlockRule(Duration(seconds: seconds));
  }

  static const String typeName = 'waitDuration';

  /// 待機する長さ。
  final Duration duration;

  @override
  String get type => typeName;

  @override
  UnlockProgress progressAt({
    required DateTime startedAt,
    required DateTime now,
  }) {
    final remaining = unlockAt(startedAt).difference(now);
    if (remaining <= Duration.zero) {
      return const UnlockSatisfied();
    }
    return UnlockPending(remaining: remaining);
  }

  @override
  DateTime unlockAt(DateTime startedAt) => startedAt.add(duration);

  @override
  Duration? get expectedWait => duration;

  @override
  Map<String, dynamic> toJson() => {
        'type': typeName,
        'seconds': duration.inSeconds,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WaitDurationUnlockRule && other.duration == duration;

  @override
  int get hashCode => Object.hash(typeName, duration);
}
