import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart' show rootBundle;

class L10n {
  static const Map<String, String> names = {
    'it': 'Italiano',
    'en': 'English',
    'fr': 'Français',
    'de': 'Deutsch',
    'es': 'Español',
    'pt': 'Português',
    'nl': 'Nederlands',
    'hr': 'Hrvatski',
    'sl': 'Slovenščina',
    'pl': 'Polski',
    'cs': 'Čeština',
    'sk': 'Slovenčina',
    'hu': 'Magyar',
    'ro': 'Română',
    'bg': 'Български',
    'el': 'Ελληνικά',
    'sv': 'Svenska',
    'da': 'Dansk',
    'nb': 'Norsk',
    'fi': 'Suomi',
    'is': 'Íslenska',
    'et': 'Eesti',
    'lv': 'Latviešu',
    'lt': 'Lietuvių',
    'mt': 'Malti',
    'ga': 'Gaeilge',
    'uk': 'Українська',
    'ru': 'Русский',
    'tr': 'Türkçe',
    'zh': '中文（简体）',
    'ja': '日本語',
    'ko': '한국어',
    'hi': 'हिन्दी',
    'id': 'Bahasa Indonesia',
    'vi': 'Tiếng Việt',
    'th': 'ไทย',
  };

  static final List<String> available = names.keys.toList();

  static String code = 'it';
  static Map<String, String> _cur = {};
  static Map<String, String> _en = {};
  static Map<String, String> _it = {};

  static String resolve(String? preferred) {
    if (preferred != null && available.contains(preferred)) return preferred;
    var device = PlatformDispatcher.instance.locale.languageCode;
    if (device == 'no' || device == 'nn') device = 'nb';
    return available.contains(device) ? device : 'en';
  }

  static Future<void> load(String c) async {
    if (_it.isEmpty) _it = await _read('it');
    if (_en.isEmpty) _en = await _read('en');
    _cur = c == 'it' ? _it : (c == 'en' ? _en : await _read(c));
    code = c;
  }

  static Future<Map<String, String>> _read(String c) async {
    try {
      final txt = await rootBundle.loadString('assets/l10n/$c.json');
      final m = Map<String, dynamic>.from(jsonDecode(txt) as Map);
      return m.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }
}

String tr(String key, [Map<String, Object?>? args]) {
  var s = L10n._cur[key] ?? L10n._en[key] ?? L10n._it[key] ?? key;
  if (args != null) {
    args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  }
  return s;
}

String trn(String key, int n, [Map<String, Object?>? args]) =>
    tr(n == 1 ? '${key}_one' : '${key}_other', {'n': n, ...?args});
