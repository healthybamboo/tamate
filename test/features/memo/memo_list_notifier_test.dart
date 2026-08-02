import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamate/features/memo/application/memo_list_notifier.dart';
import 'package:tamate/features/memo/data/memo_repository.dart';
import 'package:tamate/features/memo/domain/memo.dart';

/// テスト用のインメモリ実装。
class InMemoryMemoRepository implements MemoRepository {
  InMemoryMemoRepository([List<Memo> initial = const []])
      : _memos = [...initial];

  List<Memo> _memos;

  List<Memo> get memos => List.unmodifiable(_memos);

  @override
  Future<List<Memo>> fetchAll() async => List.unmodifiable(_memos);

  @override
  Future<void> saveAll(List<Memo> memos) async => _memos = [...memos];
}

void main() {
  late InMemoryMemoRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = InMemoryMemoRepository();
    container = ProviderContainer(
      overrides: [memoRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
  });

  Future<List<Memo>> read() => container.read(memoListProvider.future);

  test('初期状態は空', () async {
    expect(await read(), isEmpty);
  });

  test('add でメモが追加され永続化される', () async {
    await read();
    await container
        .read(memoListProvider.notifier)
        .add(title: 'タイトル', body: '本文');

    final memos = container.read(memoListProvider).requireValue;
    expect(memos, hasLength(1));
    expect(memos.single.title, 'タイトル');
    expect(repository.memos, hasLength(1));
  });

  test('update で内容が書き換わる', () async {
    await read();
    final notifier = container.read(memoListProvider.notifier);
    await notifier.add(title: '旧', body: '旧本文');
    final id = container.read(memoListProvider).requireValue.single.id;

    await notifier.edit(id: id, title: '新', body: '新本文');

    final memo = container.read(memoProvider(id));
    expect(memo?.title, '新');
    expect(memo?.body, '新本文');
  });

  test('delete でメモが消える', () async {
    await read();
    final notifier = container.read(memoListProvider.notifier);
    await notifier.add(title: 'a', body: '');
    final id = container.read(memoListProvider).requireValue.single.id;

    await notifier.delete(id);

    expect(container.read(memoListProvider).requireValue, isEmpty);
    expect(repository.memos, isEmpty);
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
    container = ProviderContainer(
      overrides: [memoRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final memos = await read();
    expect(memos.map((e) => e.id), ['new', 'old']);
  });
}
