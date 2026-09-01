import 'package:flutter_test/flutter_test.dart';
import 'package:tamate/features/memo/domain/unlock_policy.dart';
import 'package:tamate/features/memo/domain/unlock_rule.dart';

void main() {
  final startedAt = DateTime(2026, 9, 1, 12);

  group('WaitDurationUnlockRule', () {
    const rule = WaitDurationUnlockRule(Duration(minutes: 10));

    test('待機中は残り時間を返す', () {
      final progress = rule.progressAt(
        startedAt: startedAt,
        now: startedAt.add(const Duration(minutes: 4)),
      );

      expect(progress, isA<UnlockPending>());
      expect(
        (progress as UnlockPending).remaining,
        const Duration(minutes: 6),
      );
    });

    test('待機時間ちょうどで解錠になる', () {
      final progress = rule.progressAt(
        startedAt: startedAt,
        now: startedAt.add(const Duration(minutes: 10)),
      );

      expect(progress, isA<UnlockSatisfied>());
    });

    test('解錠時刻と待機時間を答えられる', () {
      expect(rule.unlockAt(startedAt), startedAt.add(rule.duration));
      expect(rule.expectedWait, const Duration(minutes: 10));
    });

    test('JSON を往復できる', () {
      final restored = UnlockRule.fromJson(rule.toJson());

      expect(restored, rule);
    });
  });

  group('UnlockRule.fromJson', () {
    test('未知の種別は既定のルールとして読む', () {
      final restored = UnlockRule.fromJson({'type': 'solvePuzzle'});

      expect(restored, UnlockRule.fallback);
      expect(restored.expectedWait, UnlockPolicy.defaultWait);
    });

    test('待機時間が壊れていても既定値で読む', () {
      final restored = UnlockRule.fromJson({
        'type': WaitDurationUnlockRule.typeName,
        'seconds': 'ten',
      });

      expect(restored.expectedWait, UnlockPolicy.defaultWait);
    });
  });
}
