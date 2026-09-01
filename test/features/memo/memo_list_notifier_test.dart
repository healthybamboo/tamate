import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamate/core/clock/clock.dart';
import 'package:tamate/core/notifications/notification_service.dart';
import 'package:tamate/features/memo/application/memo_list_notifier.dart';
import 'package:tamate/features/memo/data/memo_repository.dart';
import 'package:tamate/features/memo/domain/memo.dart';
import 'package:tamate/features/memo/domain/memo_lock_state.dart';
import 'package:tamate/features/memo/domain/unlock_policy.dart';
import 'package:tamate/features/memo/domain/unlock_rule.dart';

import '../../support/fakes.dart';

void main() {
  const notification = UnlockNotificationContent(
    channelName: 'ch',
    channelDescription: 'desc',
    title: 'title',
    body: 'body',
  );
  const rule = WaitDurationUnlockRule(Duration(minutes: 10));

  late InMemoryMemoRepository repository;
  late FakeClock clock;
  late RecordingNotificationService notifications;
  late ProviderContainer container;

  ProviderContainer createContainer() => ProviderContainer(
        overrides: [
          memoRepositoryProvider.overrideWithValue(repository),
          clockProvider.overrideWithValue(clock),
          notificationServiceProvider.overrideWithValue(notifications),
        ],
      );

  setUp(() {
    repository = InMemoryMemoRepository();
    clock = FakeClock(DateTime(2026, 9, 1, 12));
    notifications = RecordingNotificationService();
    container = createContainer();
    addTearDown(container.dispose);
  });

  Future<List<Memo>> read() => container.read(memoListProvider.future);

  MemoListNotifier notifier() => container.read(memoListProvider.notifier);

  Future<String> addMemo({
    String title = 'タイトル',
    String body = '本文',
    UnlockRule unlockRule = rule,
  }) async {
    await read();
    await notifier().add(title: title, body: body, unlockRule: unlockRule);
    return container.read(memoListProvider).requireValue.first.id;
  }

  test('初期状態は空', () async {
    expect(await read(), isEmpty);
  });

  test('add でメモが追加され永続化される', () async {
    final id = await addMemo();

    expect(repository.memos, hasLength(1));
    expect(repository.memos.single.id, id);
    expect(repository.memos.single.unlockRule, rule);
  });

  test('作った直後はロック中で本文が読めない', () async {
    final id = await addMemo();

    final memo = container.read(memoProvider(id))!;
    expect(memo.lockStateAt(clock.now()).canRead, isFalse);
  });

  test('startWaiting で待機が始まり、解錠時刻の通知が予約される', () async {
    final id = await addMemo();

    await notifier().startWaiting(id, notification: notification);

    final memo = container.read(memoProvider(id))!;
    expect(memo.wait?.resumedAt, clock.now());
    expect(notifications.permissionRequests, 1);
    expect(notifications.scheduled.single.memoId, id);
    expect(
      notifications.scheduled.single.unlockAt,
      clock.now().add(rule.duration),
    );
  });

  test('待機時間が過ぎると解錠される', () async {
    final id = await addMemo();
    await notifier().startWaiting(id, notification: notification);

    clock.advance(rule.duration);

    final memo = container.read(memoProvider(id))!;
    expect(memo.lockStateAt(clock.now()).canRead, isTrue);
  });

  test('cancelWaiting で待機がリセットされ、通知も取り消される', () async {
    final id = await addMemo();
    await notifier().startWaiting(id, notification: notification);

    await notifier().cancelWaiting(id);

    expect(container.read(memoProvider(id))!.wait, isNull);
    expect(notifications.canceled, [id]);

    // 待ち直しになるので、元の待機時間が過ぎていても読めない。
    clock.advance(rule.duration);
    expect(
      container.read(memoProvider(id))!.lockStateAt(clock.now()).canRead,
      isFalse,
    );
  });

  test('delete で通知も取り消される', () async {
    final id = await addMemo();
    await notifier().startWaiting(id, notification: notification);

    await notifier().delete(id);

    expect(container.read(memoListProvider).requireValue, isEmpty);
    expect(notifications.canceled, [id]);
  });

  test('解錠中は編集できる', () async {
    final id = await addMemo(title: '旧', body: '旧本文');
    await notifier().startWaiting(id, notification: notification);
    clock.advance(rule.duration);

    final saved = await notifier().edit(id: id, title: '新', body: '新本文');

    expect(saved, isTrue);
    expect(container.read(memoProvider(id))!.body, '新本文');
  });

  test('ロック中は編集を受け付けない', () async {
    final id = await addMemo(title: '旧', body: '旧本文');

    final saved = await notifier().edit(id: id, title: '新', body: '新本文');

    expect(saved, isFalse);
    expect(container.read(memoProvider(id))!.body, '旧本文');
  });

  test('settleUnlock は解錠を記録し、待機の経過を片付ける', () async {
    final id = await addMemo();
    await notifier().startWaiting(id, notification: notification);
    clock.advance(rule.duration);

    await notifier().settleUnlock(id);

    final memo = container.read(memoProvider(id))!;
    expect(memo.unlockedAt, clock.now());
    expect(memo.wait, isNull);
    expect(memo.openCount, 1);
  });

  test('refresh は再ロックされたメモの解錠の記録を片付ける', () async {
    final id = await addMemo();
    await notifier().startWaiting(id, notification: notification);
    clock.advance(rule.duration);
    await notifier().settleUnlock(id);
    clock.advance(UnlockPolicy.openWindow);

    await notifier().refresh();

    expect(container.read(memoProvider(id))!.unlockedAt, isNull);
    expect(repository.memos.single.wait, isNull);
  });

  test('refresh は待機中のメモには触らない', () async {
    final id = await addMemo();
    await notifier().startWaiting(id, notification: notification);
    final wait = container.read(memoProvider(id))!.wait;
    clock.advance(const Duration(minutes: 1));

    await notifier().refresh();

    expect(container.read(memoProvider(id))!.wait, wait);
  });

  test('アプリを再起動すると、待った分は残り、落ちていた間は進まない', () async {
    final id = await addMemo();
    await notifier().startWaiting(id, notification: notification);
    clock.advance(const Duration(minutes: 4));
    await notifier().pauseWaiting(id);
    clock.advance(const Duration(hours: 1));

    // 保存済みデータだけを引き継いで作り直す。
    container.dispose();
    container = createContainer();
    addTearDown(container.dispose);
    await read();

    final state = container.read(memoProvider(id))!.lockStateAt(clock.now());
    expect(
      state,
      const MemoWaiting(remaining: Duration(minutes: 6), running: false),
    );
  });

  group('待機の停止と再開', () {
    test('止めている間は残り時間が減らない', () async {
      final id = await addMemo();
      await notifier().startWaiting(id, notification: notification);
      clock.advance(const Duration(minutes: 4));

      await notifier().pauseWaiting(id);
      clock.advance(const Duration(hours: 1));

      expect(
        container.read(memoProvider(id))!.lockStateAt(clock.now()),
        const MemoWaiting(remaining: Duration(minutes: 6), running: false),
      );
      // 進まない待機に通知を残しておく意味は無い。
      expect(notifications.canceled, [id]);
    });

    test('再開すると続きから進み、通知も入れ直す', () async {
      final id = await addMemo();
      await notifier().startWaiting(id, notification: notification);
      clock.advance(const Duration(minutes: 4));
      await notifier().pauseWaiting(id);
      clock.advance(const Duration(hours: 1));

      await notifier().resumeWaiting(id, notification: notification);
      clock.advance(const Duration(minutes: 6));

      expect(
        container.read(memoProvider(id))!.lockStateAt(clock.now()).canRead,
        isTrue,
      );
      expect(notifications.scheduled, hasLength(2));
      expect(
        notifications.scheduled.last.unlockAt,
        DateTime(2026, 9, 1, 12).add(const Duration(hours: 1, minutes: 10)),
      );
    });

    test('アプリが落ちても、止めるまでに待った分は残る', () async {
      final id = await addMemo();
      await notifier().startWaiting(id, notification: notification);
      clock.advance(const Duration(minutes: 4));
      await notifier().pauseWaiting(id);
      await notifier().resumeWaiting(id, notification: notification);
      clock.advance(const Duration(minutes: 3));

      // 止めずに落ちた場合を、保存内容の読み直しで再現する。
      container.dispose();
      container = createContainer();
      addTearDown(container.dispose);
      await read();

      expect(
        container.read(memoProvider(id))!.lockStateAt(clock.now()),
        const MemoWaiting(remaining: Duration(minutes: 6), running: false),
      );
    });
  });

  test('一覧は更新日時の新しい順に並ぶ', () async {
    final now = DateTime(2026);
    repository = InMemoryMemoRepository([
      Memo(
        id: 'old',
        title: 'old',
        body: '',
        createdAt: now,
        updatedAt: now,
      ),
      Memo(
        id: 'new',
        title: 'new',
        body: '',
        createdAt: now,
        updatedAt: now.add(const Duration(days: 1)),
      ),
    ]);
    container = createContainer();
    addTearDown(container.dispose);

    final memos = await read();
    expect(memos.map((e) => e.id), ['new', 'old']);
  });

  group('開封の記録', () {
    test('解錠のたびに回数が増える', () async {
      final id = await addMemo();

      for (var i = 0; i < 2; i++) {
        await notifier().startWaiting(id, notification: notification);
        clock.advance(rule.duration);
        await notifier().settleUnlock(id);
        clock.advance(UnlockPolicy.openWindow);
        await notifier().refresh();
      }

      expect(container.read(memoProvider(id))!.openCount, 2);
    });

    test('同じ解錠のあいだは回数が増えない', () async {
      final id = await addMemo();
      await notifier().startWaiting(id, notification: notification);
      clock.advance(rule.duration);

      await notifier().settleUnlock(id);
      await notifier().settleUnlock(id);

      expect(container.read(memoProvider(id))!.openCount, 1);
    });
  });

  group('待機時間をのばす提案', () {
    test('extendWait で1段階だけ長くなる', () async {
      final id = await addMemo(
        unlockRule: const WaitDurationUnlockRule(Duration(minutes: 3)),
      );

      final extended = await notifier().extendWait(id);

      expect(extended, const Duration(minutes: 5));
      expect(
        container.read(memoProvider(id))!.unlockRule.expectedWait,
        const Duration(minutes: 5),
      );
    });

    test('いちばん長い待機時間なら何もしない', () async {
      final id = await addMemo(
        unlockRule: const WaitDurationUnlockRule(Duration(minutes: 10)),
      );

      expect(await notifier().extendWait(id), isNull);
      expect(
        container.read(memoProvider(id))!.unlockRule.expectedWait,
        const Duration(minutes: 10),
      );
    });
  });

  group('問いかけ', () {
    const questionRule = AllOfUnlockRule([
      WaitDurationUnlockRule(Duration(minutes: 1)),
      QuestionUnlockRule(['後悔しませんか']),
    ]);

    Future<String> addQuestionMemo() => addMemo(unlockRule: questionRule);

    test('待機が明けると問いに移る', () async {
      final id = await addQuestionMemo();
      await notifier().startWaiting(id, notification: notification);
      clock.advance(const Duration(minutes: 1));

      expect(
        container.read(memoProvider(id))!.lockStateAt(clock.now()),
        const MemoAwaitingAnswers(questions: ['後悔しませんか']),
      );
    });

    test('すべて「はい」なら解錠され、開封に記録される', () async {
      final id = await addQuestionMemo();
      await notifier().startWaiting(id, notification: notification);
      clock.advance(const Duration(minutes: 1));

      await notifier().acceptAnswers(id);

      final memo = container.read(memoProvider(id))!;
      expect(memo.lockStateAt(clock.now()).canRead, isTrue);
      expect(memo.openCount, 1);
      expect(memo.declineCount, 0);
    });

    test('「いいえ」なら開かず、待ち直しになる', () async {
      final id = await addQuestionMemo();
      await notifier().startWaiting(id, notification: notification);
      clock.advance(const Duration(minutes: 1));

      await notifier().declineAnswers(id);

      final memo = container.read(memoProvider(id))!;
      expect(memo.lockStateAt(clock.now()), const MemoLocked());
      expect(memo.declineCount, 1);
      expect(memo.openCount, 0);
      expect(notifications.canceled, [id]);
    });

    test('待機中は答えを受け付けない', () async {
      final id = await addQuestionMemo();
      await notifier().startWaiting(id, notification: notification);

      await notifier().acceptAnswers(id);

      expect(
        container.read(memoProvider(id))!.lockStateAt(clock.now()).canRead,
        isFalse,
      );
    });

    test('問いは解錠中だけ直せる', () async {
      final id = await addQuestionMemo();

      expect(await notifier().editQuestions(id, ['別の問い']), isFalse);

      await notifier().startWaiting(id, notification: notification);
      clock.advance(const Duration(minutes: 1));
      await notifier().acceptAnswers(id);

      expect(await notifier().editQuestions(id, ['別の問い']), isTrue);
      expect(
        container.read(memoProvider(id))!.unlockRule.questions,
        ['別の問い'],
      );
    });
  });
}
