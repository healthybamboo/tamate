import 'package:flutter_test/flutter_test.dart';
import 'package:tamate/features/memo/presentation/open_history_chart.dart';

void main() {
  final now = DateTime(2026, 9, 1, 17);

  group('rangeDays', () {
    test('記録が無くても2週間ぶんは出す', () {
      expect(OpenHistoryChart.rangeDays(const [], now), 14);
    });

    test('直近の記録だけなら2週間のまま', () {
      final days = OpenHistoryChart.rangeDays(
        [now.subtract(const Duration(days: 3))],
        now,
      );

      expect(days, 14);
    });

    test('古い記録があれば、その日まで伸ばす', () {
      final days = OpenHistoryChart.rangeDays(
        [
          now.subtract(const Duration(days: 200)),
          now.subtract(const Duration(days: 3)),
        ],
        now,
      );

      // 200日前のぶんも含めて出す。
      expect(days, 201);
    });

    test('遡れる上限で頭打ちにする', () {
      final days = OpenHistoryChart.rangeDays(
        [now.subtract(const Duration(days: 5000))],
        now,
      );

      expect(days, OpenHistoryChart.maximumDays);
    });
  });
}
