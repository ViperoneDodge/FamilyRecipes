import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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

/// Esporta un ricettario (Le mie o un gruppo) in un file `.json` con le foto, da condividere o
/// conservare come copia; si reimporta con [importRecipesFlow].
Future<void> exportRecipesFlow(BuildContext context) async {
  final List<FamilyGroup> groups = appState.isCloud ? appState.data.groups : const [];
  String? book = '';
  if (groups.isNotEmpty) {
    book = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr('export.which')),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, ''), child: Text(tr('book.mine'))),
          for (final g in groups) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, g.id), child: Text(g.name)),
        ],
      ),
    );
    if (book == null) return;
  }
  final list = book.isEmpty ? appState.recipes.where(appState.isPersonal).toList() : appState.groupRecipes(book);
  if (!context.mounted) return;
  if (list.isEmpty) {
    showSnack(context, tr('export.empty'));
    return;
  }
  final name = book.isEmpty ? tr('book.mine') : groups.firstWhere((g) => g.id == book).name;
  try {
    final photos = <String, Uint8List>{};
    for (final r in list) {
      final id = r.thumbnail;
      if (id == null) continue;
      final b = await appState.photos.load(id, bookId: appState.bookOf(r));
      if (b != null) photos[r.id] = b;
    }
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    final day = DateTime.now().toIso8601String().substring(0, 10);
    final file = File('${(await getTemporaryDirectory()).path}/ricettario-${safe.isEmpty ? 'famiglia' : safe}-$day.json');
    await file.writeAsString(RecipeImport.encode(list, photos));
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/json')],
      text: trn('export.shareText', list.length, {'name': name}),
    ));
  } catch (_) {
    if (context.mounted) showSnack(context, tr('export.failed'));
  }
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
    final list = switch (_book) {
      null => appState.recipes.where(appState.isPersonal),
      final book => appState.groupRecipes(book),
    };
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
      final r = it.recipe.copy()
        ..id = newId()
        ..bookId = _book;
      if (it.photo case final photo?) {
        try {
          r.coverPhoto = await appState.addPhoto(await compressPhoto(photo));
        } catch (_) {
          r.coverPhoto = null;
        }
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
      secondary: switch (it.photo) {
        final photo? => ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.memory(photo, width: 48, height: 48, fit: BoxFit.cover, cacheWidth: 144,
                errorBuilder: (_, __, ___) => Icon(categoryIcon(r.category))),
          ),
        null => Icon(categoryIcon(r.category)),
      },
      title: Text(r.displayTitle),
      subtitle: Text([
        categoryLabel(r.category),
        if (r.createdByName.isNotEmpty) tr('recipe.by', {'name': r.createdByName}),
        if (dup) tr('import.duplicate'),
      ].join(' · '), style: TextStyle(color: dup ? scheme.error : null)),
    );
  }
}
