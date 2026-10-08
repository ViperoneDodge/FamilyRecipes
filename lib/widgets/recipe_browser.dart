import 'package:flutter/material.dart';

import '../l10n.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import 'category_tabs.dart';
import 'common.dart';

/// Elenco di ricette con linguette per categoria (stile rubrica) e ricerca.
class RecipeBrowser extends StatefulWidget {
  final List<Recipe> recipes;
  final void Function(Recipe r) onOpen;
  final void Function(Recipe r)? onLongPress;
  final String? Function(Recipe r)? badgeFor;
  final String emptyTitle;
  final String? emptyHint;
  final Widget? emptyAction;
  final List<Widget> header;
  final List<Widget> footer;
  final RecipeCategory? initialCategory;
  final bool showCategoryChips;
  final String? selectedId;
  final ValueChanged<RecipeCategory?>? onCategoryChanged;

  const RecipeBrowser({
    super.key,
    required this.recipes,
    required this.onOpen,
    this.onLongPress,
    this.badgeFor,
    required this.emptyTitle,
    this.emptyHint,
    this.emptyAction,
    this.header = const [],
    this.footer = const [],
    this.initialCategory,
    this.showCategoryChips = true,
    this.selectedId,
    this.onCategoryChanged,
  });

  @override
  State<RecipeBrowser> createState() => _RecipeBrowserState();
}

class _RecipeBrowserState extends State<RecipeBrowser> {
  late RecipeCategory? _cat = widget.initialCategory;
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _setCat(RecipeCategory? c) {
    setState(() => _cat = c);
    widget.onCategoryChanged?.call(c);
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.recipes;
    final q = _q.text.trim().toLowerCase();
    final list = all
        .where((r) => _cat == null || r.category == _cat)
        .where((r) => q.isEmpty || r.searchText.contains(q))
        .toList();
    final listView = RefreshIndicator(
      onRefresh: appState.retrySync,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(4, 10, 10, 96),
        children: [
          ...widget.header,
          if (all.isNotEmpty) ...[
            TextField(
              controller: _q,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: tr('search.hint'),
                suffixIcon: _q.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(_q.clear),
                      ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(children: [
            if (widget.showCategoryChips && appState.theme.tabs == TabsStyle.none) _categoryMenu(context, all),
            const Spacer(),
            if (list.length > 1) sortOrderButton(context) else const SizedBox(height: 40),
          ]),
          if (list.isEmpty)
            all.isEmpty
                ? EmptyState(
                    icon: _cat == null ? Icons.menu_book_outlined : categoryIcon(_cat!),
                    title: widget.emptyTitle,
                    hint: widget.emptyHint,
                    action: widget.emptyAction,
                  )
                : q.isEmpty && _cat != null
                    ? EmptyState(
                        icon: categoryIcon(_cat!),
                        title: tr('category.empty'),
                        hint: widget.emptyHint == null ? null : tr('category.emptyHint'),
                      )
                    : EmptyState(icon: Icons.search_off, title: tr('search.none')),
          for (final r in list)
            RecipeCard(
              recipe: r,
              badge: widget.badgeFor?.call(r),
              showCategory: _cat == null,
              selected: r.id == widget.selectedId,
              onTap: () => widget.onOpen(r),
              onLongPress: widget.onLongPress == null ? null : () => widget.onLongPress!(r),
            ),
          ...widget.footer,
        ],
      ),
    );
    if (!widget.showCategoryChips) return listView;
    int count(RecipeCategory? c) => c == null ? all.length : all.where((r) => r.category == c).length;
    switch (appState.theme.tabs) {
      case TabsStyle.top:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 4),
            child: CategoryTabs(selected: _cat, onSelected: _setCat, count: count),
          ),
          Expanded(child: listView),
        ]);
      case TabsStyle.right:
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: listView),
          Padding(
            // in basso resta posto per il pulsante "Nuova ricetta"
            padding: const EdgeInsets.only(top: 6, bottom: 80),
            child: VerticalCategoryTabs(selected: _cat, onSelected: _setCat, count: count),
          ),
        ]);
      case TabsStyle.none:
        return listView;
    }
  }

  Widget _categoryMenu(BuildContext context, List<Recipe> all) {
    final nb = NotebookColors.of(context);
    String label(RecipeCategory? c) =>
        '${c == null ? tr('filter.allShort') : categoryLabel(c)} (${c == null ? all.length : all.where((r) => r.category == c).length})';
    return PopupMenuButton<RecipeCategory?>(
      tooltip: tr('filter.category'),
      initialValue: _cat,
      onSelected: _setCat,
      itemBuilder: (ctx) => [
        PopupMenuItem<RecipeCategory?>(value: null, child: Text(label(null))),
        for (final c in RecipeCategory.values)
          PopupMenuItem<RecipeCategory?>(
            value: c,
            child: Row(children: [Icon(categoryIcon(c), size: 18), const SizedBox(width: 8), Text(label(c))]),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_cat == null ? Icons.filter_list : categoryIcon(_cat!), size: 18, color: nb.accent),
          const SizedBox(width: 6),
          Text(label(_cat), style: TextStyle(color: nb.accent, fontWeight: FontWeight.w600)),
          Icon(Icons.arrow_drop_down, color: nb.accent),
        ]),
      ),
    );
  }
}

Widget sortOrderButton(BuildContext context) {
  final newest = appState.sortNewestFirst;
  return Align(
    alignment: Alignment.centerRight,
    child: TextButton.icon(
      onPressed: () => appState.setSortNewestFirst(!newest),
      icon: const Icon(Icons.swap_vert, size: 18),
      label: Text(newest ? tr('sort.newest') : tr('sort.alpha')),
    ),
  );
}
