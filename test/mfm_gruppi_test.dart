// Tester cattivo (adattato da MyFleetManager group_qr_test «codice letto dal QR», tc_d_gruppi_test,
// t24_b_gruppi_ui_test) — codici invito e QR, documenti dei gruppi strani, ruoli, avvisi di gruppo
// (T-GRP-01/06, T-RULES-04/05, T-HACK-08).
import 'package:familyrecipes/l10n.dart';
import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/services/group_watch.dart';
import 'package:familyrecipes/widgets/group_qr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => L10n.load('it'));

  group('T-GRP-01 codice letto dal QR', () {
    test('QR dell\'app, codice scritto a mano, minuscole, spazi', () {
      expect(codeFromQr(groupQrData('AB23CD45EF')), 'AB23CD45EF');
      expect(groupQrData('AB23CD45EF'), startsWith('https://'));
      expect(codeFromQr(' ab23cd45ef '), 'AB23CD45EF');
      expect(codeFromQr('ab 23 cd 45 ef'), 'AB23CD45EF');
      expect(codeFromQr('AB23CD45EF\n'), 'AB23CD45EF');
      expect(codeFromQr('familyrecipes:join:AB23CD45EF'), 'AB23CD45EF');
      expect(codeFromQr('FAMILYRECIPES:JOIN:ab23cd45ef'), 'AB23CD45EF');
      expect(codeFromQr('https://viperonedodge.github.io/FamilyRecipes/join.html?code=AB23CD45EF'), 'AB23CD45EF');
      // Dalla 1.11.3 le pagine pubbliche sono su Firebase Hosting (repository privato).
      expect(codeFromQr('https://familyrecipes-46e1a.web.app/join.html?code=AB23CD45EF'), 'AB23CD45EF');
      expect(codeFromQr('https://familyrecipes-46e1a.firebaseapp.com/join.html?code=AB23CD45EF'), 'AB23CD45EF');
      expect(codeFromQr('https://altrosito.github.io/join.html?code=AB23CD45EF'), isNull);
    });

    test('QR di altri siti, di altre app, vuoti o assurdi: nessun codice', () {
      for (final s in [
        null,
        '',
        '   ',
        'https://example.com/qualcosa',
        'https://example.com/join.html?code=AB23CD45EF',
        'https://viperonedodge.github.io/FamilyRecipes/altro.html?code=AB23CD45EF',
        'https://viperonedodge.github.io/FamilyRecipes/join.html',
        'https://viperonedodge.github.io/FamilyRecipes/join.html?code=',
        'myfleetmanager:join:AB23CD45EF',
        'javascript:alert(1)',
        'familyrecipes:join:../../books',
        'familyrecipes:join:AB/CD/EF/GH',
        'AB23', // troppo corto
        'A' * 33, // troppo lungo
        '🍝🍝🍝🍝🍝🍝',
        'ÀÈÌÒÙÀÈÌÒÙ',
        'WIFI:S:casa;T:WPA;P:segreta;;',
      ]) {
        expect(codeFromQr(s), isNull, reason: '$s');
      }
    });

    test('link con il codice due volte o con parametri in più: un solo codice valido o niente', () {
      final c = codeFromQr('https://viperonedodge.github.io/FamilyRecipes/join.html?code=AB23CD45EF&code=ZZ99ZZ99ZZ');
      expect(c, anyOf('AB23CD45EF', 'ZZ99ZZ99ZZ'));
      expect(codeFromQr('https://viperonedodge.github.io/FamilyRecipes/join.html?utm_source=x&code=ab23cd45ef'),
          'AB23CD45EF');
    });
  });

  group('documenti dei gruppi (books/{id}) letti da Firestore', () {
    test('campi mancanti: nome predefinito, nessun membro, nessun ruolo', () {
      final g = FamilyGroup.fromDoc('G', {});
      expect(g.name, tr('family.defaultName'));
      expect(g.members, isEmpty);
      expect(g.ownerUid, '');
      expect(g.roleOf('chiunque'), GroupRole.editor, reason: 'nessuno è admin o sola lettura se mancano i campi');
    });

    test('membro senza email, email non testuale, membri doppi', () {
      final g = FamilyGroup.fromDoc('G', {
        'name': 'Famiglia',
        'members': ['a', 'b', 'a', 7],
        'memberEmails': {'a': 'a@example.com', 'b': 42},
      });
      expect(g.members, {'a': 'a@example.com', 'b': '42', '7': '7'});
    });

    test('JSON locale andata e ritorno; gruppo senza id = errore chiaro, non un gruppo fantasma', () {
      final g = FamilyGroup(id: 'G', name: '{name} 🍝', ownerUid: 'O', members: {'O': 'o@x.it'}, admins: {'A'}, viewers: {'V'});
      final b = FamilyGroup.fromJson(g.toJson());
      expect([b.id, b.name, b.ownerUid, b.members, b.admins, b.viewers], [g.id, g.name, 'O', g.members, {'A'}, {'V'}]);
      expect(() => FamilyGroup.fromJson({'name': 'x'}), throwsA(isA<TypeError>()));
    });

    test('ruoli: il proprietario è sempre admin, anche se compare tra i «sola lettura»', () {
      final g = FamilyGroup(id: 'G', name: 'F', ownerUid: 'O', admins: {'A'}, viewers: {'O', 'A', 'V'});
      expect(g.roleOf('O'), GroupRole.admin);
      expect(g.roleOf('A'), GroupRole.admin);
      expect(g.roleOf('V'), GroupRole.viewer);
      expect(g.roleOf(''), GroupRole.editor);
      expect(g.roleOf(null), GroupRole.viewer);
    });
  });

  group('T-GRP-06 avvisi «un altro membro ha modificato»', () {
    Recipe r(String id, int at, {String by = 'MARIA', String name = 'Maria', bool deleted = false}) =>
        Recipe(id: id, title: 'R$id', updatedAt: at, updatedByUid: by, updatedBy: name, deleted: deleted);

    test('le proprie modifiche non avvisano, nemmeno da un altro telefono; nulla prima di «since»', () {
      final a = findActivities(
        groupName: 'F',
        me: 'ME',
        myName: 'Io',
        since: 100,
        remote: [r('1', 150, by: 'ME', name: 'Io'), r('2', 100), r('3', 50)],
        existed: (_) => false,
      );
      expect(a, isEmpty);
    });

    test('ricette vecchie senza uid dell\'autore: si confronta il nome', () {
      final a = findActivities(
        groupName: 'F',
        me: 'ME',
        myName: 'Io',
        since: 0,
        remote: [r('1', 10, by: '', name: 'Io'), r('2', 10, by: '', name: 'Maria')],
        existed: (_) => false,
      );
      expect(a.single.recipe, 'R2');
    });

    test('autore senza nome: «Un membro del gruppo»; ricetta senza titolo: «Senza titolo»', () {
      final a = findActivities(
        groupName: 'F',
        me: 'ME',
        myName: 'Io',
        since: 0,
        remote: [Recipe(id: 'x', title: '  ', updatedAt: 5, updatedByUid: 'Z', updatedBy: '')],
        existed: (_) => false,
      );
      expect(a.single.text, contains(tr('groupAct.someone')));
      expect(a.single.text, contains(tr('recipe.untitled')));
    });

    test('1000 ricette cambiate: nessun problema di tempi', () {
      final a = findActivities(
        groupName: 'F',
        me: 'ME',
        myName: 'Io',
        since: 0,
        remote: [for (var i = 0; i < 1000; i++) r('$i', i + 1)],
        existed: (id) => id.hashCode.isEven,
      );
      expect(a.length, 1000);
    });
  });
}
