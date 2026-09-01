import 'package:flutter/material.dart';

/// 開封の記録を「日付 × 時刻」の図にする。
///
/// 縦が時刻（0〜24時を2時間ごと）、横が日付。同じ枠に何度も開いていれば色が濃くなる。
/// いつ頃開きがちかと、どの日に集中したかを同じ図から読めるようにするための表示。
class OpenHistoryChart extends StatelessWidget {
  const OpenHistoryChart({
    super.key,
    required this.openedAt,
    required this.now,
    this.days = 14,
  });

  /// 1行あたりの時間幅。24時間を12行に分ける。
  static const int hoursPerRow = 2;

  static const int _rows = 24 ~/ hoursPerRow;
  static const double _cell = 14;
  static const double _gap = 2;

  /// 開封した時刻。
  final List<DateTime> openedAt;

  /// 図の右端にする日。
  final DateTime now;

  /// 見せる日数。
  final int days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = _countByCell();
    final busiest =
        counts.values.fold(0, (max, count) => count > max ? count : max);

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
            reverse: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var row = 0; row < _rows; row++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: _gap),
                    child: Row(
                      children: [
                        for (var day = days - 1; day >= 0; day--)
                          Padding(
                            padding: const EdgeInsets.only(right: _gap),
                            child: _Cell(
                              count: counts[_key(day, row)] ?? 0,
                              busiest: busiest,
                            ),
                          ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    for (var day = days - 1; day >= 0; day--)
                      SizedBox(
                        width: _cell + _gap,
                        child: Text(
                          _dayLabel(day),
                          style: theme.textTheme.labelSmall,
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 「何日前・どの時間帯か」ごとの回数。
  Map<int, int> _countByCell() {
    final today = DateTime(now.year, now.month, now.day);
    final counts = <int, int>{};
    for (final at in openedAt) {
      final day = today.difference(DateTime(at.year, at.month, at.day)).inDays;
      if (day < 0 || day >= days) {
        continue;
      }
      final key = _key(day, at.hour ~/ hoursPerRow);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  int _key(int day, int row) => day * _rows + row;

  /// 5日ごとに日付を出す。全部出すと潰れる。
  String _dayLabel(int day) {
    if (day % 5 != 0) {
      return '';
    }
    final date = now.subtract(Duration(days: day));
    return '${date.month}/${date.day}';
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.count, required this.busiest});

  final int count;
  final int busiest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = count == 0
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.primary.withValues(
            // 1回でも見えるように下限を置き、いちばん多い枠で最も濃くする。
            alpha: 0.35 + 0.65 * (count / (busiest == 0 ? 1 : busiest)),
          );

    return Container(
      width: OpenHistoryChart._cell,
      height: OpenHistoryChart._cell,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
