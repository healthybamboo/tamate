import 'package:flutter_test/flutter_test.dart';
import 'package:tamate/features/memo/domain/unlock_policy.dart';
import 'package:tamate/features/memo/domain/unlock_rule.dart';

void main() {
  group('WaitDurationUnlockRule', () {
    const rule = WaitDurationUnlockRule(Duration(minutes: 10));

    test('待機中は残り時間を返す', () {
      final progress = rule.progressFor(
          elapsed: const Duration(minutes: 4), answered: false);

      expect(progress, isA<UnlockPending>());
      expect(
        (progress as UnlockPending).remaining,
        const Duration(minutes: 6),
      );
    });

    test('待機時間ちょうどで解錠になる', () {
      final progress = rule.progressFor(
          elapsed: const Duration(minutes: 10), answered: false);

      expect(progress, isA<UnlockSatisfied>());
    });

    test('待機時間を答えられる', () {
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

  group('QuestionUnlockRule', () {
    const rule = QuestionUnlockRule(['後悔しませんか', '本当にそうですか']);

    test('時間では満たされず、問いを返す', () {
      final progress =
          rule.progressFor(elapsed: const Duration(days: 1), answered: false);

      expect(progress, isA<UnlockNeedsAnswers>());
      expect(
        (progress as UnlockNeedsAnswers).questions,
        ['後悔しませんか', '本当にそうですか'],
      );
      expect(rule.expectedWait, isNull);
    });

    test('答え終えていれば満たされる', () {
      expect(
        rule.progressFor(elapsed: Duration.zero, answered: true),
        isA<UnlockSatisfied>(),
      );
    });

    test('JSON を往復できる', () {
      expect(UnlockRule.fromJson(rule.toJson()), rule);
    });

    test('問いが空なら既定のルールとして読む', () {
      // 問いが無いと永久に開けないメモになってしまう。
      final restored = UnlockRule.fromJson({
        'type': QuestionUnlockRule.typeName,
        'questions': <dynamic>['  '],
      });

      expect(restored, UnlockRule.fallback);
    });
  });

  group('AllOfUnlockRule', () {
    const rule = AllOfUnlockRule([
      QuestionUnlockRule(['後悔しませんか']),
      WaitDurationUnlockRule(Duration(minutes: 3)),
    ]);

    test('答えるまでは問いを返す', () {
      final progress = rule.progressFor(
        elapsed: const Duration(minutes: 5),
        answered: false,
      );

      expect(progress, isA<UnlockNeedsAnswers>());
    });

    test('答えたあとは待機の状態を返す', () {
      final progress = rule.progressFor(
        elapsed: const Duration(minutes: 1),
        answered: true,
      );

      expect(progress, isA<UnlockPending>());
      expect((progress as UnlockPending).remaining, const Duration(minutes: 2));
    });

    test('待機時間と問いをまとめて答えられる', () {
      expect(rule.expectedWait, const Duration(minutes: 3));
      expect(rule.questions, ['後悔しませんか']);
    });

    test('待機時間だけを差し替えられる', () {
      final edited = rule.withWaitDuration(const Duration(minutes: 10));

      expect(edited.expectedWait, const Duration(minutes: 10));
      expect(edited.questions, ['後悔しませんか']);
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
