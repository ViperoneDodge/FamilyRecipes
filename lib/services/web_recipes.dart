import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../l10n.dart';
import '../models.dart';
import 'http_get.dart';
import 'online_recipes.dart';
import 'recipe_words.dart';

/// Un sito di ricette nella lingua dell'app: ricerca per parole e lettura della ricetta dalla pagina.
class RecipeSite {
  final String name;
  final String home;
  final String Function(String query) search;

  /// Indirizzi delle ricette nella pagina dei risultati (anche relativi a [home]).
  final RegExp link;

  /// Parole per la ricetta a sorpresa: se ne cerca una a caso.
  final List<String> surprise;

  const RecipeSite({required this.name, required this.home, required this.search, required this.link, required this.surprise});
}

String _q(String s) => Uri.encodeComponent(s.trim());

/// Siti per lingua. Leggono la ricetta dai dati strutturati della pagina (schema.org/Recipe),
/// gli stessi che usano i motori di ricerca; per le altre lingue resta TheMealDB tradotto.
final Map<String, RecipeSite> recipeSites = {
  'it': RecipeSite(
    name: 'GialloZafferano',
    home: 'https://www.giallozafferano.it',
    search: (q) => 'https://www.giallozafferano.it/ricerca-ricette/${_q(q)}/',
    link: RegExp(r'https://ricette\.giallozafferano\.it/[A-Za-z0-9_\-]+\.html'),
    surprise: ['pasta', 'risotto', 'pollo', 'zucchine', 'melanzane', 'torta', 'biscotti', 'polpette', 'zuppa', 'salmone',
      'patate', 'funghi', 'ricotta', 'lasagne', 'frittata', 'peperoni', 'gnocchi', 'crostata', 'vitello', 'ceci'],
  ),
  'fr': RecipeSite(
    name: 'Marmiton',
    home: 'https://www.marmiton.org',
    search: (q) => 'https://www.marmiton.org/recettes/recherche.aspx?aqt=${Uri.encodeQueryComponent(q.trim())}',
    link: RegExp(r'(?:https://www\.marmiton\.org)?/recettes/recette_[A-Za-z0-9_\-]+\.aspx'),
    surprise: ['poulet', 'quiche', 'gratin', 'tarte', 'soupe', 'boeuf', 'saumon', 'courgette', 'gâteau', 'crêpes',
      'risotto', 'lentilles', 'clafoutis', 'pommes de terre', 'porc'],
  ),
  'de': RecipeSite(
    name: 'Chefkoch',
    home: 'https://www.chefkoch.de',
    search: (q) => 'https://www.chefkoch.de/rs/s0/${_q(q)}/Rezepte.html',
    link: RegExp(r'https://www\.chefkoch\.de/rezepte/\d+/[A-Za-z0-9_\-%.]+\.html'),
    surprise: ['Hähnchen', 'Kuchen', 'Auflauf', 'Suppe', 'Nudeln', 'Gulasch', 'Kartoffeln', 'Lachs', 'Spätzle', 'Salat',
      'Schnitzel', 'Zucchini', 'Linsen', 'Strudel', 'Knödel'],
  ),
  'en': RecipeSite(
    name: 'BBC Good Food',
    home: 'https://www.bbcgoodfood.com',
    search: (q) => 'https://www.bbcgoodfood.com/search?q=${Uri.encodeQueryComponent(q.trim())}',
    link: RegExp(r'(?:https://www\.bbcgoodfood\.com)?/recipes/(?!collection|category)[a-z0-9\-]+'),
    surprise: ['chicken', 'curry', 'pasta', 'soup', 'cake', 'salmon', 'risotto', 'pie', 'stew', 'salad', 'lamb',
      'brownies', 'lasagne', 'stir fry', 'crumble'],
  ),
  'es': RecipeSite(
    name: 'Cookpad',
    home: 'https://cookpad.com',
    search: (q) => 'https://cookpad.com/es/buscar/${_q(q)}',
    link: RegExp(r'(?:https://cookpad\.com)?/es/recetas/\d+[A-Za-z0-9_\-]*'),
    surprise: ['pollo', 'tortilla', 'arroz', 'lentejas', 'pescado', 'bizcocho', 'croquetas', 'paella', 'flan', 'garbanzos',
      'albóndigas', 'merluza', 'empanada', 'gazpacho'],
  ),
};

class WebRecipes {
  static final Random _rnd = Random();

  /// Il sito per la lingua dell'app, se c'è.
  static RecipeSite? get site => recipeSites[L10n.code];

