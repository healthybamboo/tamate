import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'tamate';

  @override
  String get memoListTitle => 'メモ';

  @override
  String get memoListEmpty => 'まだメモがありません';

  @override
  String get memoNewTitle => '新規メモ';

  @override
  String get memoEditTitle => 'メモを編集';

  @override
  String get memoTitleLabel => 'タイトル';

  @override
  String get memoBodyLabel => '本文';

  @override
  String get memoUntitled => '無題のメモ';

  @override
  String get actionSave => '保存';

  @override
  String get actionDelete => '削除';

  @override
  String get actionCancel => 'キャンセル';

  @override
  String get deleteConfirmMessage => 'このメモを削除しますか？';

  @override
  String get errorGeneric => 'エラーが発生しました';
}
