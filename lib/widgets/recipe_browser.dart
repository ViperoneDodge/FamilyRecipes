import 'package:flutter/material.dart';

import '../l10n.dart';
import '../main.dart';
import '../models.dart';
import 'common.dart';

/// Elenco di ricette con ricerca e filtro per categoria.
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
    return RefreshIndicator(
      onRefresh: appState.retrySync,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(4, 8, 10, 96),
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
          if (widget.showCategoryChips && all.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(tr('filter.all', {'n': all.length})),
                    selected: _cat == null,
                    onSelected: (_) => _setCat(null),
                  ),
                ),
                for (final c in RecipeCategory.values)
                  if (all.any((r) => r.category == c) || _cat == c)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        avatar: Icon(categoryIcon(c), size: 18),
                        label: Text('${categoryLabel(c)} (${all.where((r) => r.category == c).length})'),
                        selected: _cat == c,
                        onSelected: (_) => _setCat(c),
                      ),
                    ),
              ]),
            ),
          if (list.length > 1) sortOrderButton(context) else const SizedBox(height: 8),
          if (list.isEmpty)
            all.isEmpty || (q.isEmpty && _cat != null)
                ? EmptyState(
                    icon: _cat == null ? Icons.menu_book_outlined : categoryIcon(_cat!),
                    title: widget.emptyTitle,
                    hint: widget.emptyHint,
                    action: widget.emptyAction,
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
