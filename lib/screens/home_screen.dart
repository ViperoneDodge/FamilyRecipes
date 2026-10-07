import 'dart:ui' show DisplayFeatureType;

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../main.dart';
import '../models.dart';
import '../services/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/recipe_browser.dart';
import 'family_screen.dart';
import 'recipe_detail_screen.dart';
import 'recipe_edit_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  RecipeCategory? _myCategory;

  String? _selectedId;
  bool _twoPane = false;

  void _openAdd({String? bookId, RecipeCategory? category}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RecipeEditScreen(
        recipe: Recipe(category: category ?? _myCategory ?? RecipeCategory.primi, bookId: bookId),
      ),
    ));
  }

  void _openDetail(Recipe r) {
    if (_twoPane) {
      setState(() => _selectedId = r.id);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipeId: r.id)));
  }

  static Rect? _verticalHinge(MediaQueryData mq) {
    for (final f in mq.displayFeatures) {
      if (f.type == DisplayFeatureType.cutout) continue;
      final b = f.bounds;
      if (b.height >= b.width && b.left > 120 && b.right < mq.size.width - 120) return b;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final hinge = _verticalHinge(mq);
    final width = mq.size.width;
    _twoPane = hinge != null || width >= 840;
    if (!_twoPane) return _mainScaffold(context);

    final leftWidth = hinge != null ? hinge.left : (width * 0.42).clamp(340.0, 480.0).toDouble();
    final gap = hinge != null ? hinge.width : 0.0;
    return TableclothBackground(
      child: Row(children: [
        SizedBox(width: leftWidth, child: _mainScaffold(context)),
        if (gap > 0) SizedBox(width: gap),
        Expanded(
          child: ListenableBuilder(
            listenable: appState,
            builder: (context, _) {
              final selected = _selectedId == null ? null : appState.recipeById(_selectedId!);
              return selected == null
                  ? _emptyDetail(context)
                  : RecipeDetailScreen(
                      key: ValueKey(selected.id),
                      recipeId: selected.id,
                      embedded: true,
                      onClosed: () => setState(() => _selectedId = null),
                    );
            },
          ),
        ),
      ]),
    );
  }

  Widget _emptyDetail(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(automaticallyImplyLeading: false),
      body: NotebookPage(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.menu_book_outlined, size: 64, color: scheme.outline),
            const SizedBox(height: 12),
            Text(tr('home.selectRecipe'),
                textAlign: TextAlign.center, style: const TextStyle(fontFamily: handFont, fontSize: 24)),
          ]),
        ),
      ),
    );
  }

  Widget _syncIcon() {
    if (!appState.isCloud) return const SizedBox.shrink();
    switch (appState.syncStatus) {
      case SyncStatus.online:
        return Tooltip(message: tr('sync.done'), child: const Icon(Icons.cloud_done));
      case SyncStatus.connecting:
        return Tooltip(message: tr('sync.connecting'), child: const Icon(Icons.cloud_sync));
      case SyncStatus.offline:
        return IconButton(
          tooltip: tr('sync.offline'),
          icon: const Icon(Icons.cloud_off),
          onPressed: appState.retrySync,
        );
      case SyncStatus.off:
        return const SizedBox.shrink();
    }
  }

  Widget _mainScaffold(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final titles = [tr('book.mine'), tr('tab.family'), tr('tab.index')];
        Widget body;
        switch (_tab) {
          case 1:
            body = FamilyTab(
              onOpen: _openDetail,
              onAdd: (g) => _openAdd(bookId: g),
              selectedId: _twoPane ? _selectedId : null,
            );
            break;
          case 2:
            body = IndexTab(onOpen: _openDetail, selectedId: _twoPane ? _selectedId : null);
            break;
          default:
            body = _myTab();
        }
        final mine = appState.myRecipes;
        final scaffold = Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text(titles[_tab]),
            actions: [
              if (_tab == 0 && mine.isNotEmpty)
                IconButton(
                  tooltip: tr('pdf.export'),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  onPressed: () {
                    final list = _myCategory == null
                        ? mine
                        : mine.where((r) => r.category == _myCategory).toList();
                    exportPdf(
                      context,
                      _myCategory == null ? tr('book.mine') : '${tr('book.mine')} - ${categoryLabel(_myCategory!)}',
                      list,
                    );
                  },
                ),
              _syncIcon(),
              IconButton(
                tooltip: tr('settings.title'),
                icon: const Icon(Icons.settings),
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
            ],
          ),
          body: NotebookPage(child: body),
          floatingActionButton: _tab == 0
              ? FloatingActionButton.extended(
                  onPressed: () => _openAdd(),
                  icon: const Icon(Icons.add),
                  label: Text(tr('recipe.new')),
                )
              : null,
          bottomNavigationBar: _bottomBar(context),
        );
        return _twoPane ? scaffold : TableclothBackground(child: scaffold);
      },
    );
  }

  Widget _bottomBar(BuildContext context) {
    final theme = Theme.of(context);
    final nb = NotebookColors.of(context);
    Widget item(int i, IconData icon, IconData selectedIcon, String label) {
      final sel = _tab == i;
      final color = sel ? nb.onCover : nb.onCover.withValues(alpha: 0.7);
      return Expanded(
        child: Semantics(
          selected: sel,
          button: true,
          label: label,
          excludeSemantics: true,
          child: InkWell(
            onTap: () => setState(() => _tab = i),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 64,
                  height: 32,
                  decoration: BoxDecoration(
                    color: sel ? nb.paper : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(sel ? selectedIcon : icon, color: sel ? theme.colorScheme.primary : color),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                      maxLines: 1, style: TextStyle(fontFamily: handFont, fontSize: 17, color: color)),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.black.withValues(alpha: 0.12),
      child: SafeArea(
        top: false,
        child: Row(children: [
          item(0, Icons.edit_note_outlined, Icons.edit_note, tr('tab.mine')),
          item(1, Icons.groups_outlined, Icons.groups, tr('tab.family')),
          item(2, Icons.menu_book_outlined, Icons.menu_book, tr('tab.index')),
        ]),
      ),
    );
  }

  Widget _myTab() {
    final all = appState.myRecipes;
    final hasGroupRecipes = appState.recipes.any((r) => !appState.isMine(r));
    return RecipeBrowser(
      key: const ValueKey('mine'),
      recipes: all,
      initialCategory: _myCategory,
      onCategoryChanged: (c) => _myCategory = c,
      selectedId: _twoPane ? _selectedId : null,
      onOpen: _openDetail,
      onLongPress: (r) => moveRecipeSheet(context, r),
      badgeFor: (r) => appState.isPersonal(r) ? null : appState.bookLabel(r),
      emptyTitle: tr('home.empty'),
      emptyHint: tr('home.emptyHint'),
      emptyAction: all.isEmpty && hasGroupRecipes
          ? OutlinedButton.icon(
              icon: const Icon(Icons.menu_book_outlined),
              label: Text(tr('home.indexHint')),
              onPressed: () => setState(() => _tab = 2),
            )
          : null,
      footer: [
        if (all.isNotEmpty && appState.isCloud && appState.data.groups.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              tr('home.longPressHint'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
            ),
          ),
      ],
    );
  }
}

/// Indice del ricettario: tutte le ricette visibili (mie e dei gruppi) per categoria.
class IndexTab extends StatefulWidget {
  final void Function(Recipe r) onOpen;
  final String? selectedId;
  const IndexTab({super.key, required this.onOpen, this.selectedId});

  @override
  State<IndexTab> createState() => _IndexTabState();
}

class _IndexTabState extends State<IndexTab> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = appState.allRecipes;
    final q = _q.text.trim().toLowerCase();
    final nb = NotebookColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final showBook = appState.isCloud && appState.data.groups.isNotEmpty;
    final children = <Widget>[
      TextField(
        controller: _q,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search),
          hintText: tr('search.hintAll'),
          suffixIcon: _q.text.isEmpty
              ? null
              : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_q.clear)),
        ),
      ),
      const SizedBox(height: 10),
    ];
    if (q.isNotEmpty) {
      final found = all.where((r) => r.searchText.contains(q)).toList();
      if (found.isEmpty) children.add(EmptyState(icon: Icons.search_off, title: tr('search.none')));
      children.addAll(found.map((r) => RecipeCard(
            recipe: r,
            badge: showBook ? appState.bookLabel(r) : null,
            selected: r.id == widget.selectedId,
            onTap: () => widget.onOpen(r),
          )));
    } else {
      children.add(LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth >= 560 ? 3 : 2;
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.25,
          children: [
            for (final c in RecipeCategory.values)
              _CategoryTile(
                category: c,
                count: all.where((r) => r.category == c).length,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CategoryScreen(category: c),
                )),
              ),
          ],
        );
      }));
      if (all.isEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(tr('index.empty'),
              textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
        ));
      } else {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text(trn('book.recipes', all.length),
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: handFont, fontSize: 20, color: nb.accent)),
        ));
      }
    }
    return RefreshIndicator(
      onRefresh: appState.retrySync,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(4, 8, 10, 32),
        children: children,
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final RecipeCategory category;
  final int count;
  final VoidCallback onTap;
  const _CategoryTile({required this.category, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nb = NotebookColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(children: [
          Positioned(
            right: -14,
            bottom: -14,
            child: Icon(categoryIcon(category), size: 84, color: nb.accent.withValues(alpha: 0.10)),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(categoryIcon(category), color: scheme.primary, size: 28),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(categoryLabel(category),
                    maxLines: 1, style: TextStyle(fontFamily: handFont, fontSize: 24, color: nb.ink)),
              ),
              Text(trn('book.recipes', count),
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Tutte le ricette visibili di una categoria.
class CategoryScreen extends StatelessWidget {
  final RecipeCategory category;
  const CategoryScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final list = appState.allRecipes.where((r) => r.category == category).toList();
        final showBook = appState.isCloud && appState.data.groups.isNotEmpty;
        return TableclothBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              title: Text(categoryLabel(category)),
              actions: [
                if (list.isNotEmpty)
                  IconButton(
                    tooltip: tr('pdf.export'),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    onPressed: () => exportPdf(context, categoryLabel(category), list),
                  ),
              ],
            ),
            body: NotebookPage(
              child: RecipeBrowser(
                recipes: list,
                showCategoryChips: false,
                initialCategory: null,
                onOpen: (r) => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipeId: r.id))),
                badgeFor: (r) => showBook ? appState.bookLabel(r) : null,
                emptyTitle: tr('category.empty'),
                emptyHint: tr('category.emptyHint'),
              ),
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => RecipeEditScreen(recipe: Recipe(category: category)),
              )),
              icon: const Icon(Icons.add),
              label: Text(tr('recipe.new')),
            ),
          ),
        );
      },
    );
  }
}
