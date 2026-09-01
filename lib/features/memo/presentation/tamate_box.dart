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

/// 待っている間の絵。箱が少しずつ海に沈んでいく。
///
/// 進み具合をそのまま輪で見せると、ただのタイマーになってしまう。竜宮へ下りていく
/// 時間だと思えるように、[progress] を水位にしてある。波は止めない。
class TamateSea extends StatefulWidget {
  const TamateSea({super.key, required this.progress, this.height = 220});

  /// 待った割合。時間で測れないルールでは null。
  final double? progress;

  /// 絵の高さ。幅は画面いっぱいに広げる。
  final double height;

  @override
  State<TamateSea> createState() => _TamateSeaState();
}

class _TamateSeaState extends State<TamateSea>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waves = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  );

  /// 動かしてよい状況か。端末の「視差効果を減らす」とテストでは止める。
  bool _animate = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = !MediaQuery.disableAnimationsOf(context);
    if (animate == _animate && _waves.isAnimating == animate) {
      return;
    }
    _animate = animate;
    if (animate) {
      _waves.repeat();
    } else {
      _waves.stop();
    }
  }

  @override
  void dispose() {
    _waves.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // 残り時間は1秒ごとにしか変わらないので、水位はその間を補間して上げる。
    // 段で上がると、待っているあいだずっとカクついて見える。
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: widget.progress ?? 0, end: widget.progress ?? 0),
      duration: _animate ? const Duration(seconds: 1) : Duration.zero,
      curve: Curves.linear,
      builder: (context, progress, _) => AnimatedBuilder(
        animation: _waves,
        builder: (context, _) => CustomPaint(
          size: Size(double.infinity, widget.height),
          painter: _TamateSeaPainter(
            progress: progress,
            phase: _waves.value,
            box: scheme.primary,
            water: scheme.primary,
            surface: scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _TamateSeaPainter extends CustomPainter {
  _TamateSeaPainter({
    required this.progress,
    required this.phase,
    required this.box,
    required this.water,
    required this.surface,
  });

  final double progress;
  final double phase;
  final Color box;
  final Color water;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    // 図案は 100 四方。海は横幅いっぱいに広げるので、大きさは高さから決める。
    final unit = size.height * 0.62 / 100;
    final center = Offset(size.width / 2, size.height * 0.36);

    // 箱。沈んでいくので、少しだけ上に置いてある。
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9 * unit
      ..color = box;
    canvas.drawCircle(center, 21 * unit, ring);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          center.dx - 34 * unit,
          center.dy - 4.5 * unit,
          center.dx + 34 * unit,
          center.dy + 4.5 * unit,
        ),
        Radius.circular(4.5 * unit),
      ),
      Paint()..color = box,
    );

    // 水位。待つほど上がってきて、最後は箱を越える。
    final level = size.height * (1.02 - 0.92 * progress.clamp(0.0, 1.0));
    _paintWave(
      canvas,
      size,
      level: level + 5 * unit,
      amplitude: 3.4 * unit,
      wavelength: size.width * 0.75,
      shift: phase,
      color: water.withValues(alpha: 0.20),
    );
    _paintWave(
      canvas,
      size,
      level: level,
      amplitude: 2.4 * unit,
      wavelength: size.width * 0.45,
      shift: -phase * 1.6,
      color: water.withValues(alpha: 0.32),
      surfaceColor: surface.withValues(alpha: 0.45),
    );
  }

  void _paintWave(
    Canvas canvas,
    Size size, {
    required double level,
    required double amplitude,
    required double wavelength,
    required double shift,
    required Color color,
    Color? surfaceColor,
  }) {
    double heightAt(double x) =>
        level + amplitude * math.sin(2 * math.pi * (x / wavelength + shift));

    final path = Path()..moveTo(0, heightAt(0));
    for (var x = 0.0; x <= size.width; x += 2) {
      path.lineTo(x, heightAt(x));
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color);

    if (surfaceColor != null) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.height * 0.008
          ..color = surfaceColor,
      );
    }
  }

  @override
  bool shouldRepaint(_TamateSeaPainter old) =>
      old.progress != progress || old.phase != phase || old.box != box;
}
