// Tester cattivo (adattato da MyFleetManager t24_b_doc_pdf_test / tc_d_documenti_pdf_test / tc_e_pdf_font_test) —
// PDF con testi assurdi, foto rovinate, 0 o 200 ricette, menù che contengono sé stessi (T-PDF-01, T-UI-04).
// Lingua italiana: nessun font scaricato da internet (quelli CJK si scaricano solo in zh/ja/ko).
import 'dart:typed_data';

import 'package:familyrecipes/l10n.dart';
import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/services/pdf_export.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _pdf(List<Recipe> rs, {Uint8List? foto, String titolo = 'Prova', Map<String, Recipe> lookup = const {}}) =>
    PdfExport.build(title: titolo, recipes: rs, photo: (r, p) async => foto, lookup: lookup);

void _unPdf(Uint8List b) => expect(String.fromCharCodes(b.take(5)), '%PDF-');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => L10n.load('it'));

  test('0 ricette: PDF valido (solo intestazione), nessuna eccezione', () async {
    _unPdf(await _pdf([]));
  });

  test('foto rovinate (3 byte, 0 byte, testo): la ricetta si esporta lo stesso', () async {
    final r = Recipe(title: 'Torta', coverPhoto: 'P', steps: [RecipeStep(text: 'impasta', photos: ['Q', 'R'])]);
    _unPdf(await _pdf([r], foto: Uint8List.fromList([1, 2, 3])));
    _unPdf(await _pdf([r], foto: Uint8List(0)));
    _unPdf(await _pdf([r], foto: Uint8List.fromList('non sono una foto'.codeUnits)));
  });

  test('foto che non si riesce a caricare (eccezione del caricatore): PDF senza foto', () async {
    final b = await PdfExport.build(
      title: 'x',
      recipes: [Recipe(title: 'Torta', coverPhoto: 'P')],
      photo: (r, p) async => throw Exception('rete assente'),
    );
    _unPdf(b);
  });

  test('emoji, arabo, cinese, giapponese, coreano, thai, hindi, zalgo, \\u0000 e spazi invisibili', () async {
    _unPdf(await _pdf([
      Recipe(
        title: '🍝🔥 كعكة 蛋糕 ケーキ 케이크 เค้ก केक t̷̢͎o̵r̸t̷a̴',
        intro: '​\u0000﻿',
        ingredients: [Ingredient(name: '👨‍👩‍👧‍👦🇮🇹', amount: '½')],
        steps: [RecipeStep(text: '{name} {n} %s <script>alert(1)</script>')],
        tips: "'; DROP TABLE --",
        createdByName: 'Nonna {recipe}',
      )
    ]));
  });

  test('titoli lunghi (300 caratteri) e ingredienti con nomi di 2000 caratteri', () async {
    _unPdf(await _pdf([
      Recipe(title: 'Torta ' * 50, ingredients: [Ingredient(name: 'farina ' * 300, amount: '1 kg')])
    ]));
  });

  test('500 ingredienti e 100 passaggi: la ricetta va su più pagine', () async {
    final r = Recipe(title: 'Infinita', ingredients: [
      for (var i = 0; i < 500; i++) Ingredient(name: 'ingrediente $i', amount: '$i g')
    ], steps: [
      for (var i = 0; i < 100; i++) RecipeStep(text: 'Passaggio numero $i: mescolare con cura.')
    ]);
    _unPdf(await _pdf([r]));
  });

  test('menù che contiene sé stesso, ricette inesistenti e doppioni', () async {
    final m = Recipe(id: 'M', title: 'Pranzo', category: RecipeCategory.menu, courses: ['M', 'M', 'NON-ESISTE', '']);
    _unPdf(await _pdf([m], lookup: {'M': m}));
  });

  test('ricettario da 200 ricette con indice: in tempi ragionevoli', () async {
    final sw = Stopwatch()..start();
    final rs = [
      for (var i = 0; i < 200; i++)
        Recipe(
          title: 'Ricetta $i',
          category: RecipeCategory.values[i % RecipeCategory.values.length],
          ingredients: [Ingredient(name: 'farina', amount: '200 g')],
          steps: [RecipeStep(text: 'Impastare ' * 20)],
        )
    ];
    _unPdf(await _pdf(rs, titolo: 'Famiglia Rossi'));
    expect(sw.elapsedMilliseconds, lessThan(60000));
  });

  test('nome del file: niente barre, punti o caratteri strani', () {
    for (final t in ['../../etc/passwd', 'a/b\\c', '🍝', '', '   ', 'Famiglia Rossi: ricette!', 'x' * 500]) {
      final n = PdfExport.fileName(t);
      expect(n, matches(RegExp(r'^FamilyRecipes(-[A-Za-z0-9-]+)?-\d{8}\.pdf$')), reason: t);
    }
  });
}
