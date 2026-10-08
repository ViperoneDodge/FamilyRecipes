import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models.dart';
import '../theme.dart';

final DateFormat dateFmt = DateFormat('dd/MM/yyyy');

String fmtDate(DateTime? d) => d == null ? '—' : dateFmt.format(d);

void showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

IconData categoryIcon(RecipeCategory c) {
  switch (c) {
    case RecipeCategory.aperitivi:
      return Icons.local_bar;
    case RecipeCategory.antipasti:
      return Icons.tapas;
    case RecipeCategory.primi:
      return Icons.ramen_dining;
    case RecipeCategory.secondi:
      return Icons.set_meal;
    case RecipeCategory.contorni:
      return Icons.eco;
    case RecipeCategory.dolci:
      return Icons.cake;
    case RecipeCategory.liquori:
      return Icons.liquor;
    case RecipeCategory.conserve:
      return Icons.kitchen;
    case RecipeCategory.menu:
      return Icons.restaurant_menu;
  }
}

IconData difficultyIcon(Difficulty d) {
  switch (d) {
    case Difficulty.veryEasy:
    case Difficulty.easy:
      return Icons.sentiment_satisfied_alt;
    case Difficulty.medium:
      return Icons.sentiment_neutral;
    case Difficulty.hard:
      return Icons.whatshot;
  }
}

/// Foto di una ricetta: dal telefono o, se manca, scaricata dal ricettario.
class RecipePhoto extends StatefulWidget {
  final String photoId;
  final Recipe recipe;
  final BoxFit fit;
  final double? width;
  final double? height;
  const RecipePhoto({
    super.key,
    required this.photoId,
    required this.recipe,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  @override
  State<RecipePhoto> createState() => _RecipePhotoState();
}

class _RecipePhotoState extends State<RecipePhoto> {
  late Future<Uint8List?> _f;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RecipePhoto old) {
    super.didUpdateWidget(old);
    if (old.photoId != widget.photoId) _load();
  }

  void _load() {
    _f = appState.photos.load(widget.photoId, bookId: appState.bookOf(widget.recipe));
  }

  @override
  Widget build(BuildContext context) {
    final cached = appState.photos.cached(widget.photoId);
    final scheme = Theme.of(context).colorScheme;
    Widget img(Uint8List b) =>
        Image.memory(b, fit: widget.fit, width: widget.width, height: widget.height, gaplessPlayback: true);
    if (cached != null) return img(cached);
    return FutureBuilder<Uint8List?>(
      future: _f,
      builder: (context, snap) {
        final b = snap.data;
        if (b != null) return img(b);
        return Container(
          width: widget.width,
          height: widget.height,
          color: scheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: snap.connectionState == ConnectionState.done
              ? Icon(Icons.image_not_supported_outlined, color: scheme.outline)
              : const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
    );
  }
}

/// Miniatura della ricetta: foto oppure icona della categoria.
class RecipeThumb extends StatelessWidget {
  final Recipe recipe;
  final double size;
  const RecipeThumb({super.key, required this.recipe, this.size = 64});

  @override
  Widget build(BuildContext context) {
    final nb = NotebookColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final t = recipe.thumbnail;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.18),
      child: SizedBox(
        width: size,
        height: size,
        child: t != null
            ? RecipePhoto(photoId: t, recipe: recipe, width: size, height: size)
            : ColoredBox(
                color: Color.alphaBlend(nb.accent.withValues(alpha: 0.14), nb.paper),
                child: Icon(categoryIcon(recipe.category), size: size * 0.5, color: scheme.primary),
              ),
      ),
    );
  }
}

class SmallTag extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const SmallTag({super.key, required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: c),
      const SizedBox(width: 3),
      Flexible(
        child: Text(text, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c)),
      ),
    ]);
  }
}

class RecipeCard extends StatelessWidget {
  final Recipe recipe;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Nome del gruppo, mostrato come etichetta.
  final String? badge;
  final bool showCategory;
  final bool selected;

  const RecipeCard({
    super.key,
    required this.recipe,
    required this.onTap,
    this.onLongPress,
    this.badge,
    this.showCategory = true,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = recipe;
    final scheme = Theme.of(context).colorScheme;
    final nb = NotebookColors.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      clipBehavior: Clip.antiAlias,
      color: selected ? scheme.secondaryContainer : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            RecipeThumb(recipe: r, size: 66),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (showCategory)
                  Text(categoryLabel(r.category).toUpperCase(),
                      style:
                          TextStyle(fontSize: 10.5, letterSpacing: 1.1, color: nb.accent, fontWeight: FontWeight.w600)),
                Text(r.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 22, fontFamily: handFont, height: 1.1, color: nb.ink)),
                const SizedBox(height: 4),
                Wrap(spacing: 10, runSpacing: 2, children: [
                  SmallTag(icon: difficultyIcon(r.difficulty), text: difficultyLabel(r.difficulty)),
                  if (r.totalMinutes > 0) SmallTag(icon: Icons.schedule, text: fmtMinutes(r.totalMinutes)),
                  if (badge != null) SmallTag(icon: Icons.groups_outlined, text: badge!, color: scheme.tertiary),
                ]),
              ]),
            ),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? hint;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.hint, this.action});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 60, left: 12, right: 12),
      child: Column(children: [
        Icon(icon, size: 72, color: scheme.outline),
        const SizedBox(height: 12),
        Text(title,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 26, fontFamily: handFont, color: NotebookColors.of(context).ink)),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint!, textAlign: TextAlign.center),
        ],
        if (action != null) ...[const SizedBox(height: 16), action!],
      ]),
    );
  }
}

/// Titolo di sezione scritto a mano, sottolineato.
class HandHeader extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Widget? trailing;
  const HandHeader(this.text, {super.key, this.icon, this.trailing});

  @override
  Widget build(BuildContext context) {
    final nb = NotebookColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Row(children: [
        if (icon != null) ...[Icon(icon, color: nb.accent, size: 22), const SizedBox(width: 6)],
        Expanded(
          child: Text(text,
              style: TextStyle(
                fontFamily: handFont,
                fontSize: 26,
                height: 1.1,
                color: nb.accent,
                decoration: TextDecoration.underline,
                decorationColor: nb.accent.withValues(alpha: 0.35),
                decorationThickness: 2,
              )),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}
