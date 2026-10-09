import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';

/// Colore della linguetta di ogni categoria (toni caldi da ricettario).
Color categoryTabColor(RecipeCategory? c) {
  switch (c) {
    case null:
      return const Color(0xFFE6D3AE);
    case RecipeCategory.aperitivi:
      return const Color(0xFFF4C9A3);
    case RecipeCategory.antipasti:
      return const Color(0xFFEBD89A);
    case RecipeCategory.primi:
      return const Color(0xFFF2B47D);
    case RecipeCategory.secondi:
      return const Color(0xFFDDA08C);
    case RecipeCategory.contorni:
      return const Color(0xFFCCD69C);
    case RecipeCategory.dolci:
      return const Color(0xFFF2BDB3);
    case RecipeCategory.liquori:
      return const Color(0xFFDAB8CB);
    case RecipeCategory.conserve:
      return const Color(0xFFE7A974);
    case RecipeCategory.menu:
      return const Color(0xFFCDBBA0);
  }
}

/// In modalità scura: stesso colore ma più profondo, così la linguetta si stacca dal foglio scuro
/// e il testo chiaro resta leggibile.
Color categoryTabColorDark(Color base) {
  final h = HSLColor.fromColor(base);
  return h.withLightness(0.34).withSaturation((h.saturation * 0.75).clamp(0.3, 0.6).toDouble()).toColor();
}

/// Linguette in stile rubrica, su due righe: "Tutte" più una per categoria.
/// La linguetta scelta ha il colore del foglio; quelle della seconda riga
/// poggiano sul foglio, quelle della prima stanno "dietro".
class CategoryTabs extends StatelessWidget {
  final RecipeCategory? selected;
  final ValueChanged<RecipeCategory?> onSelected;

  /// Numero di ricette per categoria (null = tutte).
  final int Function(RecipeCategory? c) count;

  const CategoryTabs({super.key, required this.selected, required this.onSelected, required this.count});

  static const List<RecipeCategory?> _back = [
    null,
    RecipeCategory.aperitivi,
    RecipeCategory.antipasti,
    RecipeCategory.primi,
    RecipeCategory.secondi,
  ];
  static const List<RecipeCategory?> _front = [
    RecipeCategory.contorni,
    RecipeCategory.dolci,
    RecipeCategory.liquori,
    RecipeCategory.conserve,
    RecipeCategory.menu,
  ];

  @override
  Widget build(BuildContext context) {
    final nb = NotebookColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget row(List<RecipeCategory?> cats, {required bool back}) => Padding(
          padding: EdgeInsets.symmetric(horizontal: back ? 8 : 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final c in cats) Expanded(child: _tab(context, c, nb, dark, back: back)),
          ]),
        );
    return Stack(children: [
      Positioned(left: 0, right: 0, bottom: 0, child: Container(height: 1.5, color: nb.line)),
      Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        row(_back, back: true),
        row(_front, back: false),
      ]),
    ]);
  }

  Widget _tab(BuildContext context, RecipeCategory? c, NotebookColors nb, bool dark, {required bool back}) {
    final sel = selected == c;
    final base = categoryTabColor(c);
    var color = sel ? nb.paper : (dark ? categoryTabColorDark(base) : base);
    if (back && !sel) color = Color.lerp(color, Colors.black, dark ? 0.0 : 0.05)!;
    final n = count(c);
    final label = c == null ? tr('filter.allShort') : categoryShortLabel(c);
    final ink = sel ? nb.accent : (dark ? Colors.white : nb.ink).withValues(alpha: n == 0 && c != null ? 0.5 : 0.92);
    final h = back ? 44.0 : 48.0;
    return Semantics(
      button: true,
      selected: sel,
      label: '${c == null ? label : categoryLabel(c)} ($n)',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => onSelected(c),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: sel ? h + 4 : h,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 3),
          decoration: ShapeDecoration(
            color: color,
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              side: BorderSide(color: nb.line, width: 1.2),
            ),
          ),
          foregroundDecoration: sel && !back
              ? UnderlineTabIndicator(
                  borderSide: BorderSide(color: nb.paper, width: 2.5),
                  insets: const EdgeInsets.symmetric(horizontal: 1.2))
              : null,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(c == null ? Icons.menu_book_outlined : categoryIcon(c), size: 16, color: ink),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label,
                  maxLines: 1, style: TextStyle(fontFamily: handFont, fontSize: 17, height: 1.05, color: ink)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Nome breve per le linguette ("Menù" invece di "Menù completi").
