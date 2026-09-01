import '../../../l10n/generated/app_localizations.dart';
import '../domain/memo.dart';

/// 一覧や詳細で見せるタイトル。空なら「無題のメモ」。
String memoDisplayTitle(AppLocalizations l10n, Memo memo) =>
    memo.title.trim().isEmpty ? l10n.memoUntitled : memo.title;
