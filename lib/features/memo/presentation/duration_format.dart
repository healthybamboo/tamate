import 'package:intl/intl.dart';

import '../../../l10n/generated/app_localizations.dart';

/// 残り時間の表示。秒まで出すのは1時間未満のときだけにする。
String formatRemaining(AppLocalizations l10n, Duration duration) {
  final left = duration.isNegative ? Duration.zero : duration;
  if (left.inDays > 0) {
    return l10n.durationDayHour(left.inDays, left.inHours % 24);
  }
  if (left.inHours > 0) {
    return l10n.durationHourMinute(left.inHours, left.inMinutes % 60);
  }
  if (left.inMinutes > 0) {
    return l10n.durationMinuteSecond(left.inMinutes, left.inSeconds % 60);
  }
  return l10n.durationSecond(left.inSeconds);
}

/// 待機時間そのものの表示。「10分」「1時間」など。
String formatWaitLength(AppLocalizations l10n, Duration duration) {
  if (duration.inDays > 0) {
    return l10n.waitLengthDays(duration.inDays);
  }
  if (duration.inHours > 0) {
    return l10n.waitLengthHours(duration.inHours);
  }
  return l10n.waitLengthMinutes(duration.inMinutes);
}

/// 解錠予定時刻の表示。同じ日なら時刻だけにする。
String formatUnlockTime(String locale, DateTime time, DateTime now) {
  final isSameDay =
      time.year == now.year && time.month == now.month && time.day == now.day;
  final format = isSameDay
      ? DateFormat.Hm(locale)
      : DateFormat.MMMd(locale).addPattern(' ').add_Hm();
  return format.format(time);
}
