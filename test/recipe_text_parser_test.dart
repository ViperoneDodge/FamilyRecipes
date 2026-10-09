import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/services/recipe_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scheda in stile GialloZafferano', () {
    const text = '''
Spaghetti alla Carbonara
Difficoltà: Facile
Preparazione: 15 min
Cottura: 10 min
Dosi per: 4 persone
Gli spaghetti alla carbonara sono un piatto della tradizione romana.
INGREDIENTI
Spaghetti 320 g
Guanciale 150 g
Tuorli 6
Pecorino romano 50 g
Pepe nero q.b.
PREPARAZIONE
1. Per preparare gli spaghetti alla carbonara cominciate mettendo
sul fuoco una pentola con l'acqua salata.
2. Tagliate il guanciale a listarelle.
3. Versate i tuorli in una ciotola e aggiungete il pecorino.
CONSIGLI
Niente panna!
''';
    final r = RecipeTextParser.parse(text);
    expect(r.title, 'Spaghetti alla Carbonara');
    expect(r.category, RecipeCategory.primi);
    expect(r.difficulty, Difficulty.easy);
    expect(r.prepMinutes, 15);
    expect(r.cookMinutes, 10);
    expect(r.servings, 4);
    expect(r.intro, contains('tradizione romana'));
    expect(r.ingredients.map((i) => '${i.name}|${i.amount}'), [
      'Spaghetti|320 g',
      'Guanciale|150 g',
      'Tuorli|6',
      'Pecorino romano|50 g',
      'Pepe nero|q.b.',
    ]);
    expect(r.steps, hasLength(3));
    expect(r.steps.first.text, contains("pentola con l'acqua salata"));
    expect(r.tips, 'Niente panna!');
  });

  test('pagina di quaderno senza intestazioni', () {
    const text = '''
Torta di mele della nonna
- 3 uova
- 150 g di zucchero
- 250 g farina
- 1 bustina di lievito
- 3 mele
- burro q.b.
Sbattere le uova con lo zucchero finché il composto
diventa chiaro e spumoso.
Aggiungere la farina e il lievito poco alla volta e
infine le mele a fettine.
Cuocere in forno a 180 gradi per 40 minuti.
''';
    final r = RecipeTextParser.parse(text);
    expect(r.title, 'Torta di mele della nonna');
    expect(r.category, RecipeCategory.dolci);
    expect(r.ingredients.map((i) => '${i.name}|${i.amount}'), [
      'Uova|3',
      'Zucchero|150 g',
      'Farina|250 g',
      'Lievito|1 bustina',
      'Mele|3',
      'Burro|q.b.',
    ]);
    expect(r.steps, hasLength(3));
    expect(r.steps[1].text, startsWith('Aggiungere la farina'));
    expect(r.cookMinutes, 0, reason: 'il tempo è dentro una frase del procedimento');
  });

  test('ricetta in inglese', () {
    const text = '''
Lemon Cake
Serves 8
Prep time: 20 min
Cooking: 1 h
Ingredients
200g butter
200g caster sugar
4 eggs
2 tbsp milk
Method
1) Heat the oven to 180C.
2) Beat the butter and sugar.
''';
    final r = RecipeTextParser.parse(text);
    expect(r.title, 'Lemon Cake');
    expect(r.category, RecipeCategory.dolci);
    expect(r.servings, 8);
    expect(r.prepMinutes, 20);
    expect(r.cookMinutes, 60);
    expect(r.ingredients.first.amount, '200 g');
    expect(r.ingredients.first.name, 'Butter');
    expect(r.ingredients[3].amount, '2 tbsp');
    expect(r.steps.map((s) => s.text), ['Heat the oven to 180C.', 'Beat the butter and sugar.']);
  });

  test('liquore e testo vuoto', () {
    final r = RecipeTextParser.parse('Liquore di elicriso\nIngredienti\nAlcol puro 500 ml\nZucchero 400 g');
    expect(r.category, RecipeCategory.liquori);
    expect(r.ingredients, hasLength(2));
    expect(RecipeTextParser.parse('   ').title, '');
  });
}
