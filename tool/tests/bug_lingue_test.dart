// BUG trovati dal tester cattivo su tr() (1.9.0). Il test FALLISCE finché il problema c'è.
// Lancio:  flutter test tool/tests/bug_lingue_test.dart
import 'package:familyrecipes/l10n.dart';
import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/services/group_watch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => L10n.load('it'));

  test('BUG T-IN-07 tr() sostituisce i segnaposto anche DENTRO il testo dell\'utente (più passaggi)', () {
    // l10n.dart:79-80: args.forEach(... s.replaceAll('{$k}', v)) — dopo aver inserito {recipe}, il passaggio
    // successivo sostituisce {category} anche se compariva nel titolo scritto dall'utente.
    // Caso reale: notifica di gruppo (group_watch.dart:100) per una ricetta intitolata «Torta {category}» o con
    // un membro che si chiama «{recipe}».
    final a = GroupActivity('Famiglia', 'Zia', 'Torta {category}', RecipeCategory.dolci, GroupAction.added);
    expect(a.text, contains('Torta {category}'), reason: a.text);
    final b = GroupActivity('Famiglia', '{recipe}', 'Lasagne', RecipeCategory.primi, GroupAction.edited);
    expect(b.text, startsWith('{recipe}'), reason: b.text);
    // Testo di condivisione del QR (group_qr.dart:95): un gruppo chiamato «Ricette {code}».
    final c = tr('family.qrShareText', {'name': 'Ricette {code}', 'code': 'ABCDEFGH23'});
    expect(c, contains('Ricette {code}'), reason: c);
  });
}
