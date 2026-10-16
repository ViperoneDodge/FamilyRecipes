import 'dart:convert';
import 'dart:typed_data';

import '../l10n.dart';
import '../models.dart';
import 'http_get.dart';

/// Ricetta da internet: da TheMealDB (www.themealdb.com, in inglese, da tradurre) oppure da un sito
/// di ricette nella lingua dell'app ([site] non vuoto: GialloZafferano, Marmiton…), già nella lingua giusta.
class OnlineRecipe {
  final String id;
  final String title;
  final String category;
  final String area;
  final String instructions;
  final String thumb;
  final String source;
  final List<Ingredient> ingredients;

  /// Nome del sito di ricette ('' = TheMealDB) e dati che solo i siti danno.
  final String site;
  final String intro;
  final int prepMinutes;
  final int cookMinutes;
  final int servings;
  final RecipeCategory? webCategory;

  /// Foto dei passaggi dai siti ('' = nessuna), una per ogni elemento di [steps].
  final List<String> stepImages;

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
    this.site = '',
    this.intro = '',
    this.prepMinutes = 0,
    this.cookMinutes = 0,
    this.servings = 4,
    this.webCategory,
    this.stepImages = const [],
    this.original,
    String? categoryText,
    String? areaText,
    List<String>? steps,
  })  : _categoryText = categoryText,
        _areaText = areaText,
        _steps = steps;

  bool get translated => original != null;

  /// Foto del passaggio [i] ('' = nessuna).
  String stepImage(int i) => i < stepImages.length ? stepImages[i] : '';

  /// Da un sito nella lingua dell'app: niente traduzione.
  bool get fromSite => site.isNotEmpty;

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
    String str(String key) => (j[key] as String?)?.trim() ?? '';
    return OnlineRecipe(
      id: '${j['idMeal'] ?? ''}',
      title: str('strMeal'),
      category: str('strCategory'),
      area: str('strArea'),
      instructions: str('strInstructions'),
      thumb: str('strMealThumb'),
      source: str('strSource'),
      ingredients: [
        for (var i = 1; i <= 20; i++)
          if (str('strIngredient$i').isNotEmpty) Ingredient(name: str('strIngredient$i'), amount: str('strMeasure$i')),
      ],
    );
  }

  /// Categoria del ricettario più vicina a quella di TheMealDB.
  RecipeCategory get recipeCategory =>
      webCategory ??
      switch (category.toLowerCase()) {
        'dessert' => RecipeCategory.dolci,
        'starter' => RecipeCategory.antipasti,
        'side' => RecipeCategory.contorni,
        'pasta' || 'breakfast' => RecipeCategory.primi,
        _ => RecipeCategory.secondi,
      };

  /// Passaggi: un paragrafo per passaggio, senza le righe "STEP 1".
  List<String> get steps {
    if (_steps != null) return _steps;
    return [
      for (final raw in instructions.split(RegExp(r'\r?\n')))
        raw.trim().replaceFirst(RegExp(r'^(step\s*\d+[:.)]?|\d+[.)])\s*', caseSensitive: false), ''),
    ].where((t) => t.isNotEmpty).toList();
  }

  /// Riconoscimento della fonte, messo in fondo alla ricetta.
  String get credit => [
        fromSite
            ? tr('online.creditSite', {'title': title, 'site': site})
            : tr('online.credit', {'title': original?.title ?? title}),
        if (source.isNotEmpty) tr('online.creditSource', {'url': source}),
        if (translated) tr('online.creditTranslated'),
      ].join('\n');

  /// Ricetta del ricettario (senza foto: la copertina si scarica a parte); la fonte va nei consigli.
  Recipe toRecipe() => Recipe(
        category: recipeCategory,
        title: title,
        intro: fromSite
            ? intro
            : (area.isNotEmpty && area.toLowerCase() != 'unknown' ? tr('online.cuisine', {'area': areaText}) : ''),
        prepMinutes: prepMinutes,
        cookMinutes: cookMinutes,
        servings: fromSite ? servings : 4,
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

  static Future<dynamic> _get(String path) async => jsonDecode(utf8.decode(await httpGet('$_base/$path')));

  static List<OnlineRecipe> parseMeals(dynamic j) {
    final meals = (j is Map ? j['meals'] : null) as List?;
    if (meals == null) return [];
    return [for (final m in meals) OnlineRecipe.fromJson(Map<String, dynamic>.from(m as Map))];
  }

  /// Una ricetta a caso.
  static Future<OnlineRecipe?> random() async => parseMeals(await _get('random.php')).firstOrNull;

  static Future<OnlineRecipe?> lookup(String id) async =>
      parseMeals(await _get('lookup.php?i=${Uri.encodeQueryComponent(id)}')).firstOrNull;

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
    try {
      return await httpGet(url, userAgent: browserUserAgent, maxBytes: 15 * 1024 * 1024);
    } catch (_) {
      return null;
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
