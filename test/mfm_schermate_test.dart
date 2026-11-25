// Tester cattivo (adattato da MyFleetManager t24_c_schermate_test / scroll_test / app_bar_icons_test /
// tc_e_ui_test) — le 5 schede delle Impostazioni, la schermata Backup e una ricetta assurda si costruiscono
// senza overflow né eccezioni su un telefono stretto (320 px), anche in tedesco, finlandese, greco, russo,
// thai, hindi e giapponese (T-L10N-04, T-UI-03/04/05). Niente Firebase: appState montato a mano.
import 'dart:io';

import 'package:familyrecipes/l10n.dart';
import 'package:familyrecipes/main.dart';
import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/screens/backup_screen.dart';
import 'package:familyrecipes/screens/recipe_detail_screen.dart';
import 'package:familyrecipes/screens/settings_screen.dart';
import 'package:familyrecipes/services/backup_service.dart';
import 'package:familyrecipes/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mfm_aiuti.dart';

// Tutte le 36 lingue (in tedesco, finlandese, greco… i testi sono i più lunghi).
final _lingue = L10n.available;

Widget _app(Widget home, {Brightness b = Brightness.light}) => MaterialApp(
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
      darkTheme: buildTheme(ThemeSettings(), Brightness.dark),
      themeMode: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: home,
    );

/// Raccoglie gli errori di disegno (overflow compresi) invece di farli esplodere subito.
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
  cartellaDocumentiFinta('mfm_schermate_docs');
  final backupDir = Directory.systemTemp.createTempSync('mfm_schermate_backup');
  BackupService.baseOverride = backupDir;
  final assurda = Recipe(
    id: 'ASSURDA',
    title: 'Torta ${'lunghissima ' * 60}🍝🔥👨‍👩‍👧‍👦',
    intro: 'x' * 3000,
    servings: 4,
    prepMinutes: 100000,
    cookMinutes: 59,
    ingredients: [
      Ingredient(name: 'Farina${'0' * 200}', amount: '1${'0' * 40} g'),
      Ingredient(name: '', amount: ''),
      Ingredient(name: 'Sale', amount: 'q.b.'),
      Ingredient(name: 'Uova', amount: '½'),
    ],
    steps: [RecipeStep(text: 'Impastare ${'molto ' * 300}'), RecipeStep(text: '')],
    tips: '{name} {n} %s',
    createdByName: 'Nonna ${'Pina ' * 40}',
  );
  appState = statoFinto(ricette: [assurda]);
  setUpAll(caricaCaratteriVeri);

  for (final lingua in _lingue) {
    for (final scala in [1.0, 1.5]) {
      testWidgets('$lingua, 320 px, testo ×$scala: le 5 schede delle Impostazioni senza overflow', (t) async {
        await t.runAsync(() => L10n.load(lingua));
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = scala;
        addTearDown(t.view.reset);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await t.pumpWidget(_app(const SettingsScreen()));
        await t.pump(const Duration(milliseconds: 300));
        final errori = <String>[..._errori(t)];
        for (var i = 0; i < 5; i++) {
          await t.tap(find.byType(Tab).at(i));
          await t.pump(const Duration(milliseconds: 400));
          await t.pump(const Duration(milliseconds: 400));
          errori.addAll(_errori(t).map((e) => 'scheda $i: $e'));
        }
        expect(errori, isEmpty, reason: errori.join('\n'));
      });
    }

    testWidgets('$lingua, 320 px: schermata Backup (vuota e con un backup) senza overflow', (t) async {
      await t.runAsync(() => L10n.load(lingua));
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.runAsync(() async {
        for (final f in backupDir.listSync()) {
          f.deleteSync(recursive: true);
        }
      });
      Future<void> attendi(Finder f) async {
        for (var i = 0; i < 50 && f.evaluate().isEmpty; i++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await t.pump(const Duration(milliseconds: 50));
        }
      }

      await t.pumpWidget(_app(const BackupScreen()));
      await t.pump(const Duration(milliseconds: 300));
      final errori = <String>[..._errori(t)];
      expect(find.text(tr('backup.none')), findsOneWidget);
      await t.runAsync(() => BackupService.save(appState.session!.storageKey,
          BackupService.encode(recipes: [assurda], photos: {}, favorites: {}, reason: 'import'), DateTime(2026, 11, 25, 9)));
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(_app(const BackupScreen()));
      await attendi(find.text(tr('backup.restore')));
      errori.addAll(_errori(t));
      expect(find.text(tr('backup.restore')), findsOneWidget);
      expect(errori, isEmpty, reason: errori.join('\n'));
    });
  }

  for (final b in Brightness.values) {
    testWidgets('ricetta assurda (titolo di 700 caratteri, dosi di 40 cifre), 320 px, tema ${b.name}', (t) async {
      await t.runAsync(() => L10n.load('de'));
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(_app(const RecipeDetailScreen(recipeId: 'ASSURDA'), b: b));
      await t.pump(const Duration(milliseconds: 500));
      final errori = _errori(t);
      // scorrere fino in fondo non rompe niente
      await t.drag(find.byType(Scrollable).first, const Offset(0, -20000));
      await t.pump(const Duration(milliseconds: 500));
      errori.addAll(_errori(t));
      expect(errori, isEmpty, reason: errori.join('\n'));
      await t.pumpWidget(const SizedBox());
    });
  }

}
