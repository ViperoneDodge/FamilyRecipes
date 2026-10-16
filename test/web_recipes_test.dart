import 'package:familyrecipes/l10n.dart';
import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/services/web_recipes.dart';
import 'dart:convert';

import 'package:flutter/services.dart';
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

// Passaggi con foto, immagini relative e solo il tempo totale.
const _photos = '''
<script type="application/ld+json">{"@type":"Recipe","name":"Torta di mele","totalTime":"PT1H10M",
 "image":"/img/torta.jpg","recipeYield":"8",
 "recipeIngredient":["3 mele","200 g di farina"],
 "recipeInstructions":[{"@type":"HowToStep","text":"Sbucciate le mele.","image":"https://example.org/p1.jpg"},
  {"@type":"HowToStep","text":"Impastate.","image":[{"@type":"ImageObject","url":"/p2.jpg"}]},
  {"@type":"HowToStep","text":"Infornate."}]}</script>''';

const _microdataResult = r'''R{"ld":["{\"@type\":\"Recipe\",\"name\":\"Tiramisù\",\"image\":\"https://img.example.org/t.jpg\",\"recipeIngredient\":[\"500 g di mascarpone\",\"4 uova\"],\"recipeInstructions\":[\"Separate i tuorli.\\n\\nMontate il mascarpone.\"],\"recipeYield\":\"6 persone\",\"prepTime\":\"PT40M\"}"],"site":"Galbani","title":"","image":"","text":"Tiramisù\n500 g di mascarpone\n4 uova\n\nSeparate i tuorli.\n\nMontate il mascarpone."}''';

// Pagina senza dati strutturati: solo testo (risultato reale dello script in Chromium).
const _plainResult = r'''C{"ld":[],"site":"Galbani","title":"Tiramisù classico | Galbani","image":"/img/tiramisu.jpg","text":"Tiramisù classico\n\nIl dolce al cucchiaio più amato.\n\nDosi per 6 persone\n\nIngredienti\n500 g di mascarpone\n4 uova\n100 g di zucchero\n300 g di savoiardi\ncaffè q.b.\nPreparazione\nSeparate i tuorli dagli albumi e montate i tuorli con lo zucchero.\nAggiungete il mascarpone e mescolate fino a ottenere una crema liscia.\nBagnate i savoiardi nel caffè e alternate strati di biscotti e crema."}''';

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

  test('foto dei passaggi, immagini relative e tempo totale', () {
    final r = WebRecipes.parsePage(_photos, 'https://example.org/ricette/torta.html')!;
    expect(r.thumb, 'https://example.org/img/torta.jpg');
    expect(r.steps, ['Sbucciate le mele.', 'Impastate.', 'Infornate.']);
    expect([for (var i = 0; i < 3; i++) r.stepImage(i)], ['https://example.org/p1.jpg', 'https://example.org/p2.jpg', '']);
    expect([r.prepMinutes, r.cookMinutes, r.servings], [70, 0, 8]);
    final rec = r.toRecipe();
    expect(rec.steps.length, 3);
    expect(rec.prepMinutes, 70);
  });

  test('link senza parametri di tracciamento', () {
    expect(
        WebRecipes.cleanUrl('https://www.galbani.it/ricette/tiramisu?gclsrc=aw.ds&gad_source=1&gad_campaignid=2059539802'
            '&gbraid=0AAAAADs2qd8&gclid=CjwKCAjw88HWBhA3'),
        'https://www.galbani.it/ricette/tiramisu');
    expect(WebRecipes.cleanUrl('https://example.org/r?id=5&utm_source=x'), 'https://example.org/r?id=5');
    expect(WebRecipes.cleanUrl('https://example.org/r'), 'https://example.org/r');
  });

  test('piano B: ricetta letta dal browser del telefono (JSON-LD e microdati)', () async {
    const channel = MethodChannel('familyrecipes/web');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // Come Android: il risultato di evaluateJavascript è la stringa JSON racchiusa tra virgolette.
    String answer(Map data) => jsonEncode('R${jsonEncode(data)}');
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readPage');
      return answer({
        'site': 'Galbani',
        'ld': [
          jsonEncode({
            '@type': 'Recipe',
            'name': 'Tiramisù',
            'recipeIngredient': ['Mascarpone 500 g', 'Uova 4'],
            'recipeInstructions': 'Separate i tuorli.\nMontate il mascarpone.',
            'recipeYield': '6',
          }),
        ],
      });
    });
    final r = (await WebRecipes.readInBrowser('https://www.galbani.it/ricette/tiramisu'))!;
    expect(r.title, 'Tiramisù');
    expect(r.site, 'Galbani');
    expect(r.servings, 6);
    expect(r.ingredients.map((i) => '${i.name}|${i.amount}'), ['Mascarpone|500 g', 'Uova|4']);
    expect(r.steps, ['Separate i tuorli.', 'Montate il mascarpone.']);
    // Microdati: risultato reale dello script eseguito in Chromium su una pagina con itemprop.
    messenger.setMockMethodCallHandler(channel, (call) async => jsonEncode(_microdataResult));
    final m = (await WebRecipes.readInBrowser('https://www.galbani.it/ricette/tiramisu'))!;
    expect([m.title, m.site, m.servings, m.prepMinutes, m.thumb], ['Tiramisù', 'Galbani', 6, 40, 'https://img.example.org/t.jpg']);
    expect(m.ingredients.map((i) => '${i.name}|${i.amount}'), ['Mascarpone|500 g', 'Uova|4']);
    expect(m.steps, ['Separate i tuorli.', 'Montate il mascarpone.']);
    // Solo testo: riconosciuto come una ricetta fotografata, con titolo e foto dalla pagina.
    messenger.setMockMethodCallHandler(channel, (call) async => jsonEncode(_plainResult));
    final t = (await WebRecipes.readInBrowser('https://www.galbani.it/ricette/tiramisu'))!;
    expect([t.title, t.site, t.servings, t.thumb], ['Tiramisù classico', 'Galbani', 6, 'https://www.galbani.it/img/tiramisu.jpg']);
    expect(t.ingredients.map((i) => i.name).toList(), containsAll(['Mascarpone', 'Uova', 'Zucchero', 'Savoiardi']));
    expect(t.steps.length, 3);
    expect(t.steps.first, startsWith('Separate i tuorli'));
    expect(t.recipeCategory, RecipeCategory.dolci);
    // Pagina caricata ma senza ricetta: null; pagina mai caricata: errore di rete.
    messenger.setMockMethodCallHandler(channel, (call) async => jsonEncode('C{"ld":[],"text":"Chi siamo. Contatti."}'));
    expect(await WebRecipes.readInBrowser('https://example.org'), isNull);
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    expect(WebRecipes.readInBrowser('https://example.org'), throwsA(isA<Exception>()));
    messenger.setMockMethodCallHandler(channel, null);
  });
}
