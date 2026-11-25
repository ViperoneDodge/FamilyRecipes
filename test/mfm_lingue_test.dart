// Tester cattivo (adattato da MyFleetManager l10n_congruenza.py e t24_b_lingue_test) — congruenza delle 36
// lingue e dei tr()/trn() del codice (T-L10N-01/02, T-IN-07). Gira in CI: niente rete, solo file.
import 'dart:convert';
import 'dart:io';

import 'package:familyrecipes/l10n.dart';
import 'package:familyrecipes/models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _lingua(String c) =>
    jsonDecode(File('assets/l10n/$c.json').readAsStringSync()) as Map<String, dynamic>;

final _ph = RegExp(r'\{(\w+)\}');
Set<String> _segnaposto(String s) => _ph.allMatches(s).map((m) => m[1]!).toSet();

/// Testo tra la parentesi di apertura della chiamata e quella di chiusura.
String _argomenti(String t, int start) {
  var depth = 0;
  for (var i = start; i < t.length; i++) {
    if (t[i] == '(') depth++;
    if (t[i] == ')' && --depth == 0) return t.substring(start, i);
  }
  return t.substring(start);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final it = _lingua('it');
  final file = {
    for (final f in Directory('assets/l10n').listSync().whereType<File>().where((f) => f.path.endsWith('.json')))
      f.uri.pathSegments.last.replaceAll('.json', '')
  };
  final sorgenti = {
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')))
      f.path: f.readAsStringSync()
  };

  test('lingue dichiarate in l10n.dart = file presenti', () {
    expect(L10n.available.toSet(), file);
    expect(L10n.available.length, 36);
    expect(L10n.names.values.every((n) => n.trim().isNotEmpty), isTrue);
  });

  test('nessuna chiave in più rispetto a it.json, nessun testo vuoto o non testuale', () {
    final errori = <String>[];
    for (final c in L10n.available) {
      final m = _lingua(c);
      for (final k in m.keys.where((k) => !it.containsKey(k))) {
        errori.add('$c: chiave in più $k');
      }
      m.forEach((k, v) {
        if (v is! String) {
          errori.add('$c.$k non è testo');
        } else if (v.trim().isEmpty) {
          errori.add('$c.$k vuoto');
        }
      });
    }
    expect(errori, isEmpty, reason: errori.join('\n'));
  });

  test('graffe bilanciate, niente residui %s / {{ / }} / \$var', () {
    final residuo = RegExp(r'%[sd]|\{\{|\}\}|\$\w');
    final errori = <String>[];
    for (final c in L10n.available) {
      _lingua(c).forEach((k, v) {
        final s = '$v';
        if ('{'.allMatches(s).length != '}'.allMatches(s).length) errori.add('$c.$k graffe: $s');
        if (residuo.hasMatch(s) && !residuo.hasMatch('${it[k] ?? ''}')) errori.add('$c.$k residuo: $s');
      });
    }
    expect(errori, isEmpty, reason: errori.join('\n'));
  });

  test('coppie _one / _other complete', () {
    final errori = <String>[];
    for (final k in it.keys) {
      if (k.endsWith('_one') && !it.containsKey(k.replaceFirst(RegExp(r'_one$'), '_other'))) errori.add(k);
      if (k.endsWith('_other') && !it.containsKey(k.replaceFirst(RegExp(r'_other$'), '_one'))) errori.add(k);
    }
    expect(errori, isEmpty);
  });

  test('ogni tr(\'…\') / trn(\'…\') del codice esiste e riceve tutti i segnaposto che la traduzione usa', () {
    final chiamata = RegExp(r"\b(trn?)\(\s*'([^'$]+)'");
    final errori = <String>[];
    sorgenti.forEach((path, t) {
      for (final m in chiamata.allMatches(t)) {
        final fn = m[1]!, key = m[2]!;
        final riga = '\n'.allMatches(t.substring(0, m.start)).length + 1;
        final chiavi = fn == 'trn' ? ['${key}_one', '${key}_other'] : [key];
        final corpo = _argomenti(t, t.indexOf('(', m.start));
        final passati = RegExp(r"'(\w+)'\s*:").allMatches(corpo).map((x) => x[1]!).toSet();
        if (fn == 'trn') passati.add('n');
        for (final k in chiavi) {
          if (!it.containsKey(k)) {
            errori.add('$path:$riga $fn(\'$key\'): «$k» non esiste');
            continue;
          }
          if (corpo.contains('...')) continue;
          final mancano = _segnaposto('${it[k]}').difference(passati);
          if (mancano.isNotEmpty) errori.add('$path:$riga $fn(\'$key\') non passa $mancano');
        }
      }
    });
    expect(errori, isEmpty, reason: errori.join('\n'));
  });

  test('chiavi dinamiche: ogni categoria, difficoltà, costo e ruolo ha il suo testo in tutte le lingue', () async {
    final errori = <String>[];
    for (final c in L10n.available) {
      final m = _lingua(c);
      for (final k in [
        for (final x in RecipeCategory.values) 'cat.${x.name}',
        for (final x in Difficulty.values) 'diff.${x.name}',
        for (final x in Cost.values) 'cost.${x.name}',
        for (final x in GroupRole.values) 'role.${x.name}',
      ]) {
        if (!m.containsKey(k)) errori.add('$c: $k');
      }
    }
    expect(errori, isEmpty, reason: errori.join('\n'));
  });

  group('T-L10N-02 lingua salvata e del telefono', () {
    test('lingua salvata non valida = lingua del telefono (o inglese); quelle valide restano', () {
      final telefono = L10n.resolve(null);
      expect(L10n.available, contains(telefono));
      for (final s in ['klingon', '', 'IT', 'it_IT', 'zh-Hant', ' it', 'no', 'nn', 'pt-BR']) {
        expect(L10n.resolve(s), telefono, reason: s);
      }
      for (final l in L10n.available) {
        expect(L10n.resolve(l), l);
      }
    });

    test('lingua inesistente: load() non lascia l\'app senza testi (ricade su inglese/italiano)', () async {
      await L10n.load('xx');
      expect(tr('common.save'), isNot('common.save'));
      expect(trn('book.recipes', 2), isNot(contains('{')));
      await L10n.load('it');
    });
  });

  group('T-IN-07 / plurali in tutte le lingue', () {
    test('trn con 0, 1, 2, 5, 21, -1, 1.000.000 non lascia mai {n} né la chiave', () async {
      final plurali = it.keys.where((k) => k.endsWith('_one')).map((k) => k.substring(0, k.length - 4)).toList();
      final errori = <String>[];
      for (final l in L10n.available) {
        await L10n.load(l);
        for (final k in plurali) {
          final altri = {for (final p in _segnaposto('${it['${k}_other']}')) p: 'X'}..remove('n');
          for (final n in [0, 1, 2, 5, 21, -1, 1000000]) {
            final s = trn(k, n, altri);
            if (s.contains('{') || s.contains(k)) errori.add('$l/$k/$n: $s');
          }
        }
      }
      await L10n.load('it');
      expect(errori, isEmpty, reason: errori.take(20).join('\n'));
    });

    test('testi dell\'utente con graffe, dollari e barre in un segnaposto singolo restano identici', () async {
      await L10n.load('it');
      for (final nome in [r'{name}', r'$1', r'\1', r'{{n}}', r'${x}', '{n} {date}', r'\$&', '{recipe']) {
        final s = tr('recipe.by', {'name': nome});
        expect(s.contains(nome), isTrue, reason: '«$nome» → «$s»');
      }
    });

    test('tempi: minuti, ore, ore e minuti, zero e negativi in tutte le lingue', () async {
      for (final l in L10n.available) {
        await L10n.load(l);
        for (final m in [1, 59, 60, 61, 125, 100000]) {
          final s = fmtMinutes(m);
          expect(s.contains('{'), isFalse, reason: '$l $m $s');
          expect(s, contains(RegExp(r'\d')), reason: '$l $m $s');
        }
        expect(fmtMinutes(0), '—');
        expect(fmtMinutes(-5), '—');
      }
      await L10n.load('it');
    });
  });
}
