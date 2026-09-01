import '../../../core/notifications/notification_service.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../domain/memo.dart';

/// 一覧や詳細で見せるタイトル。空なら「無題のメモ」。
String memoDisplayTitle(AppLocalizations l10n, Memo memo) =>
    memo.title.trim().isEmpty ? l10n.memoUntitled : memo.title;

/// 解錠通知の文面を組み立てる。本文は載せない。
UnlockNotificationContent unlockNotificationContent(
  AppLocalizations l10n,
  Memo memo,
) =>
    UnlockNotificationContent(
      channelName: l10n.notificationChannelName,
      channelDescription: l10n.notificationChannelDescription,
      title: l10n.notificationUnlockedTitle,
      body: l10n.notificationUnlockedBody(memoDisplayTitle(l10n, memo)),
    );
