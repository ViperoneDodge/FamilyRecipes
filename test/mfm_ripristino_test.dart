// Tester cattivo (adattato da MyFleetManager t243_a_backup_test «restoreVehicles») — AppState.restoreBackup:
// ricette doppie, gruppi spariti, sola lettura, backup di un altro account, foto e preferiti
// (T-DATA-02/04, T-FREE-…→ ruoli, T-GRP-…). Niente Firebase: sessione locale o «cloud» finta senza sync.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:familyrecipes/l10n.dart';
import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mfm_aiuti.dart';

Recipe _r(String id, String titolo, {String? book, String? cover, String createdBy = ''}) =>
    Recipe(id: id, title: titolo, bookId: book, coverPhoto: cover, createdBy: createdBy, createdAt: 1000);

BackupData _dati(List<Recipe> rs, {Map<String, Uint8List> foto = const {}, Set<String> pref = const {}}) =>
    BackupService.decode(BackupService.encode(recipes: rs, photos: foto, favorites: pref, reason: 'manual'))!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final docs = cartellaDocumentiFinta('mfm_ripristino_docs');
  late Directory dir;

  setUpAll(() => L10n.load('it'));
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mfm_ripristino');
    BackupService.baseOverride = dir;
  });
  tearDown(() async {
    BackupService.baseOverride = null;
    await dir.delete(recursive: true);
  });

  test('la ricetta torna com\'era; quelle aggiunte dopo restano', () async {
    final s = statoFinto(ricette: [_r('a', 'Rinominata'), _r('nuova', 'Aggiunta dopo')]);
    final n = await s.restoreBackup(_dati([_r('a', 'Torta della nonna')]));
    expect(n, 1);
    expect(s.recipeById('a')!.title, 'Torta della nonna');
    expect(s.recipeById('nuova'), isNotNull);
    expect(s.recipes.length, 2);
  });

  test('prima del ripristino c\'è un backup «restore» con lo stato attuale, rileggibile', () async {
    final s = statoFinto(ricette: [_r('a', 'Attuale')]);
    await s.restoreBackup(_dati([_r('a', 'Vecchia')]));
    final l = await BackupService.list(s.session!.storageKey);
    expect(l.length, 1);
    expect(l.single.reason, 'restore');
    final d = BackupService.decode(await l.single.file.readAsBytes())!;
    expect(d.recipes.single.title, 'Attuale');
  });

  test('ripristinare lo stesso file due volte non crea doppioni', () async {
    final s = statoFinto();
    final b = _dati([_r('a', 'Torta'), _r('b', 'Sugo')]);
    expect(await s.restoreBackup(b), 2);
    expect(await s.restoreBackup(b), 2);
    expect(s.recipes.length, 2);
  });

  test('id ripetuto nel file: contato e ripristinato una volta sola', () async {
    final s = statoFinto();
    final b = BackupService.decode(backupAMano([
      {'id': 'dup', 'title': 'Prima'},
      {'id': 'dup', 'title': 'Seconda'},
    ]))!;
    expect(await s.restoreBackup(b), 1);
    expect(s.recipes.length, 1);
    expect(s.recipes.single.title, 'Prima');
  });

  test('ricetta eliminata dopo il backup: torna', () async {
    final tomba = _r('a', 'Torta')..deleted = true;
    final s = statoFinto(ricette: [tomba]);
    expect(await s.restoreBackup(_dati([_r('a', 'Torta')])), 1);
    expect(s.recipeById('a'), isNotNull);
    expect(s.data.recipes.where((r) => r.id == 'a').length, 1);
  });

  test('ricetta di un gruppo che non c\'è più: torna tra le mie', () async {
    final s = statoFinto();
    final n = await s.restoreBackup(_dati([_r('g1', 'Del gruppo cancellato', book: 'GRUPPOVIA1'), _r('p1', 'Mia')]));
    expect(n, 2);
    expect(s.recipeById('g1')!.bookId, isNull);
    expect(s.isPersonal(s.recipeById('g1')!), isTrue);
  });

  test('gruppo in sola lettura: le sue ricette si saltano, le altre no', () async {
    final g = FamilyGroup(id: 'GRUPPOVIEW', name: 'Zii', ownerUid: 'zio', viewers: {'mario'}, members: {'zio': 'z', 'mario': 'm'});
    final s = statoFinto(gruppi: [g]);
    final n = await s.restoreBackup(_dati([_r('v1', 'Degli zii', book: 'GRUPPOVIEW'), _r('p1', 'Mia')]));
    expect(n, 1);
    expect(s.recipeById('v1'), isNull);
    expect(s.recipeById('p1'), isNotNull);
  });

  test('ricetta che oggi è in sola lettura (ma esiste): non viene sovrascritta', () async {
    final g = FamilyGroup(id: 'GRUPPOVIEW', name: 'Zii', ownerUid: 'zio', viewers: {'mario'}, members: {'zio': 'z', 'mario': 'm'});
    final attuale = _r('v1', 'Versione degli zii', book: 'GRUPPOVIEW');
    final s = statoFinto(ricette: [attuale], gruppi: [g]);
    // Nel backup la stessa ricetta risultava tra le mie: non deve diventare una scorciatoia per modificarla.
    final n = await s.restoreBackup(_dati([_r('v1', 'Versione vecchia')]));
    expect(n, 0);
    expect(s.recipeById('v1')!.title, 'Versione degli zii');
  });

  test('foto del backup: ripristinate se mancano, mai sovrascritte se ci sono', () async {
    final s = statoFinto();
    final p = await s.photos.file('FOTOESISTE');
    await p.writeAsBytes([9, 9, 9]);
    final b = _dati([
      _r('a', 'Torta', cover: 'FOTONUOVA')..steps = [RecipeStep(text: 'x', photos: ['FOTOESISTE'])]
    ], foto: {
      'FOTONUOVA': Uint8List.fromList([1, 2, 3]),
      'FOTOESISTE': Uint8List.fromList([4, 5, 6]),
    });
    await s.restoreBackup(b);
    expect(await (await s.photos.file('FOTONUOVA')).readAsBytes(), [1, 2, 3]);
    expect(await p.readAsBytes(), [9, 9, 9]);
  });

  test('preferiti del backup: tornano per le ricette ripristinate e vengono salvati', () async {
    final s = statoFinto();
    await s.restoreBackup(_dati([_r('a', 'Torta'), _r('b', 'Sugo')], pref: {'a', 'zzz'}));
    expect(s.favRecipes, {'a'});
    expect(s.isFavorite(s.recipeById('a')!), isTrue);
    final saved = jsonDecode(await File('${docs.path}/settings.json').readAsString()) as Map;
    expect(saved['favRecipes'], ['a']);
  });

  test('backup vuoto: 0 ricette, niente cambia, nessuna eccezione', () async {
    final s = statoFinto(ricette: [_r('a', 'Torta')]);
    expect(await s.restoreBackup(_dati([])), 0);
    expect(s.recipes.single.title, 'Torta');
  });

  test('ripristino di 500 ricette: tutte, in tempi ragionevoli', () async {
    final s = statoFinto();
    final sw = Stopwatch()..start();
    final n = await s.restoreBackup(_dati([for (var i = 0; i < 500; i++) _r('r$i', 'Ricetta $i')]));
    sw.stop();
    expect(n, 500);
    expect(s.recipes.length, 500);
    expect(sw.elapsedMilliseconds, lessThan(60000));
  });

  test('ingredienti e passaggi vuoti nel file: tolti al salvataggio come nell\'editor', () async {
    final s = statoFinto();
    final r = _r('a', 'Torta')
      ..ingredients = [Ingredient(), Ingredient(name: 'farina', amount: '1 kg'), Ingredient(name: '  ', amount: ' ')]
      ..steps = [RecipeStep(text: '  '), RecipeStep(text: 'impasta')];
    await s.restoreBackup(_dati([r]));
    expect(s.recipeById('a')!.ingredients.map((i) => i.name), ['farina']);
    expect(s.recipeById('a')!.steps.map((x) => x.text), ['impasta']);
  });
}