  /// Pagina HTML come la chiede il browser di un telefono (al massimo 4 MB).
  static Future<String> fetch(String url) async {
    final bytes = await httpGet(
      url,
      userAgent: 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36',
      headers: {
        HttpHeaders.acceptHeader: 'text/html,application/xhtml+xml',
        HttpHeaders.acceptLanguageHeader: L10n.code,
      },
      maxBytes: 4 * 1024 * 1024,
    );
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Legge la ricetta da una pagina web qualsiasi che ha i dati schema.org/Recipe.
  static Future<OnlineRecipe?> read(String url) async => parsePage(await fetch(url), url);

  /// Indirizzi delle ricette nei risultati di una ricerca.
  static List<String> links(RecipeSite s, String html) => {
        for (final m in s.link.allMatches(html)) m[0]!.startsWith('/') ? '${s.home}${m[0]}' : m[0]!,
      }.toList();

  /// Ricette trovate sul sito con queste parole (al massimo [max], lette in parallelo).
  static Future<List<OnlineRecipe>> search(RecipeSite s, String query, {int max = 8}) async {
    final urls = links(s, await fetch(s.search(query))).take(max).toList();
    final res = await Future.wait(urls.map((u) => read(u).catchError((_) => null)));
    return res.whereType<OnlineRecipe>().toList();
  }

  /// Una ricetta a sorpresa: si cerca una parola a caso e si prende un risultato a caso.
  static Future<OnlineRecipe?> surprise(RecipeSite s) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final word = s.surprise[_rnd.nextInt(s.surprise.length)];
      try {
        final urls = links(s, await fetch(s.search(word)));
        if (urls.isEmpty) continue;
        final r = await read(urls[_rnd.nextInt(min(urls.length, 15))]);
        if (r != null && !r.isPartial) return r;
      } catch (_) {
        if (attempt == 2) rethrow;
      }
    }
    return null;
  }

  // ---- Lettura dei dati schema.org/Recipe ----

  static final RegExp _ldJson =
      RegExp(r'''<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>([\s\S]*?)</script>''', caseSensitive: false);

  static OnlineRecipe? parsePage(String html, String url) {
    for (final m in _ldJson.allMatches(html)) {
      dynamic data;
      try {
        data = jsonDecode(m[1]!.trim());
      } catch (_) {
        continue;
      }
      final node = _findRecipe(data);
      if (node != null) return _toRecipe(node, url, _siteName(html, url));
    }
    return null;
  }

  static Map<String, dynamic>? _findRecipe(dynamic d) {
    if (d is List) {
      for (final x in d) {
        final r = _findRecipe(x);
        if (r != null) return r;
      }
    } else if (d is Map) {
      final t = d['@type'];
      if (t == 'Recipe' || (t is List && t.contains('Recipe'))) return Map<String, dynamic>.from(d);
      for (final k in ['@graph', 'mainEntity', 'mainEntityOfPage']) {
        final r = _findRecipe(d[k]);
        if (r != null) return r;
      }
    }
    return null;
  }

  static String _siteName(String html, String url) {
    final m = RegExp(r'''<meta[^>]*property=["']og:site_name["'][^>]*content=["']([^"']+)''', caseSensitive: false)
        .firstMatch(html);
    if (m != null) return clean(m[1]!);
    for (final s in recipeSites.values) {
      if (url.contains(Uri.parse(s.home).host.replaceFirst('www.', ''))) return s.name;
    }
    return Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? '';
  }

  static OnlineRecipe _toRecipe(Map<String, dynamic> j, String url, String site) {
    final title = clean(_text(j['name']));
    final steps = <String>[];
    void addSteps(dynamic s) {
      if (s is String) {
        for (final p in clean(s, keepLines: true).split(RegExp(r'\n\s*\n|\n'))) {
          final t = p.trim().replaceFirst(RegExp(r'^\d+[.)]\s*'), '');
          if (t.isNotEmpty) steps.add(t);
        }
      } else if (s is List) {
        for (final x in s) {
          addSteps(x);
        }
      } else if (s is Map) {
        if (s['itemListElement'] != null) {
          addSteps(s['itemListElement']);
        } else {
          final t = clean(_text(s['text'] ?? s['name']));
          if (t.isNotEmpty) steps.add(t);
        }
      }
    }

    addSteps(j['recipeInstructions']);
    final ingredients = [
      for (final i in _list(j['recipeIngredient'] ?? j['ingredients']))
        if (clean(_text(i)) case final t when t.isNotEmpty) splitIngredient(t),
    ];
    final cat = clean(_text(_first(j['recipeCategory'])));
    final cuisine = clean(_text(_first(j['recipeCuisine'])));
    return OnlineRecipe(
      id: url,
      title: title,
      category: cat,
      area: cuisine,
      thumb: _image(j['image']),
      source: url,
      ingredients: ingredients,
      steps: steps,
      site: site,
      intro: clean(_text(j['description'])),
      prepMinutes: minutes(_text(j['prepTime'])),
      cookMinutes: minutes(_text(j['cookTime'])),
      servings: servings(j['recipeYield']),
      webCategory: RecipeWords.categoryFromLabel(cat) ?? RecipeWords.guessCategory(title),
    );
  }

  static List _list(dynamic v) => v is List ? v : (v == null ? const [] : [v]);
  static dynamic _first(dynamic v) => v is List ? (v.isEmpty ? null : v.first) : v;
  static String _text(dynamic v) => v == null ? '' : (v is Map ? '${v['name'] ?? v['text'] ?? ''}' : '$v');

  static String _image(dynamic v) {
    v = _first(v);
    if (v is Map) v = v['url'] ?? v['contentUrl'];
    final s = v == null ? '' : '$v'.trim();
    return s.startsWith('//') ? 'https:$s' : s;
  }

  /// Durata ISO 8601 ("PT1H30M") in minuti.
  static int minutes(String iso) {
    final m = RegExp(r'P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?', caseSensitive: false).firstMatch(iso.trim());
    if (m == null) return 0;
    int g(int i) => int.tryParse(m[i] ?? '') ?? 0;
    return g(1) * 1440 + g(2) * 60 + g(3);
  }

  static int servings(dynamic v) {
    for (final x in _list(v)) {
      final n = int.tryParse(RegExp(r'\d+').firstMatch('$x')?[0] ?? '');
      if (n != null && n > 0 && n < 100) return n;
    }
    return 4;
  }

  static const _units = r'(?:kg|g|gr|hg|mg|l|dl|cl|ml|oz|lb|lbs|cups?|tbsp|tsp|tablespoons?|teaspoons?|EL|TL|Prise|Stk\.?|'
      r'cucchiai(?:ni|no|o)?|bicchier[ei]|tazz[ae]|spicchi?o?|fett[ae]|bustin[ae]|cubett[oi]|vasett[oi]|pizzico|'
      r'cuillères?(?:\s+à\s+(?:soupe|café))?|c\.\s*à\s*[sc]\.?|pincée|gousses?|cucharad(?:as?|itas?)|tazas?|pizca|dientes?)';

  /// "200 g di farina" → farina | 200 g; "Farina 00 300 g" → Farina 00 | 300 g; "Sale q.b." → Sale | q.b.
  static Ingredient splitIngredient(String s) {
    final lead = RegExp('^((?:\\d+(?:[.,/]\\d+)?|½|¼|¾|⅓)(?:\\s*-\\s*\\d+)?\\s*$_units?\\.?)\\s+(?:(?:di|de|d\'|of|von)\\s+)?(.+)\$',
            caseSensitive: false)
        .firstMatch(s);
    if (lead != null && lead[2]!.trim().isNotEmpty) return Ingredient(name: _cap(lead[2]!.trim()), amount: lead[1]!.trim());
    final trail = RegExp('^(.+?)\\s+((?:\\d+(?:[.,/]\\d+)?)\\s*$_units?\\.?|q\\.?\\s?b\\.?|qb|to taste|nach Belieben|al gusto)\$',
            caseSensitive: false)
        .firstMatch(s);
    if (trail != null) return Ingredient(name: trail[1]!.trim(), amount: trail[2]!.trim());
    return Ingredient(name: s);
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Testo senza tag HTML né entità.
  static String clean(String s, {bool keepLines = false}) {
    var t = s
        .replaceAll(RegExp(r'<br\s*/?>|</p>|</li>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    t = t.replaceAllMapped(RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);'), (m) {
      final e = m[1]!;
      if (e.startsWith('#')) {
        final code = e[1] == 'x' || e[1] == 'X' ? int.tryParse(e.substring(2), radix: 16) : int.tryParse(e.substring(1));
        return code == null ? m[0]! : String.fromCharCode(code);
      }
      return _entities[e] ?? m[0]!;
    });
    t = t.replaceAll(' ', ' ');
    if (keepLines) return t.split('\n').map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim()).join('\n').trim();
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static const Map<String, String> _entities = {
    'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' ', 'egrave': 'è', 'eacute': 'é',
    'agrave': 'à', 'ograve': 'ò', 'ugrave': 'ù', 'igrave': 'ì', 'Egrave': 'È', 'ecirc': 'ê', 'ccedil': 'ç',
    'uuml': 'ü', 'ouml': 'ö', 'auml': 'ä', 'szlig': 'ß', 'ntilde': 'ñ', 'aacute': 'á', 'iacute': 'í',
    'oacute': 'ó', 'uacute': 'ú', 'rsquo': '’', 'lsquo': '‘', 'rdquo': '”', 'ldquo': '“', 'hellip': '…',
    'ndash': '–', 'mdash': '—', 'deg': '°', 'frac12': '½', 'frac14': '¼', 'frac34': '¾',
  };
}

/// Primo link http(s) in un testo condiviso (es. "Guarda questa ricetta https://…").
String? firstUrl(String text) => RegExp(r'https?://[^\s<>"]+').firstMatch(text)?[0];
