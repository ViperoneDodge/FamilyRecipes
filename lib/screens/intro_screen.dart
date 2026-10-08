import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme.dart';

/// Schermata di avvio: il logo compare al centro su fondo crema.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
    ..forward();

  static const Color cream = Color(0xFFFEF6E8);
  static const Color terracotta = Color(0xFFD9653F);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appear = CurvedAnimation(parent: _c, curve: const Interval(0.0, 0.35, curve: Curves.easeOut));
    final pop = CurvedAnimation(parent: _c, curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack));
    final text = CurvedAnimation(parent: _c, curve: const Interval(0.45, 0.85, curve: Curves.easeOut));
    return Scaffold(
      backgroundColor: cream,
      body: SizedBox.expand(
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => LayoutBuilder(builder: (context, box) {
              final logo = (box.maxWidth * 0.7).clamp(180.0, 340.0).clamp(0.0, box.maxHeight * 0.55).toDouble();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Spacer(flex: 3),
                  Opacity(
                    opacity: appear.value.clamp(0.0, 1.0).toDouble(),
                    child: Transform.scale(
                      scale: 0.8 + 0.2 * pop.value,
                      child: Image.asset('assets/logo.png', width: logo, height: logo),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Opacity(
                    opacity: text.value.clamp(0.0, 1.0).toDouble(),
                    child: Transform.translate(
                      offset: Offset(0, 16 * (1 - text.value)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(tr('intro.tagline'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontFamily: handFont, fontSize: 26, color: terracotta)),
                      ),
                    ),
                  ),
                  const Spacer(flex: 4),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}
