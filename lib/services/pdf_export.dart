import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../l10n.dart';
import '../models.dart';
import '../widgets/common.dart' show fmtDate;

/// Carica i byte di una foto della ricetta (telefono o cloud).
typedef PhotoLoader = Future<Uint8List?> Function(Recipe r, String photoId);

/// PDF in stile ricettario: una ricetta per pagina (o più pagine se lunga),
/// con indice per categoria quando le ricette sono più di una.
class PdfExport {
  static const PdfColor _paper = PdfColor.fromInt(0xFFFFF7E4);
  static const PdfColor _ink = PdfColor.fromInt(0xFF3B2A1E);
  static const PdfColor _accent = PdfColor.fromInt(0xFFB4532A);
  static const PdfColor _line = PdfColor.fromInt(0xFFE6D3AE);
  static const PdfColor _muted = PdfColor.fromInt(0xFF7A6552);

  static Future<pw.Font> _asset(String name) async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/$name'));

  static String fileName(String title) {
    final safe = title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    final day = DateFormat('yyyyMMdd').format(DateTime.now());
    return 'FamilyRecipes${safe.isEmpty ? '' : '-$safe'}-$day.pdf';
  }

  static Future<void> share({
    required String title,
    required List<Recipe> recipes,
    required PhotoLoader photo,
    Map<String, Recipe> lookup = const {},
  }) async {
    final bytes = await build(title: title, recipes: recipes, photo: photo, lookup: lookup);
    await Printing.sharePdf(bytes: bytes, filename: fileName(title));
  }

  static Future<Uint8List> build({
    required String title,
    required List<Recipe> recipes,
    required PhotoLoader photo,
    Map<String, Recipe> lookup = const {},
  }) async {
    final base = await _asset('NotoSans-Regular.ttf');
    final bold = await _asset('NotoSans-Bold.ttf');
    final hand = await _asset('PatrickHand-Regular.ttf');
    final theme = pw.ThemeData.withFont(base: base, bold: bold);
    final doc = pw.Document(title: title, creator: 'FamilyRecipes', theme: theme);

    final images = <String, pw.ImageProvider>{};
    for (final r in recipes) {
      for (final p in r.photoIds) {
        try {
          final b = await photo(r, p);
          if (b != null) images[p] = pw.MemoryImage(b);
        } catch (_) {}
      }
    }

    final ordered = List.of(recipes)
      ..sort((a, b) {
        final c = a.category.index.compareTo(b.category.index);
        return c != 0 ? c : a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase());
      });

