// Tester cattivo (adattato da MyFleetManager import_test / tc_a_input_date_numeri_test / tc_d_ocr_test) —
// prove stupide su DoseScaler, RecipeTextParser, RecipeImport e WebRecipes: niente eccezioni, niente dati
// inventati (T-IN-01/02/03/04/07/11, T-OCR-01, T-DATA-01).
import 'dart:convert';
import 'dart:typed_data';

import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/services/dose_scaler.dart';
import 'package:familyrecipes/services/recipe_import.dart';
import 'package:familyrecipes/services/recipe_text_parser.dart';
import 'package:familyrecipes/services/recipe_words.dart';
import 'package:familyrecipes/services/web_recipes.dart';
import 'package:flutter_test/flutter_test.dart';

const _stupidi = [
  '',
  ' ',
  '\n\n\n',
  '\t',
  'a',
  '\u0000\u0000',
  '​',
  '🍝🔥👨‍👩‍👧‍👦🇮🇹',
  'كعكة الشوكولاتة\n٣ بيضات',
  't̷̢͎o̵r̸t̷a̴',
  '<script>alert(1)</script>',
  "'; DROP TABLE recipes; --",
  '{name} {n} \${x} %s%n',
  '../../etc/passwd',
  'null',
  'NaN',
  'Infinity',
  '-0',
  '1e308',
  '½½½½',
  '1/0',
  '0/0',
];

