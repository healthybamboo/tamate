import 'dart:math';

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

  group('PassCodeUnlockRule', () {
    const rule = PassCodeUnlockRule('0429');

    test('コードが合うまで入力待ちのまま', () {
      final progress = rule.progressAt(startedAt: startedAt, now: startedAt);

      expect(progress, isA<UnlockNeedsPassCode>());
      expect(rule.requiresPassCode, isTrue);
      expect(rule.unlockAt(startedAt), isNull);
      expect(rule.expectedWait, isNull);
    });

    test('コードの一致だけを見る', () {
      expect(rule.acceptsPassCode('0429'), isTrue);
      expect(rule.acceptsPassCode('4290'), isFalse);
      expect(rule.acceptsPassCode(''), isFalse);
    });

    test('生成されるコードは4桁', () {
      for (var seed = 0; seed < 50; seed++) {
        final generated = PassCodeUnlockRule.generate(Random(seed));

        expect(generated.code, matches(RegExp(r'^\d{4}$')));
      }
    });

    test('JSON を往復できる', () {
      expect(UnlockRule.fromJson(rule.toJson()), rule);
    });

    test('コードが壊れていたら既定のルールとして読む', () {
      // 読めないコードを持ち回っても、二度と開けないメモが残るだけなので。
      final restored = UnlockRule.fromJson({
        'type': PassCodeUnlockRule.typeName,
        'code': '12',
      });

      expect(restored, UnlockRule.fallback);
    });
  });

  group('AllOfUnlockRule', () {
    const rule = AllOfUnlockRule([
      WaitDurationUnlockRule(Duration(minutes: 3)),
      PassCodeUnlockRule('0429'),
    ]);

    test('待機中は待機の状態を返す', () {
      final progress = rule.progressAt(
        startedAt: startedAt,
        now: startedAt.add(const Duration(minutes: 1)),
      );

      expect(progress, isA<UnlockPending>());
      expect((progress as UnlockPending).remaining, const Duration(minutes: 2));
    });

    test('待機が明けたらコードの入力待ちになる', () {
      final progress = rule.progressAt(
        startedAt: startedAt,
        now: startedAt.add(const Duration(minutes: 3)),
      );

      expect(progress, isA<UnlockNeedsPassCode>());
    });

    test('時間の関門が明ける時刻と待機時間を答えられる', () {
      expect(
        rule.unlockAt(startedAt),
        startedAt.add(const Duration(minutes: 3)),
      );
      expect(rule.expectedWait, const Duration(minutes: 3));
      expect(rule.requiresPassCode, isTrue);
      expect(rule.acceptsPassCode('0429'), isTrue);
    });

    test('待機時間だけを差し替えられる', () {
      final extended = rule.withWaitDuration(const Duration(minutes: 10));

      expect(extended.expectedWait, const Duration(minutes: 10));
      expect(extended.acceptsPassCode('0429'), isTrue);
    });

    test('JSON を往復できる', () {
      expect(UnlockRule.fromJson(rule.toJson()), rule);
    });

    test('中身が無ければ既定のルールとして読む', () {
      final restored = UnlockRule.fromJson({
        'type': AllOfUnlockRule.typeName,
        'rules': <dynamic>[],
      });

      expect(restored, UnlockRule.fallback);
    });
  });
}
