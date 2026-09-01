import 'dart:math';

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

/// 時間の関門は明けていて、解錠コードの入力を待っている。
final class UnlockNeedsPassCode extends UnlockProgress {
  const UnlockNeedsPassCode();
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
        PassCodeUnlockRule.typeName => PassCodeUnlockRule.fromJson(json),
        AllOfUnlockRule.typeName => AllOfUnlockRule.fromJson(json),
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
  /// 「開くと3分待つことになります」という案内の表示に使う。
  Duration? get expectedWait;

  /// 解錠コードの入力を求めるルールか。
  ///
  /// コードそのものは決して外に出さない。使うかどうかだけを答える。
  bool get requiresPassCode => false;

  /// 解錠コードとして [input] を受け付けるか。
  ///
  /// コードを持たないルールは常に false。
  bool acceptsPassCode(String input) => false;

  /// 待機時間を [duration] に差し替えたルール。
  ///
  /// 待機時間を持たないルールは自分をそのまま返す。開封回数に応じて
  /// 待機時間を伸ばす提案から使う。
  UnlockRule withWaitDuration(Duration duration) => this;

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
  UnlockRule withWaitDuration(Duration duration) =>
      WaitDurationUnlockRule(duration);

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

/// 4桁の解錠コードの入力を求めるルール。
///
/// コードは作成時に1度だけ表示し、以降どこにも出さない。忘れたら開けないことが
/// この仕掛けの目的なので、再発行も控えの表示もしない。
final class PassCodeUnlockRule extends UnlockRule {
  const PassCodeUnlockRule(this.code);

  /// 4桁のコードをランダムに作る。
  factory PassCodeUnlockRule.generate([Random? random]) {
    final source = random ?? Random.secure();
    final value = source.nextInt(10000);
    return PassCodeUnlockRule(value.toString().padLeft(digits, '0'));
  }

  /// 保存データから復元する。壊れていれば既定の待機ルールとして読む。
  ///
  /// 読めないコードを持ち回っても、二度と開けないメモが残るだけなので。
  static UnlockRule fromJson(Map<String, dynamic> json) {
    final code = json['code'];
    if (code is! String || !_isValidCode(code)) {
      return UnlockRule.fallback;
    }
    return PassCodeUnlockRule(code);
  }

  static const String typeName = 'passCode';

  /// コードの桁数。
  static const int digits = 4;

  final String code;

  @override
  String get type => typeName;

  @override
  UnlockProgress progressAt({
    required DateTime startedAt,
    required DateTime now,
  }) =>
      const UnlockNeedsPassCode();

  @override
  DateTime? unlockAt(DateTime startedAt) => null;

  @override
  Duration? get expectedWait => null;

  @override
  bool get requiresPassCode => true;

  @override
  bool acceptsPassCode(String input) => input == code;

  @override
  Map<String, dynamic> toJson() => {'type': typeName, 'code': code};

  static bool _isValidCode(String code) =>
      code.length == digits && int.tryParse(code) != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PassCodeUnlockRule && other.code == code;

  @override
  int get hashCode => Object.hash(typeName, code);
}

/// 並べたルールをすべて満たしたときに解錠するルール。
///
/// 「3分待って、かつ解錠コードを入れる」のような組み合わせを表す。判定は先頭から順に
/// 行い、最初に満たしていないルールの状態を返す。時間の関門を先に置くこと。
final class AllOfUnlockRule extends UnlockRule {
  const AllOfUnlockRule(this.rules);

  /// 保存データから復元する。中身が読めなければ既定の待機ルールとして読む。
  static UnlockRule fromJson(Map<String, dynamic> json) {
    final rules = json['rules'];
    if (rules is! List || rules.isEmpty) {
      return UnlockRule.fallback;
    }
    return AllOfUnlockRule([
      for (final rule in rules)
        if (rule is Map<String, dynamic>)
          UnlockRule.fromJson(rule)
        else
          UnlockRule.fallback,
    ]);
  }

  static const String typeName = 'allOf';

  final List<UnlockRule> rules;

  @override
  String get type => typeName;

  @override
  UnlockProgress progressAt({
    required DateTime startedAt,
    required DateTime now,
  }) {
    for (final rule in rules) {
      final progress = rule.progressAt(startedAt: startedAt, now: now);
      if (progress is! UnlockSatisfied) {
        return progress;
      }
    }
    return const UnlockSatisfied();
  }

  /// 時間の関門が明ける時刻。いちばん遅いものに合わせる。
  @override
  DateTime? unlockAt(DateTime startedAt) {
    DateTime? latest;
    for (final rule in rules) {
      final at = rule.unlockAt(startedAt);
      if (at != null && (latest == null || at.isAfter(latest))) {
        latest = at;
      }
    }
    return latest;
  }

  @override
  Duration? get expectedWait {
    Duration? longest;
    for (final rule in rules) {
      final wait = rule.expectedWait;
      if (wait != null && (longest == null || wait > longest)) {
        longest = wait;
      }
    }
    return longest;
  }

  @override
  bool get requiresPassCode => rules.any((rule) => rule.requiresPassCode);

  @override
  bool acceptsPassCode(String input) =>
      rules.any((rule) => rule.acceptsPassCode(input));

  @override
  UnlockRule withWaitDuration(Duration duration) => AllOfUnlockRule([
        for (final rule in rules) rule.withWaitDuration(duration),
      ]);

  @override
  Map<String, dynamic> toJson() => {
        'type': typeName,
        'rules': [for (final rule in rules) rule.toJson()],
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! AllOfUnlockRule || other.rules.length != rules.length) {
      return false;
    }
    for (var i = 0; i < rules.length; i++) {
      if (other.rules[i] != rules[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll([typeName, ...rules]);
}
