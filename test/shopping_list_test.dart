import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/services/shopping_list.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pastaPatate = Recipe(id: 'pp', title: 'Pasta e patate', servings: 4, ingredients: [
    Ingredient(name: 'Patate', amount: '400 g'),
    Ingredient(name: 'Pasta mista', amount: '320 g'),
    Ingredient(name: 'Sale', amount: 'q.b.'),
  ]);
  final patateForno = Recipe(id: 'pf', title: 'Patate al forno', servings: 2, ingredients: [
    Ingredient(name: 'patate', amount: '0,5 kg'),
    Ingredient(name: 'Olio', amount: '2 cucchiai'),
    Ingredient(name: 'Rosmarino', amount: '1 rametto'),
  ]);
  Recipe? byId(String id) => {'pp': pastaPatate, 'pf': patateForno}[id];

  test('lista della spesa: stesso piatto in due giorni e un altro piatto, porzioni diverse', () {
    final list = ShoppingList.build([
      PlanEntry(recipeId: 'pp', servings: 4), // lunedì
      PlanEntry(recipeId: 'pp', servings: 2), // mercoledì: metà dose
      PlanEntry(recipeId: 'pf', servings: 4), // venerdì: dose doppia
      PlanEntry(recipeId: 'sparita', servings: 3),
    ], byId);
    final patate = list.firstWhere((i) => i.name == 'Patate');
    // 400 + 200 + 1000 g
    expect(patate.amounts, ['1,6 kg']);
    expect(patate.uses, 3);
    expect(patate.recipes, containsAll(['Pasta e patate', 'Patate al forno']));
    expect(list.firstWhere((i) => i.name == 'Pasta mista').amounts, ['480 g']);
    expect(list.firstWhere((i) => i.name == 'Sale').amountText, 'q.b.');
    expect(list.firstWhere((i) => i.name == 'Olio').amounts, ['4 cucchiai']);
    expect(list.firstWhere((i) => i.name == 'Rosmarino').amounts, ['2 rametto']);
    expect(list.map((i) => i.name), orderedEquals([...list.map((i) => i.name)]..sort()));
  });

  test('lista della spesa: unità diverse dello stesso ingrediente restano separate, numeri senza unità', () {
    final r = Recipe(id: 'a', title: 'Frittata', servings: 2, ingredients: [
      Ingredient(name: 'Uova', amount: '4'),
      Ingredient(name: 'Latte', amount: '200 ml'),
      Ingredient(name: 'Latte', amount: '1 tazza'),
      Ingredient(name: '', amount: '2 zucchine'),
    ]);
    final list = ShoppingList.build([PlanEntry(recipeId: 'a', servings: 1)], (_) => r, comma: false);
    expect(list.firstWhere((i) => i.name == 'Uova').amounts, ['2']);
    expect(list.firstWhere((i) => i.name == 'Latte').amounts, ['100 ml', '0.5 tazza']);
    expect(list.firstWhere((i) => i.name == 'Zucchine').amounts, ['1']);
  });

  test('piano: andata e ritorno JSON, pasti extra, giorni', () {
    final p = MealPlan(extraMeals: {Meal.colazione, Meal.pranzo});
    p.add('2026-11-30', Meal.cena, PlanEntry(recipeId: 'pp', servings: 3));
    p.add('2026-11-30', Meal.cena, PlanEntry(recipeId: 'pf', servings: 2));
    final b = MealPlan.fromJson(p.toJson());
    expect(b.extraMeals, {Meal.colazione}, reason: 'pranzo è già fisso');
    expect(b.meals, [Meal.colazione, Meal.pranzo, Meal.cena]);
    expect(b.entries('2026-11-30', Meal.cena).map((e) => e.servings), [3, 2]);
    b.remove('2026-11-30', Meal.cena, 0);
    b.remove('2026-11-30', Meal.cena, 0);
    expect(b.days, isEmpty);
    expect(planDay(weekStart(DateTime(2026, 12, 3))), '2026-11-30');
    expect(MealPlan.fromJson('rotto').days, isEmpty);
  });
}
