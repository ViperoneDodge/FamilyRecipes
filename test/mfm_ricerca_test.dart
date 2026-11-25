// Tester cattivo — ricerca nell'elenco delle ricette (RecipeBrowser): maiuscole, ingredienti, caratteri speciali,
// elenco vuoto (T-IN-01/02/07, T-UI-05). Niente Firebase: appState montato a mano.
import 'package:familyrecipes/l10n.dart';
import 'package:familyrecipes/main.dart';
import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/theme.dart';
import 'package:familyrecipes/widgets/recipe_browser.dart';
import 'package:familyrecipes/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mfm_aiuti.dart';

final _ricette = [
  Recipe(id: '1', title: 'Pasta e fagioli', category: RecipeCategory.primi, ingredients: [Ingredient(name: 'Borlotti')]),
  Recipe(id: '2', title: 'Tiramisù', category: RecipeCategory.dolci, ingredients: [Ingredient(name: 'Mascarpone')]),
  Recipe(id: '3', title: 'Torta di mele', category: RecipeCategory.dolci, intro: 'La torta (della nonna) *speciale*'),
  Recipe(id: '4', title: '🍝 Spaghetti', category: RecipeCategory.primi, tips: 'Niente panna!'),
];

Future<int> _trovate(WidgetTester t, String q) async {
  await t.enterText(find.byType(TextField), q);
  await t.pump();
  return find.byType(RecipeCard).evaluate().length;
}

Widget _app(List<Recipe> rs) => MaterialApp(
      theme: buildTheme(ThemeSettings(), Brightness.light),
      home: Scaffold(
        body: RecipeBrowser(recipes: rs, onOpen: (_, __) {}, emptyTitle: 'Vuoto', emptyHint: 'Aggiungi'),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  cartellaDocumentiFinta('mfm_ricerca_docs');
  appState = statoFinto(ricette: _ricette);
  setUpAll(caricaCaratteriVeri);

  testWidgets('maiuscole, ingredienti, introduzione e consigli; spazi intorno ignorati', (t) async {
    await t.runAsync(() => L10n.load('it'));
    t.view.physicalSize = const Size(320, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(_ricette));
    expect(await _trovate(t, ''), 4);
    expect(await _trovate(t, 'PASTA'), 1);
    expect(await _trovate(t, '  borlotti  '), 1);
    expect(await _trovate(t, 'mascarpone'), 1);
    expect(await _trovate(t, 'nonna'), 1);
    expect(await _trovate(t, 'panna'), 1);
    expect(await _trovate(t, 'tiramisù'), 1);
  });

  testWidgets('caratteri speciali e testi assurdi nella ricerca: nessuna eccezione', (t) async {
    await t.runAsync(() => L10n.load('it'));
    t.view.physicalSize = const Size(320, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(_ricette));
    expect(await _trovate(t, '(della'), 1);
    expect(await _trovate(t, '*speciale*'), 1);
    expect(await _trovate(t, '🍝'), 1);
    for (final q in ['.*', r'\', '[', '\u0000', 'x' * 10000, '{name}', '%s', '\n']) {
      await _trovate(t, q);
      expect(t.takeException(), isNull, reason: q);
    }
    expect(await _trovate(t, 'nessuna ricetta così'), 0);
    expect(find.text(tr('search.none')), findsOneWidget);
  });

  testWidgets('elenco vuoto: messaggio, niente schermata bianca', (t) async {
    await t.runAsync(() => L10n.load('it'));
    await t.pumpWidget(_app(const []));
    await t.pump();
    expect(find.text('Vuoto'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
