import 'dart:math';

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../main.dart';
import '../models.dart';
import '../services/online_recipes.dart';
import '../services/photo_tools.dart';
import '../theme.dart';
import '../widgets/category_tabs.dart';
import '../widgets/common.dart';
import 'recipe_edit_screen.dart';

enum MaxTime { any, m30, m60 }

enum SuggestMode { book, ingredients, internet }

/// "Cosa mangio stasera?": suggerimenti dal ricettario (per portata), per ingredienti
/// (2-3 scelti dall'utente, anche online) oppure una ricetta a sorpresa da internet.
class SuggestTab extends StatefulWidget {
  final void Function(Recipe r) onOpen;
  const SuggestTab({super.key, required this.onOpen});

  @override
  State<SuggestTab> createState() => _SuggestTabState();
}

class _SuggestTabState extends State<SuggestTab> {
  // Restano impostati finché l'app è aperta.
  static SuggestMode _mode = SuggestMode.book;
  static Set<RecipeCategory> _courses = {RecipeCategory.primi, RecipeCategory.secondi};
  static MaxTime _time = MaxTime.any;
  static bool _easyOnly = false;
  static String? _book; // null = tutte, '' = le mie, altrimenti id del gruppo
  static Map<RecipeCategory, String?> _picked = {};
  static List<String> _ings = [];
  static bool _ingSearched = false;
  static List<OnlineRecipe>? _onlineByIng;
  static OnlineRecipe? _surprise;

  static const int maxIngredients = 3;

  final Random _rnd = Random();
  bool _busy = false;
  String? _error;

  // ---- Dal ricettario ----

  List<Recipe> _pool(RecipeCategory c) => appState.recipes.where((r) {
        if (r.category != c) return false;
        if (_book == '' && !appState.isPersonal(r)) return false;
        if (_book != null && _book!.isNotEmpty && r.bookId != _book) return false;
        if (_easyOnly && (r.difficulty == Difficulty.medium || r.difficulty == Difficulty.hard)) return false;
        final t = r.totalMinutes;
        if (_time == MaxTime.m30 && (t == 0 || t > 30)) return false;
        if (_time == MaxTime.m60 && (t == 0 || t > 60)) return false;
        return true;
      }).toList();

  /// Pesca una ricetta della categoria, diversa da quella già proposta se possibile.
  String? _draw(RecipeCategory c) {
    final pool = _pool(c);
    if (pool.isEmpty) return null;
    final prev = _picked[c];
    final others = pool.where((r) => r.id != prev).toList();
    final from = others.isEmpty ? pool : others;
    return from[_rnd.nextInt(from.length)].id;
  }

  void _suggestAll() => setState(() {
        _picked = {for (final c in RecipeCategory.values.where(_courses.contains)) c: _draw(c)};
      });

  // ---- Per ingredienti ----

  /// Nomi degli ingredienti già presenti nel ricettario, per i suggerimenti mentre si scrive.
  List<String> get _knownIngredients {
    final set = <String>{};
    for (final r in appState.recipes) {
      for (final i in r.ingredients) {
        final n = i.name.trim().toLowerCase();
        if (n.isNotEmpty) set.add(n);
      }
    }
    return set.toList()..sort();
  }

  void _addIngredient(String raw) {
    final t = raw.trim().toLowerCase();
    if (t.isEmpty || _ings.contains(t) || _ings.length >= maxIngredients) return;
    setState(() {
      _ings = [..._ings, t];
      _ingSearched = false;
      _onlineByIng = null;
    });
  }

  /// Ricette del ricettario con gli ingredienti scelti: prima quelle che li hanno tutti.
  List<({Recipe r, int n})> get _localMatches {
    final out = <({Recipe r, int n})>[];
    for (final r in appState.recipes) {
      final names = r.ingredients.map((i) => i.name.toLowerCase()).toList();
      final n = _ings.where((q) => names.any((x) => x.contains(q))).length;
      if (n > 0) out.add((r: r, n: n));
    }
    out.sort((a, b) {
      final c = b.n.compareTo(a.n);
      return c != 0 ? c : a.r.displayTitle.toLowerCase().compareTo(b.r.displayTitle.toLowerCase());
    });
    return out;
  }

