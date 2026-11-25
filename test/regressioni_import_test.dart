// Regressioni: bug trovati dal tester cattivo nella 1.9.0/1.10.0 e corretti nella 1.10.1.
// Devono restare verdi: se uno fallisce, il bug è tornato.
// Lancio:  flutter test tool/tests/bug_import_test.dart
import 'dart:convert';

import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/services/dose_scaler.dart';
import 'package:familyrecipes/services/recipe_import.dart';
import 'package:familyrecipes/services/recipe_text_parser.dart';
import 'package:familyrecipes/services/recipe_words.dart';
import 'package:familyrecipes/services/web_recipes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DoseScaler (dose_scaler.dart:6-7, _lead)', () {
    test('BUG [MEDIO] «1.000 g» (mille grammi, scritto all\'italiana) per 8 persone invece di 4 diventa «2 g»', () {
      expect(DoseScaler.scale('1.000 g', 2), '2000 g');
    });

    test('BUG [MEDIO] numeri misti «1 1/2 cups» e «1½»: si raddoppia solo l\'intero', () {
      // Le ricette inglesi importate dai siti scrivono così; 1 1/2 × 2 = 3, non «2 1/2».
      expect(DoseScaler.scale('1 1/2 cups', 2), '3 cups');
      expect(DoseScaler.scale('1½ cucchiai', 2), '3 cucchiai');
    });

    test('BUG [LIEVE] intervallo con il trattino lungo «2–3» (quello che il lettore OCR accetta): '
        'diventa «4–3»', () {
      // RecipeTextParser._amountStart accetta [-–], DoseScaler solo «-».
      expect(DoseScaler.scale('2–3 foglie', 2), '4–6 foglie');
    });

    test('BUG [LIEVE] dosi piccole diventano «0»', () {
      // format arrotonda a un decimale: 0,02 g di zafferano per 8 persone = «0 g».
      expect(DoseScaler.scale('0,01 g', 2), isNot('0 g'));
    });
  });

  group('RecipeTextParser (recipe_text_parser.dart)', () {
    test('BUG [MEDIO] intestazione «Ingredienti per 4 persone»: gli ingredienti finiscono nell\'introduzione', () {
      // _meta (riga 196) riconosce «per 4 persone» e toglie TUTTA la riga, intestazione compresa: gli ingredienti
      // senza dose che seguono non vengono più riconosciuti e diventano testo dell'introduzione.
      final r = RecipeTextParser.parse(
          'Torta paradiso\nIngredienti per 4 persone\nfarina\nzucchero\nuova\nburro\nPreparazione\nMescolare tutto e infornare.');
      expect(r.servings, 4);
      expect(r.ingredients.map((i) => i.name), ['Farina', 'Zucchero', 'Uova', 'Burro'], reason: 'intro: «${r.intro}»');
    });

    test('BUG [LIEVE] «Cottura: 1 ora e 30 minuti» e «1h30» diventano 60 minuti', () {
      expect(RecipeTextParser.parse('Arrosto\nCottura: 1 ora e 30 minuti').cookMinutes, 90);
      expect(RecipeTextParser.parse('Arrosto\nPreparazione: 1h30').prepMinutes, 90);
    });

    test('BUG [LIEVE] «Dosi per 100 persone» diventa 10 persone', () {
      // (\d{1,2}) prende le prime due cifre: meglio 99 (il massimo dell'editor) o niente.
      expect(RecipeTextParser.parse('Arrosto\nDosi per 100 persone').servings, isNot(10));
    });
  });

  test('BUG [LIEVE] categoria proposta: «ripieni», «piemontese», «tortellini», «crema di zucca» = Dolci', () {
    // RecipeWords.guessCategory (recipe_words.dart:41-46) cerca sottostringhe: «pie» è in «ripieni» e
    // «piemontese», «torte» è in «tortellini», «crema» in «crema di zucca»; e i dolci si controllano prima dei primi.
    final sbagliate = <String>[];
    for (final e in {
      'Peperoni ripieni': RecipeCategory.secondi,
      'Brasato alla piemontese': RecipeCategory.secondi,
      'Tortellini in brodo': RecipeCategory.primi,
      'Crema di zucca': RecipeCategory.primi,
      'Spaghetti alla crema di pistacchio': RecipeCategory.primi,
    }.entries) {
      final c = RecipeWords.guessCategory(e.key);
      if (c == RecipeCategory.dolci) sbagliate.add('${e.key} → ${c.name}');
    }
    expect(sbagliate, isEmpty, reason: sbagliate.join('\n'));
  });

  group('RecipeImport (recipe_import.dart)', () {
    test('BUG [LIEVE] «cookMinutes»: "1 h" (scritto a mano nel file) diventa 1 minuto', () {
      final r = RecipeImport.parse(jsonEncode([
        {'title': 'Arrosto', 'cookMinutes': '1 h', 'prepMinutes': '1,5 ore'}
      ])).single.recipe;
      expect(r.cookMinutes, 60);
      expect(r.prepMinutes, 90);
    });

    test('BUG [LIEVE] una sola ricetta scritta male fa rifiutare tutto il file («File non valido»)', () {
      // _recipe fa «as List?» su ingredients/steps (righe 61, 70) e int.parse su numeri enormi (riga 98):
      // l'eccezione esce da parse() e import_screen.dart:25 mostra «file non valido» per tutte le ricette.
      final testo = jsonEncode([
        {'title': 'Buona'},
        {'title': 'Ingredienti come testo', 'ingredients': 'farina, uova'},
        {'title': 'Passaggi come mappa', 'steps': {'1': 'impasta'}},
        {'title': 'Tempo enorme', 'prepMinutes': '99999999999999999999'},
      ]);
      List<String>? titoli;
      try {
        titoli = RecipeImport.parse(testo).map((i) => i.recipe.title).toList();
      } catch (e) {
        titoli = null;
      }
      expect(titoli, contains('Buona'));
    });
  });

  test('BUG [LIEVE] pagina web con un\'entità HTML fuori dall\'Unicode (&#x110000;): eccezione, '
      'l\'app dice «sei offline»', () {
    // WebRecipes.clean (web_recipes.dart:437) chiama String.fromCharCode senza controllare il limite 0x10FFFF:
    // RangeError → openRecipeLink (new_recipe.dart:226-242) lo tratta come errore di rete.
    const html = '<script type="application/ld+json">{"@type":"Recipe","name":"Torta &#x110000; &#99999999;",'
        '"recipeIngredient":["200 g farina"],"recipeInstructions":["Impasta."]}</script>';
    expect(() => WebRecipes.parsePage(html, 'https://example.org/torta'), returnsNormally);
  });
}
