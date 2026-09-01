import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamate/app.dart';
import 'package:tamate/core/clock/clock.dart';
import 'package:tamate/core/notifications/notification_service.dart';
import 'package:tamate/features/memo/data/memo_repository.dart';

import 'support/fakes.dart';

void main() {
  late FakeClock clock;
  late InMemoryMemoRepository repository;
  late StreamController<DateTime> ticks;

  setUp(() {
    clock = FakeClock(DateTime(2026, 9, 1, 12));
    repository = InMemoryMemoRepository();
    ticks = StreamController<DateTime>.broadcast();
    addTearDown(ticks.close);
  });

  /// 秒ごとの更新をテストから手で起こす。
  Future<void> tick(WidgetTester tester) async {
    ticks.add(clock.now());
    await tester.pumpAndSettle();
  }

  Future<void> pumpApp(WidgetTester tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ja')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          memoRepositoryProvider.overrideWithValue(repository),
          clockProvider.overrideWithValue(clock),
          // 本物は1秒ごとのタイマーで動くので、テストでは手で流す。
          nowProvider.overrideWith((ref) => ticks.stream),
          notificationServiceProvider
              .overrideWithValue(RecordingNotificationService()),
        ],
        child: const TamateApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 一覧から新規メモを1件作る。
  Future<void> createMemo(
    WidgetTester tester, {
    required String title,
    required String body,
    String waitLabel = '1分',
  }) async {
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'タイトル'), title);
    await tester.enterText(find.widgetWithText(TextField, '本文'), body);
    await tester.tap(find.text(waitLabel));
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
  }

  testWidgets('起動するとメモ一覧が表示され、新規作成に遷移できる', (tester) async {
    await pumpApp(tester);

    expect(find.text('メモ'), findsOneWidget);
    expect(find.text('まだメモがありません'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('新規メモ'), findsOneWidget);
    expect(find.text('待機時間'), findsOneWidget);
  });

  testWidgets('作ったメモは一覧でロック中になり、本文が見えない', (tester) async {
    await pumpApp(tester);
    await createMemo(tester, title: '秘密', body: 'ここは読めないはず');

    expect(find.text('秘密'), findsOneWidget);
    expect(find.text('ロック中'), findsOneWidget);
    expect(find.text('ここは読めないはず'), findsNothing);
  });

  testWidgets('開くと待機画面になり、待機中も本文は出ない', (tester) async {
    await pumpApp(tester);
    await createMemo(tester, title: '秘密', body: 'ここは読めないはず');

    await tester.tap(find.text('秘密'));
    await tester.pumpAndSettle();
    expect(find.text('解錠するまで本文は読めません'), findsOneWidget);

    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();

    expect(find.text('待機中'), findsOneWidget);
    expect(find.text('あと1分0秒'), findsOneWidget);
    expect(find.text('ここは読めないはず'), findsNothing);

    clock.advance(const Duration(seconds: 45));
    await tick(tester);

    expect(find.text('あと15秒'), findsOneWidget);
    expect(find.text('ここは読めないはず'), findsNothing);
  });

  testWidgets('待機時間が過ぎると本文が読める', (tester) async {
    await pumpApp(tester);
    await createMemo(tester, title: '秘密', body: 'ここは読めないはず');

    await tester.tap(find.text('秘密'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();

    clock.advance(const Duration(minutes: 1));
    await tick(tester);

    expect(find.text('ここは読めないはず'), findsOneWidget);
    expect(find.text('あと5分0秒読めます'), findsOneWidget);
  });

  testWidgets('閲覧可能時間が過ぎると再びロックされる', (tester) async {
    await pumpApp(tester);
    await createMemo(tester, title: '秘密', body: 'ここは読めないはず');

    await tester.tap(find.text('秘密'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();

    clock.advance(const Duration(minutes: 6));
    await tick(tester);

    expect(find.text('ここは読めないはず'), findsNothing);
    expect(find.text('開く'), findsOneWidget);
  });

  testWidgets('待つのをやめると最初から待ち直しになる', (tester) async {
    await pumpApp(tester);
    await createMemo(tester, title: '秘密', body: 'ここは読めないはず');

    await tester.tap(find.text('秘密'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();

    clock.advance(const Duration(seconds: 30));
    await tick(tester);

    await tester.tap(find.text('待つのをやめる'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('開く'), findsOneWidget);

    // やめた時点で計測はリセットされるので、残り30秒では解錠しない。
    clock.advance(const Duration(seconds: 30));
    await tick(tester);
    expect(find.text('ここは読めないはず'), findsNothing);
  });
}
