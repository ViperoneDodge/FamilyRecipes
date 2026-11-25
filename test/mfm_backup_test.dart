// Tester cattivo (adattato da MyFleetManager backup_test / t243_a_backup_test) — BackupService:
// file rovinati, strani, enormi, di versioni future, orologio spostato, cartelle di utenti diversi
// (T-DATA-01/02/03/05, T-DATE-08/09, T-IN-01/02).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/services/backup_service.dart';
import 'package:familyrecipes/services/recipe_import.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mfm_aiuti.dart';

Recipe _r(String id, String titolo, {String? book}) => Recipe(id: id, title: titolo, bookId: book)
  ..ingredients = [Ingredient(name: 'farina', amount: '200 g')]
  ..steps = [RecipeStep(text: 'impasta')];

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mfm_backup');
    BackupService.baseOverride = dir;
  });
  tearDown(() async {
    BackupService.baseOverride = null;
    await dir.delete(recursive: true);
  });

  group('T-DATA-03 file stupidi', () {
    test('mai eccezioni, sempre null (e una spiegazione per l\'utente)', () {
      final casi = <List<int>>[
        [],
        [0],
        List.filled(1000, 0),
        [0xFF, 0xFE, 0x00, 0x7B],
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], // un PNG
        utf8.encode('%PDF-1.7\n'),
        utf8.encode('{"app":"FamilyRecipes","kind":"backup","recipes":'),
        utf8.encode('{"app":"FamilyRecipes","kind":"backup","recipes":{}}'),
        utf8.encode('{"app":"FamilyRecipes","kind":"backup","recipes":"tutte"}'),
        utf8.encode('{"app":"FamilyRecipes","kind":"backup"}'),
        utf8.encode('{"app":"familyrecipes","kind":"backup","recipes":[]}'),
        utf8.encode('{"app":"MyFleetManager","kind":"backup","vehicles":[]}'),
        utf8.encode('null'),
        utf8.encode('"FamilyRecipes"'),
        utf8.encode('[{"app":"FamilyRecipes","kind":"backup","recipes":[]}]'),
        utf8.encode('{"app":"FamilyRecipes","kind":"backup","recipes":[]}' * 2),
        utf8.encode('{"app":"FamilyRecipes","kind":"backup","recipes":[1,"a",null,true,[]]}'),
      ];
      for (final c in casi) {
        final b = Uint8List.fromList(c);
        expect(() => BackupService.decode(b), returnsNormally, reason: '$c');
        expect(() => BackupService.diagnose(b), returnsNormally, reason: '$c');
        expect(BackupService.diagnose(b), isNotEmpty);
      }
      for (final c in casi.take(16)) {
        expect(BackupService.decode(Uint8List.fromList(c)), isNull, reason: utf8.decode(c, allowMalformed: true));
      }
      // Elenco con elementi che non sono ricette: file valido, nessuna ricetta.
      expect(BackupService.decode(Uint8List.fromList(casi.last))!.recipes, isEmpty);
    });

    test('diagnosi: file vuoto, troppo grande, altra app, esportazione, JSON rotto', () {
      expect(BackupService.diagnose(Uint8List(0)), '0 MB');
      expect(BackupService.diagnose(byte('{"app":"Altro"}')), contains('app'));
      expect(BackupService.diagnose(byte('[1]')), contains('type'));
      expect(BackupService.diagnose(byte('{"app":"FamilyRecipes"')), contains('json@'));
      final export = RecipeImport.encode([_r('a', 'Torta')], {});
      expect(BackupService.diagnose(byte(export)), contains('export'));
    });

    test('BOM UTF-8 (file riaperto e salvato col Blocco note) e zeri/spazi in coda: accettato', () {
      final buono = BackupService.encode(recipes: [_r('a', 'Torta')], photos: {}, favorites: {}, reason: 'manual');
      expect(BackupService.decode(Uint8List.fromList([0xEF, 0xBB, 0xBF, ...buono])), isNotNull);
      expect(BackupService.decode(Uint8List.fromList([...buono, 0, 0, 0, 10, 32, 13, 10])), isNotNull);
      expect(BackupService.decode(Uint8List.fromList([...buono, ...utf8.encode('\n\n   \t')])), isNotNull);
    });

    test('versione futura: chiavi sconosciute e v=99 non impediscono la lettura', () {
      final d = BackupService.decode(backupAMano([
        {'id': 'f1', 'title': 'Futura', 'campoNuovo2030': {'a': 1}, 'servings': 6},
      ], extra: {'v': 99, 'altro': 'boh', 'at': 'ieri'}));
      expect(d, isNotNull);
      expect(d!.recipes.single.title, 'Futura');
      expect(d.recipes.single.servings, 6);
      expect(d.at, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('foto rovinate o con tipi sbagliati: si saltano, le altre restano', () {
      final d = BackupService.decode(backupAMano([
        {'id': 'a', 'title': 'Torta', 'cover': 'P1'},
      ], extra: {
        'photos': {'P1': base64Encode([1, 2, 3]), 'P2': 'non è base64 !!!', 'P3': 123, 'P4': null},
        'favorites': ['a', 5, null, 'b'],
      }))!;
      expect(d.photos.keys, ['P1']);
      expect(d.photos['P1'], [1, 2, 3]);
      expect(d.favorites, {'a', 'b'});
    });

    test('ricette eliminate (lapidi) non entrano nel backup e non escono dal file', () {
      final del = _r('x', 'Vecchia')..deleted = true;
      final b = BackupService.encode(recipes: [_r('a', 'Torta'), del], photos: {}, favorites: {}, reason: 'manual');
      expect(BackupService.decode(b)!.recipes.map((r) => r.id), ['a']);
      final aMano = BackupService.decode(backupAMano([
        {'id': 'x', 'title': 'Lapide', 'deleted': true},
        {'id': '', 'title': 'Id vuoto'},
      ]))!;
      // La lapide resta fuori; la ricetta senza id entra con un id stabile (uguale a ogni lettura).
      expect(aMano.recipes.map((r) => r.title), ['Id vuoto']);
      expect(aMano.recipes.single.id, startsWith('r'));
    });
  });

  group('T-IN-01/02 testi assurdi nelle ricette', () {
    test('emoji, RTL, zalgo, \\u0000, 100.000 caratteri: andata e ritorno identici', () {
      final strani = [
        '🍝🔥👨‍👩‍👧‍👦🇮🇹',
        'كعكة الشوكولاتة',
        'עוגת שוקולד',
        't̷̢͎o̵r̸t̷a̴',
        'a\u0000b',
        '​',
        'x' * 100000,
        '{name} {n} \${x} %s',
        '<script>alert(1)</script>',
        "'; DROP TABLE recipes; --",
        '../../etc/passwd',
      ];
      final rs = [for (var i = 0; i < strani.length; i++) _r('id$i', strani[i])..intro = strani[i]];
      final d = BackupService.decode(BackupService.encode(recipes: rs, photos: {}, favorites: {}, reason: 'manual'))!;
      expect(d.recipes.map((r) => r.title).toList(), strani);
      expect(d.recipes.map((r) => r.intro).toList(), strani);
    });

    test('BackupService.encode → decode conserva l\'intera ricetta (tutti i campi)', () {
      final r = Recipe(
        id: 'ID1',
        category: RecipeCategory.menu,
        title: 'Pranzo',
        intro: 'intro',
        coverPhoto: 'C',
        difficulty: Difficulty.hard,
        cost: Cost.high,
        prepMinutes: 5,
        cookMinutes: 7,
        servings: 12,
        ingredients: [Ingredient(name: 'a', amount: '1')],
        steps: [RecipeStep(id: 'S1', text: 't', photos: ['P'])],
        tips: 'tips',
        courses: ['X', 'Y'],
        updatedAt: 99,
        updatedBy: 'u',
        updatedByUid: 'uu',
        createdBy: 'c',
        createdByName: 'cn',
        createdAt: 11,
        bookId: 'GRUPPO1234',
      );
      final d = BackupService.decode(BackupService.encode(recipes: [r], photos: {}, favorites: {}, reason: 'x'))!;
      expect(d.recipes.single.toJson(), r.toJson());
    });
  });

  group('T-DATA-05 volumi', () {
    test('2000 ricette con 20 ingredienti e 10 passaggi: encode + decode in tempi ragionevoli', () {
      final rs = [
        for (var i = 0; i < 2000; i++)
          Recipe(id: 'r$i', title: 'Ricetta $i', ingredients: [
            for (var k = 0; k < 20; k++) Ingredient(name: 'ingrediente $k', amount: '${k * 10} g')
          ], steps: [
            for (var k = 0; k < 10; k++) RecipeStep(text: 'Passaggio $k ' * 10)
          ])
      ];
      final sw = Stopwatch()..start();
      final bytes = BackupService.encode(recipes: rs, photos: {}, favorites: {}, reason: 'manual');
      final d = BackupService.decode(bytes)!;
      sw.stop();
      expect(d.recipes.length, 2000);
      expect(sw.elapsedMilliseconds, lessThan(15000));
    });

    test('backup oltre il limite: save rifiuta, nessun file mezzo scritto', () async {
      final troppo = Uint8List(BackupService.maxBytes + 1);
      await expectLater(BackupService.save('u', troppo, DateTime(2026)), throwsA(isA<FileSystemException>()));
      expect(await BackupService.list('u'), isEmpty);
      expect(BackupService.decode(troppo), isNull);
      expect(BackupService.diagnose(troppo), contains('> 200 MB'));
    });
  });

  group('T-DATE-08/09 orologio spostato, fusi, nomi dei file', () {
    Future<File> salva(String user, DateTime at, {File? protect, String titolo = 'R'}) => BackupService.save(
        user,
        BackupService.encode(recipes: [_r('a', titolo)], photos: {}, favorites: {}, reason: 'manual', at: at),
        at,
        protect: protect);

    test('dopo 3 backup fatti con l\'orologio avanti, il backup nuovo (di adesso) resta', () async {
      final domani = DateTime.now().add(const Duration(days: 1));
      for (var i = 0; i < 3; i++) {
        await salva('u', domani.add(Duration(minutes: i)));
      }
      final nuovo = await salva('u', DateTime.now(), titolo: 'adesso');
      expect(await nuovo.exists(), isTrue);
      expect((await BackupService.list('u')).length, 3);
    });

    test('due backup nello stesso secondo: due file distinti, nessuno sovrascritto', () async {
      final at = DateTime(2026, 11, 25, 10, 0, 0);
      final a = await salva('u', at, titolo: 'primo');
      final b = await salva('u', at, titolo: 'secondo');
      expect(a.path, isNot(b.path));
      expect(BackupService.decode(await a.readAsBytes())!.recipes.single.title, 'primo');
      expect(BackupService.decode(await b.readAsBytes())!.recipes.single.title, 'secondo');
    });

    test('nomi dei file: ordine lessicale = ordine cronologico nello stesso fuso', () {
      expect(BackupService.fileName(DateTime(2026, 9, 30, 23, 59, 59))
          .compareTo(BackupService.fileName(DateTime(2026, 10, 1))), lessThan(0));
      expect(BackupService.fileName(DateTime(2026, 1, 2, 3, 4, 5)), 'FamilyRecipes_backup_2026-01-02_030405.json');
    });

    test('la data del backup si rilegge identica (salvata in UTC, mostrata in ora locale)', () {
      final at = DateTime(2026, 3, 29, 2, 30); // notte del cambio d'ora
      final d = BackupService.decode(
          BackupService.encode(recipes: [], photos: {}, favorites: {}, reason: 'manual', at: at))!;
      expect(d.at, at);
    });

    test('file estranei nella cartella dei backup: non compaiono nell\'elenco', () async {
      await salva('u', DateTime(2026, 1, 1));
      final d = Directory('${dir.path}/backups/u');
      await File('${d.path}/rotto.json').writeAsString('{"app":"FamilyRecipes"');
      await File('${d.path}/foto.jpg').writeAsBytes([1, 2, 3]);
      await Directory('${d.path}/sottocartella.json').create();
      final l = await BackupService.list('u');
      expect(l.length, 1);
    });
  });

  group('cartelle di utenti diversi', () {
    test('utente vuoto, con barre, punti e «..»: la cartella resta dentro backups/', () async {
      for (final u in ['', '../..', '../../etc', 'a/b', r'a\b', '.', '..']) {
        final f = await BackupService.save(
            u, BackupService.encode(recipes: [], photos: {}, favorites: {}, reason: 'manual'), DateTime(2026));
        expect(File(f.path).absolute.path, startsWith('${dir.path}/backups/'), reason: u);
        expect(f.parent.parent.path, '${dir.path}/backups', reason: u);
      }
    });

    test('il backup di un utente non compare a un altro (caratteri ASCII)', () async {
      await BackupService.save('local_mario',
          BackupService.encode(recipes: [_r('a', 'Torta')], photos: {}, favorites: {}, reason: 'manual'), DateTime(2026));
      expect(await BackupService.list('local_luigi'), isEmpty);
      expect(await BackupService.list('cloud_UIDXYZ'), isEmpty);
    });
  });
}
