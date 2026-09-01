import 'dart:async';

import 'package:google_fonts/google_fonts.dart';

/// テストからはフォントを取りに行かせない。
///
/// ネットワークに触れずに済み、実行のたびに結果が変わることもなくなる。
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  await testMain();
}
