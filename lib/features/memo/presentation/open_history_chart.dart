import 'package:flutter/material.dart';

/// 開封の記録を「日付 × 時刻」の図にする。
///
/// 縦が時刻（0〜24時を2時間ごと）、横が日付。同じ枠に何度も開いていれば色が濃くなる。
/// 横は記録のある日まで伸ばし、足りない場合でも [minimumDays] ぶんは出す。左へ辿れば
/// 古い記録まで遡れる。枠は数が増えても軽いようにキャンバスに直接描く。
class OpenHistoryChart extends StatelessWidget {
  const OpenHistoryChart({
    super.key,
    required this.openedAt,
    required this.now,
  });

  /// 1行あたりの時間幅。24時間を12行に分ける。
  static const int hoursPerRow = 2;

  /// 記録が少なくても、これだけの日数は出す。
  static const int minimumDays = 14;

  /// 遡れる上限。これより古い記録は図に出さない。
  static const int maximumDays = 366;

  static const int _rows = 24 ~/ hoursPerRow;
  static const double _cell = 14;
  static const double _gap = 2;
  static const double _labelHeight = 16;

  final List<DateTime> openedAt;

  /// 図の右端にする日。
  final DateTime now;

  /// 図に出す日数。いちばん古い記録まで伸ばす。
  static int rangeDays(List<DateTime> openedAt, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    var span = minimumDays;
    for (final at in openedAt) {
      final days =
          today.difference(DateTime(at.year, at.month, at.day)).inDays + 1;
      if (days > span) {
        span = days;
      }
    }
    return span > maximumDays ? maximumDays : span;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = rangeDays(openedAt, now);
    final counts = _countByCell(days);
    final busiest = counts.values.fold(0, (max, c) => c > max ? c : max);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            for (var row = 0; row < _rows; row++)
              SizedBox(
                height: _cell + _gap,
                width: 28,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    row.isEven ? '${row * hoursPerRow}' : '',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 4),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            // 右端（今日）から見せる。古い方へは左に辿る。
            reverse: true,
            child: CustomPaint(
              size: Size(
                days * (_cell + _gap),
                _rows * (_cell + _gap) + _labelHeight,
              ),
              painter: _ChartPainter(
                counts: counts,
                busiest: busiest,
                days: days,
                now: now,
                emptyColor: theme.colorScheme.surfaceContainerHighest,
                filledColor: theme.colorScheme.primary,
                labelStyle: theme.textTheme.labelSmall ?? const TextStyle(),
                textDirection: Directionality.of(context),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 「何日前・どの時間帯か」ごとの回数。
  Map<int, int> _countByCell(int days) {
    final today = DateTime(now.year, now.month, now.day);
    final counts = <int, int>{};
    for (final at in openedAt) {
      final day = today.difference(DateTime(at.year, at.month, at.day)).inDays;
      if (day < 0 || day >= days) {
        continue;
      }
      final key = day * _rows + at.hour ~/ hoursPerRow;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.counts,
    required this.busiest,
    required this.days,
    required this.now,
    required this.emptyColor,
    required this.filledColor,
    required this.labelStyle,
    required this.textDirection,
  });

  final Map<int, int> counts;
  final int busiest;
  final int days;
  final DateTime now;
  final Color emptyColor;
  final Color filledColor;
  final TextStyle labelStyle;
  final TextDirection textDirection;

  /// 日付の目盛りの間隔。日数が増えたら間引く。
  int get _labelStep => switch (days) {
        <= 21 => 5,
        <= 90 => 15,
        <= 200 => 30,
        _ => 60,
      };

  @override
  void paint(Canvas canvas, Size size) {
    const step = OpenHistoryChart._cell + OpenHistoryChart._gap;
    final paint = Paint();

    for (var day = 0; day < days; day++) {
      // 右端が今日。左へ行くほど古い。
      final x = size.width - (day + 1) * step;
      for (var row = 0; row < OpenHistoryChart._rows; row++) {
        final count = counts[day * OpenHistoryChart._rows + row] ?? 0;
        paint.color = count == 0
            ? emptyColor
            : filledColor.withValues(
                // 1回でも見えるように下限を置き、いちばん多い枠で最も濃くする。
                alpha: 0.35 + 0.65 * (count / (busiest == 0 ? 1 : busiest)),
              );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              x,
              row * step,
              OpenHistoryChart._cell,
              OpenHistoryChart._cell,
            ),
            const Radius.circular(3),
          ),
          paint,
        );
      }

      if (day % _labelStep == 0) {
        _paintLabel(canvas, x, size, day);
      }
    }
  }

  void _paintLabel(Canvas canvas, double x, Size size, int day) {
    final date = now.subtract(Duration(days: day));
    final painter = TextPainter(
      text: TextSpan(text: '${date.month}/${date.day}', style: labelStyle),
      textDirection: textDirection,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        x,
        size.height - OpenHistoryChart._labelHeight + 2,
      ),
    );
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.days != days ||
      old.busiest != busiest ||
      old.now != now ||
      old.filledColor != filledColor ||
      !_sameCounts(old.counts, counts);

  bool _sameCounts(Map<int, int> a, Map<int, int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
}
