import 'dart:convert';
import 'dart:io';

import 'package:familyrecipes/l10n.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _load(String code) =>
    jsonDecode(File('assets/l10n/$code.json').readAsStringSync()) as Map<String, dynamic>;

List<String> _placeholders(String s) => RegExp(r'\{\w+\}').allMatches(s).map((m) => m[0]!).toList()..sort();

void main() {
  final it = _load('it');

  test('ogni lingua ha un file', () {
    expect(L10n.available.length, 36);
    for (final c in L10n.available) {
      expect(File('assets/l10n/$c.json').existsSync(), isTrue, reason: c);
    }
  });

  for (final c in L10n.available) {
    test('$c: tutte le chiavi e gli stessi segnaposto', () {
      final m = _load(c);
      expect(it.keys.where((k) => !m.containsKey(k)), isEmpty, reason: 'chiavi mancanti in $c');
      for (final k in it.keys) {
        expect(_placeholders(m[k] as String), _placeholders(it[k] as String), reason: '$c $k');
      }
    });
  }
}
