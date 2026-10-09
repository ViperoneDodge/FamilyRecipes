import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../l10n.dart';
import 'online_recipes.dart';

/// Traduzione sul telefono (Google ML Kit) delle ricette da internet, che sono in inglese.
/// La prima volta scarica il pacchetto della lingua (circa 30 MB), poi funziona anche offline.
class RecipeTranslator {
  RecipeTranslator._();
  static final RecipeTranslator instance = RecipeTranslator._();

  OnDeviceTranslator? _tr;
  TranslateLanguage? _target;
  final Map<String, String> _cache = {};

  /// Lingua di destinazione per la lingua dell'app; null se è già inglese o non supportata.
  static TranslateLanguage? targetFor(String code) {
    if (code == 'en') return null;
    final c = code == 'nb' ? 'no' : code;
    for (final l in TranslateLanguage.values) {
      if (l.bcpCode == c) return l;
    }
    return null;
  }

  TranslateLanguage? get target => targetFor(L10n.code);

  /// true se il pacchetto della lingua è già sul telefono (nessun download necessario).
  Future<bool> ready() async {
    final t = target;
    if (t == null) return false;
    try {
      return await OnDeviceTranslatorModelManager().isModelDownloaded(t.bcpCode);
    } catch (_) {
      return false;
    }
  }

  Future<OnDeviceTranslator?> _translator() async {
    final t = target;
    if (t == null) return null;
    if (_tr != null && _target == t) return _tr;
    await _tr?.close();
    _cache.clear();
    final m = OnDeviceTranslatorModelManager();
    if (!await m.isModelDownloaded(t.bcpCode)) {
      await m.downloadModel(t.bcpCode, isWifiRequired: false);
    }
    _target = t;
    return _tr = OnDeviceTranslator(sourceLanguage: TranslateLanguage.english, targetLanguage: t);
  }

  Future<String> text(String s) async {
    final src = s.trim();
    if (src.isEmpty) return s;
    final c = _cache[src];
    if (c != null) return c;
    final tr = await _translator();
    if (tr == null) return s;
    final out = (await tr.translateText(src)).trim();
    return _cache[src] = out.isEmpty ? src : out;
  }

  /// Copia tradotta della ricetta (titolo, categoria, cucina, ingredienti, dosi e passaggi).
  Future<OnlineRecipe> recipe(OnlineRecipe r) async {
    if (target == null) return r;
    return r.translatedCopy(
      title: await text(r.title),
      category: await text(r.category),
      area: await text(r.area),
      ingredientNames: [for (final i in r.ingredients) await text(i.name)],
      amounts: [for (final i in r.ingredients) await text(expandMeasure(i.amount))],
      steps: [for (final s in r.steps) await text(s)],
    );
  }
}

/// Le abbreviazioni inglesi delle dosi si traducono male: prima si scrivono per esteso.
String expandMeasure(String m) {
  var s = m.trim();
  const units = {
    r'tbsp?s?\.?': 'tablespoons',
    r'tsps?\.?': 'teaspoons',
    r'oz\.?': 'ounces',
    r'lbs?\.?': 'pounds',
    r'pt\.?': 'pint',
    r'qt\.?': 'quart',
  };
  units.forEach((k, v) {
    s = s.replaceAll(RegExp('(?<=^|[\\s\\d])$k(?=\$|\\s)', caseSensitive: false), v);
  });
  return s;
}
