import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../main.dart';
import '../models.dart';
import '../services/photo_tools.dart';
import '../services/recipe_import.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Sceglie un file di ricette (`.json`) e apre l'anteprima dell'importazione.
Future<void> importRecipesFlow(BuildContext context, {String? bookId}) async {
  List<ImportedRecipe> items;
  try {
    final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['json', 'txt']);
    final path = res?.files.single.path;
    if (path == null) return;
    items = RecipeImport.parse(await File(path).readAsString());
  } catch (_) {
    if (context.mounted) showSnack(context, tr('import.badFile'));
    return;
  }
  if (!context.mounted) return;
  if (items.isEmpty) {
    showSnack(context, tr('import.empty'));
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ImportScreen(items: items, bookId: bookId)));
}

class ImportScreen extends StatefulWidget {
  final List<ImportedRecipe> items;
  final String? bookId;

  const ImportScreen({super.key, required this.items, this.bookId});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  late String? _book = appState.canAddTo(widget.bookId) ? widget.bookId : null;
  final Set<int> _selected = {};
  bool _busy = false;
  int _done = 0;

  @override
  void initState() {
    super.initState();
    _selectNew();
  }

  String _key(Recipe r) => '${r.category.name}|${r.title.trim().toLowerCase()}';

  Set<String> get _existing {
    final list = _book == null ? appState.recipes.where(appState.isPersonal) : appState.groupRecipes(_book!);
    return {for (final r in list) _key(r)};
  }

  /// Seleziona tutto tranne le ricette che ci sono già nel ricettario scelto.
  void _selectNew() {
    final ex = _existing;
    _selected
      ..clear()
      ..addAll([
        for (var i = 0; i < widget.items.length; i++)
          if (!ex.contains(_key(widget.items[i].recipe))) i
      ]);
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _done = 0;
    });
    var ok = 0;
    for (final i in _selected.toList()..sort()) {
      final it = widget.items[i];
      final r = it.recipe.copy();
      r.id = newId();
      r.bookId = _book;
      try {
        if (it.photo != null) {
          r.coverPhoto = await appState.addPhoto(await compressPhoto(it.photo!));
        }
      } catch (_) {
        r.coverPhoto = null;
      }
      try {
        await appState.saveRecipe(r);
        ok++;
      } catch (_) {}
      if (mounted) setState(() => _done++);
    }
    if (!mounted) return;
    showSnack(context, trn('import.done', ok));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final groups = appState.data.groups.where((g) => appState.canAddTo(g.id)).toList();
    final ex = _existing;
    return TableclothBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(tr('import.title'))),
        body: NotebookPage(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
            Text(trn('import.found', widget.items.length), style: const TextStyle(fontFamily: handFont, fontSize: 24)),
            const SizedBox(height: 4),
            Text(tr('import.info'), style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            if (groups.isNotEmpty)
              DropdownButtonFormField<String?>(
                initialValue: _book,
                decoration: InputDecoration(
                    labelText: tr('edit.whereSave'), prefixIcon: const Icon(Icons.menu_book_outlined)),
                items: [
                  DropdownMenuItem(value: null, child: Text(tr('book.mine'))),
                  for (final g in groups) DropdownMenuItem(value: g.id, child: Text(g.name)),
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(() {
                          _book = v;
                          _selectNew();
                        }),
              ),
            const SizedBox(height: 8),
            Row(children: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() => _selected.addAll(List.generate(widget.items.length, (i) => i))),
                child: Text(tr('import.all')),
              ),
              TextButton(
                onPressed: _busy ? null : () => setState(_selected.clear),
                child: Text(tr('import.none')),
              ),
            ]),
            for (var i = 0; i < widget.items.length; i++) _tile(i, ex, scheme),
          ]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _busy || _selected.isEmpty ? null : _import,
          icon: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.download_done),
          label: Text(_busy
              ? tr('import.progress', {'n': _done, 'tot': _selected.length})
              : trn('import.button', _selected.length)),
        ),
      ),
    );
  }

  Widget _tile(int i, Set<String> ex, ColorScheme scheme) {
    final it = widget.items[i];
    final r = it.recipe;
    final dup = ex.contains(_key(r));
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: _selected.contains(i),
      onChanged: _busy ? null : (v) => setState(() => v == true ? _selected.add(i) : _selected.remove(i)),
      secondary: it.photo != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(it.photo!, width: 48, height: 48, fit: BoxFit.cover, cacheWidth: 144,
                  errorBuilder: (_, __, ___) => Icon(categoryIcon(r.category))),
            )
          : Icon(categoryIcon(r.category)),
      title: Text(r.displayTitle),
      subtitle: Text([
        categoryLabel(r.category),
        if (r.createdByName.isNotEmpty) tr('recipe.by', {'name': r.createdByName}),
        if (dup) tr('import.duplicate'),
      ].join(' · '), style: TextStyle(color: dup ? scheme.error : null)),
    );
  }
}
