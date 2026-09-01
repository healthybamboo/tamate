import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

/// 解錠通知の文面。
///
/// 文言のローカライズは presentation 層の責務なので、組み立て済みの文字列を受け取る。
@immutable
class UnlockNotificationContent {
  const UnlockNotificationContent({
    required this.channelName,
    required this.channelDescription,
    required this.title,
    required this.body,
  });

  /// Android の通知チャンネル名。端末の設定画面に出る。
  final String channelName;
  final String channelDescription;
  final String title;
  final String body;
}

/// 解錠時刻のローカル通知を扱う。
abstract interface class NotificationService {
  /// プラグインの初期化。アプリ起動時に一度だけ呼ぶ。
  Future<void> initialize();

  /// 通知の許可を求める。拒否されても通知以外の機能は動く。
  Future<bool> requestPermission();

  /// [unlockAt] に解錠を知らせる通知を予約する。
  Future<void> scheduleUnlock({
    required String memoId,
    required DateTime unlockAt,
    required UnlockNotificationContent content,
  });

  /// 予約済みの通知を取り消す。
  Future<void> cancelUnlock(String memoId);

  /// 通知がタップされたメモの ID。
  Stream<String> get openRequests;

  /// 通知のタップでアプリが起動したときの対象メモ ID。読み出すと消える。
  String? takeLaunchMemoId();
}

/// 何もしない実装。テストと、通知を使わない実行環境向け。
class NoopNotificationService implements NotificationService {
  const NoopNotificationService();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> scheduleUnlock({
    required String memoId,
    required DateTime unlockAt,
    required UnlockNotificationContent content,
  }) async {}

  @override
  Future<void> cancelUnlock(String memoId) async {}

  @override
  Stream<String> get openRequests => const Stream<String>.empty();

  @override
  String? takeLaunchMemoId() => null;
}

/// 既定では何もしない。実機では `main()` で実装を差し込む。
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => const NoopNotificationService(),
);
