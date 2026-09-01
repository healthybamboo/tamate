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

/// 時間の関門は明けていて、問いへの答えを待っている。
final class UnlockNeedsAnswers extends UnlockProgress {
  const UnlockNeedsAnswers({required this.questions});

  /// 答えてもらう問い。
  final List<String> questions;
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
        QuestionUnlockRule.typeName => QuestionUnlockRule.fromJson(json),
        AllOfUnlockRule.typeName => AllOfUnlockRule.fromJson(json),
        _ => fallback,
      };

  /// 解錠ルールが読み取れないときに使うルール。
  static const UnlockRule fallback =
      WaitDurationUnlockRule(UnlockPolicy.defaultWait);

  /// 保存時の識別子。
  String get type;

  /// 解錠条件を満たしているか。
  ///
  /// [elapsed] は待機画面を見ていた時間、[answered] は問いに答え終えたか。
  UnlockProgress progressFor({
    required Duration elapsed,
    required bool answered,
  });

  /// 解錠までにかかる時間。時間で測れないルールでは null を返す。
  ///
  /// 「開くと3分待つことになります」という案内の表示に使う。
  Duration? get expectedWait;

  /// 答えてもらう問い。問いを持たないルールでは空。
  List<String> get questions => const [];

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
  UnlockProgress progressFor({
    required Duration elapsed,
    required bool answered,
  }) {
    final remaining = duration - elapsed;
    if (remaining <= Duration.zero) {
      return const UnlockSatisfied();
    }
    return UnlockPending(remaining: remaining);
  }

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

/// 問いに答えることを求めるルール。
///
/// 問いは順に1問ずつ出し、全部に「はい」で答えたときだけ解錠する。順番は出すたびに
/// 変える（同じ順で並ぶと惰性で答えてしまうため）。答えの記録はアプリ側で行う。
final class QuestionUnlockRule extends UnlockRule {
  const QuestionUnlockRule(this.questions);

  /// 保存データから復元する。問いが1つも読めなければ既定の待機ルールとして読む。
  static UnlockRule fromJson(Map<String, dynamic> json) {
    final raw = json['questions'];
    if (raw is! List) {
      return UnlockRule.fallback;
    }
    final questions = [
      for (final question in raw)
        if (question is String && question.trim().isNotEmpty) question,
    ];
    return questions.isEmpty
        ? UnlockRule.fallback
        : QuestionUnlockRule(questions);
  }

  static const String typeName = 'question';

  @override
  final List<String> questions;

  @override
  String get type => typeName;

  @override
  UnlockProgress progressFor({
    required Duration elapsed,
    required bool answered,
  }) =>
      answered
          ? const UnlockSatisfied()
          : UnlockNeedsAnswers(questions: questions);

  @override
  Duration? get expectedWait => null;

  @override
  Map<String, dynamic> toJson() => {'type': typeName, 'questions': questions};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuestionUnlockRule && _sameQuestions(other.questions, questions);

  @override
  int get hashCode => Object.hashAll([typeName, ...questions]);
}

/// 並べたルールをすべて満たしたときに解錠するルール。
///
/// 「3分待って、かつ問いに答える」のような組み合わせを表す。判定は先頭から順に行い、
/// 最初に満たしていないルールの状態を返す。時間の関門を先に置くこと。
final class AllOfUnlockRule extends UnlockRule {
  const AllOfUnlockRule(this.rules);

  /// 保存データから復元する。中身が読めなければ既定の待機ルールとして読む。
  static UnlockRule fromJson(Map<String, dynamic> json) {
    final raw = json['rules'];
    if (raw is! List || raw.isEmpty) {
      return UnlockRule.fallback;
    }
    return AllOfUnlockRule([
      for (final rule in raw)
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
  UnlockProgress progressFor({
    required Duration elapsed,
    required bool answered,
  }) {
    for (final rule in rules) {
      final progress = rule.progressFor(elapsed: elapsed, answered: answered);
      if (progress is! UnlockSatisfied) {
        return progress;
      }
    }
    return const UnlockSatisfied();
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
  List<String> get questions => [
        for (final rule in rules) ...rule.questions,
      ];

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

bool _sameQuestions(List<String> a, List<String> b) {
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
