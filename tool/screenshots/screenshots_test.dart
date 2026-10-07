// Screenshot delle schermate principali (per Play Store e controlli grafici).
// Esecuzione: flutter test tool/screenshots/screenshots_test.dart --update-goldens
import 'dart:io';

import 'package:familyrecipes/l10n.dart';
import 'package:familyrecipes/main.dart';
import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/screens/family_screen.dart';
import 'package:familyrecipes/screens/home_screen.dart';
import 'package:familyrecipes/screens/recipe_detail_screen.dart';
import 'package:familyrecipes/screens/recipe_edit_screen.dart';
import 'package:familyrecipes/screens/settings_screen.dart';
import 'package:familyrecipes/services/app_state.dart';
import 'package:familyrecipes/services/pdf_export.dart';
import 'package:familyrecipes/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const me = 'demo-me';
late Directory docs;

Future<void> loadFonts() async {
  final sdk = Platform.environment['FLUTTER_ROOT']!;
  Future<void> f(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final p in files) {
      final b = File(p).readAsBytesSync();
      l.addFont(Future.value(ByteData.view(b.buffer)));
    }
    await l.load();
  }

  final m = '$sdk/bin/cache/artifacts/material_fonts';
  await f('Roboto', ['$m/Roboto-Regular.ttf', '$m/Roboto-Medium.ttf', '$m/Roboto-Bold.ttf']);
  await f('MaterialIcons', ['$m/MaterialIcons-Regular.otf']);
  await f('PatrickHand', ['assets/fonts/PatrickHand-Regular.ttf']);
}

Recipe recipe(String id, RecipeCategory c, String title,
    {String? book, String by = me, String byName = 'Marco', int prep = 20, int cook = 30, Difficulty d = Difficulty.easy}) =>
    Recipe(
      id: id,
      category: c,
      title: title,
      bookId: book,
      createdBy: by,
      createdByName: byName,
      createdAt: id.codeUnitAt(1),
      prepMinutes: prep,
      cookMinutes: cook,
      difficulty: d,
    );

void setupData() {
  appState.session = Session(mode: AccountMode.cloud, key: me, displayName: 'Marco Rossi', email: 'marco.rossi@example.com');
  appState.loading = false;
  appState.syncStatus = SyncStatus.online;
  final fam = FamilyGroup(id: 'FAM7Q2K9XW', name: 'Famiglia Rossi', ownerUid: me, members: {
    me: 'Marco Rossi',
    'u2': 'Nonna Lucia',
    'u3': 'Giulia Rossi',
  }, admins: {me}, viewers: {'u3'});
  final carbonara = recipe('r1', RecipeCategory.primi, 'Spaghetti alla carbonara', prep: 15, cook: 10)
    ..coverPhoto = 'COVER1'
    ..servings = 4
    ..cost = Cost.low
    ..intro = 'La carbonara di casa: pochi ingredienti, tutti di qualità. '
        'Il segreto è mantecare fuori dal fuoco, così la crema resta liscia e vellutata.'
    ..ingredients = [
      Ingredient(name: 'Spaghetti', amount: '320 g'),
      Ingredient(name: 'Guanciale', amount: '150 g'),
      Ingredient(name: 'Tuorli', amount: '6'),
      Ingredient(name: 'Pecorino romano DOP', amount: '50 g'),
      Ingredient(name: 'Pepe nero', amount: 'q.b.'),
    ]
    ..steps = [
      RecipeStep(text: 'Tagliate il guanciale prima a fette e poi a listarelle spesse circa 1 cm.', photos: ['STEP1']),
      RecipeStep(
          text: 'Rosolatelo in padella senza olio per 15 minuti a fuoco medio, finché diventa croccante.',
          photos: ['STEP2', 'STEP1']),
      RecipeStep(text: 'In una ciotola sbattete i tuorli con il pecorino e abbondante pepe.'),
      RecipeStep(text: 'Scolate la pasta al dente, versatela nella padella e mantecate fuori dal fuoco con la crema.'),
    ]
    ..tips = 'Niente panna e niente pancetta: solo guanciale. Se la crema è troppo densa aggiungete un mestolino di acqua di cottura.';
  appState.data = UserData(
    personalBookId: me,
    groups: [fam],
    recipes: [
      carbonara,
      recipe('r2', RecipeCategory.dolci, 'Tiramisù della nonna', by: 'u2', byName: 'Nonna Lucia', book: fam.id, prep: 40, cook: 0)
        ..coverPhoto = 'COVER2',
      recipe('r3', RecipeCategory.antipasti, 'Crostini toscani', prep: 20, cook: 15),
      recipe('r4', RecipeCategory.secondi, 'Arrosto di vitello al latte', prep: 20, cook: 90, d: Difficulty.medium),
      recipe('r5', RecipeCategory.conserve, 'Passata di pomodoro', prep: 60, cook: 45),
      recipe('r6', RecipeCategory.liquori, 'Limoncello', prep: 30, cook: 0, d: Difficulty.veryEasy),
      recipe('r7', RecipeCategory.primi, 'Lasagne alla bolognese', by: 'u2', byName: 'Nonna Lucia', book: fam.id,
          prep: 60, cook: 40, d: Difficulty.medium),
      recipe('r8', RecipeCategory.contorni, 'Peperonata', book: fam.id, prep: 15, cook: 40),
      recipe('r9', RecipeCategory.menu, 'Pranzo della domenica', book: fam.id, prep: 0, cook: 0)
        ..courses = ['r7', 'r2'],
      recipe('r10', RecipeCategory.aperitivi, 'Spritz', prep: 5, cook: 0, d: Difficulty.veryEasy),
    ],
  );
}

