import 'package:meta/meta.dart';

/// 待機の経過。
///
/// 待機画面を離れた時点で捨てるので、開始時刻さえあれば残りは計算できる。
/// 止めて再開する余地を残すと「ちょっと離れる」ができてしまうため、持たない。
@immutable
class MemoWait {
  const MemoWait(this.startedAt);

  factory MemoWait.fromJson(Map<String, dynamic> json) {
    final startedAt = json['startedAt'];
    return MemoWait(
      startedAt is String
          ? DateTime.tryParse(startedAt)?.toLocal() ?? DateTime(0)
          : DateTime(0),
    );
  }

  /// 待機を始めた時刻。
  final DateTime startedAt;

  /// [now] 時点での経過。
  Duration elapsedAt(DateTime now) {
    final elapsed = now.difference(startedAt);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  Map<String, dynamic> toJson() => {
        'startedAt': startedAt.toUtc().toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemoWait && other.startedAt == startedAt;

  @override
  int get hashCode => startedAt.hashCode;
}
