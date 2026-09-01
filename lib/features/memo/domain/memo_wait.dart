import 'package:meta/meta.dart';

/// 待機の経過。
///
/// 計測が進むのは待機画面を見ている間だけなので、経過時間そのもの（[elapsed]）と、
/// 進行中ならその開始時刻（[resumedAt]）を持つ。時刻の差ではなく合計で持つのは、
/// 止めたり再開したりを繰り返しても破綻しないようにするため。
@immutable
class MemoWait {
  const MemoWait({this.elapsed = Duration.zero, this.resumedAt});

  /// 進行中の待機を [now] から始める。
  factory MemoWait.startedAt(DateTime now) => MemoWait(resumedAt: now);

  factory MemoWait.fromJson(Map<String, dynamic> json) {
    final seconds = json['elapsedSeconds'];
    final resumedAt = json['resumedAt'];
    return MemoWait(
      elapsed: Duration(seconds: seconds is int && seconds > 0 ? seconds : 0),
      resumedAt:
          resumedAt is String ? DateTime.tryParse(resumedAt)?.toLocal() : null,
    );
  }

  /// 画面を見ていた時間の合計。進行中のぶんは含まない。
  final Duration elapsed;

  /// 進行中ならその開始時刻。止まっていれば null。
  final DateTime? resumedAt;

  bool get isRunning => resumedAt != null;

  /// [now] 時点での経過。
  Duration elapsedAt(DateTime now) {
    final startedAt = resumedAt;
    if (startedAt == null) {
      return elapsed;
    }
    final running = now.difference(startedAt);
    return running.isNegative ? elapsed : elapsed + running;
  }

  /// 計測を再開する。
  MemoWait resume(DateTime now) =>
      isRunning ? this : MemoWait(elapsed: elapsed, resumedAt: now);

  /// 計測を止める。ここまでの経過は残す。
  MemoWait pause(DateTime now) =>
      isRunning ? MemoWait(elapsed: elapsedAt(now)) : this;

  /// 進行中だったぶんを捨てて止める。
  ///
  /// アプリが落とされた場合に使う。落ちている間は待っていないので、
  /// 最後に止まった時点までを経過とする。
  MemoWait dropRunning() => isRunning ? MemoWait(elapsed: elapsed) : this;

  Map<String, dynamic> toJson() => {
        'elapsedSeconds': elapsed.inSeconds,
        'resumedAt': resumedAt?.toUtc().toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemoWait &&
          other.elapsed == elapsed &&
          other.resumedAt == resumedAt;

  @override
  int get hashCode => Object.hash(elapsed, resumedAt);
}
