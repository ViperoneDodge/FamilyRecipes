import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n.dart';

enum PaperStyle { righe, quadretti, puntini, liscio }

String paperStyleLabel(PaperStyle p) {
  switch (p) {
    case PaperStyle.righe:
      return tr('paper.lines');
    case PaperStyle.quadretti:
      return tr('paper.grid');
    case PaperStyle.puntini:
      return tr('paper.dots');
    case PaperStyle.liscio:
      return tr('paper.plain');
  }
}

class AppPalette {
  final String key;
  final Color seed;
  const AppPalette(this.key, this.seed);

  String get name => tr('palette.$key');
}

/// Colori caldi da libro di cucina.
const List<AppPalette> palettes = [
  AppPalette('terracotta', Color(0xFFB4532A)),
  AppPalette('tomato', Color(0xFFB8322A)),
  AppPalette('saffron', Color(0xFFC98A12)),
  AppPalette('olive', Color(0xFF6B7536)),
  AppPalette('cinnamon', Color(0xFF8A5A33)),
  AppPalette('wine', Color(0xFF7D2E3E)),
  AppPalette('basil', Color(0xFF4E7442)),
  AppPalette('chestnut', Color(0xFF5E4031)),
];

class ThemeSettings {
  ThemeMode mode;
  int palette;
  PaperStyle paper;
  bool tablecloth;

  ThemeSettings({
    this.mode = ThemeMode.system,
    this.palette = 0,
    this.paper = PaperStyle.righe,
    this.tablecloth = true,
  });

  AppPalette get pal => palettes[palette.clamp(0, palettes.length - 1).toInt()];

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'palette': palette,
        'paper': paper.name,
        'tablecloth': tablecloth,
      };

  factory ThemeSettings.fromJson(Map<String, dynamic>? j) {
    if (j == null) return ThemeSettings();
    ThemeMode mode = ThemeMode.system;
    for (final m in ThemeMode.values) {
      if (m.name == j['mode']) mode = m;
    }
    PaperStyle paper = PaperStyle.righe;
    for (final p in PaperStyle.values) {
      if (p.name == j['paper']) paper = p;
    }
    return ThemeSettings(
      mode: mode,
      palette: (j['palette'] as num?)?.toInt() ?? 0,
      paper: paper,
      tablecloth: j['tablecloth'] as bool? ?? true,
    );
  }
}

class NotebookColors extends ThemeExtension<NotebookColors> {
  final Color cover;
  final Color onCover;
  final Color paper;
  final Color line;
  final Color margin;
  final Color hole;
  final Color ringLight;
  final Color ringDark;
  final Color ink;
  final Color accent;
  final PaperStyle style;
  final bool tablecloth;

  const NotebookColors({
    required this.cover,
    required this.onCover,
    required this.paper,
    required this.line,
    required this.margin,
    required this.hole,
    required this.ringLight,
    required this.ringDark,
    required this.ink,
    required this.accent,
    required this.style,
    required this.tablecloth,
  });

  static NotebookColors of(BuildContext context) =>
      Theme.of(context).extension<NotebookColors>()!;

  @override
  NotebookColors copyWith({
    Color? cover,
    Color? onCover,
    Color? paper,
    Color? line,
    Color? margin,
    Color? hole,
    Color? ringLight,
    Color? ringDark,
    Color? ink,
    Color? accent,
    PaperStyle? style,
    bool? tablecloth,
  }) =>
      NotebookColors(
        cover: cover ?? this.cover,
        onCover: onCover ?? this.onCover,
        paper: paper ?? this.paper,
        line: line ?? this.line,
        margin: margin ?? this.margin,
        hole: hole ?? this.hole,
        ringLight: ringLight ?? this.ringLight,
        ringDark: ringDark ?? this.ringDark,
        ink: ink ?? this.ink,
        accent: accent ?? this.accent,
        style: style ?? this.style,
        tablecloth: tablecloth ?? this.tablecloth,
      );

