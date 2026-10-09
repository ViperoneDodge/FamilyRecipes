import '../models.dart';

/// Trasforma il testo letto da una foto o da un PDF (quaderno, libro, stampa) in una bozza di
/// ricetta: titolo, ingredienti con le dosi, passaggi, tempi, persone, difficoltà e categoria.
/// Le regole valgono per testi in italiano e in inglese; quello che non si riconosce resta da
/// completare a mano nell'editor.
class RecipeTextParser {
  static final RegExp _ingHeader =
      RegExp(r'^(ingredienti|ingredients|occorrente|per la ricetta|ti servono)\b', caseSensitive: false);
  static final RegExp _stepHeader = RegExp(
      r'^(preparazione|procedimento|procedura|esecuzione|metodo|method|directions|instructions|preparation|steps)\b',
      caseSensitive: false);
  static final RegExp _tipHeader = RegExp(
      r'^(consigli|consiglio|note|nota|varianti|variante|conservazione|tips|notes|variations)\b',
      caseSensitive: false);

  /// Unità e parole tipiche delle dosi.
  static const String _units = r'(kg|g|gr|grammi|hg|mg|l|lt|litri?|dl|cl|ml|cucchiai(?:ni|no)?|cucchiaio|cucchiaini?|'
      r'bicchier[ei]|tazz[ae]|tazzin[ae]|pizzic(?:o|hi)|spicchi?|foglie|foglia|rametti?|mazzett[oi]|fett[ae]|'
      r'bustin[ae]|confezion[ei]|scatol[ae]|vasett[oi]|noce|cups?|tbsp|tsp|tablespoons?|teaspoons?|oz|lb|lbs|pinch|cloves?)';
  static final RegExp _qb =
      RegExp(r'\bq\.?\s?b\.?(?=\s|$)|\bquanto basta\b|\ba piacere\b|\bto taste\b', caseSensitive: false);
  static final RegExp _amountStart = RegExp(
      '^((?:\\d+[\\.,]?\\d*|\\d+/\\d+|½|¼|¾|⅓)(?:\\s*[-–]\\s*\\d+)?\\s*(?:$_units\\b\\.?)?(?:\\s+di)?)\\s+(.+)\$',
      caseSensitive: false);
  static final RegExp _amountEnd = RegExp(
      '^(.+?)[\\s:.…\\-–]+((?:\\d+[\\.,]?\\d*|\\d+/\\d+|½|¼|¾)(?:\\s*[-–]\\s*\\d+)?\\s*(?:$_units\\b\\.?)?)\$',
      caseSensitive: false);
  static final RegExp _bullet = RegExp(r'^[\-•·*–—▪◦●]\s*');
  static final RegExp _numbered = RegExp(r'^(?:passo\s*|step\s*)?(\d{1,2})\s*[\.\)\-:]\s*(.*)$', caseSensitive: false);

  static Recipe parse(String raw) {
    final lines = raw
        .replaceAll('\r', '\n')
        .split('\n')
        .map((l) => l.trim().replaceAll(RegExp(r'\s+'), ' '))
        .where((l) => l.isNotEmpty)
        .toList();
    final r = Recipe(category: RecipeCategory.secondi, servings: 4);
    if (lines.isEmpty) return r;

    // Informazioni sparse: tempi, persone, difficoltà (si tolgono dal testo).
    final rest = <String>[];
    for (final l in lines) {
      if (_meta(l, r)) continue;
      rest.add(l);
    }

    // Sezioni.
    String? title;
    final intro = <String>[], ings = <String>[], steps = <String>[], tips = <String>[];
    var section = 'intro';
    for (final l in rest) {
      final low = l.toLowerCase();
      if (_ingHeader.hasMatch(low)) {
        section = 'ing';
        final after = l.replaceFirst(RegExp(r'^[^:]*:\s*'), '');
        if (after != l && after.isNotEmpty) ings.add(after);
        continue;
      }
      if (_stepHeader.hasMatch(low)) {
        section = 'steps';
        final after = l.replaceFirst(RegExp(r'^[^:]*:\s*'), '');
        if (after != l && after.isNotEmpty) steps.add(after);
        continue;
      }
      if (_tipHeader.hasMatch(low) && l.length < 40) {
        section = 'tips';
        continue;
      }
      if (title == null && section == 'intro' && l.length >= 3 && l.length <= 70 && !_looksIngredient(l)) {
        title = l.replaceAll(RegExp(r'[\.:]+$'), '');
        continue;
      }
      switch (section) {
        case 'ing':
          // Dopo la lista degli ingredienti, una frase lunga senza dosi è già il procedimento.
          if (!_looksIngredient(l) &&
              ings.isNotEmpty &&
              (l.length > 40 || l.endsWith('.') || l.split(' ').length > 6)) {
            section = 'steps';
            steps.add(l);
          } else {
            ings.add(l);
          }
          break;
        case 'steps':
          steps.add(l);
          break;
        case 'tips':
          tips.add(l);
          break;
        default:
          if (_looksIngredient(l)) {
            section = 'ing';
            ings.add(l);
          } else {
            intro.add(l);
          }
      }
    }
    // Nessuna intestazione "Preparazione": il testo dopo il titolo che non è un ingrediente è il procedimento.
    if (steps.isEmpty && intro.length > 1 && ings.isNotEmpty) {
      steps.addAll(intro.skip(1));
      intro.removeRange(1, intro.length);
    }

    r.title = title ?? '';
    r.intro = _joinParagraph(intro);
    r.ingredients = [for (final l in ings) ..._ingredients(l)];
    r.steps = [for (final s in _steps(steps)) RecipeStep(text: s)];
    r.tips = _joinParagraph(tips);
    r.category = guessCategory('${r.title} ${r.intro}');
    return r;
  }

