import 'dart:typed_data';

import '../l10n.dart';
import '../models.dart';
import 'recipe_import.dart';
import 'recipe_words.dart';
import 'shopping_list.dart';
import 'xlsx.dart';

/// Modulo Excel delle ricette e della settimana, da compilare al computer e importare (o esportare per
/// modificarlo e reimportarlo).
///
/// Ricette: **un foglio per ricetta** (il nome del foglio è il titolo), sempre con questa forma:
/// - righe 1–10, in colonna B: Titolo, Categoria, Porzioni, Difficoltà, Costo, Preparazione (min),
///   Cottura (min), Autore, Introduzione, Consigli (in colonna A le etichette);
/// - riga 12: intestazione degli ingredienti (Ingrediente · Quantità), poi un ingrediente per riga;
/// - una riga con «N.» in colonna A: intestazione dei passaggi, poi un passaggio per riga (N. · Testo).
/// Per aggiungere una ricetta basta copiare un foglio. L'ultimo foglio («Valori») elenca categorie,
/// difficoltà, costi e pasti ammessi.
///
/// Settimana (file della Pianificazione): Giorno (AAAA-MM-GG) · Pasto · Ricetta · Porzioni.
class ExcelForm {
  /// Etichette delle righe 1–10 di ogni foglio ricetta.
  static List<String> get _fieldLabels => [
        tr('xls.title'),
        tr('recipe.category'),
        tr('recipe.servings'),
        tr('recipe.difficulty'),
        tr('recipe.cost'),
        '${tr('recipe.prep')} (min)',
        '${tr('recipe.cook')} (min)',
        tr('xls.author'),
        tr('xls.intro'),
        tr('recipe.tips'),
      ];

  /// Riga (0 = prima) dell'intestazione degli ingredienti.
  static const int _ingHeaderRow = 11;

  /// Marcatore della riga d'intestazione dei passaggi (colonna A), uguale in tutte le lingue.
  static const String _stepsMark = 'N.';

  static String _sheetName(String title, Set<String> used) {
    var base = title.replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (base.isEmpty) base = tr('xls.recipeTitle');
    if (base.length > 25) base = base.substring(0, 25).trim(); // con " (99)" resta entro i 31 caratteri di Excel
    var name = base;
    var i = 2;
    while (used.contains(name.toLowerCase())) {
      name = '$base ($i)';
      i++;
    }
    used.add(name.toLowerCase());
    return name;
  }

  static XlsxSheet _recipeSheet(Recipe r, Set<String> used) {
    final labels = _fieldLabels;
    final values = <Object?>[
      r.title,
      categoryLabel(r.category),
      r.servings,
      difficultyLabel(r.difficulty),
      costLabel(r.cost),
      r.prepMinutes,
      r.cookMinutes,
      r.createdByName,
      r.intro,
      r.tips,
    ];
    return XlsxSheet(
      _sheetName(r.displayTitle, used),
      [
        for (var i = 0; i < labels.length; i++) [labels[i], values[i]],
        [],
        [tr('xls.ingredient'), tr('xls.amount')],
        for (final g in r.ingredients) [g.name, g.amount],
        [],
        [_stepsMark, tr('xls.stepText')],
        for (var n = 0; n < r.steps.length; n++) [n + 1, r.steps[n].text],
      ],
      widths: const [26, 70],
      boldRows: {_ingHeaderRow, _ingHeaderRow + 2 + r.ingredients.length},
      boldFirstColumn: true,
      freezeHeader: false,
    );
  }

  static List<XlsxSheet> _recipeSheets(List<Recipe> recipes) {
    final used = <String>{tr('xls.sheetValues').toLowerCase()};
    return [for (final r in recipes) if (!r.deleted) _recipeSheet(r, used)];
  }

  static XlsxSheet _planSheet(List<({String day, Meal meal, PlanEntry entry})> plan, Recipe? Function(String) byId) =>
      XlsxSheet(tr('xls.sheetWeek'), [
        [tr('xls.day'), tr('xls.meal'), tr('xls.recipeTitle'), tr('recipe.servings')],
        for (final p in plan)
          if (byId(p.entry.recipeId) case final r?) [p.day, mealLabel(p.meal), r.displayTitle, p.entry.servings],
      ], widths: const [14, 16, 34, 10]);

