import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n.dart';
import '../main.dart';
import '../models.dart';
import '../services/app_state.dart';
import '../services/dose_scaler.dart';
import '../services/excel_form.dart';
import '../services/pdf_export.dart';
import '../services/shopping_list.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'pro_screen.dart';

bool get _comma => !decimalPointLanguages.contains(L10n.code);

String _dayLabel(DateTime d, {bool long = false}) {
  try {
    return DateFormat(long ? 'EEEE d MMMM' : 'EEE d MMM', L10n.code).format(d);
  } catch (_) {
    return fmtDate(d);
  }
}

String weekTitle(DateTime start) =>
    tr('plan.weekOf', {'from': _dayLabel(start), 'to': _dayLabel(start.add(const Duration(days: 6)))});

List<({String day, Meal meal, PlanEntry entry})> _weekEntries(DateTime start) => appState.plan.range(start, 7);

/// Scheda "Pianificazione": i pasti della settimana, giorno per giorno, con la lista della spesa.
class PlannerTab extends StatefulWidget {
  const PlannerTab({super.key});

  @override
  State<PlannerTab> createState() => _PlannerTabState();
}

class _PlannerTabState extends State<PlannerTab> {
  // Resta sulla settimana scelta finché l'app è aperta.
  static DateTime? _week;

  DateTime get _start => _week ??= weekStart(DateTime.now());

  void _move(int weeks) => setState(() => _week = _start.add(Duration(days: 7 * weeks)));

  /// Settimana non pianificabile (senza Pro, oltre le settimane di prova): solo lettura.
  bool _locked = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final nb = NotebookColors.of(context);
        _locked = !appState.canPlanWeek(_start);
        final today = planDay(DateTime.now());
        final meals = appState.plan.meals;
        return ListView(padding: const EdgeInsets.fromLTRB(4, 6, 10, 96), children: [
          Row(children: [
            IconButton(tooltip: tr('plan.prevWeek'), icon: const Icon(Icons.chevron_left), onPressed: () => _move(-1)),
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _week = weekStart(DateTime.now())),
                child: Text(weekTitle(_start),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: handFont, fontSize: 22, color: nb.ink)),
              ),
            ),
            IconButton(tooltip: tr('plan.nextWeek'), icon: const Icon(Icons.chevron_right), onPressed: () => _move(1)),
          ]),
          Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
            FilledButton.icon(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => ShoppingScreen(start: _start))),
              icon: const Icon(Icons.shopping_cart_outlined),
              label: Text(tr('shop.title')),
            ),
            OutlinedButton.icon(
              onPressed: () => exportWeek(context, _start),
              icon: const Icon(Icons.ios_share),
              label: Text(tr('shop.export')),
            ),
            PopupMenuButton<String>(
              tooltip: tr('plan.more'),
              onSelected: (v) => switch (v) {
                'import' => _importExcel(context),
                'meals' => _chooseMeals(context),
                'clear' => _clear(context),
                _ => null,
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'import', child: _menuRow(Icons.file_open_outlined, tr('plan.importExcel'))),
                PopupMenuItem(value: 'meals', child: _menuRow(Icons.tune, tr('plan.meals'))),
                PopupMenuItem(value: 'clear', child: _menuRow(Icons.delete_sweep_outlined, tr('plan.clear'))),
              ],
              child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.more_horiz)),
            ),
          ]),
          if (!appState.isPro) ...[
            const SizedBox(height: 6),
            if (_locked)
              ProTeaser(icon: Icons.calendar_month_outlined, text: tr('plan.trialOver', {'n': AppState.trialWeeks}))
            else
              Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.hourglass_bottom, color: nb.accent),
                  title: Text(tr('plan.trial', {'n': appState.trialWeeksUsed, 'max': AppState.trialWeeks})),
                  trailing: TextButton(onPressed: () => openPro(context), child: const Text('Pro')),
                ),
              ),
          ],
          const SizedBox(height: 6),
          for (var i = 0; i < 7; i++) _day(context, _start.add(Duration(days: i)), meals, today),
        ]);
      },
    );
  }

  Widget _menuRow(IconData icon, String text) =>
      Row(children: [Icon(icon, size: 20), const SizedBox(width: 10), Flexible(child: Text(text))]);

  Widget _day(BuildContext context, DateTime d, List<Meal> meals, String today) {
    final nb = NotebookColors.of(context);
    final key = planDay(d);
    final isToday = key == today;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: isToday
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: nb.accent, width: 1.5))
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_dayLabel(d, long: true),
              style: TextStyle(fontFamily: handFont, fontSize: 21, color: isToday ? nb.accent : nb.ink)),
          for (final m in meals) _meal(context, key, m),
        ]),
      ),
    );
  }

  Widget _meal(BuildContext context, String day, Meal meal) {
    final scheme = Theme.of(context).colorScheme;
    final entries = appState.plan.entries(day, meal);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 92,
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(mealLabel(meal),
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
          ),
        ),
        Expanded(
          child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (var i = 0; i < entries.length; i++) _entryChip(context, day, meal, i, entries[i]),
            if (!_locked)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: tr('plan.add'),
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => _add(context, day, meal),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _entryChip(BuildContext context, String day, Meal meal, int i, PlanEntry e) {
    final r = appState.recipeById(e.recipeId);
    return InputChip(
      label: Text('${r?.displayTitle ?? tr('plan.gone')} · ${trn('plan.portions', e.servings)}',
          overflow: TextOverflow.ellipsis),
      onPressed: () async {
        final n = await askServings(context, e.servings);
        if (n != null) await appState.planSetServings(day, meal, i, n);
      },
      onDeleted: () => appState.planRemove(day, meal, i),
      deleteButtonTooltipMessage: tr('common.delete'),
    );
  }

  Future<void> _add(BuildContext context, String day, Meal meal) async {
    final r = await pickRecipe(context);
    if (r == null || !context.mounted) return;
    final n = await askServings(context, r.servings > 0 ? r.servings : 2);
    if (n == null) return;
    await appState.planAdd(day, meal, PlanEntry(recipeId: r.id, servings: n));
  }

  Future<void> _chooseMeals(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => ListenableBuilder(
          listenable: appState,
          builder: (ctx, _) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(tr('plan.meals'), style: const TextStyle(fontFamily: handFont, fontSize: 24)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(tr('plan.mealsInfo'), style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
              ),
              for (final m in Meal.values)
                CheckboxListTile(
                  title: Text(mealLabel(m)),
                  value: baseMeals.contains(m) || appState.plan.extraMeals.contains(m),
                  onChanged: baseMeals.contains(m) ? null : (v) => appState.setExtraMeal(m, v == true),
                ),
            ]),
          ),
        ),
      );

  Future<void> _clear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('plan.clearTitle')),
        content: Text(weekTitle(_start)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('common.delete'))),
        ],
      ),
    );
    if (ok == true) await appState.planClearWeek(_start);
  }

  Future<void> _importExcel(BuildContext context) async {
    try {
      final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['xlsx'], withData: true);
      final f = res?.files.single;
      final bytes = f?.bytes ?? (f?.path == null ? null : await File(f!.path!).readAsBytes());
      if (bytes == null) return;
      final r = ExcelForm.importWeek(bytes, appState.recipes.where(appState.canOpen).toList());
      final skipped = await appState.planImport(r.entries);
      if (context.mounted) {
        showSnack(context, tr('plan.imported', {'n': r.entries.length - skipped, 'missing': r.missing}));
        if (skipped > 0) await showProOffer(context, tr('plan.trialOver', {'n': AppState.trialWeeks}));
      }
    } catch (_) {
      if (context.mounted) showSnack(context, tr('import.badFile'));
    }
  }
}

