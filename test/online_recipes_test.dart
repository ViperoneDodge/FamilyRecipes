import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/services/online_recipes.dart';
import 'package:flutter_test/flutter_test.dart';

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
    expect(r.intro, contains('TheMealDB'));
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
}
