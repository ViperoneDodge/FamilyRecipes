import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../l10n.dart';
import '../models.dart';

/// Ricetta presa da TheMealDB (www.themealdb.com), archivio gratuito di ricette in inglese.
class OnlineRecipe {
  final String id;
  final String title;
  final String category;
  final String area;
  final String instructions;
  final String thumb;
  final String source;
  final List<Ingredient> ingredients;

  /// Versione in inglese, se questa è una traduzione.
  final OnlineRecipe? original;
  final String? _categoryText;
  final String? _areaText;
  final List<String>? _steps;

  OnlineRecipe({
    required this.id,
    required this.title,
    this.category = '',
    this.area = '',
    this.instructions = '',
    this.thumb = '',
    this.source = '',
    this.ingredients = const [],
    this.original,
    String? categoryText,
    String? areaText,
    List<String>? steps,
  })  : _categoryText = categoryText,
        _areaText = areaText,
        _steps = steps;

  bool get translated => original != null;

  /// Categoria e cucina da mostrare (tradotte, se c'è la traduzione).
  String get categoryText => _categoryText ?? category;
  String get areaText => _areaText ?? area;

  /// Copia con i testi tradotti; categoria e cucina originali restano per le regole interne.
  OnlineRecipe translatedCopy({
    required String title,
    required String category,
    required String area,
    required List<String> ingredientNames,
    required List<String> amounts,
    required List<String> steps,
  }) =>
      OnlineRecipe(
        id: id,
        title: title,
        category: this.category,
        area: this.area,
        instructions: instructions,
        thumb: thumb,
        source: source,
        ingredients: [
          for (var i = 0; i < ingredients.length; i++) Ingredient(name: ingredientNames[i], amount: amounts[i]),
        ],
        original: original ?? this,
        categoryText: category,
        areaText: area,
        steps: steps,
      );

  /// true se è solo un'anteprima (dalla ricerca per ingrediente): servono i dettagli.
  bool get isPartial => instructions.isEmpty && ingredients.isEmpty;

  factory OnlineRecipe.fromJson(Map<String, dynamic> j) {
    final ings = <Ingredient>[];
    for (var i = 1; i <= 20; i++) {
      final name = (j['strIngredient$i'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      ings.add(Ingredient(name: name, amount: (j['strMeasure$i'] as String?)?.trim() ?? ''));
    }
    return OnlineRecipe(
      id: '${j['idMeal'] ?? ''}',
      title: (j['strMeal'] as String?)?.trim() ?? '',
      category: (j['strCategory'] as String?)?.trim() ?? '',
      area: (j['strArea'] as String?)?.trim() ?? '',
      instructions: (j['strInstructions'] as String?)?.trim() ?? '',
      thumb: (j['strMealThumb'] as String?)?.trim() ?? '',
      source: (j['strSource'] as String?)?.trim() ?? '',
      ingredients: ings,
    );
  }

  /// Categoria del ricettario più vicina a quella di TheMealDB.
  RecipeCategory get recipeCategory {
    switch (category.toLowerCase()) {
      case 'dessert':
        return RecipeCategory.dolci;
      case 'starter':
        return RecipeCategory.antipasti;
      case 'side':
        return RecipeCategory.contorni;
      case 'pasta':
      case 'breakfast':
        return RecipeCategory.primi;
      default:
        return RecipeCategory.secondi;
    }
  }

  /// Passaggi: un paragrafo per passaggio, senza le righe "STEP 1".
  List<String> get steps {
    if (_steps != null) return _steps;
    final out = <String>[];
    for (final raw in instructions.split(RegExp(r'\r?\n'))) {
      final t = raw.trim().replaceFirst(RegExp(r'^(step\s*\d+[:.)]?|\d+[.)])\s*', caseSensitive: false), '');
      if (t.isEmpty) continue;
      out.add(t);
    }
    return out;
  }

  /// Riconoscimento della fonte, messo in fondo alla ricetta.
  String get credit => [
        tr('online.credit', {'title': original?.title ?? title}),
        if (source.isNotEmpty) tr('online.creditSource', {'url': source}),
        if (translated) tr('online.creditTranslated'),
      ].join('\n');

  /// Ricetta del ricettario (senza foto: la copertina si scarica a parte); la fonte va nei consigli.
  Recipe toRecipe() => Recipe(
        category: recipeCategory,
        title: title,
        intro: area.isNotEmpty && area.toLowerCase() != 'unknown' ? tr('online.cuisine', {'area': areaText}) : '',
        ingredients: [for (final i in ingredients) Ingredient(name: i.name, amount: i.amount)],
        steps: [for (final s in steps) RecipeStep(text: s)],
        tips: credit,
      );

  /// Contiene un ingrediente (nome in inglese, anche parziale)?
  bool hasIngredient(String en) {
    final q = en.toLowerCase();
    return (original ?? this).ingredients.any((i) => i.name.toLowerCase().contains(q));
  }
}

class OnlineRecipes {
  static const String _base = 'https://www.themealdb.com/api/json/v1/1';
  static const Duration _timeout = Duration(seconds: 15);

  static Future<dynamic> _get(String path) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client.getUrl(Uri.parse('$_base/$path')).timeout(_timeout);
      final res = await req.close().timeout(_timeout);
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      return jsonDecode(await res.transform(utf8.decoder).join().timeout(_timeout));
    } finally {
      client.close();
    }
  }

