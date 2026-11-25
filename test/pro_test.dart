import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/services/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mfm_aiuti.dart';

void main() {
  Recipe r(String id, RecipeCategory c, int created, {String? book, String by = 'mario'}) =>
      Recipe(id: id, title: id, category: c, createdAt: created, bookId: book, createdBy: by);

  test('Pro: categorie aperte e chiuse nella versione gratuita', () {
    final s = statoFinto();
    expect(AppState.freeCategories,
        {RecipeCategory.aperitivi, RecipeCategory.primi, RecipeCategory.secondi, RecipeCategory.dolci});
    for (final c in RecipeCategory.values) {
      expect(s.categoryOpen(c), AppState.freeCategories.contains(c), reason: c.name);
    }
    s.purchasedPro = true;
    expect(RecipeCategory.values.every(s.categoryOpen), isTrue);
  });

  test('Pro: le prime 3 ricette per categoria restano modificabili, le altre in sola lettura', () {
    final s = statoFinto(ricette: [
      for (var i = 1; i <= 5; i++) r('d$i', RecipeCategory.dolci, i),
      r('a1', RecipeCategory.antipasti, 1),
    ]);
    final byId = {for (final x in s.data.recipes) x.id: x};
    expect([for (var i = 1; i <= 5; i++) s.canEdit(byId['d$i']!)], [true, true, true, false, false]);
    expect(s.canEdit(byId['a1']!), isFalse, reason: 'categoria bloccata');
    // Proprie: si aprono comunque (sola lettura) e si possono eliminare per liberare posto.
    expect(s.canOpen(byId['d5']!), isTrue);
    expect(s.canDelete(byId['d5']!), isTrue);
    expect(s.canPlace(Recipe(category: RecipeCategory.dolci)), isFalse);
    expect(s.canPlace(Recipe(category: RecipeCategory.primi)), isTrue);
    expect(s.canPlace(Recipe(category: RecipeCategory.contorni)), isFalse);
    expect(s.hasFreeSlot(null), isTrue);

    s.purchasedPro = true;
    s.notifyListeners();
    expect(s.canEdit(byId['d5']!), isTrue);
    expect(s.canPlace(Recipe(category: RecipeCategory.contorni)), isTrue);
  });

  test('Pro: modificare una ricetta nei limiti è permesso, spostarla in una categoria piena no', () {
    final s = statoFinto(ricette: [
      for (var i = 1; i <= 3; i++) r('p$i', RecipeCategory.primi, i),
      r('s1', RecipeCategory.secondi, 1),
    ]);
    final p1 = s.recipeById('p1')!.copy()..title = 'nuovo titolo';
    expect(s.canPlace(p1), isTrue);
    final s1 = s.recipeById('s1')!.copy()..category = RecipeCategory.primi;
    expect(s.canPlace(s1), isFalse);
  });

  test('Pro: nei gruppi gli stessi limiti, contati per ogni ricettario', () {
    final g = FamilyGroup(
        id: 'GRUPPO1234', name: 'Famiglia', ownerUid: 'mario', members: {'mario': 'm', 'zia': 'z'}, admins: {'mario'});
    final s = statoFinto(mode: AccountMode.cloud, personale: 'mario', gruppi: [
      g
    ], ricette: [
      for (var i = 1; i <= 3; i++) r('m$i', RecipeCategory.dolci, i),
      for (var i = 1; i <= 4; i++) r('g$i', RecipeCategory.dolci, i, book: 'GRUPPO1234', by: 'zia'),
    ]);
    // Le mie sono piene, ma nel gruppo c'è un ricettario a parte.
    expect(s.canPlace(Recipe(category: RecipeCategory.dolci)), isFalse);
    expect(s.canPlace(Recipe(category: RecipeCategory.dolci, bookId: 'GRUPPO1234')), isFalse);
    expect(s.canPlace(Recipe(category: RecipeCategory.primi, bookId: 'GRUPPO1234')), isTrue);
    // La quarta del gruppo, scritta da un altro, non si apre senza Pro.
    final g4 = s.recipeById('g4')!;
    expect(s.withinFree(g4), isFalse);
    expect(s.canOpen(g4), isFalse);
    expect(s.canOpen(s.recipeById('g3')!), isTrue);
  });

  test('Pro: senza posto in nessuna categoria non si può iniziare una nuova ricetta', () {
    final s = statoFinto(ricette: [
      for (final c in AppState.freeCategories)
        for (var i = 1; i <= 3; i++) r('${c.name}$i', c, i),
    ]);
    expect(s.hasFreeSlot(null), isFalse);
    s.purchasedPro = true;
    expect(s.hasFreeSlot(null), isTrue);
  });
}
