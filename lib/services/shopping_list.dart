import '../models.dart';
import 'dose_scaler.dart';

/// Una voce della lista della spesa: un ingrediente con le quantità sommate (per unità) e le ricette
/// che lo usano.
class ShoppingItem {
  final String name;

  /// Quantità già sommate e scritte ("1,5 kg", "3 cucchiai", "4").
  final List<String> amounts;

  /// Quantità che non si possono sommare ("q.b.", "un pizzico").
  final List<String> notes;

  /// Titoli delle ricette che lo usano.
  final List<String> recipes;

  /// Volte in cui compare nel piano (stesso piatto in giorni diversi conta più volte).
  final int uses;

  /// Voce unica della dispensa (sale, spezie, olio, aceto, acqua…): [recipes] contiene gli ingredienti
  /// da controllare, senza quantità.
  final bool pantry;

  const ShoppingItem(this.name, this.amounts, this.notes, this.recipes, this.uses, {this.pantry = false});

  String get amountText => [...amounts, ...notes].join(' + ');
}

/// Lista della spesa dalla pianificazione: ogni ricetta scalata sulle porzioni del pasto, ingredienti
/// uguali sommati (anche tra ricette diverse: patate di "pasta e patate" e di "patate al forno").
class ShoppingList {
  // unità → (chiave comune, fattore verso la chiave comune)
  static const Map<String, (String, double)> _units = {
    'g': ('g', 1), 'gr': ('g', 1), 'gr.': ('g', 1), 'grammi': ('g', 1), 'grammo': ('g', 1), 'gram': ('g', 1),
    'grams': ('g', 1), 'gramm': ('g', 1), 'grammes': ('g', 1), 'gramos': ('g', 1),
    'kg': ('g', 1000), 'kg.': ('g', 1000), 'chili': ('g', 1000), 'chilo': ('g', 1000), 'kilo': ('g', 1000),
    'kilos': ('g', 1000), 'chilogrammi': ('g', 1000), 'mg': ('g', 0.001),
    'ml': ('ml', 1), 'millilitri': ('ml', 1), 'cl': ('ml', 10), 'dl': ('ml', 100),
    'l': ('ml', 1000), 'lt': ('ml', 1000), 'litri': ('ml', 1000), 'litro': ('ml', 1000), 'liter': ('ml', 1000),
    'litre': ('ml', 1000), 'liters': ('ml', 1000), 'litres': ('ml', 1000), 'litros': ('ml', 1000),
    'cucchiaio': ('tbsp', 1), 'cucchiai': ('tbsp', 1), 'tbsp': ('tbsp', 1), 'tablespoon': ('tbsp', 1),
    'tablespoons': ('tbsp', 1), 'cucchiaino': ('tsp', 1), 'cucchiaini': ('tsp', 1), 'tsp': ('tsp', 1),
    'teaspoon': ('tsp', 1), 'teaspoons': ('tsp', 1), 'tazza': ('cup', 1), 'tazze': ('cup', 1),
    'cup': ('cup', 1), 'cups': ('cup', 1), 'pz': ('', 1), 'pz.': ('', 1), 'pezzi': ('', 1), 'pezzo': ('', 1),
  };

  // Dispensa: si controllano, non si sommano (parole intere, anche nelle lingue più comuni).
  static const Set<String> _pantryWords = {
    'sale', 'pepe', 'acqua', 'olio', 'aceto', 'spezie', 'origano', 'cannella', 'noce moscata', 'paprika', 'curry',
    'cumino', 'curcuma', 'peperoncino', 'chiodi di garofano', 'chiodo di garofano', 'alloro', 'timo', 'zafferano',
    'zenzero in polvere', 'coriandolo', 'finocchietto', 'semi di finocchio',
    'salt', 'pepper', 'water', 'oil', 'vinegar', 'spices', 'oregano', 'cinnamon', 'nutmeg', 'cumin', 'turmeric',
    'chili flakes', 'cloves', 'bay leaf', 'bay leaves', 'thyme', 'saffron', 'sel', 'poivre', 'eau', 'huile',
    'vinaigre', 'salz', 'pfeffer', 'wasser', 'ol', 'essig', 'sal', 'pimienta', 'agua', 'aceite', 'vinagre',
    'pimenta', 'azeite', 'oleo',
  };

