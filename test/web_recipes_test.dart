import 'package:familyrecipes/l10n.dart';
import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/services/web_recipes.dart';
import 'package:flutter_test/flutter_test.dart';

// Pagine di esempio costruite sul formato schema.org/Recipe usato dai siti di ricette.
const _gz = '''
<html><head><meta property="og:site_name" content="GialloZafferano">
<script type="application/ld+json">{"@context":"https://schema.org","@type":"BreadcrumbList","itemListElement":[]}</script>
<script type="application/ld+json">
{"@context":"http://schema.org","@type":"Recipe","name":"Spaghetti alla carbonara",
 "description":"Gli spaghetti alla carbonara sono un primo piatto della cucina romana.",
 "image":["https://www.giallozafferano.it/images/carbonara.jpg"],
 "recipeCategory":"Primi piatti","recipeCuisine":"Italiana",
 "prepTime":"PT15M","cookTime":"PT10M","recipeYield":"4 persone",
 "recipeIngredient":["Spaghetti 320 g","Guanciale 150 g","Tuorli 6","Pecorino Romano 50 g","Pepe nero q.b."],
 "recipeInstructions":[{"@type":"HowToStep","text":"Per preparare gli spaghetti alla carbonara cominciate mettendo sul fuoco una pentola con l&#39;acqua salata."},
  {"@type":"HowToStep","text":"Tagliate il guanciale a listarelle &amp; rosolatelo.<br>Non serve olio."}]}
</script></head><body></body></html>''';

const _graph = '''
<script type='application/ld+json'>{"@context":"https://schema.org","@graph":[{"@type":"WebPage","name":"x"},
{"@type":["Recipe","NewsArticle"],"name":"Tarte aux pommes","recipeCategory":["Dessert"],"recipeYield":["8","8 parts"],
 "image":{"@type":"ImageObject","url":"//img.example.org/tarte.jpg"},"totalTime":"PT1H",
 "recipeIngredient":["200 g de farine","4 pommes","1 pincée de sel"],
 "recipeInstructions":[{"@type":"HowToSection","name":"Pâte","itemListElement":[{"@type":"HowToStep","text":"Mélanger."}]},
   {"@type":"HowToSection","name":"Cuisson","itemListElement":[{"@type":"HowToStep","text":"Cuire 40 min."}]}]}]}</script>''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => L10n.load('it'));

  test('pagina in stile GialloZafferano', () {
    final r = WebRecipes.parsePage(_gz, 'https://ricette.giallozafferano.it/Spaghetti-alla-Carbonara.html')!;
    expect(r.fromSite, isTrue);
    expect(r.site, 'GialloZafferano');
    expect(r.title, 'Spaghetti alla carbonara');
    expect(r.recipeCategory, RecipeCategory.primi);
    expect([r.prepMinutes, r.cookMinutes, r.servings], [15, 10, 4]);
    expect(r.thumb, 'https://www.giallozafferano.it/images/carbonara.jpg');
    expect(r.ingredients.map((i) => '${i.name}|${i.amount}').toList(),
        ['Spaghetti|320 g', 'Guanciale|150 g', 'Tuorli|6', 'Pecorino Romano|50 g', 'Pepe nero|q.b.']);
    expect(r.steps.first, contains("l'acqua salata"));
    expect(r.steps[1], 'Tagliate il guanciale a listarelle & rosolatelo. Non serve olio.');
    expect(r.steps.length, 2);
    final rec = r.toRecipe();
    expect(rec.intro, startsWith('Gli spaghetti'));
    expect(rec.servings, 4);
    expect(rec.tips, contains('GialloZafferano'));
    expect(rec.tips, contains('https://ricette.giallozafferano.it/Spaghetti-alla-Carbonara.html'));
  });

  test('@graph, sezioni e immagine come oggetto', () {
    final r = WebRecipes.parsePage(_graph, 'https://www.marmiton.org/recettes/recette_tarte-aux-pommes_1.aspx')!;
    expect(r.title, 'Tarte aux pommes');
    expect(r.recipeCategory, RecipeCategory.dolci);
    expect(r.servings, 8);
    expect(r.thumb, 'https://img.example.org/tarte.jpg');
    expect(r.steps, ['Mélanger.', 'Cuire 40 min.']);
    expect(r.ingredients.map((i) => '${i.name}|${i.amount}').toList(), ['Farine|200 g', 'Pommes|4', 'Sel|1 pincée']);
    expect(r.site, 'Marmiton');
  });

  test('pagina senza ricetta e link nei risultati', () {
    expect(WebRecipes.parsePage('<html><body>niente</body></html>', 'https://example.org'), isNull);
    final s = recipeSites['it']!;
    final links = WebRecipes.links(s,
        '<a href="https://ricette.giallozafferano.it/Pasta-e-ceci.html">x</a> <a href="https://ricette.giallozafferano.it/Pasta-e-ceci.html">'
        '<a href="https://ricette.giallozafferano.it/Torta-di-mele.html">');
    expect(links, ['https://ricette.giallozafferano.it/Pasta-e-ceci.html', 'https://ricette.giallozafferano.it/Torta-di-mele.html']);
    final fr = WebRecipes.links(recipeSites['fr']!, '<a href="/recettes/recette_quiche-lorraine_30283.aspx">');
    expect(fr, ['https://www.marmiton.org/recettes/recette_quiche-lorraine_30283.aspx']);
    expect(firstUrl('Guarda qui: https://ricette.giallozafferano.it/Farinata.html bella'),
        'https://ricette.giallozafferano.it/Farinata.html');
    expect(WebRecipes.minutes('PT1H30M'), 90);
    expect(WebRecipes.minutes('P0DT0H45M'), 45);
  });
}
