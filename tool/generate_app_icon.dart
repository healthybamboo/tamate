import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// アプリアイコンの画像を作る。
///
/// 図案は玉手箱を横から見た形（蓋の合わせ目が一本通った箱）。もとは SVG で、
/// 円と横棒だけでできているので、そのまま描き直している。
/// `flutter test tool/generate_app_icon.dart` で `assets/icon/` に書き出す。
void main() {
  const size = 1024.0;
  const background = Color(0xFF1B1F2A);
  const glyph = Color(0xFFC4A87C);

  test('アイコンの画像を書き出す', () async {
    await _write('assets/icon/app_icon.png', size, (canvas) {
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, size, size),
        Paint()..color = background,
      );
      _paintGlyph(canvas, size, glyph, scale: 1);
    });

    // Android のアダプティブアイコンは、内側 66% しか安全に見えない。
    await _write(
      'assets/icon/app_icon_foreground.png',
      size,
      (canvas) => _paintGlyph(canvas, size, glyph, scale: 0.6),
    );
  });
}

/// 100 四方で描かれた図案を、[size] の画布に [scale] 倍で置く。
void _paintGlyph(
  Canvas canvas,
  double size,
  Color color, {
  required double scale,
}) {
  final unit = size / 100 * scale;
  final origin = size * (1 - scale) / 2;
  Offset at(double x, double y) => Offset(origin + x * unit, origin + y * unit);

  final paint = Paint()..color = color;

  // 蓋を開けようとしている箱の輪郭。
  canvas.drawCircle(
    at(50, 50),
    21 * unit,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9 * unit,
  );

  // 合わせ目。
  canvas.drawRect(
    Rect.fromPoints(at(16, 45.5), at(84, 54.5)),
    paint,
  );
}

Future<void> _write(
  String path,
  double size,
  void Function(Canvas canvas) paint,
) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final image =
      await recorder.endRecording().toImage(size.toInt(), size.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  expect(await file.length(), greaterThan(0));
  // ignore: avoid_print
  print(file.path);
}
