import 'package:familyrecipes/l10n.dart';
import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/services/group_watch.dart';
import 'package:familyrecipes/services/pdf_export.dart';
import 'package:flutter_test/flutter_test.dart';

Recipe _carbonara() => Recipe(
      category: RecipeCategory.primi,
      title: 'Spaghetti alla carbonara',
      intro: 'Il classico romano.',
      coverPhoto: 'COVER',
      difficulty: Difficulty.easy,
      cost: Cost.low,
      prepMinutes: 15,
      cookMinutes: 10,
      servings: 4,
      ingredients: [
        Ingredient(name: 'Spaghetti', amount: '320 g'),
        Ingredient(name: 'Guanciale', amount: '150 g'),
        Ingredient(name: 'Tuorli', amount: '6'),
      ],
      steps: [
        RecipeStep(text: 'Tagliate il guanciale a listarelle.', photos: ['P1']),
        RecipeStep(text: 'Rosolatelo in padella.', photos: ['P2', 'P3']),
        RecipeStep(text: 'Mantecate fuori dal fuoco.'),
      ],
      tips: 'Niente panna!',
      createdByName: 'Nonna',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await L10n.load('it');
  });

  test('ricetta: JSON andata e ritorno', () {
    final r = _carbonara();
    final c = Recipe.fromJson(r.toJson());
    expect(c.toJson(), r.toJson());
    expect(c.ingredients.map((i) => i.amount), ['320 g', '150 g', '6']);
    expect(c.steps[1].photos, ['P2', 'P3']);
  });

  test('ricetta: foto, anteprima, tempi e ricerca', () {
    final r = _carbonara();
    expect(r.photoIds, {'COVER', 'P1', 'P2', 'P3'});
    expect(r.thumbnail, 'COVER');
    r.coverPhoto = null;
    expect(r.thumbnail, 'P3');
    expect(r.totalMinutes, 25);
    expect(r.searchText, contains('guanciale'));
    expect(fmtMinutes(25), '25 min');
    expect(fmtMinutes(90), '1 h 30 min');
    expect(fmtMinutes(120), '2 h');
  });

  test('valori sconosciuti tornano ai predefiniti', () {
    final r = Recipe.fromJson({'id': 'X', 'category': 'boh', 'difficulty': 'boh', 'cost': 'boh'});
    expect(r.category, RecipeCategory.primi);
    expect(r.difficulty, Difficulty.easy);
    expect(r.cost, Cost.low);
    expect(r.ingredients, isEmpty);
  });

  test('tutte le categorie hanno un nome', () {
    for (final c in RecipeCategory.values) {
      expect(categoryLabel(c), isNot(startsWith('cat.')));
    }
    expect(categoryLabel(RecipeCategory.menu), 'Menù completi');
  });

  test('ruoli nel gruppo', () {
    final g = FamilyGroup(id: 'G', name: 'Famiglia', ownerUid: 'O', admins: {'A'}, viewers: {'V'});
    expect(g.roleOf('O'), GroupRole.admin);
    expect(g.roleOf('A'), GroupRole.admin);
    expect(g.roleOf('V'), GroupRole.viewer);
    expect(g.roleOf('E'), GroupRole.editor);
    expect(g.roleOf(null), GroupRole.viewer);
  });

  test('avvisi di gruppo: aggiunte, modifiche, eliminazioni', () {
    Recipe r(String id, int at, String by, {bool deleted = false}) =>
        Recipe(id: id, title: 'R$id', updatedAt: at, updatedByUid: by, updatedBy: by, deleted: deleted);
    final acts = findActivities(
      groupName: 'Famiglia',
      me: 'ME',
      myName: 'Io',
      since: 100,
      remote: [
        r('1', 150, 'MARIA'),
        r('2', 160, 'MARIA'),
        r('3', 170, 'ME'),
        r('4', 90, 'MARIA'),
        r('5', 180, 'LUCA', deleted: true),
        r('6', 190, 'LUCA', deleted: true),
      ],
      existed: (id) => id == '2' || id == '5',
    );
    expect(acts.map((a) => a.action), [GroupAction.added, GroupAction.edited, GroupAction.deleted]);
    expect(acts.first.text, contains('MARIA'));
    expect(acts.first.text, contains('R1'));
  });

  test('PDF di una ricetta e di un ricettario', () async {
    final one = await PdfExport.build(
      title: 'Carbonara',
      recipes: [_carbonara()],
      photo: (r, p) async => null,
    );
    expect(String.fromCharCodes(one.take(5)), '%PDF-');
    final many = [
      _carbonara(),
      Recipe(category: RecipeCategory.dolci, title: 'Tiramisù', servings: 6),
      Recipe(category: RecipeCategory.menu, title: 'Pranzo della domenica'),
    ];
    many[2].courses = [many[0].id, many[1].id];
    final book = await PdfExport.build(
      title: 'Famiglia Rossi',
      recipes: many,
      photo: (r, p) async => null,
      lookup: {for (final r in many) r.id: r},
    );
    expect(book.length, greaterThan(one.length));
  });

  test('i testi italiani e inglesi hanno le stesse chiavi', () async {
    await L10n.load('en');
    expect(tr('cat.dolci'), 'Desserts');
    expect(trn('book.recipes', 1), '1 recipe');
    expect(trn('book.recipes', 3), '3 recipes');
    await L10n.load('it');
    expect(trn('book.recipes', 3), '3 ricette');
  });
}