  Future<void> _searchOnline() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await OnlineRecipes.byIngredients(_ings.map(ingredientToEnglish).toList());
      if (mounted) setState(() => _onlineByIng = res);
    } catch (_) {
      if (mounted) setState(() => _error = tr('suggest.offline'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- Da internet ----

  Future<void> _randomOnline() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await OnlineRecipes.random();
      if (mounted) setState(() => _surprise = r);
    } catch (_) {
      if (mounted) setState(() => _error = tr('suggest.offline'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openOnline(OnlineRecipe o) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => OnlineRecipeScreen(recipe: o)));

  // ---- Interfaccia ----

  @override
  Widget build(BuildContext context) {
    final nb = NotebookColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 8, 10, 40),
      children: [
        Text(tr('suggest.title'), style: TextStyle(fontFamily: handFont, fontSize: 34, height: 1.1, color: nb.ink)),
        Text(tr('suggest.subtitle'), style: TextStyle(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 10),
        SegmentedButton<SuggestMode>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
                value: SuggestMode.book,
                icon: const Icon(Icons.menu_book_outlined),
                label: FittedBox(fit: BoxFit.scaleDown, child: Text(tr('suggest.modeBook'), maxLines: 1))),
            ButtonSegment(
                value: SuggestMode.ingredients,
                icon: const Icon(Icons.shopping_basket_outlined),
                label: FittedBox(fit: BoxFit.scaleDown, child: Text(tr('suggest.modeIng'), maxLines: 1))),
            ButtonSegment(
                value: SuggestMode.internet,
                icon: const Icon(Icons.public),
                label: FittedBox(fit: BoxFit.scaleDown, child: Text(tr('suggest.modeWeb'), maxLines: 1))),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() {
            _mode = s.first;
            _error = null;
          }),
        ),
        ...switch (_mode) {
          SuggestMode.book => _bookSection(context),
          SuggestMode.ingredients => _ingredientsSection(context),
          SuggestMode.internet => _internetSection(context),
        },
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: scheme.error)),
          ),
      ],
    );
  }

  List<Widget> _bookSection(BuildContext context) {
    final nb = NotebookColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final groups = appState.data.groups;
    if (appState.recipes.isEmpty) {
      return [EmptyState(icon: Icons.restaurant, title: tr('suggest.empty'), hint: tr('suggest.emptyHint'))];
    }
    final chosen = RecipeCategory.values.where(_courses.contains).toList();
    return [
      HandHeader(tr('suggest.courses'), icon: Icons.restaurant_menu),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final c in RecipeCategory.values)
          FilterChip(
            avatar: Icon(categoryIcon(c), size: 18, color: dark ? Colors.white : nb.ink),
            label:
                Text('${categoryLabel(c)} (${_pool(c).length})', style: TextStyle(color: dark ? Colors.white : nb.ink)),
            selected: _courses.contains(c),
            showCheckmark: false,
            backgroundColor:
                (dark ? categoryTabColorDark(categoryTabColor(c)) : categoryTabColor(c)).withValues(alpha: 0.35),
            selectedColor: dark ? categoryTabColorDark(categoryTabColor(c)) : categoryTabColor(c),
            side: BorderSide(color: _courses.contains(c) ? nb.accent : nb.line, width: _courses.contains(c) ? 2 : 1),
            onSelected: (on) => setState(() {
              if (on) {
                _courses = {..._courses, c};
              } else {
                _courses = {..._courses}..remove(c);
                _picked.remove(c);
              }
            }),
          ),
      ]),
      HandHeader(tr('suggest.filters'), icon: Icons.tune),
      Text(tr('suggest.maxTime'), style: TextStyle(color: scheme.onSurfaceVariant)),
      const SizedBox(height: 4),
      SegmentedButton<MaxTime>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: MaxTime.any, label: Text(tr('suggest.anyTime'))),
          ButtonSegment(value: MaxTime.m30, icon: const Icon(Icons.bolt, size: 18), label: Text(tr('suggest.t30'))),
          ButtonSegment(value: MaxTime.m60, label: Text(tr('suggest.t60'))),
        ],
        selected: {_time},
        onSelectionChanged: (s) => setState(() => _time = s.first),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('suggest.easyOnly')),
        value: _easyOnly,
        onChanged: (v) => setState(() => _easyOnly = v),
      ),
      if (appState.isCloud && groups.isNotEmpty)
        DropdownButtonFormField<String?>(
          initialValue: _book,
          decoration: InputDecoration(labelText: tr('suggest.from'), prefixIcon: const Icon(Icons.menu_book_outlined)),
          items: [
            DropdownMenuItem(value: null, child: Text(tr('suggest.fromAll'))),
            DropdownMenuItem(value: '', child: Text(tr('book.mine'))),
            for (final g in groups) DropdownMenuItem(value: g.id, child: Text(g.name)),
          ],
          onChanged: (v) => setState(() => _book = v),
        ),
      const SizedBox(height: 16),
      FilledButton.icon(
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
        onPressed: chosen.isEmpty ? null : _suggestAll,
        icon: const Icon(Icons.casino_outlined),
        label: Text(_picked.isEmpty ? tr('suggest.go') : tr('suggest.again'), style: const TextStyle(fontSize: 16)),
      ),
      if (chosen.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(tr('suggest.pickCourse'), textAlign: TextAlign.center, style: TextStyle(color: scheme.error)),
        ),
      if (_picked.isNotEmpty) ...[
        HandHeader(tr('suggest.tonight'), icon: Icons.dinner_dining),
        for (final c in chosen.where(_picked.containsKey)) _suggestion(context, c),
      ],
    ];
  }

  Widget _suggestion(BuildContext context, RecipeCategory c) {
    final id = _picked[c];
    final r = id == null ? null : appState.recipeById(id);
    final scheme = Theme.of(context).colorScheme;
    final canChange = _pool(c).length > 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(
          child: r == null
              ? Card(
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  child: ListTile(
                    leading: Icon(categoryIcon(c), color: scheme.outline),
                    title: Text(categoryLabel(c)),
                    subtitle: Text(tr('suggest.noneFor', {'category': categoryLabel(c)})),
                  ),
                )
              : RecipeCard(recipe: r, onTap: () => widget.onOpen(r)),
        ),
        IconButton(
          tooltip: tr('suggest.another'),
          icon: const Icon(Icons.refresh),
          onPressed: canChange ? () => setState(() => _picked[c] = _draw(c)) : null,
        ),
      ]),
    );
  }

  List<Widget> _ingredientsSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final full = _ings.length < maxIngredients;
    final known = _knownIngredients;
    final matches = _ingSearched ? _localMatches : const <({Recipe r, int n})>[];
    final all = matches.where((m) => m.n == _ings.length).toList();
    final some = matches.where((m) => m.n < _ings.length).toList();
    return [
      HandHeader(tr('suggest.ingTitle'), icon: Icons.shopping_basket_outlined),
      Text(tr('suggest.ingHint', {'n': maxIngredients}), style: TextStyle(color: scheme.onSurfaceVariant)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final i in _ings)
          InputChip(
            label: Text(i),
            onDeleted: () => setState(() {
              _ings = [..._ings]..remove(i);
              _ingSearched = false;
              _onlineByIng = null;
            }),
          ),
      ]),
      if (full) ...[
        const SizedBox(height: 8),
        Autocomplete<String>(
          optionsBuilder: (v) {
            final q = v.text.trim().toLowerCase();
            if (q.isEmpty) return const Iterable<String>.empty();
            return known.where((k) => k.contains(q) && !_ings.contains(k)).take(8);
          },
          onSelected: _addIngredient,
          fieldViewBuilder: (context, ctrl, focus, onSubmit) => TextField(
            controller: ctrl,
            focusNode: focus,
            textInputAction: TextInputAction.done,
            onSubmitted: (t) {
              _addIngredient(t);
              ctrl.clear();
            },
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.add),
              hintText: tr('suggest.ingField'),
              suffixIcon: IconButton(
                icon: const Icon(Icons.check),
                onPressed: () {
                  _addIngredient(ctrl.text);
                  ctrl.clear();
                },
              ),
            ),
          ),
        ),
      ],
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _ings.isEmpty ? null : () => setState(() => _ingSearched = true),
            icon: const Icon(Icons.search),
            label: Text(tr('suggest.ingSearch')),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _ings.isEmpty || _busy ? null : _searchOnline,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.public),
            label: Text(tr('suggest.ingWeb')),
          ),
        ),
      ]),
      if (_ingSearched) ...[
        HandHeader(tr('suggest.ingAll'), icon: Icons.check_circle_outline),
        if (all.isEmpty) Text(tr('suggest.ingNone'), style: TextStyle(color: scheme.onSurfaceVariant)),
        for (final m in all) RecipeCard(recipe: m.r, onTap: () => widget.onOpen(m.r)),
        if (some.isNotEmpty) ...[
          HandHeader(tr('suggest.ingSome'), icon: Icons.adjust),
          for (final m in some.take(10))
            RecipeCard(
              recipe: m.r,
              badge: tr('suggest.ingCount', {'n': m.n, 'tot': _ings.length}),
              onTap: () => widget.onOpen(m.r),
            ),
        ],
      ],
      if (_onlineByIng != null) ...[
        HandHeader(tr('suggest.webResults'), icon: Icons.public),
        Text(tr('suggest.webNote'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        if (_onlineByIng!.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(tr('suggest.webNone'), style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
        for (final o in _onlineByIng!.take(15)) OnlineRecipeCard(recipe: o, onTap: () => _openOnline(o)),
      ],
    ];
  }

  List<Widget> _internetSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return [
      HandHeader(tr('suggest.webTitle'), icon: Icons.public),
      Text(tr('suggest.webNote'), style: TextStyle(color: scheme.onSurfaceVariant)),
      const SizedBox(height: 12),
      FilledButton.icon(
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
        onPressed: _busy ? null : _randomOnline,
        icon: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.casino_outlined),
        label: Text(_surprise == null ? tr('suggest.webGo') : tr('suggest.webAgain'),
            style: const TextStyle(fontSize: 16)),
      ),
      if (_surprise != null) ...[
        const SizedBox(height: 10),
        OnlineRecipeCard(recipe: _surprise!, big: true, onTap: () => _openOnline(_surprise!)),
      ],
    ];
  }
}

