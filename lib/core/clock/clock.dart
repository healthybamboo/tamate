import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 現在時刻の取得口。
///
/// 待機の経過はすべて「現在時刻 − 起点」で計算するため、テストから時刻を
/// 差し替えられるように抽象にしてある。
abstract interface class Clock {
  DateTime now();
}

/// 端末の時計をそのまま使う実装。
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

final clockProvider = Provider<Clock>((ref) => const SystemClock());

/// 1秒ごとに現在時刻を流す。カウントダウンの表示にだけ使う。
///
/// 監視されている間しか動かないよう autoDispose にしてある。ロック中・解錠中の
/// メモしか無ければ誰も監視しないので、タイマーも動かない。
final nowProvider = StreamProvider.autoDispose<DateTime>((ref) async* {
  final clock = ref.watch(clockProvider);
  yield clock.now();
  yield* Stream<void>.periodic(const Duration(seconds: 1))
      .map((_) => clock.now());
});

/// 1秒ごとに更新される現在時刻を読む。
///
/// カウントダウンを表示するウィジェットからだけ呼ぶこと。呼ぶとタイマーが動く。
DateTime watchNow(WidgetRef ref) =>
    ref.watch(nowProvider).valueOrNull ?? ref.read(clockProvider).now();