  static bool _looksIngredient(String l) {
    final t = l.replaceFirst(_bullet, '');
    if (t.length > 70) return false;
    if (_bullet.hasMatch(l) && t.length < 50) return true;
    if (_qb.hasMatch(t)) return true;
    if (_amountStart.hasMatch(t)) return true;
    final e = _amountEnd.firstMatch(t);
    return e != null && e.group(1)!.split(' ').length <= 6;
  }

  /// Un ingrediente, o più se sulla stessa riga separati da virgola con le loro dosi.
  static List<Ingredient> _ingredients(String line) {
    var t = line.replaceFirst(_bullet, '').trim();
    final parts = t.contains(',') && RegExp(r'\d').allMatches(t).length > 1 ? t.split(',') : [t];
    final out = <Ingredient>[];
    for (var p in parts) {
      p = p.trim();
      if (p.isEmpty) continue;
      final qb = _qb.firstMatch(p);
      if (qb != null) {
        final name = p.replaceRange(qb.start, qb.end, '').replaceAll(RegExp(r'[\s:\.…\-–]+$'), '').trim();
        out.add(Ingredient(name: _cap(name), amount: 'q.b.'));
        continue;
      }
      final s = _amountStart.firstMatch(p);
      if (s != null) {
        out.add(Ingredient(
            name: _cap(s.group(3)!.replaceFirst(RegExp(r'^di\s+', caseSensitive: false), '')),
            amount: _fixAmount(s.group(1)!.replaceFirst(RegExp(r'\s+di$', caseSensitive: false), ''))));
        continue;
      }
      final e = _amountEnd.firstMatch(p);
      if (e != null) {
        out.add(Ingredient(name: _cap(e.group(1)!), amount: _fixAmount(e.group(2)!)));
        continue;
      }
      out.add(Ingredient(name: _cap(p)));
    }
    return out;
  }

  static String _fixAmount(String a) => a.trim().replaceAllMapped(
      RegExp(r'^(\d+[\.,]?\d*)\s*(g|gr|kg|ml|l|cl|dl)\b', caseSensitive: false),
      (m) => '${m[1]} ${m[2]!.toLowerCase() == 'gr' ? 'g' : m[2]!.toLowerCase()}');

