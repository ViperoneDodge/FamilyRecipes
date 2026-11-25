// BUG trovati dal tester cattivo su backup e ripristino (1.9.0). Questi test FALLISCONO finché il
// problema c'è: per questo stanno in tool/tests e non in test/ (la CI resterebbe rossa).
// Lancio:  flutter test tool/tests/bug_ripristino_test.dart
import 'dart:io';

import 'package:familyrecipes/l10n.dart';
import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/mfm_aiuti.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  cartellaDocumentiFinta('bug_ripristino_docs');
  late Directory dir;

  setUpAll(() => L10n.load('it'));
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bug_ripristino');
    BackupService.baseOverride = dir;
  });
  tearDown(() async {
    BackupService.baseOverride = null;
    await dir.delete(recursive: true);
  });

  test('BUG backup di un altro account (o dell\'account senza registrazione): le ricette ripristinate '
      'non compaiono in «Le mie» né altrove', () async {
    // Backup fatto con l'account locale «mario» (createdBy = 'mario'), poi ripristinato dopo essere passati
    // a un account online (o un backup condiviso da un parente). restoreBackup (app_state.dart:675) mette la
    // ricetta nel ricettario personale (bookId = null) ma lascia createdBy dell'altro account: isMine
    // (app_state.dart:64-68) la esclude da «Le mie», e non appartiene a nessun gruppo. Il messaggio dice
    // «1 ricetta ripristinata» ma l'utente non la trova da nessuna parte.
    // (personalBookId null: così saveRecipe non prova a scrivere su Firestore.)
    final s = statoFinto(key: 'uidOnline', mode: AccountMode.cloud);
    final b = BackupService.decode(BackupService.encode(
      recipes: [Recipe(id: 'a', title: 'Torta della nonna', createdBy: 'mario', createdByName: 'Mario', createdAt: 5)],
      photos: {},
      favorites: {},
      reason: 'manual',
    ))!;
    expect(await s.restoreBackup(b), 1);
    expect(s.isPersonal(s.recipeById('a')!), isTrue);
    expect(s.myRecipes.map((r) => r.id), contains('a'), reason: 'ricetta ripristinata ma invisibile in «Le mie»');
  });

  test('BUG ricetta senza id nel file: ogni lettura inventa un id nuovo, ripristinare due volte = doppione',
      () async {
    // Recipe.fromJson (models.dart:180) usa newId() quando manca «id»; BackupService.decode non lo scarta.
    final bytes = backupAMano([
      {'title': 'Senza id', 'ingredients': [{'name': 'farina', 'amount': '1 kg'}]},
    ]);
    final s = statoFinto();
    await s.restoreBackup(BackupService.decode(bytes)!);
    await s.restoreBackup(BackupService.decode(bytes)!);
    expect(s.recipes.where((r) => r.title == 'Senza id').length, 1,
        reason: 'ripristinando due volte lo stesso file la stessa ricetta compare due volte');
  });

  test('BUG ricetta spostata in un gruppo dopo il backup: il ripristino crea un doppione', () async {
    // Spostando una ricetta tra Le mie e un gruppo (online) saveRecipe (app_state.dart:296-308) lascia una
    // lapide con il vecchio id e crea una copia con id NUOVO nel gruppo. Il backup ha il vecchio id:
    // restoreBackup trova la lapide (old.deleted), non la copia, e resuscita la ricetta tra le mie.
    // Stato ricostruito come lo lascia saveRecipe dopo lo spostamento.
    final g = FamilyGroup(id: 'GRUPPO1234', name: 'Famiglia', ownerUid: 'mario', members: {'mario': 'm'});
    final tomba = Recipe(id: 'X', title: 'Lasagne', createdBy: 'mario', createdAt: 5)..deleted = true;
    final spostata = Recipe(id: 'Y', title: 'Lasagne', bookId: 'GRUPPO1234', createdBy: 'mario', createdAt: 5);
    final s = statoFinto(ricette: [tomba, spostata], gruppi: [g]);
    await s.restoreBackup(BackupService.decode(BackupService.encode(
        recipes: [Recipe(id: 'X', title: 'Lasagne', createdBy: 'mario', createdAt: 5)],
        photos: {},
        favorites: {},
        reason: 'manual'))!);
    final lasagne = s.recipes.where((r) => r.title == 'Lasagne').map((r) => '${r.id}@${r.bookId ?? 'mie'}');
    expect(lasagne.length, 1, reason: 'stessa ricetta due volte: $lasagne');
  });

  group('BUG una sola ricetta (o un solo campo) con un tipo inatteso rende illeggibile TUTTO il backup', () {
    // BackupService.decode (backup_service.dart:76-99) mette tutto in un unico try: un TypeError su un campo
    // (Recipe.fromJson usa «as String?» / «as bool?») fa tornare null per l'intero file. L'elenco dei backup
    // invece lo mostra come valido (_read legge solo l'intestazione), quindi l'utente vede «12 ricette», tocca
    // Ripristina e ottiene «File di backup non valido (… MB, recipes)».
    test('campo «reason» numerico (file modificato a mano / versione futura)', () {
      final d = BackupService.decode(backupAMano([
        {'id': 'a', 'title': 'Torta'},
      ], extra: {'reason': 42}));
      expect(d, isNotNull);
    });

    test('una ricetta rovinata su tre: le altre due si devono poter ripristinare', () {
      final d = BackupService.decode(backupAMano([
        {'id': 'a', 'title': 'Buona 1'},
        {'id': 'b', 'title': 123, 'deleted': 'no', 'servings': '4'},
        {'id': 'c', 'title': 'Buona 2'},
      ]));
      expect(d?.recipes.map((r) => r.id), containsAll(['a', 'c']));
    });
  });
  test('BUG [LIEVE] id di foto con «../» nel file di backup: la foto viene scritta FUORI dalla cartella foto/', () async {
    // PhotoStore.file (photo_store.dart:22) costruisce «foto/$id.jpg» senza ripulire l'id; restoreBackup
    // (app_state.dart:687-690) usa gli id del file così come sono. Un backup preparato ad arte (o una ricetta di
    // un gruppo con cover "../../qualcosa") scrive file .jpg dove vuole dentro (e sopra) i documenti dell'app.
    final docs = Directory((await statoFinto().photos.file('X')).parent.parent.path);
    final b = BackupService.decode(backupAMano([
      {'id': 'a', 'title': 'Torta', 'cover': '../fuori'}
    ], extra: {
      'photos': {'../fuori': 'QUJD'}
    }))!;
    final s = statoFinto();
    await s.restoreBackup(b);
    expect(File('${docs.path}/fuori.jpg').existsSync(), isFalse, reason: 'scritto ${docs.path}/fuori.jpg');
  });
}
