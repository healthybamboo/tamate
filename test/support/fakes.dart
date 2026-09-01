import 'package:tamate/core/clock/clock.dart';
import 'package:tamate/features/memo/data/memo_repository.dart';
import 'package:tamate/features/memo/domain/memo.dart';

/// 時刻を手で進められる [Clock]。
class FakeClock implements Clock {
  FakeClock(this.value);

  DateTime value;

  void advance(Duration duration) => value = value.add(duration);

  @override
  DateTime now() => value;
}

/// メモリ上だけのリポジトリ。
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
