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
    var color = sel ? nb.paper : (dark ? Color.lerp(base, nb.paper, 0.72)! : base);
    if (back && !sel) color = Color.lerp(color, Colors.black, dark ? 0.0 : 0.05)!;
    final n = count(c);
    final label = c == null ? tr('filter.allShort') : categoryShortLabel(c);
    final ink = sel ? nb.accent : nb.ink.withValues(alpha: n == 0 && c != null ? 0.45 : 0.85);
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
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(c == null ? Icons.menu_book_outlined : categoryIcon(c), size: 16, color: ink),
              const SizedBox(width: 3),
              Text('$n', style: TextStyle(fontSize: 10.5, color: ink.withValues(alpha: 0.8))),
            ]),
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