  @override
  NotebookColors lerp(ThemeExtension<NotebookColors>? other, double t) {
    if (other is! NotebookColors) return this;
    return NotebookColors(
      cover: Color.lerp(cover, other.cover, t)!,
      onCover: Color.lerp(onCover, other.onCover, t)!,
      paper: Color.lerp(paper, other.paper, t)!,
      line: Color.lerp(line, other.line, t)!,
      margin: Color.lerp(margin, other.margin, t)!,
      hole: Color.lerp(hole, other.hole, t)!,
      ringLight: Color.lerp(ringLight, other.ringLight, t)!,
      ringDark: Color.lerp(ringDark, other.ringDark, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      style: t < 0.5 ? style : other.style,
      tablecloth: t < 0.5 ? tablecloth : other.tablecloth,
    );
  }
}

const String handFont = 'PatrickHand';

ThemeData buildTheme(ThemeSettings s, Brightness b) {
  final seed = s.pal.seed;
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: b,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  final hsl = HSLColor.fromColor(seed);
  final cover = dark
      ? hsl.withLightness(0.12).withSaturation((hsl.saturation * 0.45).clamp(0.0, 1.0).toDouble()).toColor()
      : hsl.withLightness((hsl.lightness * 0.85).clamp(0.22, 0.4).toDouble()).toColor();
  final nb = NotebookColors(
    cover: cover,
    onCover: const Color(0xFFFFF8EC),
    // Carta color crema da blocco degli appunti.
    paper: dark ? const Color(0xFF26221D) : const Color(0xFFFFF7E4),
    line: dark ? const Color(0xFF3B352C) : const Color(0xFFE6D3AE),
    margin: dark ? const Color(0xFF7A3A2C) : const Color(0xFFE39A84),
    hole: dark ? const Color(0xFF0E0C0A) : hsl.withLightness(0.14).toColor(),
    ringLight: dark ? const Color(0xFFBDB6AC) : const Color(0xFFF6F2EA),
    ringDark: dark ? const Color(0xFF5E5850) : const Color(0xFF8E867A),
    ink: dark ? const Color(0xFFEFE6D6) : const Color(0xFF3B2A1E),
    accent: dark ? scheme.primary : hsl.withLightness(0.36).toColor(),
    style: s.paper,
    tablecloth: s.tablecloth,
  );

  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: b);
  final hand = base.textTheme.apply(fontFamily: handFont);
  final cardColor = dark ? const Color(0xFF2E2923) : const Color(0xFFFFFBF2);
  return base.copyWith(
    scaffoldBackgroundColor: cover,
    textTheme: base.textTheme.copyWith(
      headlineLarge: hand.headlineLarge,
      headlineMedium: hand.headlineMedium,
      headlineSmall: hand.headlineSmall?.copyWith(fontSize: 30),
      titleLarge: hand.titleLarge?.copyWith(fontSize: 26),
      titleMedium: hand.titleMedium?.copyWith(fontSize: 21),
    ),
    appBarTheme: AppBarTheme(
      systemOverlayStyle: SystemUiOverlayStyle.light,
      backgroundColor: Colors.transparent,
      foregroundColor: nb.onCover,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: handFont, fontSize: 28, color: nb.onCover),
    ),
    cardTheme: CardThemeData(
      color: cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: nb.line),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: cardColor,
      side: BorderSide(color: nb.line),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cardColor,
      border: const OutlineInputBorder(),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cover,
      indicatorColor: nb.paper,
      surfaceTintColor: Colors.transparent,
    ),
    extensions: [nb],
  );
}

/// Sfondo "tovaglia a quadretti" dietro al blocco degli appunti.
class TableclothBackground extends StatelessWidget {
  final Widget child;
  const TableclothBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final nb = NotebookColors.of(context);
    if (!nb.tablecloth) return ColoredBox(color: nb.cover, child: child);
    return CustomPaint(painter: _GinghamPainter(nb.cover), child: child);
  }
}

class _GinghamPainter extends CustomPainter {
  final Color base;
  _GinghamPainter(this.base);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    const q = 18.0;
    final band = Paint()..color = Colors.white.withValues(alpha: 0.055);
    for (var x = 0.0; x < size.width; x += q * 2) {
      canvas.drawRect(Rect.fromLTWH(x, 0, q, size.height), band);
    }
    for (var y = 0.0; y < size.height; y += q * 2) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, q), band);
    }
  }

  @override
  bool shouldRepaint(covariant _GinghamPainter old) => old.base != base;
}

/// Foglio di un blocco degli appunti con la spirale in alto.
class NotebookPage extends StatelessWidget {
  final Widget child;
  final bool lines;
  const NotebookPage({super.key, required this.child, this.lines = true});

  static const double spiral = 26;
  static const double gutter = 30;
  static const double maxPageWidth = 860;

