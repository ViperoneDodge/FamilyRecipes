import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Un foglio da scrivere: righe di celle (testo o numeri); la prima riga è l'intestazione (in grassetto,
/// bloccata in alto).
class XlsxSheet {
  final String name;
  final List<List<Object?>> rows;
  final List<double> widths;

  /// Prima riga come intestazione (grassetto e bloccata in alto).
  final bool freezeHeader;

  /// Altre righe in grassetto (intestazioni di sezione).
  final Set<int> boldRows;

  /// Prima colonna in grassetto (etichette).
  final bool boldFirstColumn;

  const XlsxSheet(this.name, this.rows,
      {this.widths = const [], this.freezeHeader = true, this.boldRows = const {}, this.boldFirstColumn = false});
}

/// File Excel (.xlsx) essenziali, scritti e letti senza librerie esterne: bastano per il modulo delle
/// ricette e della settimana (testi e numeri, niente formule).
class Xlsx {
  /// Limite per ogni parte del file (foglio, testi condivisi) una volta decompressa.
  static const int maxPartBytes = 20 * 1024 * 1024;

  static String _col(int i) {
    var n = i + 1;
    var s = '';
    while (n > 0) {
      final r = (n - 1) % 26;
      s = String.fromCharCode(65 + r) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  static int _colIndex(String ref) {
    var n = 0;
    for (final c in ref.codeUnits) {
      if (c < 65 || c > 90) break;
      n = n * 26 + (c - 64);
    }
    return n - 1;
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      // caratteri di controllo non ammessi in XML
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

  static String _sheetXml(XlsxSheet s) {
    final b = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
      ..write(s.freezeHeader
          ? '<sheetViews><sheetView workbookViewId="0">'
              '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>'
          : '<sheetViews><sheetView workbookViewId="0"/></sheetViews>');
    if (s.widths.isNotEmpty) {
      b.write('<cols>');
      for (var i = 0; i < s.widths.length; i++) {
        b.write('<col min="${i + 1}" max="${i + 1}" width="${s.widths[i]}" customWidth="1"/>');
      }
      b.write('</cols>');
    }
    b.write('<sheetData>');
    for (var r = 0; r < s.rows.length; r++) {
      b.write('<row r="${r + 1}">');
      final row = s.rows[r];
      for (var c = 0; c < row.length; c++) {
        final v = row[c];
        if (v == null || (v is String && v.isEmpty)) continue;
        final ref = '${_col(c)}${r + 1}';
        final bold = (r == 0 && s.freezeHeader) || s.boldRows.contains(r);
        final style = bold ? ' s="1"' : (c == 0 && s.boldFirstColumn ? ' s="3"' : ' s="2"');
        if (v is num && v.isFinite) {
          b.write('<c r="$ref"$style><v>$v</v></c>');
        } else {
          b.write('<c r="$ref" t="inlineStr"$style><is><t xml:space="preserve">${_esc('$v')}</t></is></c>');
        }
      }
      b.write('</row>');
    }
    b.write('</sheetData></worksheet>');
    return b.toString();
  }

  static Uint8List write(List<XlsxSheet> sheets) {
    final a = Archive();
    void add(String name, String text) => a.addFile(ArchiveFile.bytes(name, utf8.encode(text)));
    add('[Content_Types].xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '${[for (var i = 0; i < sheets.length; i++) '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
        '</Types>');
    add('_rels/.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>');
    add('xl/workbook.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
        '${[for (var i = 0; i < sheets.length; i++) '<sheet name="${_esc(_sheetName(sheets[i].name))}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
        '</sheets></workbook>');
    add('xl/_rels/workbook.xml.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '${[for (var i = 0; i < sheets.length; i++) '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>'].join()}'
        '<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>');
    // Stili: 0 normale, 1 intestazione (grassetto su fondo crema), 2 testo a capo in alto.
    add('xl/styles.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
        '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>'
        '<fill><patternFill patternType="solid"><fgColor rgb="FFF4E4C1"/><bgColor indexed="64"/></patternFill></fill></fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
        '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>'
        '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>'
        '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment vertical="top"/></xf>'
        '</cellXfs></styleSheet>');
    for (var i = 0; i < sheets.length; i++) {
      add('xl/worksheets/sheet${i + 1}.xml', _sheetXml(sheets[i]));
    }
    return Uint8List.fromList(ZipEncoder().encode(a));
  }

  /// I nomi dei fogli: al massimo 31 caratteri, senza : \ / ? * [ ].
  static String _sheetName(String s) {
    final t = s.replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ').trim();
    return t.length > 31 ? t.substring(0, 31) : (t.isEmpty ? 'Foglio' : t);
  }

  /// Legge tutti i fogli: nome → righe di testi (celle vuote = ''). Lancia [FormatException] se non è un .xlsx.
  static Map<String, List<List<String>>> read(Uint8List bytes) {
    final Archive a;
    try {
      a = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('not xlsx');
    }
    String? text(String name) {
      final f = a.findFile(name);
      // Un foglio "gonfiato" (pochi KB compressi, GB decompressi) non deve riempire la memoria.
      if (f != null && f.size > maxPartBytes) throw const FormatException('xlsx part too large');
      final b = f?.readBytes();
      return b == null ? null : utf8.decode(b, allowMalformed: true);
    }

    final wb = text('xl/workbook.xml');
    if (wb == null) throw const FormatException('not xlsx');
    final shared = <String>[];
    final ss = text('xl/sharedStrings.xml');
    if (ss != null) {
      for (final si in XmlDocument.parse(ss).findAllElements('si')) {
        shared.add(si.findAllElements('t').map((t) => t.innerText).join());
      }
    }
    final rels = <String, String>{};
    final relText = text('xl/_rels/workbook.xml.rels');
    if (relText != null) {
      for (final r in XmlDocument.parse(relText).findAllElements('Relationship')) {
        final id = r.getAttribute('Id');
        final target = r.getAttribute('Target');
        if (id != null && target != null) {
          rels[id] = target.startsWith('/') ? target.substring(1) : 'xl/$target';
        }
      }
    }
    final out = <String, List<List<String>>>{};
    var n = 0;
    for (final s in XmlDocument.parse(wb).findAllElements('sheet')) {
      n++;
      final name = s.getAttribute('name') ?? 'Sheet$n';
      final rid = s.attributes.where((x) => x.localName == 'id').map((x) => x.value).firstOrNull;
      final path = rels[rid] ?? 'xl/worksheets/sheet$n.xml';
      final xml = text(path);
      if (xml == null) continue;
      final rows = <List<String>>[];
      for (final row in XmlDocument.parse(xml).findAllElements('row')) {
        final idx = (int.tryParse(row.getAttribute('r') ?? '') ?? rows.length + 1) - 1;
        if (idx < 0 || idx > 100000) continue;
        while (rows.length <= idx) {
          rows.add([]);
        }
        final cells = rows[idx];
        var next = 0;
        for (final c in row.findElements('c')) {
          final ref = c.getAttribute('r');
          final col = ref == null ? next : _colIndex(ref);
          next = col + 1;
          if (col < 0 || col > 200) continue;
          final t = c.getAttribute('t');
          String v;
          if (t == 'inlineStr') {
            v = c.findAllElements('t').map((e) => e.innerText).join();
          } else {
            final raw = c.getElement('v')?.innerText ?? '';
            if (t == 's') {
              final i = int.tryParse(raw);
              v = i != null && i >= 0 && i < shared.length ? shared[i] : '';
            } else if (t == 'b') {
              v = raw == '1' ? 'TRUE' : 'FALSE';
            } else {
              v = raw;
              // 4.0 → 4
              final d = double.tryParse(raw);
              if (d != null && d == d.roundToDouble() && d.abs() < 1e15) v = d.round().toString();
            }
          }
          while (cells.length <= col) {
            cells.add('');
          }
          cells[col] = v.trim();
        }
      }
      out[name] = rows;
    }
    return out;
  }
}