Future<void> precacheAll(WidgetTester tester) async {
  await tester.runAsync(() async {
    final ctx = tester.element(find.byType(Scaffold).first);
    await precacheImage(const AssetImage('assets/gian_trip_logo.png'), ctx);
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> shot(WidgetTester tester, Widget home, String name, {Future<void> Function()? then}) async {
  await tester.runAsync(() async {
    for (final p in ['COVER1', 'COVER2', 'STEP1', 'STEP2']) {
      await appState.photos.load(p);
    }
  });
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(ListenableBuilder(
    listenable: appState,
    builder: (_, __) => MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: Locale(L10n.code),
      supportedLocales: const [Locale('en'), Locale('it')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildTheme(appState.theme, Brightness.light),
      darkTheme: buildTheme(appState.theme, Brightness.dark),
      themeMode: appState.theme.mode,
      home: home,
    ),
  ));
  await tester.pumpAndSettle();
  await precacheAll(tester);
  if (then != null) {
    await then();
    await tester.pumpAndSettle();
    await precacheAll(tester);
  }
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/${L10n.code}/$name.png'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  docs = Directory.systemTemp.createTempSync('familyrecipes');
  final photos = Directory('${docs.path}/foto')..createSync();
  for (final f in Directory('tool/screenshots/photos').listSync().whereType<File>()) {
    f.copySync('${photos.path}/${f.uri.pathSegments.last}');
  }
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => docs.path,
  );
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  appState = AppState();
  debugDefaultTargetPlatformOverride = null;
  for (final lang in ['it', 'en']) {
    group(lang, () {
      setUp(() async {
        await L10n.load(lang);
        setupData();
      });
      testWidgets('screens', (tester) async {
        await tester.runAsync(loadFonts);
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 2.625;
        addTearDown(tester.view.reset);
        debugDisableShadows = false;

        await shot(tester, const HomeScreen(), '01_mine');
        await shot(tester, const RecipeDetailScreen(recipeId: 'r1'), '02_recipe');
        await shot(tester, const RecipeDetailScreen(recipeId: 'r1'), '03_steps', then: () async {
          await tester.drag(find.byType(ListView).first, const Offset(0, -900));
        });
        await shot(tester, const HomeScreen(), '04_index', then: () async {
          await tester.tap(find.text(tr('tab.index')).last);
        });
        await shot(tester, const HomeScreen(), '05_groups', then: () async {
          await tester.tap(find.text(tr('tab.family')).last);
        });
        await shot(tester, const GroupScreen(groupId: 'FAM7Q2K9XW'), '06_members', then: () async {
          await tester.drag(find.byType(ListView).first, const Offset(0, -560));
        });
        await shot(tester, RecipeEditScreen(recipe: appState.recipeById('r1')!.copy()), '07_edit', then: () async {
          await tester.drag(find.byType(ListView).first, const Offset(0, -1300));
        });
        await shot(tester, const SettingsScreen(), '08_settings', then: () async {
          await tester.drag(find.byType(ListView).first, const Offset(0, -300));
        });
        await shot(tester, const RecipeDetailScreen(recipeId: 'r9'), '09_menu');
        appState.theme = ThemeSettings(mode: ThemeMode.dark, palette: 3, paper: PaperStyle.quadretti);
        await shot(tester, const RecipeDetailScreen(recipeId: 'r1'), '10_dark');
        appState.theme = ThemeSettings();
        await tester.runAsync(() async {
          Future<Uint8List?> photo(Recipe r, String p) => appState.photos.load(p);
          final one = await PdfExport.build(title: 'Carbonara', recipes: [appState.recipeById('r1')!], photo: photo);
          File('tool/screenshots/out/${L10n.code}/recipe.pdf').writeAsBytesSync(one);
          final book = await PdfExport.build(
            title: 'Famiglia Rossi',
            recipes: appState.allRecipes,
            photo: photo,
            lookup: {for (final r in appState.recipes) r.id: r},
          );
          File('tool/screenshots/out/${L10n.code}/book.pdf').writeAsBytesSync(book);
        });
        debugDisableShadows = true;
      });
    });
  }
}
