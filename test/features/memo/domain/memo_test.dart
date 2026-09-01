import 'package:flutter_test/flutter_test.dart';
import 'package:tamate/features/memo/domain/memo.dart';
import 'package:tamate/features/memo/domain/memo_lock_state.dart';
import 'package:tamate/features/memo/domain/unlock_policy.dart';
import 'package:tamate/features/memo/domain/unlock_rule.dart';

void main() {
  final createdAt = DateTime(2026, 9, 1, 12);
  const rule = WaitDurationUnlockRule(Duration(minutes: 10));

  Memo memo({DateTime? waitStartedAt, DateTime? unlockedAt}) => Memo(
        id: 'id',
        title: 'タイトル',
        body: '本文',
        createdAt: createdAt,
        updatedAt: createdAt,
        unlockRule: rule,
        waitStartedAt: waitStartedAt,
        unlockedAt: unlockedAt,
      );

  group('lockStateAt', () {
    test('開こうとしていなければロック中', () {
      expect(memo().lockStateAt(createdAt), const MemoLocked());
    });

    test('待機中は残り時間と解錠時刻を返す', () {
      final startedAt = createdAt;
      final state = memo(waitStartedAt: startedAt)
          .lockStateAt(startedAt.add(const Duration(minutes: 3)));

      expect(
        state,
        MemoWaiting(
          remaining: const Duration(minutes: 7),
          unlockAt: startedAt.add(const Duration(minutes: 10)),
        ),
      );
      expect(state.canRead, isFalse);
    });

    test('待機時間が過ぎたら解錠中になる', () {
      final startedAt = createdAt;
      final state = memo(waitStartedAt: startedAt)
          .lockStateAt(startedAt.add(const Duration(minutes: 11)));

      expect(state.canRead, isTrue);
      expect(
        (state as MemoUnlocked).remaining,
        UnlockPolicy.openWindow - const Duration(minutes: 1),
      );
    });

    test('閲覧可能時間を過ぎたら再びロック中になる', () {
      final startedAt = createdAt;
      final relockedAt = startedAt
          .add(const Duration(minutes: 10))
          .add(UnlockPolicy.openWindow);

      expect(
        memo(waitStartedAt: startedAt).lockStateAt(relockedAt),
        const MemoLocked(),
      );
    });

    test('アプリを閉じている間に待機が終わっていても解錠中になる', () {
      // 起動しっぱなしかどうかに関係なく、時刻の差だけで決まる。
      final startedAt = createdAt;
      final state = memo(waitStartedAt: startedAt).lockStateAt(
        startedAt.add(const Duration(minutes: 10, seconds: 1)),
      );

      expect(state.canRead, isTrue);
    });

    test('解錠を記録した時刻があればそこから閲覧可能時間を数える', () {
      // 解錠時刻を計算できないルールを想定した経路。
      final startedAt = createdAt;
      final unlockedAt = startedAt.add(const Duration(minutes: 30));
      final state = memo(waitStartedAt: startedAt, unlockedAt: unlockedAt)
          .lockStateAt(unlockedAt.add(const Duration(minutes: 1)));

      expect(
        (state as MemoUnlocked).relocksAt,
        unlockedAt.add(UnlockPolicy.openWindow),
      );
    });
  });

  group('状態の遷移', () {
    test('startWaiting は前回の解錠の記録を捨てる', () {
      final started = memo(unlockedAt: createdAt).startWaiting(createdAt);

      expect(started.waitStartedAt, createdAt);
      expect(started.unlockedAt, isNull);
    });

    test('cancelWaiting で待機がリセットされる', () {
      final canceled = memo(waitStartedAt: createdAt).cancelWaiting();

      expect(canceled.waitStartedAt, isNull);
      expect(canceled.lockStateAt(createdAt), const MemoLocked());
    });

    test('copyWith は解錠の状態を引き継ぐ', () {
      final edited = memo(waitStartedAt: createdAt).copyWith(body: '書き換え');

      expect(edited.body, '書き換え');
      expect(edited.waitStartedAt, createdAt);
    });
  });

  group('JSON', () {
    test('往復しても内容が変わらない', () {
      final original = memo(
        waitStartedAt: createdAt,
        unlockedAt: createdAt.add(const Duration(minutes: 10)),
      );

      expect(Memo.fromJson(original.toJson()), original);
    });

    test('解錠まわりのフィールドが無い古いデータも読める', () {
      final restored = Memo.fromJson({
        'id': 'old',
        'title': '昔のメモ',
        'body': '本文',
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': createdAt.toIso8601String(),
      });

      expect(restored.unlockRule, UnlockRule.fallback);
      expect(restored.waitStartedAt, isNull);
      expect(restored.lockStateAt(createdAt), const MemoLocked());
    });

    test('壊れた日時でも読み込みで落ちない', () {
      final restored = Memo.fromJson({
        'id': 'broken',
        'title': 'こわれ',
        'body': '',
        'createdAt': 'not-a-date',
        'updatedAt': null,
        'waitStartedAt': 42,
      });

      expect(restored.id, 'broken');
      expect(restored.waitStartedAt, isNull);
    });
  });

  group('解錠コード', () {
    const codeRule = AllOfUnlockRule([
      WaitDurationUnlockRule(Duration(minutes: 3)),
      PassCodeUnlockRule('0429'),
    ]);

    Memo codeMemo({DateTime? waitStartedAt, DateTime? unlockedAt}) => Memo(
          id: 'id',
          title: 'タイトル',
          body: '本文',
          createdAt: createdAt,
          updatedAt: createdAt,
          unlockRule: codeRule,
          waitStartedAt: waitStartedAt,
          unlockedAt: unlockedAt,
        );

    test('待機が明けてもコードを入れるまで読めない', () {
      final state = codeMemo(waitStartedAt: createdAt)
          .lockStateAt(createdAt.add(const Duration(minutes: 5)));

      expect(state, const MemoAwaitingPassCode());
      expect(state.canRead, isFalse);
    });

    test('コードが通ったら閲覧可能時間が始まる', () {
      final acceptedAt = createdAt.add(const Duration(minutes: 5));
      final state = codeMemo(waitStartedAt: createdAt, unlockedAt: acceptedAt)
          .lockStateAt(acceptedAt.add(const Duration(minutes: 1)));

      expect(state.canRead, isTrue);
      expect(
        (state as MemoUnlocked).relocksAt,
        acceptedAt.add(UnlockPolicy.openWindow),
      );
    });

    test('コードの判定はメモから引ける', () {
      expect(codeMemo().acceptsPassCode('0429'), isTrue);
      expect(codeMemo().acceptsPassCode('0000'), isFalse);
    });
  });

  group('開封の記録', () {
    test('解錠のたびに履歴が1件増える', () {
      final first = createdAt.add(const Duration(minutes: 10));
      final second = createdAt.add(const Duration(hours: 1));

      final opened =
          memo().markUnlocked(first).startWaiting(second).markUnlocked(second);

      expect(opened.openedAt, [first, second]);
      expect(opened.openCount, 2);
    });

    test('待機のやり直しでは履歴が消えない', () {
      final at = createdAt.add(const Duration(minutes: 10));
      final canceled = memo().markUnlocked(at).cancelWaiting();

      expect(canceled.openCount, 1);
      expect(canceled.waitStartedAt, isNull);
    });

    test('JSON を往復しても履歴が残る', () {
      final at = createdAt.add(const Duration(minutes: 10));
      final opened = memo(waitStartedAt: createdAt).markUnlocked(at);

      expect(Memo.fromJson(opened.toJson()), opened);
    });

    test('履歴が無い古いデータは0回として読む', () {
      final restored = Memo.fromJson({
        'id': 'old',
        'title': '昔のメモ',
        'body': '本文',
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': createdAt.toIso8601String(),
      });

      expect(restored.openCount, 0);
    });
  });

  group('待機時間の差し替え', () {
    test('withWaitDuration で待機時間だけが変わる', () {
      final extended = memo(waitStartedAt: createdAt)
          .withWaitDuration(const Duration(minutes: 10));

      expect(extended.unlockRule.expectedWait, const Duration(minutes: 10));
      expect(extended.waitStartedAt, createdAt);
    });
  });
}