  /// Passaggi: righe numerate, altrimenti frasi riunite (l'OCR spezza le righe) e divise sul punto finale.
  static List<String> _steps(List<String> lines) {
    if (lines.isEmpty) return [];
    final numbered = lines.where((l) => _numbered.hasMatch(l)).length;
    final out = <String>[];
    if (numbered >= 2) {
      for (final l in lines) {
        final m = _numbered.firstMatch(l);
        if (m != null) {
          out.add(m.group(2)!);
        } else if (out.isNotEmpty) {
          out[out.length - 1] = '${out.last} $l'.trim();
        } else {
          out.add(l);
        }
      }
    } else {
      var cur = '';
      for (final l in lines) {
        final clean = l.replaceFirst(_bullet, '');
        cur = cur.isEmpty ? clean : '$cur $clean';
        if (RegExp(r'[\.!]$').hasMatch(clean) && cur.length > 40) {
          out.add(cur);
          cur = '';
        }
      }
      if (cur.isNotEmpty) out.add(cur);
    }
    return out.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  static String _joinParagraph(List<String> lines) => lines.join(' ').trim();

  static String _cap(String s) {
    final t = s.trim().replaceAll(RegExp(r'^[:\-–\s]+|[:\-–\s]+$'), '');
    return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
  }

  /// Tempi, persone e difficoltà; true se la riga contiene solo queste informazioni.
  static bool _meta(String l, Recipe r) {
    final low = l.toLowerCase();
    var used = false;
    final serv = RegExp(
            r'(?:dosi\s+per|per|porzioni|serves|servings|for)\s*:?\s*(\d{1,2})\s*(?:persone|porzioni|people|servings|pers\.?)?',
            caseSensitive: false)
        .firstMatch(low);
    if (serv != null &&
        (low.contains('person') || low.contains('porzion') || low.contains('dosi') || low.contains('serv'))) {
      r.servings = int.parse(serv.group(1)!);
      used = true;
    }
    int? minutes(String key) {
      final m = RegExp('(?:$key)[^\\d]{0,20}(\\d+(?:[\\.,]\\d)?)\\s*(min|minuti|m\\b|h|ore|ora|hours?|hrs?)',
              caseSensitive: false)
          .firstMatch(low);
      if (m == null) return null;
      final v = double.parse(m.group(1)!.replaceAll(',', '.'));
      final u = m.group(2)!;
      return (u.startsWith('h') || u.startsWith('or') ? v * 60 : v).round();
    }

    final prep = minutes('preparazione|prep|preparation');
    if (prep != null) {
      r.prepMinutes = prep;
      used = true;
    }
    final cook = minutes('cottura|cook|cooking|forno');
    if (cook != null) {
      r.cookMinutes = cook;
      used = true;
    }
    final diff =
        RegExp(r'difficolt[aà]\s*:?\s*(molto facile|facile|media|medio|difficile|alta|bassa)', caseSensitive: false)
            .firstMatch(low);
    if (diff != null) {
      final d = diff.group(1)!;
      r.difficulty = d.startsWith('molto')
          ? Difficulty.veryEasy
          : d.startsWith('facile') || d == 'bassa'
              ? Difficulty.easy
              : d.startsWith('medi')
                  ? Difficulty.medium
                  : Difficulty.hard;
      used = true;
    }
    // La riga è "solo meta" se è corta e non sembra un ingrediente né una frase.
    return used && l.length < 80 && !l.endsWith('.');
  }

  /// Categoria proposta dalle parole del titolo.
  static RecipeCategory guessCategory(String text) {
    final t = text.toLowerCase();
    bool any(List<String> w) => w.any(t.contains);
    if (any(['menù', 'menu '])) return RecipeCategory.menu;
    if (any([
      'liquore',
      'limoncello',
      'nocino',
      'amaro',
      'grappa',
      'rosolio',
      'mirto',
      'genziana',
      'elicriso',
      'liqueur'
    ])) {
      return RecipeCategory.liquori;
    }
    if (any([
      'marmellata',
      'confettura',
      'conserva',
      "sott'olio",
      'sottolio',
      'sottaceto',
      'passata',
      'salsa di pomodoro',
      'giardiniera',
      'jam',
      'pickle'
    ])) {
      return RecipeCategory.conserve;
    }
    if (any(['spritz', 'cocktail', 'aperitivo', 'negroni', 'sangria'])) return RecipeCategory.aperitivi;
    if (any([
      'torta',
      'dolce',
      'biscott',
      'crostata',
      'tiramis',
      'gelato',
      'budino',
      'panna cotta',
      'ciambell',
      'frittell',
      'cake',
      'cookie',
      'pie',
      'dessert',
      'muffin',
      'crema',
      'semifreddo',
      'strudel'
    ])) {
      return RecipeCategory.dolci;
    }
    if (any([
      'pasta',
      'spaghetti',
      'risotto',
      'lasagn',
      'gnocchi',
      'zuppa',
      'minestr',
      'tagliatelle',
      'ravioli',
      'tortellini',
      'penne',
      'fusilli',
      'orecchiette',
      'pappardelle',
      'cannelloni',
      'polenta',
      'soup',
      'noodle'
    ])) {
      return RecipeCategory.primi;
    }
    if (any(['insalata', 'contorno', 'patate', 'verdure', 'peperonata', 'caponata', 'salad', 'purè', 'pure '])) {
      return RecipeCategory.contorni;
    }
    if (any(['crostini', 'bruschett', 'antipasto', 'tartine', 'frittatine', 'vol-au-vent', 'starter'])) {
      return RecipeCategory.antipasti;
    }
    return RecipeCategory.secondi;
  }
}
