import 'package:flutter_test/flutter_test.dart';
import 'package:tamate/features/memo/domain/memo.dart';
import 'package:tamate/features/memo/domain/memo_lock_state.dart';
import 'package:tamate/features/memo/domain/memo_wait.dart';
import 'package:tamate/features/memo/domain/unlock_policy.dart';
import 'package:tamate/features/memo/domain/unlock_rule.dart';

void main() {
  final createdAt = DateTime(2026, 9, 1, 12);
  const rule = WaitDurationUnlockRule(Duration(minutes: 10));

  Memo memo({MemoWait? wait, DateTime? unlockedAt}) => Memo(
        id: 'id',
        title: 'タイトル',
        body: '本文',
        createdAt: createdAt,
        updatedAt: createdAt,
        unlockRule: rule,
        wait: wait,
        unlockedAt: unlockedAt,
      );

  group('lockStateAt', () {
    test('開こうとしていなければロック中', () {
      expect(memo().lockStateAt(createdAt), const MemoLocked());
    });

    test('待機中は残り時間を返す', () {
      final state = memo(wait: MemoWait.startedAt(createdAt))
          .lockStateAt(createdAt.add(const Duration(minutes: 3)));

      expect(
        state,
        const MemoWaiting(remaining: Duration(minutes: 7), running: true),
      );
      expect(state.canRead, isFalse);
    });

    test('待機時間ぶん見ていたら解錠中になる', () {
      final state = memo(wait: MemoWait.startedAt(createdAt))
          .lockStateAt(createdAt.add(const Duration(minutes: 11)));

      expect(state.canRead, isTrue);
    });

    test('閲覧可能時間を過ぎたら再びロック中になる', () {
      final unlockedAt = createdAt.add(const Duration(minutes: 10));

      expect(
        memo(unlockedAt: unlockedAt)
            .lockStateAt(unlockedAt.add(UnlockPolicy.openWindow)),
        const MemoLocked(),
      );
    });

    test('解錠を記録した時刻から閲覧可能時間を数える', () {
      final unlockedAt = createdAt.add(const Duration(minutes: 30));
      final state = memo(unlockedAt: unlockedAt)
          .lockStateAt(unlockedAt.add(const Duration(minutes: 1)));

      expect(
        (state as MemoUnlocked).relocksAt,
        unlockedAt.add(UnlockPolicy.openWindow),
      );
    });
  });

  group('待機の経過', () {
    test('止めている間は残り時間が減らない', () {
      final paused = memo(wait: MemoWait.startedAt(createdAt))
          .pauseWaiting(createdAt.add(const Duration(minutes: 2)));

      // 止めてから1時間経っても、経過は止めた時点のまま。
      final state = paused.lockStateAt(createdAt.add(const Duration(hours: 1)));

      expect(
        state,
        const MemoWaiting(remaining: Duration(minutes: 8), running: false),
      );
    });

    test('再開すると続きから減る', () {
      final pausedAt = createdAt.add(const Duration(minutes: 2));
      final resumedAt = createdAt.add(const Duration(hours: 1));
      final resumed = memo(wait: MemoWait.startedAt(createdAt))
          .pauseWaiting(pausedAt)
          .resumeWaiting(resumedAt);

      final state =
          resumed.lockStateAt(resumedAt.add(const Duration(minutes: 3)));

      expect(
        state,
        const MemoWaiting(remaining: Duration(minutes: 5), running: true),
      );
    });

    test('アプリが落ちた場合、進行中だったぶんは経過に入らない', () {
      final dropped = memo(wait: MemoWait.startedAt(createdAt))
          .pauseWaiting(createdAt.add(const Duration(minutes: 2)))
          .resumeWaiting(createdAt.add(const Duration(minutes: 3)))
          .dropRunningWait();

      // 残るのは止めるまでに見ていた2分だけ。
      final state =
          dropped.lockStateAt(createdAt.add(const Duration(hours: 1)));

      expect(
        state,
        const MemoWaiting(remaining: Duration(minutes: 8), running: false),
      );
    });

    test('cancelWaiting で経過ごと捨てる', () {
      final canceled = memo(wait: MemoWait.startedAt(createdAt))
          .pauseWaiting(createdAt.add(const Duration(minutes: 9)))
          .cancelWaiting();

      expect(canceled.wait, isNull);
      expect(canceled.lockStateAt(createdAt), const MemoLocked());
    });

    test('startWaiting は前回の解錠の記録を捨てる', () {
      final started = memo(unlockedAt: createdAt).startWaiting(createdAt);

      expect(started.wait?.isRunning, isTrue);
      expect(started.unlockedAt, isNull);
    });

    test('copyWith は待機の経過を引き継ぐ', () {
      final wait = MemoWait.startedAt(createdAt);
      final edited = memo(wait: wait).copyWith(body: '書き換え');

      expect(edited.body, '書き換え');
      expect(edited.wait, wait);
    });
  });

  group('解錠予定時刻', () {
    test('進んでいる待機は残り時間から求まる', () {
      final now = createdAt.add(const Duration(minutes: 4));
      final memoAt = memo(wait: MemoWait.startedAt(createdAt));

      expect(
        memoAt.scheduledUnlockAt(now),
        now.add(const Duration(minutes: 6)),
      );
    });

    test('止まっている待機では分からない', () {
      final paused = memo(wait: MemoWait.startedAt(createdAt))
          .pauseWaiting(createdAt.add(const Duration(minutes: 4)));

      expect(paused.scheduledUnlockAt(createdAt), isNull);
    });
  });

  group('JSON', () {
    test('往復しても内容が変わらない', () {
      final original = memo(wait: MemoWait.startedAt(createdAt))
          .pauseWaiting(createdAt.add(const Duration(minutes: 2)));

      expect(Memo.fromJson(original.toJson()), original);
    });

    test('待機のフィールドが無い古いデータも読める', () {
      final restored = Memo.fromJson({
        'id': 'old',
        'title': '昔のメモ',
        'body': '本文',
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': createdAt.toIso8601String(),
      });

      expect(restored.unlockRule, UnlockRule.fallback);
      expect(restored.wait, isNull);
      expect(restored.lockStateAt(createdAt), const MemoLocked());
    });

    test('旧仕様の waitStartedAt は読まずに未着手へ戻す', () {
      // 経過ではなく起点の時刻しか無いので、そのまま引き継ぐと
      // 閉じている間も待てたことになってしまう。
      final restored = Memo.fromJson({
        'id': 'old',
        'title': '待機中だったメモ',
        'body': '本文',
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': createdAt.toIso8601String(),
        'waitStartedAt': createdAt.toIso8601String(),
      });

      expect(restored.wait, isNull);
      expect(restored.lockStateAt(createdAt), const MemoLocked());
    });

    test('壊れた日時でも読み込みで落ちない', () {
      final restored = Memo.fromJson({
        'id': 'broken',
        'title': 'こわれ',
        'body': '',
        'createdAt': 'not-a-date',
        'updatedAt': null,
        'wait': 42,
      });

      expect(restored.id, 'broken');
      expect(restored.wait, isNull);
    });
  });

  group('開封の記録', () {
    test('解錠のたびに履歴が1件増える', () {
      final first = createdAt.add(const Duration(minutes: 10));
      final second = createdAt.add(const Duration(hours: 1));

      final opened = memo(wait: MemoWait.startedAt(createdAt))
          .markUnlocked(first)
          .startWaiting(second)
          .markUnlocked(second);

      expect(opened.openedAt, [first, second]);
      expect(opened.openCount, 2);
    });

    test('解錠すると待機の経過は役目を終える', () {
      final at = createdAt.add(const Duration(minutes: 10));
      final opened = memo(wait: MemoWait.startedAt(createdAt)).markUnlocked(at);

      expect(opened.wait, isNull);
      expect(opened.lockStateAt(at).canRead, isTrue);
    });

    test('待機のやり直しでは履歴が消えない', () {
      final at = createdAt.add(const Duration(minutes: 10));
      final canceled = memo().markUnlocked(at).cancelWaiting();

      expect(canceled.openCount, 1);
      expect(canceled.wait, isNull);
    });

    test('JSON を往復しても履歴が残る', () {
      final at = createdAt.add(const Duration(minutes: 10));
      final opened = memo(wait: MemoWait.startedAt(createdAt)).markUnlocked(at);

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
      final wait = MemoWait.startedAt(createdAt);
      final extended =
          memo(wait: wait).withWaitDuration(const Duration(minutes: 10));

      expect(extended.unlockRule.expectedWait, const Duration(minutes: 10));
      expect(extended.wait, wait);
    });
  });
}