/// Anteprima di una ricetta da internet.
class OnlineRecipeCard extends StatelessWidget {
  final OnlineRecipe recipe;
  final VoidCallback onTap;
  final bool big;
  const OnlineRecipeCard({super.key, required this.recipe, required this.onTap, this.big = false});

  @override
  Widget build(BuildContext context) {
    final nb = NotebookColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final meta = [if (recipe.category.isNotEmpty) recipe.category, if (recipe.area.isNotEmpty) recipe.area].join(' · ');
    final img = recipe.thumb.isEmpty
        ? Container(color: scheme.surfaceContainerHighest, child: Icon(Icons.restaurant, color: scheme.outline))
        : Image.network(big ? recipe.thumb : '${recipe.thumb}/preview',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                Container(color: scheme.surfaceContainerHighest, child: Icon(Icons.restaurant, color: scheme.outline)));
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: big
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                AspectRatio(aspectRatio: 4 / 3, child: img),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (meta.isNotEmpty)
                      Text(meta.toUpperCase(),
                          style: TextStyle(
                              fontSize: 11, letterSpacing: 1.1, color: nb.accent, fontWeight: FontWeight.w600)),
                    Text(recipe.title, style: TextStyle(fontFamily: handFont, fontSize: 26, color: nb.ink)),
                    Text(tr('suggest.webOpen'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ]),
                ),
              ])
            : Padding(
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  ClipRRect(
                      borderRadius: BorderRadius.circular(12), child: SizedBox(width: 66, height: 66, child: img)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (meta.isNotEmpty)
                        Text(meta.toUpperCase(),
                            style: TextStyle(
                                fontSize: 10.5, letterSpacing: 1.1, color: nb.accent, fontWeight: FontWeight.w600)),
                      Text(recipe.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: handFont, fontSize: 21, height: 1.1, color: nb.ink)),
                    ]),
                  ),
                  const Icon(Icons.chevron_right),
                ]),
              ),
      ),
    );
  }
}