  static XlsxSheet _valuesSheet() {
    final cols = <List<String>>[
      [for (final c in RecipeCategory.values) categoryLabel(c)],
      [for (final d in Difficulty.values) difficultyLabel(d)],
      [for (final c in Cost.values) costLabel(c)],
      [for (final m in Meal.values) mealLabel(m)],
    ];
    final n = cols.map((c) => c.length).reduce((a, b) => a > b ? a : b);
    return XlsxSheet(tr('xls.sheetValues'), [
      [tr('recipe.category'), tr('recipe.difficulty'), tr('recipe.cost'), tr('xls.meal')],
      for (var i = 0; i < n; i++) [for (final c in cols) i < c.length ? c[i] : ''],
    ], widths: const [22, 16, 14, 18]);
  }

  /// Ricette (e, se c'è, la settimana) in un file .xlsx.
  static Uint8List export(
    List<Recipe> recipes, {
    List<({String day, Meal meal, PlanEntry entry})> plan = const [],
    Recipe? Function(String id)? byId,
  }) =>
      Xlsx.write([
        ..._recipeSheets(recipes),
        if (plan.isNotEmpty) _planSheet(plan, byId ?? (_) => null),
        _valuesSheet(),
      ]);

  /// Modulo vuoto con una ricetta d'esempio, da compilare.
  static Uint8List template() {
    final example = Recipe(
      title: tr('xls.exampleTitle'),
      category: RecipeCategory.primi,
      servings: 4,
      prepMinutes: 15,
      cookMinutes: 20,
      ingredients: [
        Ingredient(name: tr('xls.exampleIng1'), amount: '320 g'),
        Ingredient(name: tr('xls.exampleIng2'), amount: '400 g'),
      ],
      steps: [RecipeStep(text: tr('xls.exampleStep1')), RecipeStep(text: tr('xls.exampleStep2'))],
    );
    return export([example]);
  }

  /// Settimana e lista della spesa in un file .xlsx.
  static Uint8List exportWeek(
    List<({String day, Meal meal, PlanEntry entry})> plan,
    Recipe? Function(String id) byId, {
    bool comma = true,
  }) {
    final shopping = ShoppingList.build([for (final p in plan) p.entry], byId,
        comma: comma, pantryLabel: tr('shop.pantry'), eggsLabel: tr('shop.eggs'));
    return Xlsx.write([
      _planSheet(plan, byId),
      XlsxSheet(tr('shop.title'), [
        [tr('xls.ingredient'), tr('xls.amount'), tr('shop.usedIn')],
        for (final i in shopping) [i.name, i.amountText, i.recipes.join(', ')],
      ], widths: const [28, 22, 50]),
    ]);
  }

  // ---- Importazione ----

  static String _cell(List<String> row, int i) => i < row.length ? row[i].trim() : '';

  static int _num(String s) {
    final m = RegExp(r'\d+').firstMatch(s);
    return m == null ? 0 : (int.tryParse(m[0]!) ?? 0).clamp(0, 100000);
  }

  static RecipeCategory? _category(String s) {
    if (s.isEmpty) return null;
    final f = foldForSearch(s);
    for (final c in RecipeCategory.values) {
      if (foldForSearch(categoryLabel(c)) == f) return c;
    }
    return RecipeWords.categoryFromLabel(s);
  }

  static T? _match<T>(String s, List<T> values, String Function(T) label) {
    final f = foldForSearch(s);
    for (final v in values) {
      if (foldForSearch(label(v)) == f) return v;
    }
    return null;
  }

  /// Ricette del modulo: un foglio per ricetta (vedi sopra); gli altri fogli si saltano. Lancia
  /// [FormatException] se il file non è un .xlsx o non contiene ricette.
  static List<ImportedRecipe> importRecipes(Uint8List bytes) {
    final book = Xlsx.read(bytes);
    final out = <ImportedRecipe>[];
    for (final rows in book.values) {
      final r = _readRecipeSheet(rows);
      if (r != null) out.add(ImportedRecipe(r, null));
    }
    if (out.isEmpty) throw const FormatException('no recipes');
    return out;
  }

