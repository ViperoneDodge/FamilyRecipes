import 'package:familyrecipes/l10n.dart';
import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/services/recipe_translator.dart';
import 'package:familyrecipes/services/online_recipes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

// Risposta di esempio nel formato di www.themealdb.com/api/json/v1/1/lookup.php
const sample = {
  'meals': [
    {
      'idMeal': '52982',
      'strMeal': 'Spaghetti alla Carbonara',
      'strCategory': 'Pasta',
      'strArea': 'Italian',
      'strInstructions': 'STEP 1\r\nPut a large saucepan of water on to boil.\r\n\r\n'
          'STEP 2\r\nFinely chop the pancetta.\r\n\r\n3. Beat the eggs with the cheese.',
      'strMealThumb': 'https://www.themealdb.com/images/media/meals/llcbn01574260722.jpg',
      'strSource': 'https://www.bbcgoodfood.com/recipes/ultimate-spaghetti-carbonara-recipe',
      'strIngredient1': 'Spaghetti',
      'strMeasure1': '320g',
      'strIngredient2': 'Egg Yolks',
      'strMeasure2': '6',
      'strIngredient3': 'Pancetta',
      'strMeasure3': '150g',
      'strIngredient4': '',
      'strMeasure4': ' ',
      'strIngredient5': null,
      'strMeasure5': null,
    }
  ]
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => L10n.load('it'));

  test('legge una ricetta di TheMealDB', () {
    final list = OnlineRecipes.parseMeals(sample);
    expect(list, hasLength(1));
    final r = list.first;
    expect(r.title, 'Spaghetti alla Carbonara');
    expect(r.ingredients.map((i) => i.name), ['Spaghetti', 'Egg Yolks', 'Pancetta']);
    expect(r.ingredients.first.amount, '320g');
    expect(r.steps, [
      'Put a large saucepan of water on to boil.',
      'Finely chop the pancetta.',
      'Beat the eggs with the cheese.',
    ]);
    expect(r.hasIngredient('pancetta'), isTrue);
    expect(r.hasIngredient('chicken'), isFalse);
    expect(r.isPartial, isFalse);
  });

  test('risposta vuota', () {
    expect(OnlineRecipes.parseMeals({'meals': null}), isEmpty);
    expect(OnlineRecipes.parseMeals('boh'), isEmpty);
  });

  test('diventa una ricetta del ricettario', () {
    final r = OnlineRecipes.parseMeals(sample).first.toRecipe();
    expect(r.category, RecipeCategory.primi);
    expect(r.title, 'Spaghetti alla Carbonara');
    expect(r.ingredients, hasLength(3));
    expect(r.steps, hasLength(3));
    expect(r.intro, contains('Italian'));
    expect(r.tips, contains('TheMealDB'));
  });

  test('categorie e traduzione degli ingredienti', () {
    OnlineRecipe o(String c) => OnlineRecipe(id: '1', title: 't', category: c);
    expect(o('Dessert').recipeCategory, RecipeCategory.dolci);
    expect(o('Starter').recipeCategory, RecipeCategory.antipasti);
    expect(o('Side').recipeCategory, RecipeCategory.contorni);
    expect(o('Beef').recipeCategory, RecipeCategory.secondi);
    expect(ingredientToEnglish('Pollo'), 'chicken');
    expect(ingredientToEnglish(' zucchine '), 'zucchini');
    expect(ingredientToEnglish('quinoa'), 'quinoa');
  });

  test('dosi inglesi scritte per esteso prima della traduzione', () {
    expect(expandMeasure('2 tbsp'), '2 tablespoons');
    expect(expandMeasure('1 tsp'), '1 teaspoons');
    expect(expandMeasure('8 oz'), '8 ounces');
    expect(expandMeasure('1 lb'), '1 pounds');
    expect(expandMeasure('320g'), '320g');
    expect(expandMeasure('Pinch'), 'Pinch');
  });

  test('copia tradotta e fonte in fondo', () {
    final o = OnlineRecipes.parseMeals(sample).first;
    final t = o.translatedCopy(
      title: 'Spaghetti alla carbonara',
      category: 'Pasta',
      area: 'Italiana',
      ingredientNames: ['Spaghetti', 'Tuorli', 'Pancetta'],
      amounts: ['320 g', '6', '150 g'],
      steps: ['Metti a bollire l\'acqua.', 'Trita la pancetta.', 'Sbatti le uova col formaggio.'],
    );
    expect(t.translated, isTrue);
    expect(t.steps.first, "Metti a bollire l'acqua.");
    expect(t.recipeCategory, RecipeCategory.primi);
    expect(t.hasIngredient('egg'), isTrue, reason: 'la ricerca usa i nomi originali in inglese');
    final r = t.toRecipe();
    expect(r.intro, 'Cucina: Italiana.');
    expect(r.ingredients[1].name, 'Tuorli');
    expect(r.tips, contains('TheMealDB'));
    expect(r.tips, contains('bbcgoodfood'));
    expect(r.tips, contains("Tradotta automaticamente dall'inglese"));
    expect(o.toRecipe().tips, isNot(contains('Tradotta')));
  });

  test('lingua di destinazione', () {
    expect(RecipeTranslator.targetFor('en'), isNull);
    expect(RecipeTranslator.targetFor('it')?.bcpCode, 'it');
    expect(RecipeTranslator.targetFor('nb')?.bcpCode, 'no');
  });
}