/// Elenco delle ricette (apribili) con la ricerca, per scegliere quella del pasto.
Future<Recipe?> pickRecipe(BuildContext context) => showModalBottomSheet<Recipe>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const FractionallySizedBox(heightFactor: 0.85, child: _RecipePicker()),
    );

class _RecipePicker extends StatefulWidget {
  const _RecipePicker();

  @override
  State<_RecipePicker> createState() => _RecipePickerState();
}

class _RecipePickerState extends State<_RecipePicker> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = appState.sortedForList(appState.recipes.where(appState.canOpen));
    final list = all.where((r) => r.matchesSearch(_q.text)).toList()
      ..sort((a, b) => a.category.index.compareTo(b.category.index));
    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _q,
            autofocus: false,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('plan.pickHint')),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(child: Text(all.isEmpty ? tr('plan.noRecipes') : tr('search.none')))
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (ctx, i) {
                    final r = list[i];
                    final head = i == 0 || list[i - 1].category != r.category;
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (head)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                          child: Text(categoryLabel(r.category),
                              style: TextStyle(fontWeight: FontWeight.w700, color: NotebookColors.of(ctx).accent)),
                        ),
                      ListTile(
                        dense: true,
                        leading: RecipeThumb(recipe: r, size: 40),
                        title: Text(r.displayTitle),
                        subtitle: r.servings > 0 ? Text(tr('recipe.people', {'n': r.servings})) : null,
                        onTap: () => Navigator.pop(ctx, r),
                      ),
                    ]);
                  },
                ),
        ),
      ]),
    );
  }
}

/// Porzioni da 1 a 99 con − e +.
Future<int?> askServings(BuildContext context, int initial) {
  var n = initial.clamp(1, 99);
  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(tr('plan.portionsTitle')),
        content: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton.filledTonal(onPressed: n > 1 ? () => set(() => n--) : null, icon: const Icon(Icons.remove)),
          SizedBox(
            width: 64,
            child: Text('$n', textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
          ),
          IconButton.filledTonal(onPressed: n < 99 ? () => set(() => n++) : null, icon: const Icon(Icons.add)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, n), child: Text(tr('common.ok'))),
        ],
      ),
    ),
  );
}

