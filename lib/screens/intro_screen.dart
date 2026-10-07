import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme.dart';

/// Schermata di avvio: il blocco delle ricette compare e il vapore sale dalla pentola.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1900))..forward();

  static const Color _bg = Color(0xFFB4532A);
  static const Color _bgDark = Color(0xFF6E2E15);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appear = CurvedAnimation(parent: _c, curve: const Interval(0.0, 0.25, curve: Curves.easeOut));
    final pop = CurvedAnimation(parent: _c, curve: const Interval(0.0, 0.45, curve: Curves.easeOutBack));
    final text = CurvedAnimation(parent: _c, curve: const Interval(0.35, 0.75, curve: Curves.easeOut));
    final steam = CurvedAnimation(parent: _c, curve: const Interval(0.4, 1.0, curve: Curves.easeInOut));
    return Scaffold(
      backgroundColor: _bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bg, _bg, _bgDark],
            stops: [0, 0.45, 1],
          ),
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              return LayoutBuilder(builder: (context, box) {
                final iconSize = (box.maxHeight * 0.2).clamp(80.0, 140.0).toDouble();
                return Column(children: [
                  const Spacer(flex: 3),
                  Opacity(
                    opacity: appear.value.clamp(0.0, 1.0).toDouble(),
                    child: Transform.scale(
                      scale: 0.7 + 0.3 * pop.value,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(iconSize * 0.23),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35 * appear.value),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(iconSize * 0.23),
                          child: Image.asset('assets/icon.png', width: iconSize, height: iconSize),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Opacity(
                    opacity: text.value.clamp(0.0, 1.0).toDouble(),
                    child: Transform.translate(
                      offset: Offset(0, 20 * (1 - text.value)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('FamilyRecipes',
                                maxLines: 1,
                                style: TextStyle(
                                    fontFamily: handFont,
                                    fontSize: 46,
                                    color: Color(0xFFFFF7E4),
                                    letterSpacing: 0.5)),
                          ),
                          const SizedBox(height: 4),
                          Text(tr('intro.tagline'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontFamily: handFont, fontSize: 22, color: Color(0xCCFFF7E4))),
                        ]),
                      ),
                    ),
                  ),
                  const Spacer(flex: 4),
                  SizedBox(
                    height: 90,
                    width: 120,
                    child: CustomPaint(painter: _PotPainter(steam.value)),
                  ),
                  const SizedBox(height: 32),
                ]);
              });
            },
          ),
        ),
      ),
    );
  }
}

class _PotPainter extends CustomPainter {
  final double t;
  _PotPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final cream = const Color(0xFFFFF7E4);
    final pot = Paint()..color = cream.withValues(alpha: 0.9);
    final w = size.width;
    final h = size.height;
    final body = RRect.fromRectAndCorners(
      Rect.fromLTWH(w * 0.2, h * 0.58, w * 0.6, h * 0.36),
      bottomLeft: const Radius.circular(12),
      bottomRight: const Radius.circular(12),
    );
    canvas.drawRRect(body, pot);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.14, h * 0.54, w * 0.72, h * 0.07), const Radius.circular(4)),
        pot);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.06, h * 0.64, w * 0.1, h * 0.05), const Radius.circular(3)),
        pot);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.84, h * 0.64, w * 0.1, h * 0.05), const Radius.circular(3)),
        pot);
    final steam = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3
      ..color = cream.withValues(alpha: 0.7 * t);
    for (var i = 0; i < 3; i++) {
      final x = w * (0.35 + i * 0.15);
      final top = h * 0.5 - h * 0.42 * t;
      final path = Path()..moveTo(x, h * 0.5);
      const segs = 12;
      for (var k = 1; k <= segs; k++) {
        final y = h * 0.5 - (h * 0.5 - top) * k / segs;
        path.lineTo(x + math.sin(k / segs * math.pi * 2 + i + t * 6) * 5, y);
      }
      canvas.drawPath(path, steam);
    }
  }

  @override
  bool shouldRepaint(covariant _PotPainter old) => old.t != t;
}
