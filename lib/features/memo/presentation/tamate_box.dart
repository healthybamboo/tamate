import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 玉手箱の図。アプリアイコンと同じ形を画面の中でも使う。
///
/// 円は箱、横棒は蓋の合わせ目。待っている間は円が [progress] のぶんだけ描かれ、
/// 解錠すると蓋が浮く。開けてしまったことが図で分かるようにするため。
class TamateBox extends StatelessWidget {
  const TamateBox({
    super.key,
    this.size = 96,
    this.progress,
    this.open = false,
    this.dimmed = false,
  });

  final double size;

  /// 待機の進み具合。null なら輪郭をそのまま描く。
  final double? progress;

  /// 蓋が開いているか。
  final bool open;

  /// ロック中のように、控えめに見せたいとき。
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return CustomPaint(
      size: Size.square(size),
      painter: _TamateBoxPainter(
        color: dimmed ? scheme.onSurfaceVariant : scheme.primary,
        trackColor: scheme.outlineVariant,
        progress: progress,
        open: open,
      ),
    );
  }
}

class _TamateBoxPainter extends CustomPainter {
  _TamateBoxPainter({
    required this.color,
    required this.trackColor,
    required this.progress,
    required this.open,
  });

  final Color color;
  final Color trackColor;
  final double? progress;
  final bool open;

  @override
  void paint(Canvas canvas, Size size) {
    // アイコンと同じ 100 四方の図案を、渡された大きさに合わせる。
    final unit = size.width / 100;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = 21 * unit;
    final stroke = 9 * unit;

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final done = progress;
    if (done == null) {
      canvas.drawCircle(center, radius, ring..color = color);
    } else {
      // 残りは薄く、進んだぶんだけ濃く。待つほど箱が形になる。
      canvas.drawCircle(center, radius, ring..color = trackColor);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * done.clamp(0.0, 1.0),
        false,
        ring..color = color,
      );
    }

    // 蓋の合わせ目。開いていれば浮かせて傾ける。
    final lid = Paint()..color = color;
    final lidRect = Rect.fromLTRB(
      16 * unit,
      45.5 * unit,
      84 * unit,
      54.5 * unit,
    );

    canvas.save();
    if (open) {
      canvas.translate(0, -13 * unit);
      canvas.translate(center.dx, center.dy);
      canvas.rotate(-0.09);
      canvas.translate(-center.dx, -center.dy);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(lidRect, Radius.circular(stroke / 2)),
      lid,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TamateBoxPainter old) =>
      old.color != color ||
      old.trackColor != trackColor ||
      old.progress != progress ||
      old.open != open;
}
