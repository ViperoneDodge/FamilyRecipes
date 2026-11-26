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
    // Sale e olio vanno nella voce della dispensa, da controllare.
    expect(list.last.pantry, isTrue);
    expect(list.last.recipes, ['Olio', 'Sale']);
    expect(list.firstWhere((i) => i.name == 'Rosmarino').amounts, ['2 rametto']);
    final buy = list.where((i) => !i.pantry).map((i) => i.name).toList();
    expect(buy, orderedEquals([...buy]..sort()));
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

  group('uova: intere, tuorli e albumi', () {
    int eggs(List<Ingredient> ings, {int servings = 4, int planned = 4}) {
      final r = Recipe(id: 'x', title: 'Dolce', servings: servings, ingredients: ings);
      final l = ShoppingList.build([PlanEntry(recipeId: 'x', servings: planned)], (_) => r, eggsLabel: 'Uova');
      return int.parse(l.firstWhere((i) => i.name == 'Uova').amounts.single);
    }

    test('4 tuorli e 3 albumi = 4 uova', () {
      expect(eggs([Ingredient(name: 'Tuorli', amount: '4'), Ingredient(name: 'Albumi', amount: '3')]), 4);
    });
    test('4 tuorli e 6 albumi = 6 uova', () {
      expect(eggs([Ingredient(name: 'tuorli d\'uovo', amount: '4'), Ingredient(name: '', amount: '6 albumi')]), 6);
    });
    test('4 uova e 3 tuorli = 7 uova', () {
      expect(eggs([Ingredient(name: 'Uova', amount: '4'), Ingredient(name: 'Tuorlo', amount: '3')]), 7);
    });
    test('mezze dosi: si arrotonda all\'uovo intero', () {
      // 3 uova per 4 → per 2 = 1,5 → 2
      expect(eggs([Ingredient(name: 'Uova', amount: '3 medie')], planned: 2), 2);
    });
    test('in inglese e in tedesco', () {
      expect(eggs([Ingredient(name: 'Egg yolks', amount: '2'), Ingredient(name: 'eggs', amount: '2')]), 4);
      expect(eggs([Ingredient(name: 'Eigelb', amount: '3'), Ingredient(name: 'Eiweiß', amount: '1')]), 3);
    });
    test('a peso: uovo medio 50 g, tuorlo 18 g, albume 32 g, arrotondando per eccesso', () {
      // 120 g di albumi = 3,75 → 4 uova
      expect(eggs([Ingredient(name: 'Albumi', amount: '120 g')]), 4);
      // 100 g di uova intere = 2 uova; più 3 tuorli = 5
      expect(eggs([Ingredient(name: 'Uova', amount: '100 g'), Ingredient(name: 'Tuorli', amount: '3')]), 5);
      // 40 g di tuorli = 2,2 tuorli; 3 albumi → 3 uova
      expect(eggs([Ingredient(name: 'Tuorli', amount: '40 g'), Ingredient(name: 'Albumi', amount: '3')]), 3);
      // 0,25 kg di albumi = 7,8 → 8
      expect(eggs([Ingredient(name: 'Albumi', amount: '0,25 kg')]), 8);
      // 100 ml di albume = 3,1 → 4
      expect(eggs([Ingredient(name: 'Albume', amount: '100 ml')]), 4);
    });
  });

  test('dispensa: sale, pepe, spezie, acqua, olio e aceto in una sola voce, per ultima', () {
    final r = Recipe(id: 'x', title: 'Insalata', servings: 2, ingredients: [
      Ingredient(name: 'Sale', amount: 'q.b.'),
      Ingredient(name: 'Pepe nero', amount: 'un pizzico'),
      Ingredient(name: 'Olio extravergine d\'oliva', amount: '3 cucchiai'),
      Ingredient(name: 'Aceto balsamico', amount: '1 cucchiaio'),
      Ingredient(name: 'Acqua', amount: '200 ml'),
      Ingredient(name: 'Origano', amount: ''),
      Ingredient(name: 'Peperoni', amount: '2'),
      Ingredient(name: 'Insalata', amount: '1 cespo'),
      Ingredient(name: 'Salsiccia', amount: '300 g'),
    ]);
    final l = ShoppingList.build([PlanEntry(recipeId: 'x', servings: 2)], (_) => r, pantryLabel: 'Dispensa');
    expect(l.map((i) => i.name), ['Insalata', 'Peperoni', 'Salsiccia', 'Dispensa']);
    expect(l.last.pantry, isTrue);
    expect(l.last.recipes, ['Aceto balsamico', 'Acqua', 'Olio extravergine d\'oliva', 'Origano', 'Pepe nero', 'Sale']);
    expect(l.last.amounts, isEmpty);
  });
}