  static bool _isPantry(String folded) {
    final words = folded.split(RegExp(r"[^a-z0-9à-ÿ]+")).where((w) => w.isNotEmpty).toList();
    final joined = ' ${words.join(' ')} ';
    // "pepe nero", "olio extravergine", "sale grosso" sì; "peperoni", "insalata" no.
    for (final w in _pantryWords) {
      if (joined.startsWith(' $w ')) return true;
    }
    // "un pizzico di sale", "olio e aceto": anche se la parola non è la prima ma il nome è corto.
    return words.length <= 4 && words.every((w) => _pantryWords.contains(w) || _glue.contains(w));
  }

  static const Set<String> _glue = {'e', 'di', 'q', 'b', 'qb', 'and', 'of', 'et', 'de', 'und', 'y', 'un', 'pizzico'};

  // Uova: intere, tuorli e albumi (parole iniziali, in più lingue).
  static const List<String> _yolk = ['tuorl', 'rosso d uovo', 'rossi d uovo', 'yolk', 'egg yolk', 'jaune', 'eigelb', 'yema', 'gema'];
  static const List<String> _white = ['albume', 'albumi', 'bianco d uovo', 'bianchi d uovo', 'egg white', 'blanc', 'eiweiss', 'clara'];
  static const List<String> _whole = ['uovo', 'uova', 'egg', 'eggs', 'oeuf', 'oeufs', 'ei', 'eier', 'huevo', 'huevos', 'ovo', 'ovos'];

  /// Peso medio (g, senza guscio) di un uovo medio: intero, tuorlo, albume. Servono per le dosi a peso
  /// ("120 g di albumi" = 4 albumi, arrotondando per eccesso).
  static const Map<String, double> eggGrams = {'e': 50, 'y': 18, 'w': 32};

