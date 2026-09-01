import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamate/core/clock/clock.dart';
import 'package:tamate/features/memo/application/memo_list_notifier.dart';
import 'package:tamate/features/memo/data/memo_repository.dart';
import 'package:tamate/features/memo/domain/memo.dart';
import 'package:tamate/features/memo/domain/memo_lock_state.dart';
import 'package:tamate/features/memo/domain/unlock_policy.dart';
import 'package:tamate/features/memo/domain/unlock_rule.dart';

import '../../support/fakes.dart';

void main() {
  const rule = WaitDurationUnlockRule(Duration(minutes: 10));

  late InMemoryMemoRepository repository;
  late FakeClock clock;
  late ProviderContainer container;

  ProviderContainer createContainer() => ProviderContainer(
        overrides: [
          memoRepositoryProvider.overrideWithValue(repository),
          clockProvider.overrideWithValue(clock),
        ],
      );

  setUp(() {
    repository = InMemoryMemoRepository();
    clock = FakeClock(DateTime(2026, 9, 1, 12));
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

  test('startWaiting で待機が始まる', () async {
    final id = await addMemo();

    await notifier().startWaiting(id);

    final memo = container.read(memoProvider(id))!;
    expect(memo.wait?.startedAt, clock.now());
  });

  test('待機時間が過ぎると解錠される', () async {
    final id = await addMemo();
    await notifier().startWaiting(id);

    clock.advance(rule.duration);

    final memo = container.read(memoProvider(id))!;
    expect(memo.lockStateAt(clock.now()).canRead, isTrue);
  });

  test('cancelWaiting で待機がリセットされ、通知も取り消される', () async {
    final id = await addMemo();
    await notifier().startWaiting(id);

    await notifier().cancelWaiting(id);

    expect(container.read(memoProvider(id))!.wait, isNull);

    // 待ち直しになるので、元の待機時間が過ぎていても読めない。
    clock.advance(rule.duration);
    expect(
      container.read(memoProvider(id))!.lockStateAt(clock.now()).canRead,
      isFalse,
    );
  });

  test('delete で通知も取り消される', () async {
    final id = await addMemo();
    await notifier().startWaiting(id);

    await notifier().delete(id);

    expect(container.read(memoListProvider).requireValue, isEmpty);
  });

  test('解錠中は編集できる', () async {
    final id = await addMemo(title: '旧', body: '旧本文');
    await notifier().startWaiting(id);
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
    await notifier().startWaiting(id);
    clock.advance(rule.duration);

    await notifier().settleUnlock(id);

    final memo = container.read(memoProvider(id))!;
    expect(memo.unlockedAt, clock.now());
    expect(memo.wait, isNull);
    expect(memo.openCount, 1);
  });

  test('refresh は再ロックされたメモの解錠の記録を片付ける', () async {
    final id = await addMemo();
    await notifier().startWaiting(id);
    clock.advance(rule.duration);
    await notifier().settleUnlock(id);
    clock.advance(UnlockPolicy.openWindow);

    await notifier().refresh();

    expect(container.read(memoProvider(id))!.unlockedAt, isNull);
    expect(repository.memos.single.wait, isNull);
  });

  test('refresh は待機中のメモには触らない', () async {
    final id = await addMemo();
    await notifier().startWaiting(id);
    final wait = container.read(memoProvider(id))!.wait;
    clock.advance(const Duration(minutes: 1));

    await notifier().refresh();

    expect(container.read(memoProvider(id))!.wait, wait);
  });

  test('アプリを再起動すると待機は消える', () async {
    final id = await addMemo();
    await notifier().startWaiting(id);
    clock.advance(const Duration(minutes: 4));

    // 保存済みデータだけを引き継いで作り直す。
    container.dispose();
    container = createContainer();
    addTearDown(container.dispose);
    await read();

    final memo = container.read(memoProvider(id))!;
    expect(memo.wait, isNull);
    expect(memo.lockStateAt(clock.now()), const MemoLocked());
  });

  test('待機画面を離れると、経過ごと捨てて最初からになる', () async {
    final id = await addMemo();
    await notifier().startWaiting(id);
    clock.advance(const Duration(minutes: 9));

    // 画面を離れると呼ばれる。
    await notifier().cancelWaiting(id);

    expect(container.read(memoProvider(id))!.wait, isNull);

    // 残り1分だったぶんは戻らない。開き直せば最初から10分。
    await notifier().startWaiting(id);
    expect(
      container.read(memoProvider(id))!.lockStateAt(clock.now()),
      MemoWaiting(remaining: rule.duration),
    );
  });

  group('問いかけ', () {
    const questionRule = AllOfUnlockRule([
      WaitDurationUnlockRule(Duration(minutes: 1)),
      QuestionUnlockRule(['後悔しませんか']),
    ]);

    Future<String> addQuestionMemo() => addMemo(unlockRule: questionRule);

    test('問いだけのメモでは通知の許可を求めない', () async {
      final id = await addMemo(
        unlockRule: const QuestionUnlockRule(['後悔しませんか']),
      );

      await notifier().startWaiting(id);
    });

    test('待機が明けると問いに移る', () async {
      final id = await addQuestionMemo();
      await notifier().startWaiting(id);
      clock.advance(const Duration(minutes: 1));

      expect(
        container.read(memoProvider(id))!.lockStateAt(clock.now()),
        const MemoAwaitingAnswers(questions: ['後悔しませんか']),
      );
    });

    test('すべて「はい」なら解錠され、開封に記録される', () async {
      final id = await addQuestionMemo();
      await notifier().startWaiting(id);
      clock.advance(const Duration(minutes: 1));

      await notifier().acceptAnswers(id);

      final memo = container.read(memoProvider(id))!;
      expect(memo.lockStateAt(clock.now()).canRead, isTrue);
      expect(memo.openCount, 1);
      expect(memo.declineCount, 0);
    });

    test('「いいえ」なら開かず、待ち直しになる', () async {
      final id = await addQuestionMemo();
      await notifier().startWaiting(id);
      clock.advance(const Duration(minutes: 1));

      await notifier().declineAnswers(id);

      final memo = container.read(memoProvider(id))!;
      expect(memo.lockStateAt(clock.now()), const MemoLocked());
      expect(memo.declineCount, 1);
      expect(memo.openCount, 0);
    });

    test('待機中は答えを受け付けない', () async {
      final id = await addQuestionMemo();
      await notifier().startWaiting(id);

      await notifier().acceptAnswers(id);

      expect(
        container.read(memoProvider(id))!.lockStateAt(clock.now()).canRead,
        isFalse,
      );
    });

    test('解錠のしかたは解錠中だけ直せる', () async {
      final id = await addQuestionMemo();
      const edited = QuestionUnlockRule(['別の問い']);

      expect(
        await notifier().edit(
          id: id,
          title: 'タイトル',
          body: '本文',
          unlockRule: edited,
        ),
        isFalse,
      );

      await notifier().startWaiting(id);
      clock.advance(const Duration(minutes: 1));
      await notifier().acceptAnswers(id);

      expect(
        await notifier().edit(
          id: id,
          title: 'タイトル',
          body: '本文',
          unlockRule: edited,
        ),
        isTrue,
      );
      final memo = container.read(memoProvider(id))!;
      expect(memo.unlockRule, edited);
      // 待機時間も含めて解錠中なら変えられる。
      expect(memo.unlockRule.expectedWait, isNull);
    });
  });
}