/// Ricetta da internet: si legge e, se piace, si salva nel ricettario (passando dall'editor).
class OnlineRecipeScreen extends StatefulWidget {
  final OnlineRecipe recipe;
  const OnlineRecipeScreen({super.key, required this.recipe});

  @override
  State<OnlineRecipeScreen> createState() => _OnlineRecipeScreenState();
}

class _OnlineRecipeScreenState extends State<OnlineRecipeScreen> {
  late OnlineRecipe _r = widget.recipe;
  bool _loading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (_r.isPartial) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final full = await OnlineRecipes.lookup(_r.id);
      if (full != null && mounted) setState(() => _r = full);
    } catch (_) {
      if (mounted) showSnack(context, tr('suggest.offline'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final recipe = _r.toRecipe();
    final added = <String>{};
    try {
      final bytes = await OnlineRecipes.download(_r.thumb);
      if (bytes != null) {
        final id = await appState.addPhoto(await compressPhoto(bytes));
        recipe.coverPhoto = id;
        added.add(id);
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _saving = false);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RecipeEditScreen(recipe: recipe, newPhotos: added),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final nb = NotebookColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final r = _r;
    final ink = TextStyle(color: nb.ink, fontSize: 16, height: 1.45);
    return TableclothBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(tr('suggest.webTitle'))),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _loading || _saving ? null : _save,
          icon: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.bookmark_add_outlined),
          label: Text(tr('suggest.webSave')),
        ),
        body: NotebookPage(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(6, 6, 12, 96),
            children: [
              if (r.category.isNotEmpty || r.area.isNotEmpty)
                Text([r.category, r.area].where((e) => e.isNotEmpty).join(' · ').toUpperCase(),
                    style: TextStyle(fontSize: 12, letterSpacing: 1.3, color: nb.accent, fontWeight: FontWeight.w700)),
              Text(r.title, style: TextStyle(fontFamily: handFont, fontSize: 36, height: 1.1, color: nb.ink)),
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 10),
                child: Text(tr('suggest.webSource'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ),
              if (r.thumb.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: Image.network(r.thumb,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(color: scheme.surfaceContainerHighest)),
                  ),
                ),
              if (_loading)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              if (r.ingredients.isNotEmpty) ...[
                HandHeader(tr('recipe.ingredients'), icon: Icons.shopping_basket_outlined),
                for (final i in r.ingredients)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: nb.line))),
                    child: Row(children: [
                      Expanded(child: Text(i.name, style: ink)),
                      Text(i.amount, style: ink.copyWith(fontWeight: FontWeight.w700)),
                    ]),
                  ),
              ],
              if (r.steps.isNotEmpty) ...[
                HandHeader(tr('recipe.steps'), icon: Icons.format_list_numbered),
                for (var n = 0; n < r.steps.length; n++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: nb.accent, shape: BoxShape.circle),
                        child: Text('${n + 1}',
                            style: TextStyle(fontFamily: handFont, fontSize: 19, color: scheme.onPrimary, height: 1)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(r.steps[n], style: ink)),
                    ]),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