    pw.PageTheme pageTheme() => pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(46, 40, 36, 36),
          buildBackground: (ctx) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(
              color: _paper,
              child: pw.Stack(children: [
                pw.Positioned(
                  left: 30,
                  top: 0,
                  bottom: 0,
                  child: pw.Container(width: 1, color: const PdfColor.fromInt(0xFFE39A84)),
                ),
              ]),
            ),
          ),
        );

    pw.Widget footer(pw.Context ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text('$title · ${ctx.pageNumber} / ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: _muted)),
        );

    if (ordered.length > 1) {
      doc.addPage(pw.MultiPage(
        pageTheme: pageTheme(),
        footer: footer,
        build: (ctx) => _index(title, ordered, hand),
      ));
    }
    for (final r in ordered) {
      doc.addPage(pw.MultiPage(
        pageTheme: pageTheme(),
        footer: footer,
        build: (ctx) => _recipe(r, images, hand, lookup),
      ));
    }
    return doc.save();
  }

  static List<pw.Widget> _index(String title, List<Recipe> recipes, pw.Font hand) {
    final out = <pw.Widget>[
      pw.Text('FamilyRecipes', style: const pw.TextStyle(fontSize: 10, color: _muted)),
      pw.Text(title, style: pw.TextStyle(font: hand, fontSize: 34, color: _accent)),
      pw.Text(
          '${tr('pdf.generated', {'date': fmtDate(DateTime.now())})} · ${trn('book.recipes', recipes.length)}',
          style: const pw.TextStyle(fontSize: 10, color: _muted)),
      pw.Container(height: 1.5, color: _accent, margin: const pw.EdgeInsets.only(top: 8, bottom: 6)),
      pw.Text(tr('pdf.index'), style: pw.TextStyle(font: hand, fontSize: 24, color: _ink)),
    ];
    for (final c in RecipeCategory.values) {
      final list = recipes.where((r) => r.category == c).toList();
      if (list.isEmpty) continue;
      out.add(pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10, bottom: 2),
        child: pw.Text(categoryLabel(c), style: pw.TextStyle(font: hand, fontSize: 19, color: _accent)),
      ));
      for (final r in list) {
        out.add(pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.6))),
          child: pw.Row(children: [
            pw.Expanded(child: pw.Text(r.displayTitle, style: const pw.TextStyle(fontSize: 10.5, color: _ink))),
            pw.Text(
                [
                  difficultyLabel(r.difficulty),
                  if (r.totalMinutes > 0) fmtMinutes(r.totalMinutes),
                ].join(' · '),
                style: const pw.TextStyle(fontSize: 9, color: _muted)),
          ]),
        ));
      }
    }
    return out;
  }

  static List<pw.Widget> _recipe(
      Recipe r, Map<String, pw.ImageProvider> images, pw.Font hand, Map<String, Recipe> lookup) {
    pw.Widget info(String label, String value) => pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _line, width: 0.8),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(label.toUpperCase(), style: const pw.TextStyle(fontSize: 7, color: _muted, letterSpacing: 0.6)),
            pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
          ]),
        );

    pw.Widget section(String t) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 14, bottom: 4),
          child: pw.Text(t, style: pw.TextStyle(font: hand, fontSize: 22, color: _accent)),
        );

    final cover = r.coverPhoto == null ? null : images[r.coverPhoto];
    final out = <pw.Widget>[
      pw.Text(categoryLabel(r.category).toUpperCase(),
          style: const pw.TextStyle(fontSize: 9, color: _accent, letterSpacing: 1.2)),
      pw.Text(r.displayTitle, style: pw.TextStyle(font: hand, fontSize: 32, color: _ink)),
      if (r.createdByName.isNotEmpty)
        pw.Text(tr('recipe.by', {'name': r.createdByName}), style: const pw.TextStyle(fontSize: 9, color: _muted)),
      pw.SizedBox(height: 8),
      if (cover != null)
        pw.ClipRRect(
          horizontalRadius: 6,
          verticalRadius: 6,
          child: pw.Container(
            height: 220,
            width: double.infinity,
            child: pw.Image(cover, fit: pw.BoxFit.cover),
          ),
        ),
      pw.SizedBox(height: 8),
      pw.Wrap(spacing: 6, runSpacing: 6, children: [
        info(tr('recipe.difficulty'), difficultyLabel(r.difficulty)),
        if (r.prepMinutes > 0) info(tr('recipe.prep'), fmtMinutes(r.prepMinutes)),
        if (r.cookMinutes > 0) info(tr('recipe.cook'), fmtMinutes(r.cookMinutes)),
        if (r.servings > 0) info(tr('recipe.servings'), tr('recipe.people', {'n': r.servings})),
        info(tr('recipe.cost'), costLabel(r.cost)),
      ]),
      if (r.intro.trim().isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10),
          child: pw.Text(r.intro.trim(), style: const pw.TextStyle(fontSize: 10.5, color: _ink, lineSpacing: 2)),
        ),
    ];

    final courses = r.courses.map((id) => lookup[id]).whereType<Recipe>().toList();
    if (r.category == RecipeCategory.menu && courses.isNotEmpty) {
      out.add(section(tr('recipe.courses')));
      for (final c in courses) {
        out.add(pw.Bullet(
          text: '${c.displayTitle}  (${categoryLabel(c.category)})',
          style: const pw.TextStyle(fontSize: 10.5, color: _ink),
          bulletColor: _accent,
        ));
      }
    }

    if (r.ingredients.isNotEmpty) {
      out.add(section(tr('recipe.ingredients')));
      if (r.servings > 0) {
        out.add(pw.Text(tr('recipe.dosesFor', {'n': r.servings}),
            style: const pw.TextStyle(fontSize: 9, color: _muted)));
      }
      out.add(pw.Table(
        columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1.4)},
        children: [
          for (final i in r.ingredients)
            pw.TableRow(
              decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.6))),
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 3),
                  child: pw.Text(i.name, style: const pw.TextStyle(fontSize: 10.5, color: _ink)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 3),
                  child: pw.Text(i.amount,
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: _ink)),
                ),
              ],
            ),
        ],
      ));
    }

    if (r.steps.isNotEmpty) {
      out.add(section(tr('recipe.steps')));
      for (var n = 0; n < r.steps.length; n++) {
        final s = r.steps[n];
        final pics = s.photos.map((p) => images[p]).whereType<pw.ImageProvider>().toList();
        out.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Container(
              width: 20,
              height: 20,
              alignment: pw.Alignment.center,
              decoration: const pw.BoxDecoration(color: _accent, shape: pw.BoxShape.circle),
              child: pw.Text('${n + 1}',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                if (s.text.trim().isNotEmpty)
                  pw.Text(s.text.trim(), style: const pw.TextStyle(fontSize: 10.5, color: _ink, lineSpacing: 2)),
                if (pics.isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 5),
                    child: pw.Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final p in pics)
                        pw.ClipRRect(
                          horizontalRadius: 4,
                          verticalRadius: 4,
                          child: pw.Image(p, width: 120, height: 90, fit: pw.BoxFit.cover),
                        ),
                    ]),
                  ),
              ]),
            ),
          ]),
        ));
      }
    }

    if (r.tips.trim().isNotEmpty) {
      out.add(section(tr('recipe.tips')));
      out.add(pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: const PdfColor.fromInt(0xFFFBEBC8),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Text(r.tips.trim(), style: const pw.TextStyle(fontSize: 10.5, color: _ink, lineSpacing: 2)),
      ));
    }
    return out;
  }
}
