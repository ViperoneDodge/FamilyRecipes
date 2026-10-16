import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n.dart';
import '../models.dart';
import '../services/online_recipes.dart' show OnlineRecipe;
import '../services/recipe_reader.dart';
import '../services/web_recipes.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/group_qr.dart' show scanQr;
import 'import_screen.dart';
import 'recipe_edit_screen.dart';
import 'suggest_screen.dart' show OnlineRecipeScreen;

/// "Nuova ricetta": scritta a mano oppure letta da foto (fotocamera o galleria) o da un PDF.
Future<void> newRecipeFlow(BuildContext context, {String? bookId, RecipeCategory? category}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) {
      Widget option(String value, IconData icon, String title, String subtitle) => ListTile(
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text(subtitle),
            onTap: () => Navigator.pop(ctx, value),
          );
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(tr('recipe.new'), style: const TextStyle(fontFamily: handFont, fontSize: 26)),
          ),
          option('write', Icons.edit_note, tr('scan.write'), tr('scan.writeInfo')),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(tr('scan.readTitle'), style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
          ),
          option('camera', Icons.document_scanner_outlined, tr('scan.camera'), tr('scan.cameraInfo')),
          option('gallery', Icons.photo_library_outlined, tr('scan.gallery'), tr('scan.galleryInfo')),
          option('pdf', Icons.picture_as_pdf_outlined, tr('scan.pdf'),
              tr('scan.pdfInfo', {'n': RecipeReader.maxPdfPages})),
          option('link', Icons.qr_code_2, tr('link.menu'), tr('link.menuInfo')),
          const Divider(height: 1),
          option('import', Icons.file_open_outlined, tr('import.menu'), tr('import.menuInfo')),
          const SizedBox(height: 8),
        ]),
      );
    },
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'write':
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RecipeEditScreen(recipe: Recipe(category: category ?? RecipeCategory.primi, bookId: bookId)),
      ));
    case 'link':
      await recipeFromLinkFlow(context);
    case 'import':
      await importRecipesFlow(context, bookId: bookId);
    default:
      final paths = await _pick(context, choice);
      if (paths.isNotEmpty && context.mounted) {
        await _readAndEdit(context, paths, bookId: bookId, category: category);
      }
  }
}

/// Finestra "sto leggendo…" che non si può chiudere: la toglie chi l'ha aperta, con `pop`.
void _showProgress(BuildContext context, String text) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 18),
          Expanded(child: Text(text)),
        ]),
      ),
    ),
  );
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
        return [for (final x in xs) x.path];
      case 'pdf':
        final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
        return [if (res?.files.single.path case final p?) p];
    }
  } catch (e) {
    if (context.mounted) showSnack(context, tr('photo.error', {'error': e}));
  }
  return [];
}

Future<void> _readAndEdit(BuildContext context, List<String> paths, {String? bookId, RecipeCategory? category}) async {
  final nav = Navigator.of(context);
  _showProgress(context, tr('scan.reading'));
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
  final recipe = r..bookId = bookId;
  if (category != null && recipe.category == RecipeCategory.secondi) recipe.category = category;
  nav.push(MaterialPageRoute(builder: (_) => RecipeEditScreen(recipe: recipe, notice: tr('scan.check'))));
}

/// Ricetta da internet: chiede il link (scritto, incollato o da QR) e apre la ricetta letta.
Future<void> recipeFromLinkFlow(BuildContext context) async {
  final url = await _askLink(context);
  if (url != null && context.mounted) await openRecipeLink(context, url);
}

/// Chiede il link di una ricetta: scritto, incollato dagli appunti o letto da un QR.
Future<String?> _askLink(BuildContext context) async {
  Future<String> clipboardUrl() async {
    try {
      return firstUrl((await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '') ?? '';
    } catch (_) {
      return '';
    }
  }

  // Il campo parte vuoto (niente link rimasto dall'ultima volta): per quello copiato c'è Incolla.
  final ctrl = TextEditingController();
  const scan = '\u0000qr';
  final res = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('link.title')),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('link.info')),
        const SizedBox(height: 10),
        TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: 'https://…',
            prefixIcon: const Icon(Icons.link),
            suffixIcon: IconButton(
              tooltip: tr('link.paste'),
              icon: const Icon(Icons.content_paste),
              onPressed: () async {
                final u = await clipboardUrl();
                if (u.isNotEmpty) ctrl.text = u;
              },
            ),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.pop(ctx, scan),
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(tr('link.scan')),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('common.cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(tr('link.read'))),
      ],
    ),
  );
  if (res == scan && context.mounted) {
    return scanQr(context, title: tr('link.qrTitle'), parse: (raw) => firstUrl(raw ?? ''), notFound: tr('link.qrNone'));
  }
  return res == null ? null : firstUrl(res);
}

/// Legge la ricetta dalla pagina di un sito (link scritto o condiviso dal browser) e la mostra,
/// pronta da salvare nel ricettario.
Future<void> openRecipeLink(BuildContext context, String text) async {
  final found = firstUrl(text);
  if (found == null) {
    showSnack(context, tr('link.none'));
    return;
  }
  final url = WebRecipes.cleanUrl(found);
  final nav = Navigator.of(context);
  _showProgress(context, tr('link.reading'));
  OnlineRecipe? r;
  var failed = false;
  try {
    r = await WebRecipes.read(url);
  } catch (_) {
    failed = true;
  }
  // Se il sito rifiuta la lettura diretta o non ha la ricetta nella pagina scaricata, la si apre nel
  // browser del telefono (piano B).
  if (r == null || r.isPartial) {
    try {
      final b = await WebRecipes.readInBrowser(url);
      failed = false; // la pagina si è aperta: se manca la ricetta non è un problema di rete
      if (b != null) r = b;
    } catch (_) {}
  }
  nav.pop();
  if (!context.mounted) return;
  if (r == null || r.isPartial) {
    showSnack(context, failed ? tr('suggest.offline') : tr('link.none'));
    return;
  }
  final recipe = r;
  nav.push(MaterialPageRoute(builder: (_) => OnlineRecipeScreen(recipe: recipe)));
}