  /// "y" tuorli, "w" albumi, "e" uova intere; null se non sono uova.
  static String? _eggKind(String folded) {
    final t = folded.replaceAll(RegExp(r"[^a-z0-9 ]+"), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    bool starts(List<String> ws) => ws.any((w) => t == w || t.startsWith('$w ') || t.startsWith(w) && w.length > 4);
    if (starts(_yolk)) return 'y';
    if (starts(_white)) return 'w';
    final first = t.split(' ').first;
    if (_whole.contains(first)) return 'e';
    return null;
  }

  /// [plan]: le voci della settimana; [recipeById]: le ricette (quelle che non ci sono più si saltano).
  /// Le uova si contano insieme a tuorli e albumi (4 tuorli e 3 albumi = 4 uova; 4 uova e 3 tuorli = 7);
  /// sale, spezie, olio, aceto e acqua vanno in una sola voce [pantryLabel] da controllare.
  static List<ShoppingItem> build(
    List<PlanEntry> plan,
    Recipe? Function(String id) recipeById, {
    bool comma = true,
    String pantryLabel = 'Dispensa',
    String eggsLabel = 'Uova',
  }) {
    final pantry = <String, String>{}; // chiave → nome come scritto
    final pantryRecipes = <String>{};
    var whole = 0.0, yolks = 0.0, whites = 0.0;
    final eggRecipes = <String>{};
    var eggUses = 0;
    final totals = <String, Map<String, double>>{}; // nome → unità → quantità
    final unitLabel = <String, String>{}; // "nome|unità" → come scriverla (la prima incontrata)
    final notes = <String, Set<String>>{};
    final names = <String, String>{};
    final recipes = <String, Set<String>>{};
    final uses = <String, int>{};
    final order = <String>[];

    for (final e in plan) {
      final r = recipeById(e.recipeId);
      if (r == null) continue;
      final factor = r.servings > 0 ? e.servings / r.servings : 1.0;
      for (final ing in r.ingredients) {
        var name = ing.name.trim();
        var amount = ing.amount.trim();
        if (name.isEmpty) {
          if (amount.isEmpty) continue;
          // Tutto nel campo della dose ("2 uova"): il nome è il testo dopo il numero.
          final p = DoseScaler.parse(amount);
          if (p == null || p.rest.isEmpty) continue;
          name = p.rest;
          amount = _fmt(p.value, comma);
        }
        final key = _key(name);
        if (key.isEmpty) continue;
        if (_isPantry(key)) {
          pantry.putIfAbsent(key, () => name[0].toUpperCase() + name.substring(1));
          pantryRecipes.add(r.displayTitle);
          continue;
        }
        final egg = _eggKind(key);
        if (egg != null) {
          final p = DoseScaler.parse(amount.isEmpty ? '1' : amount);
          final unit = p == null ? null : _units[p.rest.split(RegExp(r'\s+')).first.toLowerCase()];
          // Uova contate, oppure a peso/volume ("120 g di albumi", "100 ml di albumi") convertite con il
          // peso medio di un uovo medio.
          final byWeight = unit != null && (unit.$1 == 'g' || unit.$1 == 'ml');
          if (p != null && (unit == null || unit.$1 == '' || byWeight)) {
            var n = p.value * factor;
            if (byWeight) n = n * unit.$2 / eggGrams[egg]!;
            if (egg == 'y') {
              yolks += n;
            } else if (egg == 'w') {
              whites += n;
            } else {
              whole += n;
            }
            eggRecipes.add(r.displayTitle);
            eggUses++;
            continue;
          }
        }
        if (!names.containsKey(key)) {
          names[key] = name[0].toUpperCase() + name.substring(1);
          order.add(key);
        }
        (recipes[key] ??= {}).add(r.displayTitle);
        uses[key] = (uses[key] ?? 0) + 1;
        final p = DoseScaler.parse(amount);
        if (p == null) {
          if (amount.isNotEmpty) (notes[key] ??= {}).add(amount);
          continue;
        }
        final word = p.rest.split(RegExp(r'\s+')).first.toLowerCase();
        final known = _units[word];
        final String unit;
        double value = p.value * factor;
        if (known != null) {
          unit = known.$1;
          value *= known.$2;
          if (unit != 'g' && unit != 'ml') unitLabel.putIfAbsent('$key|$unit', () => p.rest);
        } else {
          unit = p.rest.toLowerCase();
          unitLabel.putIfAbsent('$key|$unit', () => p.rest);
        }
        final t = totals[key] ??= {};
        t[unit] = (t[unit] ?? 0) + value;
      }
    }

    final eggs = (whole + (yolks > whites ? yolks : whites) - 1e-9).ceil();
    return [
      if (eggUses > 0) ShoppingItem(eggsLabel, ['$eggs'], const [], eggRecipes.toList(), eggUses),
      for (final k in order)
        ShoppingItem(
          names[k]!,
          [
            for (final u in (totals[k] ?? const <String, double>{}).entries)
              _amount(u.value, u.key, unitLabel['$k|${u.key}'], comma),
          ],
          (notes[k] ?? const <String>{}).toList(),
          (recipes[k] ?? const <String>{}).toList(),
          uses[k] ?? 0,
        ),
    ]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()))
      // La dispensa per ultima: è un promemoria, non qualcosa da comprare per forza.
      ..addAll([
        if (pantry.isNotEmpty)
          ShoppingItem(pantryLabel, const [], const [], (pantry.values.toList()..sort()), pantryRecipes.length, pantry: true),
      ]);
  }

  static String _key(String name) => foldForSearch(name).trim();

  static String _fmt(double v, bool comma) => DoseScaler.format(v, comma: comma);

  static String _amount(double v, String unit, String? label, bool comma) {
    switch (unit) {
      case 'g':
        return v >= 1000 ? '${_fmt(v / 1000, comma)} kg' : '${_fmt(v, comma)} g';
      case 'ml':
        return v >= 1000 ? '${_fmt(v / 1000, comma)} l' : '${_fmt(v, comma)} ml';
      case '':
        return _fmt(v, comma);
      default:
        return '${_fmt(v, comma)} ${label ?? unit}';
    }
  }
}