  static Recipe? _readRecipeSheet(List<List<String>> rows) {
    // Un foglio ricetta ha la riga «N.» dei passaggi e il titolo in B1.
    final stepsRow = rows.indexWhere((r) => _cell(r, 0) == _stepsMark);
    if (stepsRow < 0 || rows.isEmpty) return null;
    String field(int i) => i < rows.length ? _cell(rows[i], 1) : '';
    final title = field(0);
    if (title.isEmpty) return null;
    final servings = _num(field(2));
    final r = Recipe(
      title: title,
      category: _category(field(1)) ?? RecipeWords.guessCategory(title),
      servings: servings == 0 ? 4 : servings.clamp(1, 99),
      difficulty: _match(field(3), Difficulty.values, difficultyLabel) ?? RecipeWords.difficulty(field(3)) ?? Difficulty.easy,
      cost: _match(field(4), Cost.values, costLabel) ?? RecipeWords.cost(field(4)) ?? Cost.low,
      prepMinutes: _num(field(5)),
      cookMinutes: _num(field(6)),
      intro: field(8),
      tips: field(9),
    )..createdByName = field(7);
    for (var i = _ingHeaderRow + 1; i < stepsRow && i < rows.length; i++) {
      final name = _cell(rows[i], 0), amount = _cell(rows[i], 1);
      if (name.isNotEmpty || amount.isNotEmpty) r.ingredients.add(Ingredient(name: name, amount: amount));
    }
    final steps = <(int, int, String)>[];
    for (var i = stepsRow + 1; i < rows.length; i++) {
      final text = _cell(rows[i], 1).isNotEmpty ? _cell(rows[i], 1) : _cell(rows[i], 0);
      if (text.isEmpty || RegExp(r'^\d+$').hasMatch(text)) continue;
      final n = int.tryParse(_cell(rows[i], 0));
      steps.add((n ?? 100000 + i, i, text));
    }
    steps.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    r.steps = [for (final s in steps) RecipeStep(text: s.$3)];
    return r;
  }

  /// Voci della settimana del modulo: le ricette si cercano per titolo tra [recipes]; quelle che non si
  /// trovano sono contate in `missing`.
  static ({List<({String day, Meal meal, PlanEntry entry})> entries, int missing}) importWeek(
      Uint8List bytes, List<Recipe> recipes) {
    final book = Xlsx.read(bytes);
    // Il foglio della settimana: quello con una data nella prima colonna (dalla seconda riga).
    final rows = book.values.firstWhere(
      (rows) => rows.skip(1).any((r) => _day(_cell(r, 0)) != null),
      orElse: () => const [],
    );
    final byTitle = <String, Recipe>{for (final r in recipes.reversed) if (!r.deleted) foldForSearch(r.title.trim()): r};
    final out = <({String day, Meal meal, PlanEntry entry})>[];
    var missing = 0;
    for (final row in rows.skip(1)) {
      final day = _day(_cell(row, 0));
      final meal = _match(_cell(row, 1), Meal.values, mealLabel) ?? mealFrom(_cell(row, 1).toLowerCase());
      final title = _cell(row, 2);
      if (day == null || meal == null || title.isEmpty) continue;
      final r = byTitle[foldForSearch(title)];
      if (r == null) {
        missing++;
        continue;
      }
      final n = _num(_cell(row, 3));
      out.add((day: day, meal: meal, entry: PlanEntry(recipeId: r.id, servings: n == 0 ? (r.servings > 0 ? r.servings : 2) : n.clamp(1, 99))));
    }
    return (entries: out, missing: missing);
  }

  /// "2026-11-30", "30/11/2026" o un numero di serie di Excel → "2026-11-30".
  static String? _day(String s) {
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
    if (iso != null) return planDay(DateTime(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!)));
    final eu = RegExp(r'^(\d{1,2})[/.](\d{1,2})[/.](\d{4})$').firstMatch(s);
    if (eu != null) return planDay(DateTime(int.parse(eu[3]!), int.parse(eu[2]!), int.parse(eu[1]!)));
    final serial = int.tryParse(s);
    if (serial != null && serial > 20000 && serial < 80000) {
      return planDay(DateTime(1899, 12, 30).add(Duration(days: serial)));
    }
    return null;
  }
}
