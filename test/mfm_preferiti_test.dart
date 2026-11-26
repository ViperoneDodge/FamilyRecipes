// Tester cattivo (adattato da MyFleetManager favorites_test) — preferiti: ricette singole, gruppi interi,
// ricette eliminate, impostazioni salvate e rilette, file impostazioni rovinato (T-DATA-07).
import 'dart:convert';
import 'dart:io';

import 'package:familyrecipes/l10n.dart';
import 'package:familyrecipes/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mfm_aiuti.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final docs = cartellaDocumentiFinta('mfm_preferiti_docs');
  setUpAll(() => L10n.load('it'));
  setUp(() {
    for (final f in docs.listSync()) {
      f.deleteSync(recursive: true);
    }
  });

  final mia = Recipe(id: 'a', title: 'Torta');
  final g1 = Recipe(id: 'b', title: 'Sugo', bookId: 'G1G1G1G1G1');
  final g2 = Recipe(id: 'c', title: 'Arrosto', bookId: 'G1G1G1G1G1');
  final altra = Recipe(id: 'd', title: 'Zuppa', bookId: 'G2G2G2G2G2');

  test('stella su una singola ricetta, tocco doppio = tolta', () async {
    final s = statoFinto(ricette: [mia, g1]);
    await s.toggleFavorite(mia);
    expect(s.isFavorite(mia), isTrue);
    expect(s.isFavorite(g1), isFalse);
    await s.toggleFavorite(mia);
    expect(s.isFavorite(mia), isFalse);
    expect(s.favoriteRecipes, isEmpty);
  });

  test('gruppo intero tra i preferiti: tutte le sue ricette, non quelle degli altri gruppi', () async {
    final s = statoFinto(ricette: [mia, g1, g2, altra]);
    await s.toggleFavoriteGroup('G1G1G1G1G1');
    expect(s.favoriteRecipes.map((r) => r.id), unorderedEquals(['b', 'c']));
    expect(s.isFavorite(altra), isFalse);
    // una ricetta nuova aggiunta al gruppo è subito tra i preferiti
    final nuova = Recipe(id: 'e', title: 'Nuova', bookId: 'G1G1G1G1G1');
    s.data.recipes.add(nuova);
    expect(s.isFavorite(nuova), isTrue);
    await s.toggleFavoriteGroup('G1G1G1G1G1');
    expect(s.favoriteRecipes, isEmpty);
  });

  test('ricetta eliminata: sparisce dai preferiti anche se la stella resta salvata', () async {
    final s = statoFinto(ricette: [mia]);
    await s.toggleFavorite(mia);
    s.data.recipes[0] = mia.tombstone(at: 1, by: 'x', byUid: 'x');
    expect(s.favoriteRecipes, isEmpty);
  });

  test('salvati e riletti all\'avvio, con «apri sui preferiti»', () async {
    final s = statoFinto(ricette: [mia, g1]);
    await s.toggleFavorite(mia);
    await s.toggleFavoriteGroup('G1G1G1G1G1');
    await s.setStartOnFavorites(true);
    await s.setSortNewestFirst(true);
    final j = jsonDecode(File('${docs.path}/settings.json').readAsStringSync()) as Map;
    expect(j['favRecipes'], ['a']);
    expect(j['favGroups'], ['G1G1G1G1G1']);
    expect(j['start'], 'plan');
    final t = statoFinto()..session = null;
    await t.init();
    expect(t.favRecipes, {'a'});
    expect(t.favGroups, {'G1G1G1G1G1'});
    expect(t.startOnFavorites, isTrue);
    expect(t.sortNewestFirst, isTrue);
  });

  test('impostazioni con tipi strani (versione futura o file rovinato): nessuna eccezione', () async {
    for (final contenuto in [
      '{"favRecipes":[1,null,"a"],"favGroups":["G"],"start":"boh"}',
      '{"favRecipes":null,"favGroups":null}',
      '{"lang":"klingon","sortNewest":"si"}',
      '{"favRecipes":',
    ]) {
      File('${docs.path}/settings.json').writeAsStringSync(contenuto);
      final t = statoFinto()..session = null;
      await t.init();
      expect(t.loading, isFalse, reason: contenuto);
      expect(t.startOnFavorites, isFalse, reason: contenuto);
    }
  });

  test('ordinamento: alfabetico senza badare alle maiuscole, titoli vuoti come «Senza titolo», a parità per id',
      () {
    final s = statoFinto(ricette: [
      Recipe(id: '2', title: 'banana'),
      Recipe(id: '1', title: 'Banana'),
      Recipe(id: '3', title: ''),
      Recipe(id: '4', title: '   '),
      Recipe(id: '5', title: 'Árbol'),
      Recipe(id: '6', title: 'zuppa'),
    ]);
    final l = s.allRecipes.map((r) => r.id).toList();
    expect(l.indexOf('1'), lessThan(l.indexOf('2')));
    expect(l.length, 6);
    s.sortNewestFirst = true;
    expect(s.allRecipes.length, 6);
  });
}
