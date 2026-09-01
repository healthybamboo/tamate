import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/memo/application/memo_list_notifier.dart';
import 'l10n/generated/app_localizations.dart';

/// アプリのルートウィジェット。
///
/// ライフサイクルの監視をここに置く。画面に紐づかず、アプリが生きている間ずっと
/// 必要なため。
class TamateApp extends ConsumerStatefulWidget {
  const TamateApp({super.key});

  @override
  ConsumerState<TamateApp> createState() => _TamateAppState();
}

class _TamateAppState extends ConsumerState<TamateApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(onResume: _onResume);
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  /// バックグラウンドにいる間も待機は進むので、復帰時に保存内容を読み直す。
  void _onResume() {
    unawaited(ref.read(memoListProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      routerConfig: router,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