  @override
  Widget build(BuildContext context) {
    final nb = NotebookColors.of(context);
    return LayoutBuilder(builder: (context, box) {
      final extra = box.maxWidth > maxPageWidth ? (box.maxWidth - maxPageWidth) / 2 : 0.0;
      return Padding(
        padding: EdgeInsets.fromLTRB(10 + extra, 10, 10 + extra, 6),
        child: CustomPaint(
          painter: _PagePainter(nb, lines),
          foregroundPainter: _SpiralPainter(nb),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.only(left: gutter, top: spiral),
              child: child,
            ),
          ),
        ),
      );
    });
  }
}

class _PagePainter extends CustomPainter {
  final NotebookColors nb;
  final bool lines;
  _PagePainter(this.nb, this.lines);

  static const _radius = BorderRadius.only(
    topLeft: Radius.circular(3),
    topRight: Radius.circular(3),
    bottomLeft: Radius.circular(10),
    bottomRight: Radius.circular(10),
  );

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Fogli sottostanti, leggermente sfalsati.
    for (var i = 2; i >= 1; i--) {
      final r = _radius.toRRect(Rect.fromLTRB(i * 2.0, 4, size.width - i * 1.0, size.height + i * 2.5));
      canvas.drawRRect(r, Paint()..color = Color.lerp(nb.paper, nb.cover, 0.22 * i)!);
    }
    final page = _radius.toRRect(rect);
    canvas.drawShadow(Path()..addRRect(page), Colors.black, 3, false);
    canvas.drawRRect(page, Paint()..color = nb.paper);

    canvas.save();
    canvas.clipRRect(page);
    final line = Paint()
      ..color = nb.line
      ..strokeWidth = 1;
    const top = NotebookPage.spiral + 8;
    switch (lines ? nb.style : PaperStyle.liscio) {
      case PaperStyle.righe:
        for (var y = top + 22; y < size.height; y += 30) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
        break;
      case PaperStyle.quadretti:
        const q = 22.0;
        for (var y = top; y < size.height; y += q) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
        for (var x = q; x < size.width; x += q) {
          canvas.drawLine(Offset(x, top), Offset(x, size.height), line);
        }
        break;
      case PaperStyle.puntini:
        const q = 20.0;
        final dot = Paint()..color = nb.line;
        for (var y = top; y < size.height; y += q) {
          for (var x = q; x < size.width; x += q) {
            canvas.drawCircle(Offset(x, y), 1.3, dot);
          }
        }
        break;
      case PaperStyle.liscio:
        break;
    }
    // Margine rosso a sinistra.
    final m = Paint()
      ..color = nb.margin
      ..strokeWidth = 1.2;
    const mx = NotebookPage.gutter - 6;
    canvas.drawLine(const Offset(mx, top - 8), Offset(mx, size.height), m);
    // Bordo perforato sotto la spirale.
    final perf = Paint()..color = nb.line.withValues(alpha: 0.9);
    for (var x = 6.0; x < size.width - 4; x += 7) {
      canvas.drawCircle(Offset(x, NotebookPage.spiral + 1), 0.9, perf);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PagePainter old) => old.nb != nb || old.lines != lines;
}

class _SpiralPainter extends CustomPainter {
  final NotebookColors nb;
  _SpiralPainter(this.nb);

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 26.0;
    final count = ((size.width - 28) / spacing).floor();
    if (count <= 0) return;
    final start = (size.width - (count - 1) * spacing) / 2;
    final holePaint = Paint()..color = nb.hole;
    for (var i = 0; i < count; i++) {
      final x = start + i * spacing;
      const holeY = 13.0;
      canvas.drawCircle(Offset(x, holeY), 3.8, holePaint);
      final path = Path()
        ..moveTo(x - 2, holeY)
        ..cubicTo(x - 9, holeY - 6, x - 7, -9, x + 1, -9)
        ..cubicTo(x + 5, -9, x + 6, -4, x + 4, 0);
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 5
            ..color = Colors.black.withValues(alpha: 0.25));
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 3.6
            ..shader = LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [nb.ringDark, nb.ringLight, nb.ringDark],
            ).createShader(Rect.fromLTWH(x - 9, -10, 16, 24)));
    }
  }

  @override
  bool shouldRepaint(covariant _SpiralPainter old) => old.nb != nb;
}
