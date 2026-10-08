import 'dart:ui' show DisplayFeatureType;

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../main.dart';
import '../models.dart';
import '../services/app_state.dart';
import '../theme.dart';
import '../widgets/recipe_browser.dart';
import 'family_screen.dart';
import 'suggest_screen.dart';
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
        final titles = [tr('book.mine'), tr('tab.family'), tr('tab.suggest')];
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
            body = SuggestTab(onOpen: _openDetail);
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
          item(2, Icons.lightbulb_outline, Icons.lightbulb, tr('tab.tonight')),
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
              icon: const Icon(Icons.groups_outlined),
              label: Text(tr('home.groupsHint')),
              onPressed: () => setState(() => _tab = 1),
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
