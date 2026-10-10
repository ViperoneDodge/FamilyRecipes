import 'dart:convert';
import 'dart:typed_data';

import '../models.dart';

/// Una ricetta letta da un file di importazione, con la sua foto (se c'è).
class ImportedRecipe {
  final Recipe recipe;
  final Uint8List? photo;

  ImportedRecipe(this.recipe, this.photo);
}

/// Legge i file di importazione (`.json`), come quelli creati dal modulo web "Ricettario da compilare".
///
/// Formato: `{"app": "FamilyRecipes", "format": 1, "recipes": [ ... ]}` oppure direttamente l'elenco.
/// Ogni ricetta: `category`, `title`, `intro`, `difficulty`, `cost`, `prepMinutes`, `cookMinutes`,
/// `servings`, `ingredients` (`[{name, amount}]` o testi), `steps` (testi o `[{text}]`), `tips`,
/// `author`, `photo` (JPEG/PNG in base64, anche come `data:image/...`). I valori mancanti o sconosciuti
/// diventano quelli predefiniti.
class RecipeImport {
  static List<ImportedRecipe> parse(String text) {
    final root = jsonDecode(text.trim().replaceFirst('﻿', ''));
    final list = root is List ? root : (root is Map ? root['recipes'] : null);
    if (list is! List) throw const FormatException('no recipes');
    final out = <ImportedRecipe>[];
    for (final e in list) {
      if (e is! Map) continue;
      final r = _recipe(Map<String, dynamic>.from(e));
      if (r != null) out.add(r);
    }
    return out;
  }

  static ImportedRecipe? _recipe(Map<String, dynamic> j) {
    final title = _str(j['title']);
    final ingredients = <Ingredient>[];
    for (final i in (j['ingredients'] as List?) ?? const []) {
      if (i is Map) {
        final name = _str(i['name']);
        if (name.isNotEmpty) ingredients.add(Ingredient(name: name, amount: _str(i['amount'])));
      } else if (_str(i).isNotEmpty) {
        ingredients.add(Ingredient(name: _str(i)));
      }
    }
    final steps = <RecipeStep>[];
    for (final s in (j['steps'] as List?) ?? const []) {
      final t = s is Map ? _str(s['text']) : _str(s);
      if (t.isNotEmpty) steps.add(RecipeStep(text: t));
    }
    if (title.isEmpty && ingredients.isEmpty && steps.isEmpty) return null;
    final r = Recipe(
      category: _category(j['category']),
      title: title,
      intro: _str(j['intro']),
      difficulty: _pick(Difficulty.values, j['difficulty'], _diffWords, Difficulty.easy),
      cost: _pick(Cost.values, j['cost'], _costWords, Cost.low),
      prepMinutes: _int(j['prepMinutes'] ?? j['prep']),
      cookMinutes: _int(j['cookMinutes'] ?? j['cook']),
      servings: _int(j['servings'], 4).clamp(1, 99),
      ingredients: ingredients,
      steps: steps,
      tips: _str(j['tips']),
    );
    r.createdByName = _str(j['author']);
    return ImportedRecipe(r, _photo(j['photo']));
  }

  static String _str(Object? v) => v == null ? '' : v.toString().trim();

  static int _int(Object? v, [int fallback = 0]) {
    if (v is num) return v.round().clamp(0, 100000);
    final m = RegExp(r'\d+').firstMatch(_str(v));
    return m == null ? fallback : int.parse(m[0]!);
  }

  static String _key(Object? v) => _str(v).toLowerCase().replaceAll(RegExp(r'[^a-zàèéìòù]'), '');

  static const Map<String, RecipeCategory> _catWords = {
    'aperitivo': RecipeCategory.aperitivi,
    'aperitivi': RecipeCategory.aperitivi,
    'antipasto': RecipeCategory.antipasti,
    'antipasti': RecipeCategory.antipasti,
    'primo': RecipeCategory.primi,
    'primi': RecipeCategory.primi,
    'primipiatti': RecipeCategory.primi,
    'secondo': RecipeCategory.secondi,
    'secondi': RecipeCategory.secondi,
    'secondipiatti': RecipeCategory.secondi,
    'contorno': RecipeCategory.contorni,
    'contorni': RecipeCategory.contorni,
    'dolce': RecipeCategory.dolci,
    'dolci': RecipeCategory.dolci,
    'liquore': RecipeCategory.liquori,
    'liquori': RecipeCategory.liquori,
    'conserva': RecipeCategory.conserve,
    'conserve': RecipeCategory.conserve,
    'menù': RecipeCategory.menu,
    'menu': RecipeCategory.menu,
    'menùcompleti': RecipeCategory.menu,
    'menucompleti': RecipeCategory.menu,
  };

  static RecipeCategory _category(Object? v) {
    final k = _key(v);
    for (final c in RecipeCategory.values) {
      if (c.name == k) return c;
    }
    return _catWords[k] ?? RecipeCategory.secondi;
  }

  static const Map<String, Difficulty> _diffWords = {
    'moltofacile': Difficulty.veryEasy,
    'facile': Difficulty.easy,
    'media': Difficulty.medium,
    'medio': Difficulty.medium,
    'difficile': Difficulty.hard,
  };

  static const Map<String, Cost> _costWords = {
    'moltobasso': Cost.veryLow,
    'basso': Cost.low,
    'medio': Cost.medium,
    'alto': Cost.high,
    'elevato': Cost.high,
  };

  static T _pick<T extends Enum>(List<T> values, Object? v, Map<String, T> words, T fallback) {
    final k = _key(v);
    for (final x in values) {
      if (x.name.toLowerCase() == k) return x;
    }
    return words[k] ?? fallback;
  }

  static Uint8List? _photo(Object? v) {
    var s = _str(v);
    if (s.isEmpty) return null;
    final comma = s.indexOf(',');
    if (s.startsWith('data:') && comma > 0) s = s.substring(comma + 1);
    try {
      final b = base64Decode(s.replaceAll(RegExp(r'\s'), ''));
      return b.isEmpty ? null : b;
    } catch (_) {
      return null;
    }
  }
}
