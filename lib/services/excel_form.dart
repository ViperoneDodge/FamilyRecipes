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
/// Fogli, sempre in quest'ordine (l'importazione li riconosce dalla posizione, non dal nome, che è tradotto):
/// 1. Ricette: ID · Titolo · Categoria · Introduzione · Difficoltà · Costo · Preparazione (min) · Cottura (min)
///    · Porzioni · Consigli · Autore
/// 2. Ingredienti: ID ricetta · Titolo ricetta · Ingrediente · Quantità
/// 3. Passaggi: ID ricetta · Titolo ricetta · N. · Testo
/// 4. Settimana: Giorno (AAAA-MM-GG) · Pasto · Ricetta · Porzioni
/// 5. Valori: le categorie, difficoltà, costi e pasti ammessi.
class ExcelForm {
  static List<String> get _recipeHeader => [
        'ID',
        tr('xls.title'),
        tr('recipe.category'),
        tr('xls.intro'),
        tr('recipe.difficulty'),
        tr('recipe.cost'),
        '${tr('recipe.prep')} (min)',
        '${tr('recipe.cook')} (min)',
        tr('recipe.servings'),
        tr('recipe.tips'),
        tr('xls.author'),
      ];

  static List<XlsxSheet> _recipeSheets(List<Recipe> recipes) {
    final live = [for (final r in recipes) if (!r.deleted) r];
    String id(int i) => 'R${(i + 1).toString().padLeft(3, '0')}';
    return [
      XlsxSheet(tr('xls.sheetRecipes'), [
        _recipeHeader,
        for (var i = 0; i < live.length; i++)
          [
            id(i),
            live[i].title,
            categoryLabel(live[i].category),
            live[i].intro,
            difficultyLabel(live[i].difficulty),
            costLabel(live[i].cost),
            live[i].prepMinutes,
            live[i].cookMinutes,
            live[i].servings,
            live[i].tips,
            live[i].createdByName,
          ],
      ], widths: const [8, 30, 16, 40, 14, 12, 14, 14, 10, 40, 18]),
      XlsxSheet(tr('xls.sheetIngredients'), [
        ['ID', tr('xls.recipeTitle'), tr('xls.ingredient'), tr('xls.amount')],
        for (var i = 0; i < live.length; i++)
          for (final g in live[i].ingredients) [id(i), live[i].title, g.name, g.amount],
      ], widths: const [8, 30, 30, 16]),
      XlsxSheet(tr('xls.sheetSteps'), [
        ['ID', tr('xls.recipeTitle'), 'N.', tr('xls.stepText')],
        for (var i = 0; i < live.length; i++)
          for (var n = 0; n < live[i].steps.length; n++) [id(i), live[i].title, n + 1, live[i].steps[n].text],
      ], widths: const [8, 30, 6, 80]),
    ];
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
        _planSheet(plan, byId ?? (_) => null),
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
    final shopping = ShoppingList.build([for (final p in plan) p.entry], byId, comma: comma);
    return Xlsx.write([
      _planSheet(plan, byId),
      XlsxSheet(tr('shop.title'), [
        [tr('xls.ingredient'), tr('xls.amount'), tr('shop.usedIn')],
        for (final i in shopping) [i.name, i.amountText, i.recipes.join(', ')],
      ], widths: const [28, 22, 50]),
    ]);
  }

  // ---- Importazione ----

  static List<List<String>> _sheet(Map<String, List<List<String>>> book, int i) {
    final l = book.values.toList();
    return i < l.length ? l[i] : const [];
  }

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

  /// Ricette del modulo. Gli ingredienti e i passaggi si collegano alla ricetta con l'ID o, se manca, con
  /// il titolo. Lancia [FormatException] se il file non è un .xlsx o non ha il foglio delle ricette.
  static List<ImportedRecipe> importRecipes(Uint8List bytes) {
    final book = Xlsx.read(bytes);
    final rows = _sheet(book, 0);
    if (rows.isEmpty) throw const FormatException('no recipes sheet');
    final byKey = <String, Recipe>{};
    final out = <Recipe>[];
    String key(String id, String title) => id.isNotEmpty ? 'id:${id.toLowerCase()}' : 't:${foldForSearch(title)}';
    for (final row in rows.skip(1)) {
      final title = _cell(row, 1);
      if (title.isEmpty) continue;
      final servings = _num(_cell(row, 8));
      final r = Recipe(
        title: title,
        category: _category(_cell(row, 2)) ?? RecipeWords.guessCategory(title),
        intro: _cell(row, 3),
        difficulty: _match(_cell(row, 4), Difficulty.values, difficultyLabel) ??
            RecipeWords.difficulty(_cell(row, 4)) ??
            Difficulty.easy,
        cost: _match(_cell(row, 5), Cost.values, costLabel) ?? RecipeWords.cost(_cell(row, 5)) ?? Cost.low,
        prepMinutes: _num(_cell(row, 6)),
        cookMinutes: _num(_cell(row, 7)),
        servings: servings == 0 ? 4 : servings.clamp(1, 99),
        tips: _cell(row, 9),
      )..createdByName = _cell(row, 10);
      out.add(r);
      byKey.putIfAbsent(key(_cell(row, 0), title), () => r);
      byKey.putIfAbsent(key('', title), () => r);
    }
    Recipe? find(List<String> row) => byKey[key(_cell(row, 0), _cell(row, 1))] ?? byKey[key('', _cell(row, 1))];
    for (final row in _sheet(book, 1).skip(1)) {
      final r = find(row);
      final name = _cell(row, 2);
      if (r != null && (name.isNotEmpty || _cell(row, 3).isNotEmpty)) {
        r.ingredients.add(Ingredient(name: name, amount: _cell(row, 3)));
      }
    }
    final steps = <Recipe, List<(int, String)>>{};
    for (final row in _sheet(book, 2).skip(1)) {
      final r = find(row);
      final text = _cell(row, 3);
      if (r != null && text.isNotEmpty) (steps[r] ??= []).add((_num(_cell(row, 2)), text));
    }
    steps.forEach((r, l) {
      l.sort((a, b) => a.$1.compareTo(b.$1));
      r.steps = [for (final s in l) RecipeStep(text: s.$2)];
    });
    return [for (final r in out) ImportedRecipe(r, null)];
  }

  /// Voci della settimana del modulo: le ricette si cercano per titolo tra [recipes]; quelle che non si
  /// trovano sono contate in `missing`.
  static ({List<({String day, Meal meal, PlanEntry entry})> entries, int missing}) importWeek(
      Uint8List bytes, List<Recipe> recipes) {
    final book = Xlsx.read(bytes);
    // Il foglio della settimana è il quarto nel modulo completo, il primo in quello della settimana.
    var rows = _sheet(book, 3);
    if (rows.isEmpty || _cell(rows.first, 0) == 'ID') rows = _sheet(book, 0);
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
