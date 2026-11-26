import 'dart:typed_data';

import 'package:familyrecipes/l10n.dart';
import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/services/excel_form.dart';
import 'package:familyrecipes/services/xlsx.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => L10n.load('it'));

  test('xlsx: testi strani e numeri andata e ritorno', () {
    final bytes = Xlsx.write([
      const XlsxSheet('Uno/<prova>', [
        ['A', 'B & C', 'Città "quoted"'],
        ['x', 42, '🍝 ricetta\nsu due righe'],
        [null, '', 3.5],
      ]),
    ]);
    final book = Xlsx.read(bytes);
    final rows = book.values.single;
    expect(rows[0], ['A', 'B & C', 'Città "quoted"']);
    expect(rows[1], ['x', '42', '🍝 ricetta\nsu due righe']);
    expect(rows[2], ['', '', '3.5']);
  });

  test('modulo Excel: ricette esportate e reimportate', () {
    final r = Recipe(
      title: 'Pasta e patate',
      category: RecipeCategory.primi,
      difficulty: Difficulty.medium,
      cost: Cost.veryLow,
      servings: 4,
      prepMinutes: 10,
      cookMinutes: 30,
      intro: 'Della nonna',
      tips: 'Con la provola',
      ingredients: [Ingredient(name: 'Patate', amount: '400 g'), Ingredient(name: 'Pasta mista', amount: '320 g')],
      steps: [RecipeStep(text: 'Soffriggi'), RecipeStep(text: 'Cuoci la pasta nel brodo')],
    );
    final back = ExcelForm.importRecipes(ExcelForm.export([r, Recipe(title: 'Patate al forno', category: RecipeCategory.contorni)]));
    expect(back.length, 2);
    final b = back.first.recipe;
    expect([b.title, b.category, b.difficulty, b.cost, b.servings, b.prepMinutes, b.cookMinutes, b.intro, b.tips],
        ['Pasta e patate', RecipeCategory.primi, Difficulty.medium, Cost.veryLow, 4, 10, 30, 'Della nonna', 'Con la provola']);
    expect(b.ingredients.map((i) => '${i.name}=${i.amount}'), ['Patate=400 g', 'Pasta mista=320 g']);
    expect(b.steps.map((s) => s.text), ['Soffriggi', 'Cuoci la pasta nel brodo']);
    expect(back.last.recipe.category, RecipeCategory.contorni);
  });

  test('modulo vuoto: si importa la ricetta d\'esempio; file non Excel = errore', () {
    expect(ExcelForm.importRecipes(ExcelForm.template()).single.recipe.ingredients, hasLength(2));
    expect(() => ExcelForm.importRecipes(Uint8ListOf('ciao')), throwsFormatException);
  });

  test('settimana: esportata e reimportata cercando le ricette per titolo', () {
    final pp = Recipe(id: 'pp', title: 'Pasta e patate', servings: 4);
    final plan = [
      (day: '2026-11-30', meal: Meal.pranzo, entry: PlanEntry(recipeId: 'pp', servings: 3)),
      (day: '2026-12-01', meal: Meal.cena, entry: PlanEntry(recipeId: 'pp', servings: 2)),
    ];
    final bytes = ExcelForm.exportWeek(plan, (id) => id == 'pp' ? pp : null);
    final res = ExcelForm.importWeek(bytes, [Recipe(id: 'nuovo', title: 'pasta E PATATE')]);
    expect(res.missing, 0);
    expect(res.entries.map((e) => '${e.day} ${e.meal.name} ${e.entry.recipeId} ${e.entry.servings}'),
        ['2026-11-30 pranzo nuovo 3', '2026-12-01 cena nuovo 2']);
    final none = ExcelForm.importWeek(bytes, []);
    expect(none.missing, 2);
  });
}

// ignore: non_constant_identifier_names
Uint8List Uint8ListOf(String s) => Uint8List.fromList(s.codeUnits);