String categoryShortLabel(RecipeCategory c) => c == RecipeCategory.menu ? tr('cat.menuShort') : categoryLabel(c);

/// Linguette verticali sul bordo destro del foglio, con il testo ruotato.
class VerticalCategoryTabs extends StatelessWidget {
  final RecipeCategory? selected;
  final ValueChanged<RecipeCategory?> onSelected;
  final int Function(RecipeCategory? c) count;

  const VerticalCategoryTabs({super.key, required this.selected, required this.onSelected, required this.count});

  static const double width = 40;

  @override
  Widget build(BuildContext context) {
    final nb = NotebookColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: width,
      child: Stack(children: [
        Positioned(left: 0, top: 0, bottom: 0, child: Container(width: 1.5, color: nb.line)),
        Column(children: [
          for (final c in <RecipeCategory?>[null, ...RecipeCategory.values])
            Expanded(child: _tab(context, c, nb, dark)),
        ]),
      ]),
    );
  }

  Widget _tab(BuildContext context, RecipeCategory? c, NotebookColors nb, bool dark) {
    final sel = selected == c;
    final base = categoryTabColor(c);
    final color = sel ? nb.paper : (dark ? categoryTabColorDark(base) : base);
    final n = count(c);
    final label = c == null ? tr('filter.allShort') : categoryShortLabel(c);
    final ink = sel ? nb.accent : (dark ? Colors.white : nb.ink).withValues(alpha: n == 0 && c != null ? 0.5 : 0.92);
    return Semantics(
      button: true,
      selected: sel,
      label: '${c == null ? label : categoryLabel(c)} ($n)',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => onSelected(c),
        child: Align(
          alignment: Alignment.centerLeft,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: sel ? VerticalCategoryTabs.width : VerticalCategoryTabs.width - 5,
            margin: const EdgeInsets.symmetric(vertical: 1.2),
            padding: const EdgeInsets.fromLTRB(2, 4, 3, 4),
            decoration: ShapeDecoration(
              color: color,
              shape: RoundedRectangleBorder(
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(11)),
                side: BorderSide(color: nb.line, width: 1.2),
              ),
            ),
            foregroundDecoration: sel ? _LeftEdgeCover(nb.paper) : null,
            child: LayoutBuilder(builder: (context, box) {
              final showIcon = box.maxHeight >= 64;
              return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (showIcon) ...[
                  Icon(c == null ? Icons.menu_book_outlined : categoryIcon(c), size: 15, color: ink),
                  const SizedBox(height: 2),
                ],
                Flexible(
                  child: RotatedBox(
                    quarterTurns: 1,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(label,
                          maxLines: 1, style: TextStyle(fontFamily: handFont, fontSize: 13.5, height: 1.0, color: ink)),
                    ),
                  ),
                ),
              ]);
            }),
          ),
        ),
      ),
    );
  }
}

/// Copre il bordo sinistro della linguetta scelta, che così sembra unita al foglio.
class _LeftEdgeCover extends Decoration {
  final Color color;
  const _LeftEdgeCover(this.color);

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _LeftEdgePainter(color);
}

class _LeftEdgePainter extends BoxPainter {
  final Color color;
  _LeftEdgePainter(this.color);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size!;
    canvas.drawRect(Rect.fromLTWH(offset.dx, offset.dy + 1.2, 2.5, size.height - 2.4), Paint()..color = color);
  }
}
