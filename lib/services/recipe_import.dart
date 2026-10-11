import 'dart:convert';
import 'dart:typed_data';

import '../models.dart';
import 'recipe_words.dart';

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
  /// File di esportazione, nello stesso formato letto da [parse]; [photos]: foto del piatto per id ricetta.
  static String encode(List<Recipe> recipes, Map<String, Uint8List> photos) => const JsonEncoder.withIndent(' ').convert({
        'app': 'FamilyRecipes',
        'format': 1,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'recipes': [
          for (final r in recipes)
            {
              'category': r.category.name,
              'title': r.title,
              'intro': r.intro,
              'difficulty': r.difficulty.name,
              'cost': r.cost.name,
              'prepMinutes': r.prepMinutes,
              'cookMinutes': r.cookMinutes,
              'servings': r.servings,
              'ingredients': [for (final i in r.ingredients) {'name': i.name, 'amount': i.amount}],
              'steps': [for (final s in r.steps) s.text],
              'tips': r.tips,
              'author': r.createdByName,
              if (photos[r.id] != null) 'photo': 'data:image/jpeg;base64,${base64Encode(photos[r.id]!)}',
            },
        ],
      });

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
      category: RecipeWords.categoryFromLabel(_str(j['category'])) ?? RecipeCategory.secondi,
      title: title,
      intro: _str(j['intro']),
      difficulty: RecipeWords.difficulty(_str(j['difficulty'])) ?? Difficulty.easy,
      cost: RecipeWords.cost(_str(j['cost'])) ?? Cost.low,
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
