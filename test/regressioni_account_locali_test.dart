// Regressioni: bug trovati dal tester cattivo nella 1.9.0/1.10.0 e corretti nella 1.10.1.
// Devono restare verdi: se uno fallisce, il bug è tornato.
// Lancio:  flutter test tool/tests/bug_account_locali_test.dart
import 'dart:io';

import 'package:familyrecipes/l10n.dart';
import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/services/auth_service.dart';
import 'package:familyrecipes/services/backup_service.dart';
import 'package:familyrecipes/services/local_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mfm_aiuti.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final docs = cartellaDocumentiFinta('bug_account_docs');
  setUpAll(() => L10n.load('it'));
  setUp(() {
    for (final f in docs.listSync()) {
      f.deleteSync(recursive: true);
    }
  });

  test('BUG nomi utente diversi finiscono nello stesso file dati (uno vede e sovrascrive le ricette dell\'altro)',
      () async {
    // Session.storageKey (models.dart:372) e BackupService._dir (backup_service.dart:41) sostituiscono con «_»
    // tutto quello che non è [A-Za-z0-9_-]; registerLocal (auth_service.dart:33) accetta qualsiasi nome di
    // almeno 3 caratteri e li considera account diversi.
    final store = LocalStore();
    final auth = AuthService(store);
    final coppie = [
      ['mario.rossi', 'mario_rossi'],
      ['nonna pina', 'nonna_pina'],
      ['张三丰', '李小龙'],
      ['иван', 'олег'],
      ['josé', 'josè'],
    ];
    final rotte = <String>[];
    for (final c in coppie) {
      final a = await auth.registerLocal(c[0], '1234');
      final b = await auth.registerLocal(c[1], '5678'); // l'app li accetta come due account distinti
      await store.writeUserData(a, UserData(recipes: [Recipe(id: 'segreta', title: 'Ricetta segreta di ${c[0]}')]));
      final visto = await store.readUserData(b);
      if (visto.recipes.any((r) => r.id == 'segreta')) rotte.add('${c[0]} → ${c[1]} (${a.storageKey})');
    }
    expect(rotte, isEmpty, reason: 'l\'utente B vede (e sovrascrive) le ricette dell\'utente A:\n${rotte.join('\n')}');
  });

  test('BUG backup: cartella condivisa tra «张三丰» e «李小龙»', () async {
    final dir = await Directory.systemTemp.createTemp('bug_account_backup');
    BackupService.baseOverride = dir;
    addTearDown(() {
      BackupService.baseOverride = null;
      dir.deleteSync(recursive: true);
    });
    final zhang = Session(mode: AccountMode.local, key: '张三丰', displayName: '张三丰');
    final li = Session(mode: AccountMode.local, key: '李小龙', displayName: '李小龙');
    await BackupService.save(zhang.storageKey,
        BackupService.encode(recipes: [Recipe(id: 'a', title: 'Di Zhang')], photos: {}, favorites: {}, reason: 'manual'),
        DateTime(2026));
    expect(await BackupService.list(li.storageKey), isEmpty, reason: 'Li vede (e può ripristinare) il backup di Zhang');
  });

  test('BUG file dati con un tipo inatteso (JSON valido): l\'avvio si blocca sulla schermata iniziale', () async {
    // LocalStore.readUserData (local_store.dart:62-65) protegge solo jsonDecode: UserData.fromJson che lancia
    // (es. «recipes» come mappa, file di una versione futura poi tornata indietro) risale fino ad AppState.init
    // (app_state.dart:139) che non lo intercetta: loading resta true e l'app resta sull'IntroScreen per sempre.
    final s = Session(mode: AccountMode.local, key: 'mario', displayName: 'Mario');
    final store = LocalStore();
    await store.writeSession(s);
    await File('${docs.path}/data_${s.storageKey}.json').writeAsString('{"recipes":{"a":{"title":"Torta"}}}');
    final app = statoFinto()..session = null;
    try {
      await app.init();
    } catch (_) {}
    expect(app.loading, isFalse, reason: 'l\'app non esce mai dalla schermata iniziale');
  });

  test('BUG sessione salvata con «key» non testuale: l\'avvio si blocca', () async {
    await File('${docs.path}/session.json').writeAsString('{"mode":"local","key":123,"displayName":"x"}');
    final app = statoFinto()..session = null;
    try {
      await app.init();
    } catch (_) {}
    expect(app.loading, isFalse);
  });
  test('BUG impostazioni con «lang» non testuale: l\'avvio si blocca', () async {
    // AppState.init (app_state.dart:126) fa «settings?['lang'] as String?» senza protezione.
    await File('${docs.path}/settings.json').writeAsString('{"lang":5}');
    final app = statoFinto()..session = null;
    try {
      await app.init();
    } catch (_) {}
    expect(app.loading, isFalse);
  });
}
