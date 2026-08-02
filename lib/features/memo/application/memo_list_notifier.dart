import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/memo_repository.dart';
import '../domain/memo.dart';

/// メモ一覧の状態を保持し、CRUD を提供する。
class MemoListNotifier extends AsyncNotifier<List<Memo>> {
  static const Uuid _uuid = Uuid();

  MemoRepository get _repository => ref.read(memoRepositoryProvider);

  @override
  Future<List<Memo>> build() async {
    final memos = await _repository.fetchAll();
    return _sorted(memos);
  }

  Future<void> add({required String title, required String body}) async {
    final now = DateTime.now();
    final memo = Memo(
      id: _uuid.v4(),
      title: title,
      body: body,
      createdAt: now,
      updatedAt: now,
    );
    await _mutate((memos) => [...memos, memo]);
  }

  Future<void> edit({
    required String id,
    required String title,
    required String body,
  }) async {
    await _mutate(
      (memos) => memos
          .map(
            (memo) => memo.id == id
                ? memo.copyWith(
                    title: title,
                    body: body,
                    updatedAt: DateTime.now(),
                  )
                : memo,
          )
          .toList(),
    );
  }

  Future<void> delete(String id) async {
    await _mutate((memos) => memos.where((memo) => memo.id != id).toList());
  }

  /// 現在の一覧に [transform] を適用し、永続化まで行う。
  Future<void> _mutate(
      List<Memo> Function(List<Memo> current) transform) async {
    final current = state.valueOrNull ?? const <Memo>[];
    final next = _sorted(transform(current));
    state = AsyncData(next);
    await _repository.saveAll(next);
  }

  /// 更新日時の新しい順。
  List<Memo> _sorted(List<Memo> memos) =>
      [...memos]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}

final memoListProvider =
    AsyncNotifierProvider<MemoListNotifier, List<Memo>>(MemoListNotifier.new);

/// 指定 ID のメモ。存在しなければ null。
final memoProvider = Provider.family<Memo?, String>((ref, id) {
  final memos = ref.watch(memoListProvider).valueOrNull;
  if (memos == null) {
    return null;
  }
  for (final memo in memos) {
    if (memo.id == id) {
      return memo;
    }
  }
  return null;
});
