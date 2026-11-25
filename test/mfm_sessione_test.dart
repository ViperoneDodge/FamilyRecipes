// Tester cattivo (adattato da MyFleetManager session_test / t250_senza_account_test / tc_b_dati_test) —
// sessione salvata, account senza registrazione (locali), file locali rovinati (T-DATA-03/08, T-IN-09/10).
import 'dart:io';

import 'package:familyrecipes/l10n.dart';
import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/services/auth_service.dart';
import 'package:familyrecipes/services/local_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mfm_aiuti.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final docs = cartellaDocumentiFinta('mfm_sessione_docs');
  setUpAll(() => L10n.load('it'));

  group('T-DATA-08 sessione salvata', () {
    test('andata e ritorno; sessioni rovinate = nessuna sessione', () {
      final s = Session(mode: AccountMode.cloud, key: 'uid-demo', displayName: 'Demo', email: 'demo@example.com');
      final b = Session.fromJson(s.toJson())!;
      expect([b.mode, b.key, b.displayName, b.email], [AccountMode.cloud, 'uid-demo', 'Demo', 'demo@example.com']);
      expect(Session.fromJson(null), isNull);
      expect(Session.fromJson({}), isNull);
      expect(Session.fromJson({'mode': 'cloud'}), isNull);
      // modo sconosciuto (versione futura) = locale, mai «cloud» per sbaglio
      expect(Session.fromJson({'mode': 'boh', 'key': 'k'})!.mode, AccountMode.local);
      expect(Session.fromJson({'mode': 'CLOUD', 'key': 'k'})!.mode, AccountMode.local);
      expect(Session.fromJson({'key': 'k'})!.displayName, '');
    });

    test('storageKey: niente barre, punti o «..» nel nome del file dati', () {
      for (final k in ['../../etc/passwd', 'a/b', r'a\b', '..', 'nul', 'con', '<>:"|?*', ' ', '🍝']) {
        final sk = Session(mode: AccountMode.local, key: k, displayName: k).storageKey;
        expect(sk, matches(RegExp(r'^local_[A-Za-z0-9_-]*$')), reason: k);
      }
      expect(Session(mode: AccountMode.cloud, key: 'AbC123xyz', displayName: '').storageKey, 'cloud_AbC123xyz');
      // stesso nome, modi diversi: file diversi
      expect(Session(mode: AccountMode.local, key: 'x', displayName: '').storageKey,
          isNot(Session(mode: AccountMode.cloud, key: 'x', displayName: '').storageKey));
    });
  });

  group('T-IN-09/10 account senza registrazione (sul telefono)', () {
    late AuthService auth;
    setUp(() async {
      for (final f in docs.listSync()) {
        f.deleteSync(recursive: true);
      }
      auth = AuthService(LocalStore());
    });

    test('nome troppo corto, password troppo corta, nome già usato (anche con maiuscole e spazi)', () async {
      await expectLater(auth.registerLocal('ab', '1234'), throwsA(isA<AuthException>()));
      await expectLater(auth.registerLocal('   ab   ', '1234'), throwsA(isA<AuthException>()));
      await expectLater(auth.registerLocal('mario', '123'), throwsA(isA<AuthException>()));
      await auth.registerLocal('Mario', '1234');
      await expectLater(auth.registerLocal('mario', '9999'), throwsA(isA<AuthException>()));
      await expectLater(auth.registerLocal('  MARIO  ', '9999'), throwsA(isA<AuthException>()));
    });

    test('accesso: maiuscole e spazi nel nome sì, password sbagliata no, utente inesistente no', () async {
      await auth.registerLocal('Nonna Pina', 'pässwörd 🍝');
      final s = await auth.loginLocal('  nonna pina ', 'pässwörd 🍝');
      expect(s.key, 'nonna pina');
      expect(s.displayName, 'Nonna Pina');
      expect(s.mode, AccountMode.local);
      await expectLater(auth.loginLocal('nonna pina', 'pässwörd'), throwsA(isA<AuthException>()));
      await expectLater(auth.loginLocal('nonna pina', 'PÄSSWÖRD 🍝'), throwsA(isA<AuthException>()));
      await expectLater(auth.loginLocal('nessuno', 'x'), throwsA(isA<AuthException>()));
    });

    test('password di 1000 caratteri, solo spazi, con a capo: accettate e verificate esattamente', () async {
      final lunga = 'x' * 1000;
      await auth.registerLocal('lungo', lunga);
      expect((await auth.loginLocal('lungo', lunga)).key, 'lungo');
      await expectLater(auth.loginLocal('lungo', '${lunga}x'), throwsA(isA<AuthException>()));
      await auth.registerLocal('spazi', '    ');
      expect((await auth.loginLocal('spazi', '    ')).key, 'spazi');
      await expectLater(auth.loginLocal('spazi', '   '), throwsA(isA<AuthException>()));
    });

    test('la password non è salvata in chiaro', () async {
      await auth.registerLocal('segreto', 'Pa55word!');
      final txt = await File('${docs.path}/accounts.json').readAsString();
      expect(txt, isNot(contains('Pa55word!')));
    });
  });

  group('T-DATA-03 file locali rovinati', () {
    final store = LocalStore();
    final s = Session(mode: AccountMode.local, key: 'mario', displayName: 'Mario');
    final dataFile = File('${docs.path}/data_${s.storageKey}.json');

    test('file dati vuoto, troncato, binario, «null», elenco: si riparte vuoti senza eccezioni', () async {
      for (final contenuto in ['', '   ', '{"recipes":[{"id":"a","title":"Tor', 'null', '[]', '"ciao"', '\u0000\u0000']) {
        await dataFile.writeAsString(contenuto);
        final d = await store.readUserData(s);
        expect(d.recipes, isEmpty, reason: contenuto);
      }
      await dataFile.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0, 0, 1, 2]);
      expect((await store.readUserData(s)).recipes, isEmpty);
    });

    test('scrittura e rilettura: nessun file .tmp lasciato in giro', () async {
      await store.writeUserData(s, UserData(recipes: [Recipe(id: 'a', title: 'Torta')]));
      expect((await store.readUserData(s)).recipes.single.title, 'Torta');
      expect(File('${dataFile.path}.tmp').existsSync(), isFalse);
    });

    test('impostazioni e sessione rovinate: null, nessuna eccezione', () async {
      await File('${docs.path}/settings.json').writeAsString('{"lang":');
      expect(await store.readSettings(), isNull);
      await File('${docs.path}/session.json').writeAsString('[1,2,3]');
      expect(await store.readSession(), isNull);
      await store.writeSession(null);
      expect(File('${docs.path}/session.json').existsSync(), isFalse);
      await store.writeSession(null); // due volte di fila: nessun errore
    });

    test('avvio con sessione locale e file dati sano (anche vuoto o troncato): l\'app esce dalla schermata iniziale',
        () async {
      final s = Session(mode: AccountMode.local, key: 'mario', displayName: 'Mario');
      await store.writeSession(s);
      for (final contenuto in ['{"recipes":[{"id":"a","title":"Torta"}]}', '', '{"recipes":[{"id":"a"']) {
        await dataFile.writeAsString(contenuto);
        final app = statoFinto()..session = null;
        await app.init();
        expect(app.loading, isFalse, reason: contenuto);
        expect(app.session?.key, 'mario');
      }
      await store.writeSession(null);
    });

    test('UserData: campi mancanti o null (file vecchi)', () {
      final d = UserData.fromJson({'recipes': null, 'groups': null, 'uploaded': null});
      expect(d.recipes, isEmpty);
      expect(d.groups, isEmpty);
      expect(d.personalBookId, isNull);
      final r = Recipe.fromJson({'id': 'x'});
      expect([r.title, r.prepMinutes, r.ingredients.length, r.deleted], ['', 0, 0, false]);
      expect(r.displayTitle, tr('recipe.untitled'));
    });
  });
}
