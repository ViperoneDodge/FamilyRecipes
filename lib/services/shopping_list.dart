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

  const ShoppingItem(this.name, this.amounts, this.notes, this.recipes, this.uses);

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

  /// [plan]: le voci della settimana; [recipeById]: le ricette (quelle che non ci sono più si saltano).
  static List<ShoppingItem> build(
    List<PlanEntry> plan,
    Recipe? Function(String id) recipeById, {
    bool comma = true,
  }) {
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

    return [
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
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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