List<ShoppingItem> _shopping(DateTime start) => ShoppingList.build(
      [for (final e in _weekEntries(start)) e.entry],
      appState.recipeById,
      comma: _comma,
      pantryLabel: tr('shop.pantry'),
      eggsLabel: tr('shop.eggs'),
    );

/// Un solo pulsante "Esporta": poi si sceglie il formato (PDF o Excel).
Future<void> exportWeek(BuildContext context, DateTime start, {bool includePlan = true}) async {
  final format = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(tr('shop.exportWhich'), style: const TextStyle(fontFamily: handFont, fontSize: 24)),
        ),
        ListTile(
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: const Text('PDF'),
          subtitle: Text(includePlan ? tr('plan.pdf') : tr('shop.title')),
          onTap: () => Navigator.pop(ctx, 'pdf'),
        ),
        ListTile(
          leading: const Icon(Icons.table_chart_outlined),
          title: const Text('Excel'),
          subtitle: Text(tr('shop.excelInfo')),
          onTap: () => Navigator.pop(ctx, 'xlsx'),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (!context.mounted || format == null) return;
  format == 'pdf' ? await _sharePdf(context, start, includePlan: includePlan) : await _shareExcel(context, start);
}

const String _xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

Future<void> _sharePdf(BuildContext context, DateTime start, {bool includePlan = true}) async {
  showSnack(context, tr('pdf.creating'));
  try {
    final bytes = await PdfExport.buildWeek(
      title: weekTitle(start),
      start: start,
      meals: appState.plan.meals,
      plan: appState.plan,
      byId: appState.recipeById,
      shopping: _shopping(start),
      includePlan: includePlan,
    );
    if (!context.mounted) return;
    await saveThenOfferShare(context, bytes,
        PdfExport.fileName(includePlan ? tr('plan.title') : tr('shop.title')), 'application/pdf', weekTitle(start));
  } catch (e) {
    if (context.mounted) showSnack(context, tr('pdf.error', {'error': e}));
  }
}

Future<void> _shareExcel(BuildContext context, DateTime start) async {
  try {
    final bytes = ExcelForm.exportWeek(_weekEntries(start), appState.recipeById, comma: _comma);
    await saveThenOfferShare(context, bytes, 'FamilyRecipes-${planDay(start)}.xlsx', _xlsxMime, weekTitle(start));
  } catch (_) {
    if (context.mounted) showSnack(context, tr('export.failed'));
  }
}

/// Prima salva il file sul telefono (si sceglie dove), poi offre di condividerlo. Se il salvataggio
/// non è disponibile o viene annullato, si può comunque condividere.
Future<void> saveThenOfferShare(
    BuildContext context, Uint8List bytes, String fileName, String mime, String text) async {
  Future<void> share() async {
    final f = File('${(await getTemporaryDirectory()).path}/$fileName');
    await f.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: mime)], text: text));
  }

  String? saved;
  try {
    saved = await FilePicker.saveFile(fileName: fileName, bytes: bytes);
  } catch (_) {}
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: Text(saved != null ? tr('shop.saved', {'name': fileName}) : tr('shop.notSaved')),
      action: SnackBarAction(label: tr('backup.share'), onPressed: () => share()),
    ));
}

/// Lista della spesa della settimana: ingredienti sommati, da spuntare mentre si compra.
class ShoppingScreen extends StatefulWidget {
  final DateTime start;
  const ShoppingScreen({super.key, required this.start});

  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> {
  final Set<String> _done = {};

  @override
  Widget build(BuildContext context) {
    final items = _shopping(widget.start);
    final scheme = Theme.of(context).colorScheme;
    return TableclothBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(tr('shop.title'))),
        // Esportazione sempre in vista, in basso.
        bottomNavigationBar: items.isEmpty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                  child: FilledButton.icon(
                    onPressed: () => exportWeek(context, widget.start, includePlan: false),
                    icon: const Icon(Icons.ios_share),
                    label: Text(tr('shop.export')),
                  ),
                ),
              ),
        body: NotebookPage(
          child: ListView(padding: const EdgeInsets.fromLTRB(4, 8, 10, 24), children: [
            Text(weekTitle(widget.start),
                textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            if (items.isEmpty) EmptyState(icon: Icons.shopping_cart_outlined, title: tr('shop.empty'), hint: tr('shop.emptyHint')),
            for (final i in items)
              CheckboxListTile(
                controlAffinity: ListTileControlAffinity.leading,
                value: _done.contains(i.name),
                onChanged: (v) => setState(() => v == true ? _done.add(i.name) : _done.remove(i.name)),
                title: Text(i.name,
                    style: TextStyle(
                        decoration: _done.contains(i.name) ? TextDecoration.lineThrough : null,
                        fontWeight: FontWeight.w600)),
                subtitle: Text(i.recipes.join(', '), maxLines: i.pantry ? 6 : 2, overflow: TextOverflow.ellipsis),
                secondary: i.pantry
                    ? Icon(Icons.kitchen_outlined, color: scheme.onSurfaceVariant)
                    : Text(i.amountText, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ]),
        ),
      ),
    );
  }
}
