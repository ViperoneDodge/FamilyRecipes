// BUG trovati dal tester cattivo sulle schermate (1.9.0). Questi test FALLISCONO finché il problema c'è.
// Lancio:  flutter test tool/tests/bug_schermate_test.dart
import 'package:familyrecipes/l10n.dart';
import 'package:familyrecipes/main.dart';
import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/screens/recipe_detail_screen.dart';
import 'package:familyrecipes/screens/settings_screen.dart';
import 'package:familyrecipes/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/mfm_aiuti.dart';

Widget _app(Widget home) => MaterialApp(
      // come main.dart: le lingue che Flutter non ha (mt, ga) usano l'inglese per i testi di sistema
      locale: GlobalMaterialLocalizations.delegate.isSupported(Locale(L10n.code)) ? Locale(L10n.code) : const Locale('en'),
      supportedLocales: [
        for (final c in L10n.available)
          if (GlobalMaterialLocalizations.delegate.isSupported(Locale(c))) Locale(c),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildTheme(ThemeSettings(), Brightness.light),
      home: home,
    );

List<String> _errori(WidgetTester t) {
  final out = <String>[];
  Object? e;
  while ((e = t.takeException()) != null) {
    out.add('$e'.split('\n').first);
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  cartellaDocumentiFinta('bug_schermate_docs');
  appState = statoFinto(ricette: [Recipe(id: 'R1', title: 'Torta', servings: 2, ingredients: [Ingredient(name: 'Uova', amount: '½')])]);
  setUpAll(caricaCaratteriVeri);

  for (final lingua in ['cs', 'sk', 'hu', 'ro', 'fi', 'is', 'mt', 'ga', 'zh', 'ja', 'ko', 'hi', 'id', 'th']) {
    testWidgets('BUG [LIEVE] $lingua, 320 px, testo al 200%: le schede delle Impostazioni escono di 2-3 px in basso',
        (t) async {
      // settings_screen.dart:30-34: Tab(height: 58) con icona 22 + etichetta in una FittedBox(scaleDown). Al 200%
      // la riga di testo è alta ~30 px: se l'etichetta è CORTA (non va ridotta in larghezza) la FittedBox non la
      // rimpicciolisce e la scheda sfora di 2-3 px. Succede proprio nelle lingue con le parole più brevi; in it/de/en
      // le etichette lunghe vengono ridotte e ci stanno. Caratteri veri (Roboto) caricati con caricaCaratteriVeri.
      await t.runAsync(() => L10n.load(lingua));
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(t.view.reset);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.pumpWidget(_app(const SettingsScreen()));
      await t.pump(const Duration(milliseconds: 300));
      final errori = _errori(t);
      expect(errori, isEmpty, reason: errori.join('\n'));
    });
  }

  testWidgets('BUG [LIEVE] ricetta che non c\'è più (eliminata da un altro membro, id vecchio): chiudendo la pagina '
      'l\'AnimationController viene creato dentro dispose()', (t) async {
    // recipe_detail_screen.dart:42 «late final _flip = AnimationController(vsync: this)» è pigro: se la ricetta
    // manca, build non lo usa mai e dispose() (riga 59) lo crea in quel momento → in debug:
    // «Looking up a deactivated widget's ancestor is unsafe»; in release un Ticker creato e buttato.
    await t.runAsync(() => L10n.load('it'));
    await t.pumpWidget(_app(const RecipeDetailScreen(recipeId: 'NON-ESISTE')));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text(tr('recipe.gone')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    final errori = _errori(t);
    expect(errori, isEmpty, reason: errori.join('\n'));
  });

  for (final lingua in ['ja', 'zh', 'ko', 'th', 'hi', 'ga', 'mt']) {
    testWidgets('BUG [LIEVE] $lingua: le dosi ricalcolate usano la virgola decimale («0,8») dove si usa il punto',
        (t) async {
      // recipe_detail_screen.dart:309 «comma: L10n.code != 'en'»: solo l'inglese ha il punto; giapponese,
      // cinese, coreano, thai, hindi, irlandese e maltese scrivono 0.8, non 0,8.
      await t.runAsync(() => L10n.load(lingua));
      t.view.physicalSize = const Size(400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(_app(const RecipeDetailScreen(recipeId: 'R1')));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byIcon(Icons.add_circle_outline)); // 2 → 3 persone: ½ × 1,5 = 0,75 → 0,8
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('0.8'), findsOneWidget, reason: 'trovato «0,8»: ${find.text('0,8').evaluate().isNotEmpty}');
      await t.pumpWidget(const SizedBox());
    });
  }
}