void main() {
  group('DoseScaler: dosi assurde', () {
    test('fattore 1: il testo resta identico, qualunque cosa sia', () {
      for (final s in [..._stupidi, '200 g', '1,5 l', '2-3']) {
        expect(DoseScaler.scale(s, 1), s);
      }
    });

    test('testi stupidi con fattori diversi: mai eccezioni', () {
      for (final s in _stupidi) {
        for (final f in [0.01, 0.5, 2.0, 99.0]) {
          expect(() => DoseScaler.scale(s, f), returnsNormally, reason: '$s × $f');
        }
      }
    });

    test('quello che non è un numero all\'inizio resta com\'è', () {
      for (final s in ['q.b.', 'un pizzico', 'a piacere', 'sale', '(200 g)', 'circa 200 g', '-5 g', '+5 g', 'NaN g']) {
        expect(DoseScaler.scale(s, 2), s, reason: s);
      }
    });

    test('frazioni, simboli, intervalli con spazi, divisione per zero', () {
      expect(DoseScaler.scale('1 / 2', 2), '1');
      expect(DoseScaler.scale('⅓ tazza', 3), '1 tazza');
      expect(DoseScaler.scale('¾ l', 2), '1,5 l');
      expect(DoseScaler.scale('5 - 6 foglie', 0.5), '2,5-3 foglie');
      expect(DoseScaler.scale('1/0 bustina', 2), '1/0 bustina');
      expect(DoseScaler.scale('0 g', 2), '0 g');
      expect(DoseScaler.scale('200g', 1.5), '300g');
      expect(DoseScaler.scale('200 g 🍫', 2), '400 g 🍫');
      expect(DoseScaler.scale('1,5 l', 2, comma: false), '3 l');
      expect(DoseScaler.scale('1.5 l', 3, comma: false), '4.5 l');
    });

    test('arrotondamento: sotto 10 un decimale, da 10 in su interi', () {
      expect(DoseScaler.format(9.94), '9,9');
      expect(DoseScaler.format(9.96), '10');
      expect(DoseScaler.format(10.4), '10');
      expect(DoseScaler.format(0.25), '0,3');
      expect(DoseScaler.format(2.0), '2');
      expect(DoseScaler.format(1234567), '1234567');
    });

    test('andata e ritorno 4 → 8 → 4 persone: torna la dose di partenza', () {
      for (final s in ['200 g', '1,5 l', '3 uova', '2-3 foglie', '125 g (provare 110)', '0,5 bustina']) {
        expect(DoseScaler.scale(DoseScaler.scale(s, 2), 0.5), s, reason: s);
      }
    });
  });

  group('RecipeTextParser: OCR e testi assurdi (T-OCR-01)', () {
    test('testi stupidi: mai eccezioni, mai ingredienti o passaggi inventati da testo vuoto', () {
      for (final s in _stupidi) {
        final r = RecipeTextParser.parse(s);
        expect(r.servings, inInclusiveRange(0, 99), reason: s);
        if (s.trim().isEmpty) {
          expect(r.title, '', reason: s);
          expect(r.ingredients, isEmpty);
          expect(r.steps, isEmpty);
        }
      }
    });

    test('solo intestazioni, nessun contenuto: ricetta vuota', () {
      final r = RecipeTextParser.parse('INGREDIENTI\nPREPARAZIONE\nCONSIGLI');
      expect(r.ingredients, isEmpty);
      expect(r.steps, isEmpty);
      expect(r.tips, '');
    });

    test('testo enorme (200.000 caratteri, una riga sola o 10.000 righe): termina in fretta', () {
      final sw = Stopwatch()..start();
      RecipeTextParser.parse('a' * 200000);
      RecipeTextParser.parse(List.generate(10000, (i) => '$i g farina').join('\n'));
      RecipeTextParser.parse(List.generate(10000, (i) => 'Mescolare con cura per $i minuti.').join('\n'));
      expect(sw.elapsedMilliseconds, lessThan(20000));
    });

    test('a capo di Windows e vecchi Mac, spazi multipli e tabulazioni', () {
      final r = RecipeTextParser.parse('Torta\r\nIngredienti\r\n200 g\t\tfarina\r3 uova\r\nPreparazione\r\nImpastare tutto.');
      expect(r.title, 'Torta');
      expect(r.ingredients.map((i) => i.amount), ['200 g', '3']);
      expect(r.steps.single.text, 'Impastare tutto.');
    });

    test('il titolo non è mai un ingrediente con la dose', () {
      final r = RecipeTextParser.parse('200 g farina\n3 uova\n1 bustina di lievito');
      expect(r.title, '');
      expect(r.ingredients.length, 3);
    });

    test('persone fuori misura non oltre 99, dosi 0 non rompono', () {
      expect(RecipeTextParser.parse('Torta\nPer 0 persone\n200 g farina').servings, inInclusiveRange(0, 99));
      expect(RecipeTextParser.parse('Torta\nServes 12\n200 g farina').servings, 12);
    });
  });

  group('RecipeImport: file del modulo scritti male (T-DATA-01)', () {
    test('file stupidi: o FormatException o un elenco, mai altri errori', () {
      for (final s in [..._stupidi, '[]', '{}', '{"recipes":null}', '{"recipes":{}}', '[1,2,3]', '[null]', '[[]]', '"x"']) {
        try {
          final l = RecipeImport.parse(s);
          expect(l, isA<List<ImportedRecipe>>());
        } on FormatException {
          // va bene: «file non valido»
        }
      }
      expect(RecipeImport.parse('[1,"a",null,[]]'), isEmpty);
    });

    test('BOM, spazi, numeri negativi o enormi: tutto rientra nei limiti', () {
      final l = RecipeImport.parse('﻿  ${jsonEncode([
            {'title': 'A', 'prepMinutes': -5, 'cookMinutes': 1e300, 'servings': -3},
            {'title': 'B', 'servings': 1000, 'prepMinutes': '  12 minuti '},
            {'title': 'C', 'servings': 0},
          ])}  ');
      expect(l.map((i) => i.recipe.prepMinutes), [0, 12, 0]);
      expect(l.first.recipe.cookMinutes, 100000);
      expect(l.map((i) => i.recipe.servings), everyElement(inInclusiveRange(1, 99)));
    });

    test('foto: vuota, non base64, data URL senza dati, testo enorme → nessuna foto, nessuna eccezione', () {
      for (final p in ['', 'data:image/jpeg;base64,', 'non è base64!!', 'data:', 123, ['x']]) {
        final l = RecipeImport.parse(jsonEncode([
          {'title': 'Torta', 'photo': p}
        ]));
        expect(l.single.photo, isNull, reason: '$p');
      }
    });

    test('titoli, autori e passaggi con testi assurdi: identici dopo esportazione e reimportazione', () {
      final r = Recipe(
        title: '🍝 {name} <b>Torta</b> 💥',
        intro: 'كعكة',
        ingredients: [Ingredient(name: '${'x' * 5000} 👨‍👩‍👧‍👦', amount: '½')],
        steps: [RecipeStep(text: "'; DROP TABLE --")],
        createdByName: 'Nonna {n}',
      );
      final back = RecipeImport.parse(RecipeImport.encode([r], {r.id: Uint8List.fromList([0, 255])})).single;
      expect(back.recipe.title, r.title);
      expect(back.recipe.intro, r.intro);
      expect(back.recipe.ingredients.single.name, r.ingredients.single.name);
      expect(back.recipe.steps.single.text, r.steps.single.text);
      expect(back.recipe.createdByName, 'Nonna {n}');
      expect(back.photo, [0, 255]);
    });

    test('l\'importazione non porta id, gruppo, autore nascosto o data di creazione dal file', () {
      final l = RecipeImport.parse(jsonEncode([
        {'id': 'FISSO', 'title': 'X', 'bookId': 'GRUPPOALTRUI', 'createdBy': 'uidAltrui', 'createdAt': 5, 'deleted': true}
      ]));
      final r = l.single.recipe;
      expect(r.id, isNot('FISSO'));
      expect(r.bookId, isNull);
      expect(r.createdBy, '');
      expect(r.createdAt, 0);
      expect(r.deleted, isFalse);
    });
  });

  group('RecipeWords e WebRecipes: parole e pagine strane', () {
    test('categorie, difficoltà e costi da parole strane: null o predefinito, mai eccezioni', () {
      for (final s in [..._stupidi, 'PRIMI', 'Primi piatti', 'Dessert', 'Nachspeise']) {
        expect(() => RecipeWords.categoryFromLabel(s), returnsNormally);
        expect(() => RecipeWords.difficulty(s), returnsNormally);
        expect(() => RecipeWords.cost(s), returnsNormally);
        expect(() => RecipeWords.guessCategory(s), returnsNormally);
      }
      expect(RecipeWords.categoryFromLabel(''), isNull);
      expect(RecipeWords.categoryFromLabel('PRIMI'), RecipeCategory.primi);
      expect(RecipeWords.difficulty('boh'), isNull);
    });

    test('pagine senza ricetta, JSON-LD rotto, tag non chiusi, 2 MB di HTML: null senza eccezioni', () {
      for (final html in [
        '',
        '<html>',
        '<script type="application/ld+json">{rotto</script>',
        '<script type="application/ld+json">',
        '<script type="application/ld+json">null</script>',
        '<script type="application/ld+json">[[[[[]]]]]</script>',
        '<script type="application/ld+json">{"@type":"Recipe"}</script>',
        '<div>${'x' * 2000000}</div>',
      ]) {
        expect(() => WebRecipes.parsePage(html, 'https://example.org/r'), returnsNormally, reason: html.length > 80 ? 'grande' : html);
      }
    });

    test('durate ISO, persone e link: valori strani', () {
      expect(WebRecipes.minutes(''), 0);
      expect(WebRecipes.minutes('boh'), 0);
      expect(WebRecipes.minutes('PT1H30M'), 90);
      expect(WebRecipes.minutes('P1DT2H'), 1560);
      expect(WebRecipes.servings(null), 4);
      expect(WebRecipes.servings('0 persone'), 4);
      expect(WebRecipes.servings('500 biscotti'), 4);
      expect(WebRecipes.servings(['', '6 porzioni']), 6);
      expect(WebRecipes.cleanUrl('non è un link'), 'non è un link');
      expect(WebRecipes.cleanUrl('https://x.it/r?utm_source=a&id=3'), 'https://x.it/r?id=3');
      expect(WebRecipes.cleanUrl('https://x.it/r?utm_source=a'), 'https://x.it/r');
      expect(firstUrl('guarda javascript:alert(1) e ftp://x'), isNull);
      expect(firstUrl('ecco https://x.it/a"b'), 'https://x.it/a');
    });
  });
}
