import 'dart:convert';

import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/services/recipe_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('file del modulo: ricette, valori italiani e foto', () {
    final photo = base64Encode([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
    final items = RecipeImport.parse(jsonEncode({
      'app': 'FamilyRecipes',
      'format': 1,
      'recipes': [
        {
          'category': 'Primi',
          'title': 'Lasagne della nonna',
          'intro': 'Quelle della domenica.',
          'difficulty': 'Media',
          'cost': 'medium',
          'prepMinutes': 60,
          'cookMinutes': '40 min',
          'servings': 6,
          'ingredients': [
            {'name': 'Ragù', 'amount': '500 g'},
            'Besciamella',
            {'name': '', 'amount': '3'},
          ],
          'steps': ['Prepara il ragù.', {'text': 'Fai gli strati.'}, ''],
          'tips': 'Meglio il giorno dopo.',
          'author': 'Nonna Pina',
          'photo': 'data:image/jpeg;base64,$photo',
        },
        {'title': '', 'ingredients': [], 'steps': []},
        {'category': 'boh', 'title': 'Senza niente'},
      ],
    }));
    expect(items.length, 2);
    final r = items.first.recipe;
    expect(r.category, RecipeCategory.primi);
    expect(r.difficulty, Difficulty.medium);
    expect(r.cost, Cost.medium);
    expect(r.prepMinutes, 60);
    expect(r.cookMinutes, 40);
    expect(r.servings, 6);
    expect(r.ingredients.map((i) => '${i.name}|${i.amount}'), ['Ragù|500 g', 'Besciamella|']);
    expect(r.steps.map((s) => s.text), ['Prepara il ragù.', 'Fai gli strati.']);
    expect(r.createdByName, 'Nonna Pina');
    expect(items.first.photo, isNotNull);
    expect(items.first.photo!.first, 0xFF);
    final d = items[1].recipe;
    expect(d.category, RecipeCategory.secondi);
    expect(d.difficulty, Difficulty.easy);
    expect(d.servings, 4);
    expect(items[1].photo, isNull);
  });

  test('anche un elenco semplice; file non valido', () {
    expect(RecipeImport.parse('[{"title": "Tiramisù", "category": "dolci"}]').single.recipe.category,
        RecipeCategory.dolci);
    expect(() => RecipeImport.parse('{"ciao": 1}'), throwsFormatException);
    expect(() => RecipeImport.parse('non è json'), throwsFormatException);
  });
}
