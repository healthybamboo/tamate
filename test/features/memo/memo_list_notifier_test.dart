import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamate/core/clock/clock.dart';
import 'package:tamate/core/notifications/notification_service.dart';
import 'package:tamate/features/memo/application/memo_list_notifier.dart';
import 'package:tamate/features/memo/data/memo_repository.dart';
import 'package:tamate/features/memo/domain/memo.dart';
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
    expect(memo.waitStartedAt, clock.now());
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

    expect(container.read(memoProvider(id))!.waitStartedAt, isNull);
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

  test('settleUnlock は解錠時刻を記録する', () async {
    final id = await addMemo();
    final startedAt = clock.now();
    await notifier().startWaiting(id, notification: notification);
    clock.advance(rule.duration + const Duration(seconds: 30));

    await notifier().settleUnlock(id);

    // 記録するのは検知した時刻ではなく、実際に解錠された時刻。
    expect(
      container.read(memoProvider(id))!.unlockedAt,
      startedAt.add(rule.duration),
    );
  });

  test('refresh は再ロックされたメモの待機状態を片付ける', () async {
    final id = await addMemo();
    await notifier().startWaiting(id, notification: notification);
    clock.advance(rule.duration + UnlockPolicy.openWindow);

    await notifier().refresh();

    expect(container.read(memoProvider(id))!.waitStartedAt, isNull);
    expect(repository.memos.single.waitStartedAt, isNull);
  });

  test('refresh は待機中のメモには触らない', () async {
    final id = await addMemo();
    await notifier().startWaiting(id, notification: notification);
    final startedAt = container.read(memoProvider(id))!.waitStartedAt;
    clock.advance(const Duration(minutes: 1));

    await notifier().refresh();

    expect(container.read(memoProvider(id))!.waitStartedAt, startedAt);
  });

  test('アプリを再起動しても待機の途中経過が残る', () async {
    final id = await addMemo();
    await notifier().startWaiting(id, notification: notification);
    clock.advance(const Duration(minutes: 4));

    // 保存済みデータだけを引き継いで作り直す。
    container.dispose();
    container = createContainer();
    addTearDown(container.dispose);
    await read();

    final state = container.read(memoProvider(id))!.lockStateAt(clock.now());
    expect(state.canRead, isFalse);
    expect(
      container.read(memoProvider(id))!.waitStartedAt,
      DateTime(2026, 9, 1, 12),
    );
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

  group('解錠コード', () {
    Future<String> addCodeMemo() => addMemo(unlockRule: codeRule);

    test('待機が明けるまではコードを受け付けない', () async {
      final id = await addCodeMemo();
      await notifier().startWaiting(id, notification: notification);

      expect(await notifier().submitPassCode(id, '0429'), isFalse);
      expect(container.read(memoProvider(id))!.unlockedAt, isNull);
    });

    test('正しいコードで解錠される', () async {
      final id = await addCodeMemo();
      await notifier().startWaiting(id, notification: notification);
      clock.advance(const Duration(minutes: 1));

      expect(await notifier().submitPassCode(id, '0429'), isTrue);

      final memo = container.read(memoProvider(id))!;
      expect(memo.lockStateAt(clock.now()).canRead, isTrue);
      expect(memo.openCount, 1);
    });

    test('違うコードでは解錠されない', () async {
      final id = await addCodeMemo();
      await notifier().startWaiting(id, notification: notification);
      clock.advance(const Duration(minutes: 1));

      expect(await notifier().submitPassCode(id, '9999'), isFalse);

      final memo = container.read(memoProvider(id))!;
      expect(memo.lockStateAt(clock.now()).canRead, isFalse);
      expect(memo.openCount, 0);
    });

    test('何度間違えても入力を受け付け続ける', () async {
      final id = await addCodeMemo();
      await notifier().startWaiting(id, notification: notification);
      clock.advance(const Duration(minutes: 1));

      for (var i = 0; i < 5; i++) {
        expect(await notifier().submitPassCode(id, '0000'), isFalse);
      }

      expect(await notifier().submitPassCode(id, '0429'), isTrue);
    });
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

    test('解錠コード付きでも待機時間だけが変わる', () async {
      final id = await addMemo(unlockRule: codeRule);

      await notifier().extendWait(id);

      final memo = container.read(memoProvider(id))!;
      expect(memo.unlockRule.expectedWait, const Duration(minutes: 3));
      expect(memo.acceptsPassCode('0429'), isTrue);
    });
  });
}

/// 解錠コード付きのルール。待機1分 + コード。
const AllOfUnlockRule codeRule = AllOfUnlockRule([
  WaitDurationUnlockRule(Duration(minutes: 1)),
  PassCodeUnlockRule('0429'),
]);
