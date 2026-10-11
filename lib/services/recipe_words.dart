import '../models.dart';

/// Parole delle ricette in più lingue, usate da tutte le letture (foto, file, siti di ricette):
/// nomi delle categorie, difficoltà e costo, parole del titolo che suggeriscono la categoria.
class RecipeWords {
  static String _key(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-zà-öø-ÿß]'), '');

  /// Categoria dal suo nome ("Primi", "Dessert", "Plat principal"…); null se non è un nome noto.
  static RecipeCategory? categoryFromLabel(String? label) {
    final k = _key(label ?? '');
    if (k.isEmpty) return null;
    for (final c in RecipeCategory.values) {
      if (c.name == k) return c;
    }
    for (final e in _labels.entries) {
      if (e.value.any((w) => k == w || k.startsWith(w))) return e.key;
    }
    return null;
  }

  static const Map<RecipeCategory, List<String>> _labels = {
    RecipeCategory.menu: ['menù', 'menu', 'menùcompleti', 'menucompleti'],
    RecipeCategory.aperitivi: ['aperitiv', 'fingerfood', 'apéritif', 'aperitif', 'drink', 'cocktail', 'bevand', 'boisson', 'getränk'],
    RecipeCategory.antipasti: ['antipast', 'starter', 'appetizer', 'entrée', 'entree', 'vorspeise', 'entrante', 'tapas'],
    RecipeCategory.primi: ['primi', 'primo', 'primipiatti', 'firstcourse', 'pasta', 'risott', 'zupp', 'minestr', 'soup', 'suppe', 'soupe', 'sopa', 'nudel'],
    RecipeCategory.secondi: ['second', 'main', 'platprincipal', 'plat', 'hauptgericht', 'hauptspeise', 'platoprincipal', 'segundo', 'dinner', 'lunch'],
    RecipeCategory.contorni: ['contorn', 'side', 'beilage', 'accompagnement', 'guarnici', 'acompañamiento', 'salad', 'insalat', 'salat'],
    RecipeCategory.dolci: ['dolc', 'dessert', 'postre', 'nachspeise', 'nachtisch', 'kuchen', 'torte', 'gâteau', 'gateau', 'cake', 'baking', 'backen', 'pâtisserie', 'patisserie', 'biscott', 'cookie'],
    RecipeCategory.liquori: ['liquor', 'liqueur', 'likör', 'licor', 'amari', 'distillat'],
    RecipeCategory.conserve: ['conserv', 'preserve', 'confettur', 'marmellat', 'jam', 'confiture', 'marmelade', 'einmach', 'pickle'],
  };

  /// Categoria proposta dalle parole del titolo (o di un testo), anche in altre lingue.
  static RecipeCategory guessCategory(String text) {
    final t = text.toLowerCase();
    bool any(List<String> w) => w.any(t.contains);
    if (any(['menù', 'menu '])) return RecipeCategory.menu;
    if (any(['liquore', 'limoncello', 'nocino', 'amaro', 'grappa', 'rosolio', 'mirto', 'genziana', 'elicriso', 'liqueur', 'likör'])) {
      return RecipeCategory.liquori;
    }
    if (any(['marmellata', 'confettura', 'conserva', "sott'olio", 'sottolio', 'sottaceto', 'passata', 'salsa di pomodoro',
      'giardiniera', 'jam', 'pickle', 'confiture', 'marmelade'])) {
      return RecipeCategory.conserve;
    }
    if (any(['spritz', 'cocktail', 'aperitivo', 'negroni', 'sangria'])) return RecipeCategory.aperitivi;
    if (any(['torta', 'dolce', 'biscott', 'crostata', 'tiramis', 'gelato', 'budino', 'panna cotta', 'ciambell', 'frittell',
      'cake', 'cookie', 'pie', 'dessert', 'muffin', 'crema', 'semifreddo', 'strudel', 'gâteau', 'tarte', 'kuchen', 'torte', 'tarta', 'flan'])) {
      return RecipeCategory.dolci;
    }
    if (any(['pasta', 'spaghetti', 'risotto', 'lasagn', 'gnocchi', 'zuppa', 'minestr', 'tagliatelle', 'ravioli', 'tortellini',
      'penne', 'fusilli', 'orecchiette', 'pappardelle', 'cannelloni', 'polenta', 'soup', 'noodle', 'soupe', 'suppe', 'nudeln', 'sopa'])) {
      return RecipeCategory.primi;
    }
    if (any(['insalata', 'contorno', 'patate', 'verdure', 'peperonata', 'caponata', 'salad', 'purè', 'pure ', 'salade', 'salat', 'ensalada'])) {
      return RecipeCategory.contorni;
    }
    if (any(['crostini', 'bruschett', 'antipasto', 'tartine', 'frittatine', 'vol-au-vent', 'starter'])) {
      return RecipeCategory.antipasti;
    }
    return RecipeCategory.secondi;
  }

  /// Difficoltà da una parola ("Facile", "Media", "easy", "difficile"…); null se non riconosciuta.
  static Difficulty? difficulty(String? text) {
    final k = _key(text ?? '');
    if (k.isEmpty) return null;
    for (final d in Difficulty.values) {
      if (d.name.toLowerCase() == k) return d;
    }
    if (k.startsWith('molto') || k == 'veryeasy' || k == 'trèsfacile' || k == 'trèsfacile') return Difficulty.veryEasy;
    if (k.startsWith('facil') || k == 'bassa' || k == 'easy' || k == 'einfach' || k == 'leicht') return Difficulty.easy;
    if (k.startsWith('medi') || k == 'moyen' || k == 'moyenne' || k == 'normal') return Difficulty.medium;
    if (k.startsWith('diffic') || k == 'alta' || k == 'hard' || k == 'schwer' || k == 'difícil') return Difficulty.hard;
    return null;
  }

  /// Costo da una parola ("Basso", "medium"…); null se non riconosciuto.
  static Cost? cost(String? text) {
    final k = _key(text ?? '');
    if (k.isEmpty) return null;
    for (final c in Cost.values) {
      if (c.name.toLowerCase() == k) return c;
    }
    if (k.startsWith('moltobass')) return Cost.veryLow;
    if (k.startsWith('bass')) return Cost.low;
    if (k.startsWith('medi')) return Cost.medium;
    if (k.startsWith('alt') || k.startsWith('elevat')) return Cost.high;
    return null;
  }
}
