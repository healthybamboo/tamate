import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'tamate';

  @override
  String get memoListTitle => 'Memos';

  @override
  String get memoListEmpty => 'No memos yet';

  @override
  String get memoNewTitle => 'New memo';

  @override
  String get memoEditTitle => 'Edit memo';

  @override
  String get memoTitleLabel => 'Title';

  @override
  String get memoBodyLabel => 'Body';

  @override
  String get memoUntitled => 'Untitled memo';

  @override
  String get actionSave => 'Save';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get deleteConfirmMessage => 'Delete this memo?';

  @override
  String get errorGeneric => 'Something went wrong';
}
