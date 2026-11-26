// Schermate della pianificazione: settimana con tutti i 6 pasti e lista della spesa, su un telefono stretto
// con il testo grande, in tutte le lingue.
import 'package:familyrecipes/l10n.dart';
import 'package:familyrecipes/main.dart';
import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/screens/planner_screen.dart';
import 'package:familyrecipes/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mfm_aiuti.dart';

Widget _app(Widget home) => MaterialApp(
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
  cartellaDocumentiFinta('planner_docs');
  final pp = Recipe(id: 'pp', title: 'Pasta e patate ${'lunghissima ' * 8}', servings: 4, ingredients: [
    Ingredient(name: 'Patate', amount: '400 g'),
    Ingredient(name: 'Pasta mista', amount: '320 g'),
  ]);
  final pf = Recipe(id: 'pf', title: 'Patate al forno', servings: 2, ingredients: [Ingredient(name: 'patate', amount: '1 kg')]);
  appState = statoFinto(ricette: [pp, pf])..purchasedPro = true;
  setUpAll(caricaCaratteriVeri);

  for (final lingua in L10n.available) {
    testWidgets('$lingua, 320 px, testo ×1.3: settimana con 6 pasti e lista della spesa senza overflow', (t) async {
      await t.runAsync(() => L10n.load(lingua));
      appState.data.plan = MealPlan();
      final start = weekStart(DateTime.now());
      for (final m in Meal.values) {
        appState.plan.extraMeals.add(m);
        appState.plan.add(planDay(start), m, PlanEntry(recipeId: 'pp', servings: 12));
      }
      appState.plan.add(planDay(start.add(const Duration(days: 2))), Meal.cena, PlanEntry(recipeId: 'pf', servings: 4));
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(t.view.reset);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.pumpWidget(_app(const Scaffold(body: PlannerTab())));
      await t.pump(const Duration(milliseconds: 300));
      final errori = _errori(t);
      expect(find.byType(InputChip), findsWidgets);
      await t.pumpWidget(_app(ShoppingScreen(start: start)));
      await t.pump(const Duration(milliseconds: 300));
      errori.addAll(_errori(t).map((e) => 'spesa: $e'));
      expect(find.text('Patate'), findsOneWidget);
      expect(errori, isEmpty, reason: errori.join('\n'));
    });
  }
}
