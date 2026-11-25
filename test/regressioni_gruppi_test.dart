// Regressioni: bug trovati dal tester cattivo nella 1.9.0/1.10.0 e corretti nella 1.10.1.
// Lancio:  flutter test tool/tests/bug_gruppi_test.dart
import 'package:familyrecipes/l10n.dart';
import 'package:familyrecipes/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => L10n.load('it'));

  test('BUG [MEDIO] T-HACK-05 un admin del gruppo scrive un campo del tipo sbagliato: FamilyGroup.fromDoc lancia e '
      'TUTTI i membri smettono di vedere gli aggiornamenti di TUTTI i loro gruppi', () {
    // Le regole (firestore.rules:63-69, ramo dell'admin del gruppo) non controllano il tipo di name, memberEmails,
    // viewers: provato sull'emulatore (tool/tests/rules_test.mjs, «limite»). FamilyGroup.fromDoc (models.dart:283-298)
    // usa «as String?», «as Map?», «as List?»: l'eccezione esce dal listener dei gruppi (sync_service.dart:257-262)
    // prima di onGroups, quindi l'elenco dei gruppi del telefono resta congelato (nuovi gruppi, ruoli, uscite).
    // Con il buco A delle regole chiunque abbia il codice invito può diventare admin e farlo.
    final rotti = <String>[];
    for (final e in <String, Object?>{
      'name': 123,
      'memberEmails': 'tutti',
      'viewers': 'tutti',
      'admins': {'a': true},
      'ownerUid': ['x'],
      'members': 'tutti',
    }.entries) {
      try {
        FamilyGroup.fromDoc('ABCDEFGH23', {'name': 'Famiglia', 'members': ['a'], e.key: e.value});
      } catch (err) {
        rotti.add('${e.key}: ${e.value} → ${err.runtimeType}');
      }
    }
    expect(rotti, isEmpty, reason: rotti.join('\n'));
  });
}
