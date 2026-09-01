import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'notification_service.dart';

/// `flutter_local_notifications` を使った実装。
///
/// 通知は「あると便利」な機能なので、失敗してもアプリを止めない。
/// 例外はここで握りつぶし、呼び出し側は成否を気にしなくてよいようにしている。
class LocalNotificationService implements NotificationService {
  LocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const String _channelId = 'memo_unlock';

  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<String> _openRequests =
      StreamController<String>.broadcast();

  bool _initialized = false;
  String? _launchMemoId;

  @override
  Stream<String> get openRequests => _openRequests.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    await _setUpTimeZone();

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      // 許可は待機を始めるときに求めるので、起動時には出さない。
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    try {
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: (response) {
          final memoId = response.payload;
          if (memoId != null && memoId.isNotEmpty) {
            _openRequests.add(memoId);
          }
        },
      );

      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _launchMemoId = launch?.notificationResponse?.payload;
      }
    } on Exception catch (error) {
      debugPrint('通知の初期化に失敗した: $error');
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? false;
      }

      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        return await ios.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
    } on Exception catch (error) {
      debugPrint('通知の許可リクエストに失敗した: $error');
    }
    return false;
  }

  @override
  Future<void> scheduleUnlock({
    required String memoId,
    required DateTime unlockAt,
    required UnlockNotificationContent content,
  }) async {
    await initialize();

    final scheduledAt = tz.TZDateTime.from(unlockAt, tz.local);
    if (!scheduledAt.isAfter(tz.TZDateTime.now(tz.local))) {
      // すでに解錠済みなら知らせる意味がない。
      return;
    }

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        content.channelName,
        channelDescription: content.channelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: const DarwinNotificationDetails(),
    );

    try {
      await _plugin.zonedSchedule(
        _notificationId(memoId),
        content.title,
        content.body,
        scheduledAt,
        details,
        payload: memoId,
        // 正確なアラーム（SCHEDULE_EXACT_ALARM）は権限のハードルが高いわりに、
        // 数分の遅れが問題になる用途でもないので使わない。
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } on Exception catch (error) {
      debugPrint('通知の予約に失敗した: $error');
    }
  }

  @override
  Future<void> cancelUnlock(String memoId) async {
    try {
      await _plugin.cancel(_notificationId(memoId));
    } on Exception catch (error) {
      debugPrint('通知の取り消しに失敗した: $error');
    }
  }

  @override
  String? takeLaunchMemoId() {
    final memoId = _launchMemoId;
    _launchMemoId = null;
    return memoId;
  }

  Future<void> _setUpTimeZone() async {
    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(
          tz.getLocation(await FlutterTimezone.getLocalTimezone()));
    } on Exception catch (error) {
      // タイムゾーンが引けなくても UTC 基準で予約はできる。
      debugPrint('タイムゾーンの取得に失敗した: $error');
    }
  }

  /// メモ ID から通知 ID を作る。
  ///
  /// アプリを再起動しても同じ ID になるよう、`String.hashCode` ではなく
  /// 内容から決まるハッシュ（FNV-1a）を使う。
  static int _notificationId(String memoId) {
    var hash = 0x811c9dc5;
    for (final unit in memoId.codeUnits) {
      hash = (hash ^ unit) * 0x01000193;
      hash &= 0xffffffff;
    }
    // Android の通知 ID は 32bit 符号付き整数。
    return hash & 0x7fffffff;
  }
}
