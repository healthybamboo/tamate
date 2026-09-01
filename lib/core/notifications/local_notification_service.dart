import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  /// 正確なアラームが許可されていないときにプラグインが返すエラーコード。
  static const String _exactAlarmsNotPermitted = 'exact_alarms_not_permitted';

  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<String> _openRequests =
      StreamController<String>.broadcast();

  bool _initialized = false;
  bool _exactAlarmsRequested = false;
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
        final granted = await android.requestNotificationsPermission() ?? false;
        await _requestExactAlarms(android);
        return granted;
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
      await _schedule(
        memoId: memoId,
        content: content,
        scheduledAt: scheduledAt,
        details: details,
        mode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } on PlatformException catch (error) {
      if (error.code != _exactAlarmsNotPermitted) {
        debugPrint('通知の予約に失敗した: $error');
        return;
      }
      // 正確なアラームを許可されていない場合。精度は落ちるが予約はできる。
      // 残り時間の表示は現在時刻から計算しているので、通知が遅れてもズレない。
      try {
        await _schedule(
          memoId: memoId,
          content: content,
          scheduledAt: scheduledAt,
          details: details,
          mode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } on Exception catch (error) {
        debugPrint('通知の予約に失敗した: $error');
      }
    } on Exception catch (error) {
      debugPrint('通知の予約に失敗した: $error');
    }
  }

  Future<void> _schedule({
    required String memoId,
    required UnlockNotificationContent content,
    required tz.TZDateTime scheduledAt,
    required NotificationDetails details,
    required AndroidScheduleMode mode,
  }) =>
      _plugin.zonedSchedule(
        _notificationId(memoId),
        content.title,
        content.body,
        scheduledAt,
        details,
        payload: memoId,
        androidScheduleMode: mode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

  /// 解錠時刻ちょうどに知らせるための許可を求める。
  ///
  /// Android 14 以降は設定画面が開くため、1回だけ求める。断られても
  /// 予約自体はできる（[AndroidScheduleMode.inexactAllowWhileIdle] に落とす）。
  Future<void> _requestExactAlarms(
    AndroidFlutterLocalNotificationsPlugin android,
  ) async {
    if (_exactAlarmsRequested) {
      return;
    }
    _exactAlarmsRequested = true;
    if (await android.canScheduleExactNotifications() ?? false) {
      return;
    }
    await android.requestExactAlarmsPermission();
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
