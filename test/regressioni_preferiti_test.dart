// Regressioni: bug trovati dal tester cattivo nella 1.9.0/1.10.0 e corretti nella 1.10.1.
// Lancio:  flutter test tool/tests/bug_preferiti_test.dart
import 'dart:async';

import 'package:familyrecipes/l10n.dart';
import 'package:familyrecipes/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mfm_aiuti.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  cartellaDocumentiFinta('bug_preferiti_docs');
  setUpAll(() => L10n.load('it'));

  test('BUG ricetta preferita spostata in un gruppo (account online): perde la stella', () async {
    // saveRecipe (app_state.dart:296-308), con l'account online, sposta la ricetta creando una copia con id
    // NUOVO e una lapide col vecchio id; favRecipes contiene ancora il vecchio id e nessuno lo aggiorna.
    // (Firebase non c'è: gli errori della scrittura su Firestore, che partirebbe in background, si ignorano.)
    final g = FamilyGroup(id: 'GRUPPO1234', name: 'Famiglia', ownerUid: 'uid1', members: {'uid1': 'm'});
    final s = statoFinto(ricette: [Recipe(id: 'a', title: 'Torta della nonna')], gruppi: [g], key: 'uid1',
        mode: AccountMode.cloud);
    await s.toggleFavorite(s.recipeById('a')!);
    await runZonedGuarded(() => s.moveRecipe('a', 'GRUPPO1234'), (e, st) {});
    final torta = s.recipes.singleWhere((r) => r.title == 'Torta della nonna');
    expect(torta.bookId, 'GRUPPO1234');
    expect(s.isFavorite(torta), isTrue, reason: 'la stella è rimasta sull\'id ${s.favRecipes} della lapide, '
        'la ricetta spostata ha id ${torta.id}');
  });
}
