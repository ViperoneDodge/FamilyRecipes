import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import '../models.dart';
import 'recipe_text_parser.dart';

/// Legge una ricetta da foto o PDF direttamente sul telefono (Google ML Kit, senza server)
/// e la trasforma in una bozza con [RecipeTextParser].
class RecipeReader {
  /// Pagine massime lette da un PDF.
  static const int maxPdfPages = 6;

  /// Testo di tutte le immagini (o pagine del PDF), nell'ordine.
  static Future<String> readText(List<String> paths) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final temp = <File>[];
    try {
      final images = <String>[];
      for (final p in paths) {
        if (p.toLowerCase().endsWith('.pdf')) {
          final bytes = await File(p).readAsBytes();
          final dir = await getTemporaryDirectory();
          var i = 0;
          await for (final page in Printing.raster(bytes, pages: List.generate(maxPdfPages, (k) => k), dpi: 200)) {
            final f = File('${dir.path}/ricetta_${DateTime.now().millisecondsSinceEpoch}_$i.png');
            await f.writeAsBytes(await page.toPng());
            temp.add(f);
            images.add(f.path);
            i++;
          }
        } else {
          images.add(p);
        }
      }
      final out = StringBuffer();
      for (final img in images) {
        final res = await recognizer.processImage(InputImage.fromFilePath(img));
        out.writeln(_ordered(res));
      }
      return out.toString();
    } finally {
      await recognizer.close();
      for (final f in temp) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }

  /// Righe dall'alto in basso; su due colonne (es. ingredienti a sinistra e procedimento a destra)
  /// prima la colonna di sinistra, poi quella di destra.
  static String _ordered(RecognizedText res) {
    final lines = <TextLine>[for (final b in res.blocks) ...b.lines];
    if (lines.isEmpty) return '';
    final minX = lines.map((l) => l.boundingBox.left).reduce((a, b) => a < b ? a : b);
    final maxX = lines.map((l) => l.boundingBox.right).reduce((a, b) => a > b ? a : b);
    final mid = (minX + maxX) / 2;
    final left = lines.where((l) => l.boundingBox.right < mid + (maxX - minX) * 0.05).toList();
    final right = lines.where((l) => l.boundingBox.left > mid - (maxX - minX) * 0.05 && !left.contains(l)).toList();
    final twoColumns = left.length >= 4 && right.length >= 4 && left.length + right.length >= lines.length * 0.9;
    int byY(TextLine a, TextLine b) => a.boundingBox.top.compareTo(b.boundingBox.top);
    if (twoColumns) {
      final wide = lines.where((l) => !left.contains(l) && !right.contains(l)).toList()..sort(byY);
      left.sort(byY);
      right.sort(byY);
      return [...wide, ...left, ...right].map((l) => l.text).join('\n');
    }
    lines.sort(byY);
    return lines.map((l) => l.text).join('\n');
  }

  static Future<Recipe> read(List<String> paths) async => RecipeTextParser.parse(await readText(paths));
}
