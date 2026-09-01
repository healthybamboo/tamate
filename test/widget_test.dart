import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamate/app.dart';
import 'package:tamate/core/clock/clock.dart';
import 'package:tamate/features/memo/data/memo_repository.dart';
import 'package:tamate/features/memo/domain/memo.dart';
import 'package:tamate/features/memo/domain/unlock_rule.dart';
import 'package:tamate/features/memo/presentation/open_history_chart.dart';

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

  testWidgets('メモが無いときは、作るところまで案内する', (tester) async {
    await pumpApp(tester);

    expect(find.text('メモ'), findsOneWidget);
    expect(find.text('まだメモがありません'), findsOneWidget);
    expect(find.text('ここに書いたメモは、待たないと読めなくなります'), findsOneWidget);

    await tester.tap(find.text('メモを作る'));
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
    // 見出しの下に、何件あって何が起きているかを出す。
    expect(find.text('1件'), findsOneWidget);
  });

  testWidgets('開くと待機画面になり、待機中も本文は出ない', (tester) async {
    await pumpApp(tester);
    await createMemo(tester, title: '秘密', body: 'ここは読めないはず');

    await tester.tap(find.text('秘密'));
    await tester.pumpAndSettle();

    // 開いた時点で待機が始まる。
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

    clock.advance(const Duration(minutes: 1));
    await tick(tester);

    expect(find.text('ここは読めないはず'), findsOneWidget);
    expect(find.text('この画面を開いている間だけ読めます'), findsOneWidget);
  });

  testWidgets('解錠しても、画面を離れれば閉じる', (tester) async {
    await pumpApp(tester);
    await createMemo(tester, title: '秘密', body: 'ここは読めないはず');

    await tester.tap(find.text('秘密'));
    await tester.pumpAndSettle();
    clock.advance(const Duration(minutes: 1));
    await tick(tester);
    expect(find.text('ここは読めないはず'), findsOneWidget);

    // 一覧に戻ると、その場でロック中に戻る。
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('ここは読めないはず'), findsNothing);
    expect(find.text('ロック中'), findsOneWidget);
  });

  testWidgets('待つのをやめると最初から待ち直しになる', (tester) async {
    await pumpApp(tester);
    await createMemo(tester, title: '秘密', body: 'ここは読めないはず');

    await tester.tap(find.text('秘密'));
    await tester.pumpAndSettle();

    clock.advance(const Duration(seconds: 30));
    await tick(tester);

    await tester.tap(find.text('待つのをやめる'));
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

  testWidgets('待機画面を離れると、待機は最初からやり直しになる', (tester) async {
    await pumpApp(tester);
    await createMemo(tester, title: '秘密', body: 'ここは読めないはず');

    await tester.tap(find.text('秘密'));
    await tester.pumpAndSettle();

    clock.advance(const Duration(seconds: 30));
    await tick(tester);
    expect(find.text('あと30秒'), findsOneWidget);

    // 一覧に戻ると待機そのものが消える。
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('ロック中'), findsOneWidget);

    // 開き直しても、待った30秒は戻らない。
    await tester.tap(find.text('秘密'));
    await tester.pumpAndSettle();
    clock.advance(const Duration(seconds: 30));
    await tick(tester);

    expect(find.text('あと30秒'), findsOneWidget);
    expect(find.text('ここは読めないはず'), findsNothing);
  });

  testWidgets('開封の記録がグラフで出る', (tester) async {
    repository = InMemoryMemoRepository([
      Memo(
        id: 'often',
        title: 'よく開くメモ',
        body: '中身',
        createdAt: clock.now(),
        updatedAt: clock.now(),
        unlockRule: const WaitDurationUnlockRule(Duration(minutes: 1)),
        openedAt: [
          clock.now().subtract(const Duration(days: 1)),
          clock.now().subtract(const Duration(hours: 2)),
        ],
      ),
    ]);

    await pumpApp(tester);
    await tester.tap(find.text('よく開くメモ'));
    await tester.pumpAndSettle();

    expect(find.byType(OpenHistoryChart), findsNothing);

    await tester.tap(find.text('開封の記録'));
    await tester.pumpAndSettle();

    expect(find.byType(OpenHistoryChart), findsOneWidget);
    expect(
      find.text('縦が時刻、横が日付。濃いほど回数が多い。左へ辿ると古い記録'),
      findsOneWidget,
    );
  });

  testWidgets('古い記録があると、その日まで図が伸びる', (tester) async {
    repository = InMemoryMemoRepository([
      Memo(
        id: 'old',
        title: '古いメモ',
        body: '中身',
        createdAt: clock.now(),
        updatedAt: clock.now(),
        unlockRule: const WaitDurationUnlockRule(Duration(minutes: 1)),
        openedAt: [clock.now().subtract(const Duration(days: 100))],
      ),
    ]);

    await pumpApp(tester);
    await tester.tap(find.text('古いメモ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('開封の記録'));
    await tester.pumpAndSettle();

    // 101日ぶんの幅がある（既定の2週間ではない）。
    final painter = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(OpenHistoryChart),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(painter.size.width, 101 * 16);
  });

  testWidgets('問いかけだけのメモは、すべて「はい」で開く', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'タイトル'), '秘密');
    await tester.enterText(find.widgetWithText(TextField, '本文'), 'ここは読めないはず');

    await tester.tap(find.text('問いかけだけ'));
    await tester.pumpAndSettle();

    // 候補から2問入れる。
    await tester.tap(find.text('一年後の自分に、後悔はないですか'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('目を瞑って、本当にそうか確かめましたか'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('秘密'));
    await tester.pumpAndSettle();

    // 待たずに問いへ進む。本文はまだ出ない。
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('ここは読めないはず'), findsNothing);
    // 登録した順に出る。
    expect(find.text('一年後の自分に、後悔はないですか'), findsOneWidget);

    await tester.tap(find.text('はい'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('目を瞑って、本当にそうか確かめましたか'), findsOneWidget);

    await tester.tap(find.text('はい'));
    await tester.pumpAndSettle();

    // 待機時間が無いので、答え終えた時点で読める。
    expect(find.text('ここは読めないはず'), findsOneWidget);
  });

  testWidgets('「いいえ」を選ぶと開かず、ロック中に戻る', (tester) async {
    repository = InMemoryMemoRepository([
      Memo(
        id: 'ask',
        title: '秘密',
        body: 'ここは読めないはず',
        createdAt: clock.now(),
        updatedAt: clock.now(),
        unlockRule: const QuestionUnlockRule(['後悔しませんか']),
      ),
    ]);

    await pumpApp(tester);
    await tester.tap(find.text('秘密'));
    await tester.pumpAndSettle();

    expect(find.text('後悔しませんか'), findsOneWidget);

    await tester.tap(find.text('いいえ'));
    await tester.pumpAndSettle();

    // 一覧に戻され、ロック中のまま。本文はどこにも出ない。
    expect(find.text('開かずに閉じました'), findsOneWidget);
    expect(find.text('ロック中'), findsOneWidget);
    expect(find.text('ここは読めないはず'), findsNothing);
    expect(repository.memos.single.declineCount, 1);
  });

  testWidgets('解錠中なら、編集から待機時間も解錠のしかたも変えられる', (tester) async {
    repository = InMemoryMemoRepository([
      Memo(
        id: 'open',
        title: '開いているメモ',
        body: '中身',
        createdAt: clock.now(),
        updatedAt: clock.now(),
        unlockRule: const WaitDurationUnlockRule(Duration(minutes: 1)),
      ),
    ]);

    await pumpApp(tester);
    await tester.tap(find.text('開いているメモ'));
    await tester.pumpAndSettle();

    // 解錠するまで編集できない。
    clock.advance(const Duration(minutes: 1));
    await tick(tester);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    // 今の設定が初期値として入っている。
    expect(find.text('メモを編集'), findsOneWidget);
    expect(find.text('待機時間'), findsOneWidget);

    await tester.tap(find.text('10分'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(
      repository.memos.single.unlockRule.expectedWait,
      const Duration(minutes: 10),
    );
  });
}
