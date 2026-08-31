import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The branded light hero background used on the auth screens (login, PIN):
/// a soft blue gradient with subtle diagonal stripes and dot grids, in the
/// app's blue palette. Theme-aware (adapts if dark is ever used).
class HeroBackground extends StatelessWidget {
  const HeroBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bgColors = dark
        ? const [Color(0xFF0F1B30), Color(0xFF122340), Color(0xFF0A1120)]
        : const [Color(0xFFF6F8FC), Color(0xFFE7EEF9), Color(0xFFF6F8FC)];
    final stripe = dark ? const Color(0x334A78B4) : const Color(0x1A4A78B4);
    final dot = dark ? const Color(0x296FA0E6) : const Color(0x244A78B4);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: bgColors,
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: CustomPaint(
        painter: _HeroDecorPainter(stripe: stripe, dot: dot),
        size: Size.infinite,
      ),
    );
  }
}

class _HeroDecorPainter extends CustomPainter {
  _HeroDecorPainter({required this.stripe, required this.dot});

  final Color stripe;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    _stripes(canvas, size, topLeft: true);
    _stripes(canvas, size, topLeft: false);
    _dots(canvas, Offset(size.width - 84, 56), 6, 7);
    _dots(canvas, Offset(20, size.height - 150), 6, 6);
  }

  void _stripes(Canvas canvas, Size size, {required bool topLeft}) {
    canvas.save();
    if (topLeft) {
      canvas.translate(-size.width * 0.08, -size.height * 0.05);
    } else {
      canvas.translate(size.width * 1.02, size.height * 1.05);
      canvas.rotate(math.pi);
    }
    canvas.rotate(-0.92);
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 3; i++) {
      final rect = Rect.fromLTWH(i * 34.0, 0, 16, size.height * 0.55);
      paint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [stripe, stripe.withValues(alpha: 0.0)],
      ).createShader(rect);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(10)),
        paint,
      );
    }
    canvas.restore();
  }

  void _dots(Canvas canvas, Offset origin, int cols, int rows) {
    final paint = Paint()..color = dot;
    const gap = 12.0;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        canvas.drawCircle(origin + Offset(c * gap, r * gap), 1.6, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HeroDecorPainter old) =>
      old.stripe != stripe || old.dot != dot;
}
