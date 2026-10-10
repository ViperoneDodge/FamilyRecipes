import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n.dart';
import '../models.dart';
import '../services/recipe_reader.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'import_screen.dart';
import 'recipe_edit_screen.dart';

/// "Nuova ricetta": scritta a mano oppure letta da foto (fotocamera o galleria) o da un PDF.
Future<void> newRecipeFlow(BuildContext context, {String? bookId, RecipeCategory? category}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(tr('recipe.new'), style: const TextStyle(fontFamily: handFont, fontSize: 26)),
        ),
        ListTile(
          leading: const Icon(Icons.edit_note),
          title: Text(tr('scan.write')),
          subtitle: Text(tr('scan.writeInfo')),
          onTap: () => Navigator.pop(ctx, 'write'),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Text(tr('scan.readTitle'), style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
        ),
        ListTile(
          leading: const Icon(Icons.document_scanner_outlined),
          title: Text(tr('scan.camera')),
          subtitle: Text(tr('scan.cameraInfo')),
          onTap: () => Navigator.pop(ctx, 'camera'),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: Text(tr('scan.gallery')),
          subtitle: Text(tr('scan.galleryInfo')),
          onTap: () => Navigator.pop(ctx, 'gallery'),
        ),
        ListTile(
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: Text(tr('scan.pdf')),
          subtitle: Text(tr('scan.pdfInfo', {'n': RecipeReader.maxPdfPages})),
          onTap: () => Navigator.pop(ctx, 'pdf'),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.file_open_outlined),
          title: Text(tr('import.menu')),
          subtitle: Text(tr('import.menuInfo')),
          onTap: () => Navigator.pop(ctx, 'import'),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'write') {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RecipeEditScreen(recipe: Recipe(category: category ?? RecipeCategory.primi, bookId: bookId)),
    ));
    return;
  }
  if (choice == 'import') {
    await importRecipesFlow(context, bookId: bookId);
    return;
  }
  final paths = await _pick(context, choice);
  if (paths.isEmpty || !context.mounted) return;
  await _readAndEdit(context, paths, bookId: bookId, category: category);
}

Future<List<String>> _pick(BuildContext context, String choice) async {
  final picker = ImagePicker();
  try {
    switch (choice) {
      case 'camera':
        final out = <String>[];
        while (context.mounted) {
          final x =
              await picker.pickImage(source: ImageSource.camera, maxWidth: 3000, maxHeight: 3000, imageQuality: 95);
          if (x == null) break;
          out.add(x.path);
          if (!context.mounted) break;
          final more = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(tr('scan.morePagesTitle')),
              content: Text(trn('scan.pagesSoFar', out.length)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('scan.addPage'))),
                FilledButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('scan.readNow'))),
              ],
            ),
          );
          if (more != true) break;
        }
        return out;
      case 'gallery':
        final xs = await picker.pickMultiImage(maxWidth: 3000, maxHeight: 3000, imageQuality: 95);
        return xs.map((x) => x.path).toList();
      case 'pdf':
        final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
        final p = res?.files.single.path;
        return p == null ? [] : [p];
    }
  } catch (e) {
    if (context.mounted) showSnack(context, tr('photo.error', {'error': e}));
  }
  return [];
}

Future<void> _readAndEdit(BuildContext context, List<String> paths, {String? bookId, RecipeCategory? category}) async {
  final nav = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 18),
          Expanded(child: Text(tr('scan.reading'))),
        ]),
      ),
    ),
  );
  Recipe? r;
  Object? error;
  try {
    r = await RecipeReader.read(paths);
  } catch (e) {
    error = e;
  }
  nav.pop();
  if (!context.mounted) return;
  if (r == null || (r.title.isEmpty && r.ingredients.isEmpty && r.steps.isEmpty)) {
    showSnack(context, error == null ? tr('scan.nothing') : tr('scan.failed', {'error': error}));
    return;
  }
  r.bookId = bookId;
  if (category != null && r.category == RecipeCategory.secondi) r.category = category;
  nav.push(MaterialPageRoute(builder: (_) => RecipeEditScreen(recipe: r!, notice: tr('scan.check'))));
}
