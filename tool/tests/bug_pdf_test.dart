// BUG trovato dal tester cattivo sul PDF (1.9.0). Il test FALLISCE finché il problema c'è.
// Lancio:  flutter test tool/tests/bug_pdf_test.dart
import 'package:familyrecipes/l10n.dart';
import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/services/pdf_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => L10n.load('it'));

  // pdf_export.dart:228, 293, 321 (intro, testo del passaggio, consigli) sono pw.Text dentro Container/Row: un
  // widget che non si può spezzare tra le pagine. Più alto di una pagina A4 (≈ 500 parole) → eccezione
  // «Widget won't fit into the page…», exportPdf (family_screen.dart:284) mostra l'errore e non esporta NIENTE:
  // basta una ricetta lunga per non poter stampare l'intero ricettario del gruppo.
  final lungo = List.generate(600, (i) => 'parola$i').join(' ');
  for (final caso in {
    'introduzione di 600 parole (racconto della nonna, descrizione importata da un sito)': Recipe(title: 'Torta', intro: lungo),
    'un passaggio di 600 parole (OCR di una pagina senza punti)': Recipe(title: 'Torta', steps: [RecipeStep(text: lungo)]),
    'consigli di 600 parole': Recipe(title: 'Torta', tips: lungo),
  }.entries) {
    test('BUG [MEDIO] PDF: ${caso.key} → eccezione, nessun PDF', () async {
      final altre = [Recipe(title: 'Sugo'), Recipe(title: 'Arrosto')];
      final b = await PdfExport.build(title: 'Ricettario', recipes: [...altre, caso.value], photo: (r, p) async => null);
      expect(String.fromCharCodes(b.take(5)), '%PDF-');
    });
  }
}
