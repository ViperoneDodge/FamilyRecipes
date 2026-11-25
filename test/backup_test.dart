import 'dart:io';
import 'dart:typed_data';

import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/services/backup_service.dart';
import 'package:familyrecipes/services/recipe_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Recipe recipe(String title, {String? book, String? cover}) => Recipe(title: title, bookId: book, coverPhoto: cover)
    ..ingredients = [Ingredient(name: 'farina', amount: '200 g')]
    ..steps = [
      RecipeStep(text: 'impasta', photos: ['P2'])
    ];

  test('backup: ricette, foto e preferiti andata e ritorno', () {
    final a = recipe('Torta', cover: 'P1');
    final b = recipe('Sugo', book: 'GRUPPO1234');
    final del = recipe('Vecchia')..deleted = true;
    final bytes = BackupService.encode(
      recipes: [a, b, del],
      photos: {
        'P1': Uint8List.fromList([1, 2, 3]),
        'P2': Uint8List.fromList([4, 5])
      },
      favorites: {a.id},
      reason: 'manual',
      at: DateTime(2026, 11, 25, 10, 30),
    );
    final d = BackupService.decode(bytes)!;
    expect(d.recipes.map((r) => r.title), ['Torta', 'Sugo']);
    expect(d.recipes[0].id, a.id);
    expect(d.recipes[1].bookId, 'GRUPPO1234');
    expect(d.recipes[0].steps.single.photos, ['P2']);
    expect(d.photos['P1'], [1, 2, 3]);
    expect(d.favorites, {a.id});
    expect(d.reason, 'manual');
    expect(d.at, DateTime(2026, 11, 25, 10, 30));
  });

  test('backup: file non validi', () {
    expect(BackupService.decode(Uint8List(0)), isNull);
    expect(BackupService.decode(Uint8List.fromList('{"app":"MyFleetManager","recipes":[]}'.codeUnits)), isNull);
    // Un file di esportazione (da condividere) non è un backup.
    final export = RecipeImport.encode([recipe('Torta')], {});
    final bytes = Uint8List.fromList(export.codeUnits);
    expect(BackupService.decode(bytes), isNull);
    expect(BackupService.diagnose(bytes), contains('export'));
  });

  test('backup: sul telefono restano gli ultimi 3, più quello protetto', () async {
    final tmp = await Directory.systemTemp.createTemp('fr_backup');
    BackupService.baseOverride = tmp;
    addTearDown(() => tmp.delete(recursive: true));
    Future<File> save(int day, {File? protect}) {
      final at = DateTime(2026, 11, day);
      return BackupService.save('uid',
          BackupService.encode(recipes: [recipe('R$day')], photos: {}, favorites: {}, reason: 'manual', at: at), at,
          protect: protect);
    }

    final first = await save(1);
    await save(2);
    await save(3);
    await save(4);
    var list = await BackupService.list('uid');
    expect(list.map((b) => b.at.day), [4, 3, 2]);
    expect(list.first.recipes, 1);
    expect(await first.exists(), isFalse);

    final two = list.last.file;
    await save(5, protect: two);
    list = await BackupService.list('uid');
    expect(list.map((b) => b.at.day), [5, 4, 2]);
  });
}
