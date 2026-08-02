import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tamate/app.dart';
import 'package:tamate/core/providers/shared_preferences_provider.dart';

void main() {
  testWidgets('起動するとメモ一覧が表示され、新規作成に遷移できる', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ja')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const TamateApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('メモ'), findsOneWidget);
    expect(find.text('まだメモがありません'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('新規メモ'), findsOneWidget);
  });
}
