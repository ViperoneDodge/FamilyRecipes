import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'family_screen.dart';
import 'recipe_edit_screen.dart';

class RecipeDetailScreen extends StatefulWidget {
  final String recipeId;

  /// Le ricette dell'elenco da cui si è aperta, nello stesso ordine: con lo swipe si sfogliano.
  final List<String> sequence;
  final bool embedded;
  final VoidCallback? onClosed;
  final ValueChanged<String>? onRecipeChanged;
  const RecipeDetailScreen({
    super.key,
    required this.recipeId,
    this.sequence = const [],
    this.embedded = false,
    this.onClosed,
    this.onRecipeChanged,
  });

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> with SingleTickerProviderStateMixin {
  late String _id = widget.recipeId;

  /// Durante lo sfoglio: la ricetta che arriva e il verso (+1 successiva, -1 precedente).
  String? _other;
  int _dir = 0;
  late final AnimationController _flip =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 480));

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  List<String> get _seq => [for (final id in widget.sequence) if (appState.recipeById(id) != null) id];

  void _go(int dir) {
    if (_flip.isAnimating) return;
    final seq = _seq;
    final j = seq.indexOf(_id) + dir;
    if (j < 0 || j >= seq.length || seq.indexOf(_id) < 0) return;
    setState(() {
      _other = seq[j];
      _dir = dir;
    });
    _flip.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _id = _other ?? _id;
        _other = null;
        _dir = 0;
      });
      _flip.value = 0;
      widget.onRecipeChanged?.call(_id);
    });
  }

  void _onSwipe(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v < -250) _go(1);
    if (v > 250) _go(-1);
  }

  /// Il foglio che gira attorno agli anelli in alto: `t` va da 0 (steso) a 1 (di taglio, sparito).
  Widget _lifted(Widget sheet, double t) {
    if (t >= 0.999) return const SizedBox.shrink();
    return Transform(
      alignment: Alignment.topCenter,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0009)
        ..rotateX(-t * math.pi / 2),
      child: Stack(fit: StackFit.expand, children: [
        sheet,
        IgnorePointer(child: ColoredBox(color: Colors.black.withValues(alpha: 0.28 * t))),
      ]),
    );
  }

  Widget _pages(BuildContext context, Widget Function(Widget) sheet, Recipe r) {
    return GestureDetector(
      onHorizontalDragEnd: _onSwipe,
      child: AnimatedBuilder(
        animation: _flip,
        builder: (context, _) {
          final o = _other == null ? null : appState.recipeById(_other!);
          if (o == null) return sheet(_body(context, r));
          final t = Curves.easeInOutCubic.transform(_flip.value);
          return Stack(fit: StackFit.expand, children: _dir > 0
              ? [sheet(_body(context, o)), _lifted(sheet(_body(context, r)), t)]
              : [sheet(_body(context, r)), _lifted(sheet(_body(context, o)), 1 - t)]);
        },
      ),
    );
  }

  Future<void> _delete(Recipe r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('recipe.deleteTitle')),
        content: Text(tr(appState.isPersonal(r) ? 'recipe.deleteBody' : 'recipe.deleteBodyGroup',
            {'name': r.displayTitle, 'group': appState.bookLabel(r)})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('common.cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('common.delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await appState.deleteRecipe(r.id);
    if (widget.embedded) {
      widget.onClosed?.call();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _edit(Recipe r) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => RecipeEditScreen(recipe: r.copy())));

  void _openPhoto(Recipe r, List<String> photos, int index) => Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PhotoViewer(recipe: r, photos: photos, initial: index),
      ));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final r = appState.recipeById(_id);
        if (r == null) {
          return TableclothBackground(
            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(automaticallyImplyLeading: !widget.embedded),
              body: NotebookPage(child: Center(child: Text(tr('recipe.gone')))),
            ),
          );
        }
        final canEdit = appState.canEdit(r);
        final scaffold = Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            automaticallyImplyLeading: !widget.embedded,
            title: Text(categoryLabel(r.category)),
            actions: [
              IconButton(
                tooltip: tr('pdf.exportRecipe'),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                onPressed: () => exportPdf(context, r.displayTitle, [r]),
              ),
              if (canEdit)
                IconButton(tooltip: tr('common.edit'), icon: const Icon(Icons.edit), onPressed: () => _edit(r)),
              PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'move':
                      moveRecipeSheet(context, r);
                      break;
                    case 'copy':
                      copyToMine(context, r);
                      break;
                    case 'delete':
                      _delete(r);
                      break;
                  }
                },
                itemBuilder: (ctx) => [
                  if (appState.isCloud && canEdit)
                    PopupMenuItem(value: 'move', child: Text(tr('recipe.moveMenu'))),
                  if (!appState.isPersonal(r)) PopupMenuItem(value: 'copy', child: Text(tr('recipe.copyMine'))),
                  if (canEdit) PopupMenuItem(value: 'delete', child: Text(tr('common.delete'))),
                ],
              ),
            ],
          ),
          body: NotebookPage.sheets(builder: (context, sheet) => _pages(context, sheet, r)),
        );
        return widget.embedded ? scaffold : TableclothBackground(child: scaffold);
      },
    );
  }

  Widget _body(BuildContext context, Recipe r) {
    final nb = NotebookColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final ink = TextStyle(color: nb.ink, fontSize: 16, height: 1.45);
    final courses = r.courses.map(appState.recipeById).whereType<Recipe>().toList();
    final cover = r.coverPhoto;
    final seq = _seq;
    final pos = seq.indexOf(r.id);
    return ListView(
      key: PageStorageKey('recipe-${r.id}'),
      padding: const EdgeInsets.fromLTRB(6, 6, 12, 40),
      children: [
        Text([categoryLabel(r.category).toUpperCase(), if (pos >= 0 && seq.length > 1) '${pos + 1} / ${seq.length}'].join('  ·  '),
            style: TextStyle(fontSize: 12, letterSpacing: 1.3, color: nb.accent, fontWeight: FontWeight.w700)),
        Text(r.displayTitle, style: TextStyle(fontFamily: handFont, fontSize: 38, height: 1.1, color: nb.ink)),
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 10),
          child: Wrap(spacing: 12, runSpacing: 2, children: [
            if (r.createdByName.isNotEmpty)
              SmallTag(icon: Icons.person_outline, text: tr('recipe.by', {'name': r.createdByName})),
            if (appState.isCloud) SmallTag(icon: Icons.menu_book_outlined, text: appState.bookLabel(r)),
          ]),
        ),
        if (cover != null)
          GestureDetector(
            onTap: () => _openPhoto(r, [cover], 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(aspectRatio: 4 / 3, child: RecipePhoto(photoId: cover, recipe: r)),
            ),
          ),
        const SizedBox(height: 10),
        _InfoGrid(recipe: r),
        if (r.intro.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(r.intro.trim(), style: ink),
        ],
        if (r.category == RecipeCategory.menu && courses.isNotEmpty) ...[
          HandHeader(tr('recipe.courses'), icon: Icons.restaurant_menu),
          for (final c in courses)
            RecipeCard(
              recipe: c,
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipeId: c.id))),
            ),
        ],
        if (r.ingredients.isNotEmpty) ...[
          HandHeader(tr('recipe.ingredients'), icon: Icons.shopping_basket_outlined),
          if (r.servings > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(tr('recipe.dosesFor', {'n': r.servings}),
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
            ),
          for (final ing in r.ingredients)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: nb.line))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Text(ing.name, style: ink)),
                const SizedBox(width: 8),
                Text(ing.amount, style: ink.copyWith(fontWeight: FontWeight.w700)),
              ]),
            ),
        ],
        if (r.steps.isNotEmpty) ...[
          HandHeader(tr('recipe.steps'), icon: Icons.format_list_numbered),
          for (var n = 0; n < r.steps.length; n++) _step(context, r, n),
        ],
        if (r.tips.trim().isNotEmpty) ...[
          HandHeader(tr('recipe.tips'), icon: Icons.lightbulb_outline),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color.alphaBlend(const Color(0xFFF2C14E).withValues(alpha: 0.22), nb.paper),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: nb.line),
            ),
            child: Text(r.tips.trim(), style: ink),
          ),
        ],
        if (r.ingredients.isEmpty && r.steps.isEmpty && r.intro.trim().isEmpty && courses.isEmpty)
          EmptyState(icon: Icons.edit_note, title: tr('recipe.emptyBody')),
      ],
    );
  }

  Widget _step(BuildContext context, Recipe r, int n) {
    final s = r.steps[n];
    final nb = NotebookColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: nb.accent, shape: BoxShape.circle),
          child: Text('${n + 1}',
              style: TextStyle(fontFamily: handFont, fontSize: 20, color: scheme.onPrimary, height: 1)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (s.text.trim().isNotEmpty)
              Text(s.text.trim(), style: TextStyle(color: nb.ink, fontSize: 16, height: 1.45)),
            if (s.photos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  height: 120,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: s.photos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => GestureDetector(
                      onTap: () => _openPhoto(r, s.photos, i),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: RecipePhoto(photoId: s.photos[i], recipe: r, width: 160, height: 120),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  final Recipe recipe;
  const _InfoGrid({required this.recipe});

  @override
  Widget build(BuildContext context) {
    final r = recipe;
    final nb = NotebookColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    Widget cell(IconData icon, String label, String value) => Container(
          constraints: const BoxConstraints(minWidth: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: nb.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 20, color: nb.accent),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(label.toUpperCase(),
                  style: TextStyle(fontSize: 10, letterSpacing: 0.8, color: scheme.onSurfaceVariant)),
              Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: nb.ink)),
            ]),
          ]),
        );
    return Wrap(spacing: 8, runSpacing: 8, children: [
      cell(difficultyIcon(r.difficulty), tr('recipe.difficulty'), difficultyLabel(r.difficulty)),
      if (r.prepMinutes > 0) cell(Icons.timer_outlined, tr('recipe.prep'), fmtMinutes(r.prepMinutes)),
      if (r.cookMinutes > 0) cell(Icons.local_fire_department_outlined, tr('recipe.cook'), fmtMinutes(r.cookMinutes)),
      if (r.servings > 0) cell(Icons.people_outline, tr('recipe.servings'), tr('recipe.people', {'n': r.servings})),
      cell(Icons.euro, tr('recipe.cost'), costLabel(r.cost)),
    ]);
  }
}

/// Foto a schermo intero, con zoom e scorrimento.
class PhotoViewer extends StatefulWidget {
  final Recipe recipe;
  final List<String> photos;
  final int initial;
  const PhotoViewer({super.key, required this.recipe, required this.photos, this.initial = 0});

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final PageController _pc = PageController(initialPage: widget.initial);
  late int _i = widget.initial;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.photos.length > 1 ? '${_i + 1} / ${widget.photos.length}' : ''),
      ),
      body: PageView.builder(
        controller: _pc,
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() => _i = i),
        itemBuilder: (context, i) => InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: RecipePhoto(photoId: widget.photos[i], recipe: widget.recipe, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
