import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamate/app.dart';
import 'package:tamate/core/clock/clock.dart';
import 'package:tamate/core/notifications/notification_service.dart';
import 'package:tamate/features/memo/data/memo_repository.dart';
import 'package:tamate/features/memo/domain/memo.dart';
import 'package:tamate/features/memo/domain/unlock_rule.dart';

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

  testWidgets('生成した4桁のコードは、保存すると待たないと読めない', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'タイトル'),
      'スクリーンタイム',
    );
    await tester.tap(find.text('1分'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('4桁のコードを生成'));
    await tester.pumpAndSettle();

    // 設定先に入力できるよう、保存するまでは見えている。
    final generated = tester
        .widget<TextField>(find.widgetWithText(TextField, '本文'))
        .controller!
        .text;
    expect(generated, matches(RegExp(r'^\d{4}$')));
    expect(find.text(generated), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // 保存した時点でロックされ、一覧からも詳細からも読めない。
    expect(find.text(generated), findsNothing);
    await tester.tap(find.text('スクリーンタイム'));
    await tester.pumpAndSettle();
    expect(find.text(generated), findsNothing);

    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    clock.advance(const Duration(minutes: 1));
    await tick(tester);

    expect(find.text(generated), findsOneWidget);
  });

  testWidgets('開いた回数が記録され、増えると待機時間をのばす提案が出る', (tester) async {
    final openedAt = [
      for (var i = 0; i < 3; i++) clock.now().subtract(Duration(hours: i + 1)),
    ];
    repository = InMemoryMemoRepository([
      Memo(
        id: 'often',
        title: 'よく開くメモ',
        body: '中身',
        createdAt: clock.now(),
        updatedAt: clock.now(),
        unlockRule: const WaitDurationUnlockRule(Duration(minutes: 1)),
        openedAt: openedAt,
      ),
    ]);

    await pumpApp(tester);
    await tester.tap(find.text('よく開くメモ'));
    await tester.pumpAndSettle();

    expect(find.text('3回開いた'), findsOneWidget);

    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    clock.advance(const Duration(minutes: 1));
    await tick(tester);

    expect(find.text('よく開いていますね'), findsOneWidget);
    expect(find.text('待機時間を3分にしますか？'), findsOneWidget);

    await tester.tap(find.text('のばす'));
    await tester.pumpAndSettle();

    expect(find.text('次からは3分待ちます'), findsOneWidget);
    expect(find.text('よく開いていますね'), findsNothing);
    // 開封の記録は解錠のたびに増える。
    expect(find.text('4回開いた'), findsOneWidget);
  });
}
