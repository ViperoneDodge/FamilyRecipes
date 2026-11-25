// BUG trovati dal tester cattivo sulla ricerca (1.9.0). Questi test FALLISCONO finché il problema c'è.
// Lancio:  flutter test tool/tests/bug_ricerca_test.dart
import 'package:familyrecipes/l10n.dart';
import 'package:familyrecipes/main.dart';
import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/theme.dart';
import 'package:familyrecipes/widgets/common.dart';
import 'package:familyrecipes/widgets/recipe_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/mfm_aiuti.dart';

final _ricette = [
  Recipe(id: '1', title: 'Pasta e fagioli', ingredients: [Ingredient(name: 'Borlotti')]),
  Recipe(id: '2', title: 'Tiramisù', category: RecipeCategory.dolci, ingredients: [Ingredient(name: 'Mascarpone')]),
  Recipe(id: '3', title: 'Torta di mele', category: RecipeCategory.dolci),
];

Future<int> _trovate(WidgetTester t, String q) async {
  await t.enterText(find.byType(TextField), q);
  await t.pump();
  return find.byType(RecipeCard).evaluate().length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  cartellaDocumentiFinta('bug_ricerca_docs');
  appState = statoFinto(ricette: _ricette);
  setUpAll(caricaCaratteriVeri);

  // recipe_browser.dart:66-69: q = testo.trim().toLowerCase() e r.searchText.contains(q): la frase intera deve
  // comparire identica, parola per parola e con gli accenti.
  for (final c in {
    'due parole non attaccate («pasta fagioli» per «Pasta e fagioli»)': ['pasta fagioli', 1],
    'titolo e ingrediente insieme («torta mele»)': ['torta mele', 1],
    'senza accento («tiramisu» per «Tiramisù»)': ['tiramisu', 1],
    'due spazi tra le parole («torta  di mele»)': ['torta  di mele', 1],
  }.entries) {
    testWidgets('BUG [LIEVE] ricerca: ${c.key} → nessun risultato', (t) async {
      await t.runAsync(() => L10n.load('it'));
      t.view.physicalSize = const Size(400, 2000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(ThemeSettings(), Brightness.light),
        home: Scaffold(body: RecipeBrowser(recipes: _ricette, onOpen: (_, __) {}, emptyTitle: 'Vuoto')),
      ));
      expect(await _trovate(t, c.value[0] as String), c.value[1]);
    });
  }
}
