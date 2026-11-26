import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mfm_aiuti.dart';

void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('fr_zip');
    BackupService.baseOverride = tmp;
  });
  tearDown(() async {
    BackupService.baseOverride = null;
    await tmp.delete(recursive: true);
  });

  Recipe r(String id, {String? cover, List<String> step = const []}) =>
      Recipe(id: id, title: 'Ricetta $id', coverPhoto: cover)..steps = [RecipeStep(text: 'x', photos: step)];

  test('backup .zip: ricette, preferiti e foto (lette una alla volta) andata e ritorno', () async {
    final fotos = {for (var i = 0; i < 30; i++) 'P$i': Uint8List.fromList(List.filled(2000 + i, i))};
    final recipes = [
      for (var i = 0; i < 10; i++) r('r$i', cover: 'P${i * 3}', step: ['P${i * 3 + 1}', 'P${i * 3 + 2}']),
      r('del')..deleted = true,
    ];
    var asked = 0;
    final f = await BackupService.saveZip('u',
        recipes: recipes,
        favorites: {'r1'},
        reason: 'manual',
        at: DateTime(2026, 11, 26, 9),
        photo: (rec, p) async {
          asked++;
          return fotos[p];
        });
    expect(f.path, endsWith('.zip'));
    expect(asked, 30);
    final list = await BackupService.list('u');
    expect(list.single.recipes, 10);
    final d = (await BackupService.readFile(f.path)).data!;
    expect(d.recipes.length, 10);
    expect(d.favorites, {'r1'});
    expect(d.photos, isEmpty, reason: 'le foto restano nel file');
    expect(await d.photo('P7'), fotos['P7']);
    expect(await d.photo('../fuori'), isNull);
    expect(await d.photo('NONCE'), isNull);
    // Lo stesso file scelto «senza percorso» (byte in memoria).
    final m = (await BackupService.readBytes(await f.readAsBytes())).data!;
    expect(m.photos['P29'], fotos['P29']);
  });

  test('backup .zip: sul telefono restano gli ultimi 3 anche mescolati ai vecchi .json', () async {
    await BackupService.save(
        'u', BackupService.encode(recipes: [r('a')], photos: {}, favorites: {}, reason: 'manual', at: DateTime(2026, 1, 1)), DateTime(2026, 1, 1));
    for (var d = 2; d <= 4; d++) {
      await BackupService.saveZip('u',
          recipes: [r('a')], favorites: {}, reason: 'manual', at: DateTime(2026, 1, d), photo: (_, __) async => null);
    }
    final list = await BackupService.list('u');
    expect(list.map((b) => b.at.day), [4, 3, 2]);
    expect(list.every((b) => b.name.endsWith('.zip')), isTrue);
  });

  test('i backup .json delle versioni precedenti si leggono ancora', () async {
    final f = File('${tmp.path}/vecchio.json')
      ..writeAsBytesSync(BackupService.encode(
          recipes: [r('a', cover: 'P1')], photos: {'P1': Uint8List.fromList([1, 2])}, favorites: {}, reason: 'manual'));
    final d = (await BackupService.readFile(f.path)).data!;
    expect(await d.photo('P1'), [1, 2]);
  });

  test('zip senza backup.json o rovinato: file non valido, nessuna eccezione', () async {
    final f = File('${tmp.path}/rotto.zip')..writeAsBytesSync([0x50, 0x4B, 3, 4, ...utf8.encode('spazzatura')]);
    final res = await BackupService.readFile(f.path);
    expect(res.data, isNull);
    expect(byte('x'), isNotEmpty);
  });
}