  static List<OnlineRecipe> parseMeals(dynamic j) {
    final meals = (j is Map ? j['meals'] : null) as List?;
    if (meals == null) return [];
    return [for (final m in meals) OnlineRecipe.fromJson(Map<String, dynamic>.from(m as Map))];
  }

  /// Una ricetta a caso.
  static Future<OnlineRecipe?> random() async {
    final list = parseMeals(await _get('random.php'));
    return list.isEmpty ? null : list.first;
  }

  static Future<OnlineRecipe?> lookup(String id) async {
    final list = parseMeals(await _get('lookup.php?i=${Uri.encodeQueryComponent(id)}'));
    return list.isEmpty ? null : list.first;
  }

  /// Ricette che contengono tutti gli ingredienti (nomi in inglese). TheMealDB gratuito cerca un
  /// ingrediente alla volta: si cerca il primo e si controllano gli altri nei dettagli.
  static Future<List<OnlineRecipe>> byIngredients(List<String> en, {int maxDetails = 12}) async {
    if (en.isEmpty) return [];
    final first = en.first.trim().toLowerCase().replaceAll(' ', '_');
    final previews = parseMeals(await _get('filter.php?i=${Uri.encodeQueryComponent(first)}'));
    if (en.length == 1) return previews;
    final out = <OnlineRecipe>[];
    for (final p in previews.take(maxDetails)) {
      try {
        final full = await lookup(p.id);
        if (full != null && en.skip(1).every(full.hasIngredient)) out.add(full);
      } catch (_) {}
    }
    return out;
  }

  static Future<Uint8List?> download(String url) async {
    if (url.isEmpty) return null;
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(_timeout);
      final res = await req.close().timeout(_timeout);
      if (res.statusCode != 200) return null;
      final b = BytesBuilder(copy: false);
      await for (final chunk in res.timeout(_timeout)) {
        b.add(chunk);
      }
      return b.takeBytes();
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}

/// Traduzione in inglese degli ingredienti più comuni, per cercarli su TheMealDB.
const Map<String, String> ingredientItEn = {
  'pollo': 'chicken',
  'petto di pollo': 'chicken breast',
  'manzo': 'beef',
  'carne macinata': 'minced beef',
  'macinato': 'minced beef',
  'maiale': 'pork',
  'agnello': 'lamb',
  'vitello': 'veal',
  'salsiccia': 'sausage',
  'pancetta': 'bacon',
  'guanciale': 'bacon',
  'prosciutto': 'ham',
  'tacchino': 'turkey',
  'anatra': 'duck',
  'pesce': 'fish',
  'salmone': 'salmon',
  'tonno': 'tuna',
  'merluzzo': 'cod',
  'gamberi': 'prawns',
  'gamberetti': 'prawns',
  'cozze': 'mussels',
  'vongole': 'clams',
  'calamari': 'squid',
  'acciughe': 'anchovy',
  'uova': 'egg',
  'uovo': 'egg',
  'latte': 'milk',
  'burro': 'butter',
  'panna': 'cream',
  'yogurt': 'yogurt',
  'formaggio': 'cheese',
  'parmigiano': 'parmesan',
  'mozzarella': 'mozzarella',
  'ricotta': 'ricotta',
  'pecorino': 'pecorino',
  'mascarpone': 'mascarpone',
  'farina': 'flour',
  'zucchero': 'sugar',
  'riso': 'rice',
  'pasta': 'pasta',
  'spaghetti': 'spaghetti',
  'pane': 'bread',
  'patate': 'potatoes',
  'patata': 'potatoes',
  'pomodoro': 'tomato',
  'pomodori': 'tomatoes',
  'passata': 'passata',
  'cipolla': 'onion',
  'cipolle': 'onion',
  'aglio': 'garlic',
  'carote': 'carrots',
  'carota': 'carrots',
  'sedano': 'celery',
  'zucchine': 'zucchini',
  'zucchina': 'zucchini',
  'melanzane': 'aubergine',
  'melanzana': 'aubergine',
  'peperoni': 'pepper',
  'peperone': 'pepper',
  'funghi': 'mushrooms',
  'spinaci': 'spinach',
  'piselli': 'peas',
  'fagioli': 'beans',
  'ceci': 'chickpeas',
  'lenticchie': 'lentils',
  'cavolfiore': 'cauliflower',
  'broccoli': 'broccoli',
  'cavolo': 'cabbage',
  'zucca': 'pumpkin',
  'insalata': 'lettuce',
  'limone': 'lemon',
  'arancia': 'orange',
  'mele': 'apples',
  'mela': 'apples',
  'fragole': 'strawberries',
  'banane': 'banana',
  'cioccolato': 'chocolate',
  'miele': 'honey',
  'olio': 'olive oil',
  'basilico': 'basil',
  'prezzemolo': 'parsley',
  'rosmarino': 'rosemary',
  'zenzero': 'ginger',
  'peperoncino': 'chilli',
  'noci': 'walnuts',
  'mandorle': 'almonds',
  'vino': 'wine',
};

/// Nome inglese per la ricerca online (se non è in elenco si usa così com'è).
String ingredientToEnglish(String it) {
  final k = it.trim().toLowerCase();
  return ingredientItEn[k] ?? k;
}
