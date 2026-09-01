import 'package:tamate/core/clock/clock.dart';
import 'package:tamate/core/notifications/notification_service.dart';
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

/// 予約・取り消しの呼び出しだけを記録する通知サービス。
class RecordingNotificationService implements NotificationService {
  final List<({String memoId, DateTime unlockAt})> scheduled = [];
  final List<String> canceled = [];
  int permissionRequests = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> scheduleUnlock({
    required String memoId,
    required DateTime unlockAt,
    required UnlockNotificationContent content,
  }) async {
    scheduled.add((memoId: memoId, unlockAt: unlockAt));
  }

  @override
  Future<void> cancelUnlock(String memoId) async => canceled.add(memoId);

  @override
  Stream<String> get openRequests => const Stream<String>.empty();

  @override
  String? takeLaunchMemoId() => null;
}
