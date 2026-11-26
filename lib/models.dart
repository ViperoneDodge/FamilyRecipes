import 'dart:math';

import 'l10n.dart';

String newId([int length = 16]) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = Random.secure();
  return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
}

enum RecipeCategory { aperitivi, antipasti, primi, secondi, contorni, dolci, liquori, conserve, menu }

RecipeCategory categoryFrom(String? s) => RecipeCategory.values.asNameMap()[s] ?? RecipeCategory.primi;

String categoryLabel(RecipeCategory c) => tr('cat.${c.name}');

enum Difficulty { veryEasy, easy, medium, hard }

Difficulty difficultyFrom(String? s) => Difficulty.values.asNameMap()[s] ?? Difficulty.easy;

String difficultyLabel(Difficulty d) => tr('diff.${d.name}');

enum Cost { veryLow, low, medium, high }

Cost costFrom(String? s) => Cost.values.asNameMap()[s] ?? Cost.low;

String costLabel(Cost c) => tr('cost.${c.name}');

// Lettura tollerante dei JSON (file locali, backup, documenti Firestore scritti da altri): un campo del
// tipo sbagliato diventa il valore predefinito invece di far fallire tutto.

/// Elenco JSON come testi (vuoto se manca o non è un elenco).
List<String> _strings(Object? l) => l is List ? [for (final e in l) if (e != null) e.toString()] : <String>[];

/// Elenco JSON di oggetti (vuoto se manca; gli elementi che non sono oggetti si saltano).
List<Map<String, dynamic>> _maps(Object? l) =>
    l is List ? [for (final e in l) if (e is Map) Map<String, dynamic>.from(e)] : <Map<String, dynamic>>[];

String _str(Object? v, [String fallback = '']) => v is String ? v : (v is num || v is bool ? '$v' : fallback);

String? _optStr(Object? v) => v is String ? v : (v is num ? '$v' : null);

int _int(Object? v) => v is num && v.isFinite ? v.toInt() : (v is String ? int.tryParse(v.trim()) ?? 0 : 0);

String fmtMinutes(int m) {
  if (m <= 0) return '—';
  if (m < 60) return tr('time.min', {'n': m});
  final h = m ~/ 60;
  final r = m % 60;
  return r == 0 ? tr('time.h', {'n': h}) : tr('time.hmin', {'h': h, 'm': r});
}

class Ingredient {
  String name;
  String amount;

  Ingredient({this.name = '', this.amount = ''});

  bool get isEmpty => name.trim().isEmpty && amount.trim().isEmpty;

  Map<String, dynamic> toJson() => {'name': name, 'amount': amount};

  factory Ingredient.fromJson(Map<String, dynamic> j) => Ingredient(
        name: _str(j['name']),
        amount: _str(j['amount']),
      );
}

class RecipeStep {
  String id;
  String text;

  /// Id delle foto del passaggio (file locali in `foto/` e documenti in `books/{id}/photos`).
  List<String> photos;

  RecipeStep({String? id, this.text = '', List<String>? photos})
      : id = id ?? newId(8),
        photos = photos ?? [];

  bool get isEmpty => text.trim().isEmpty && photos.isEmpty;

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'photos': photos};

  factory RecipeStep.fromJson(Map<String, dynamic> j) => RecipeStep(
        id: _optStr(j['id']),
        text: _str(j['text']),
        photos: _strings(j['photos']),
      );
}

class Recipe {
  String id;
  RecipeCategory category;
  String title;
  String intro;

  String? coverPhoto;
  Difficulty difficulty;
  Cost cost;
  int prepMinutes;
  int cookMinutes;
  int servings;
  List<Ingredient> ingredients;
  List<RecipeStep> steps;
  String tips;

  /// Per i "Menù completi": le ricette che compongono il menù.
  List<String> courses;

  int updatedAt;
  String updatedBy;
  String updatedByUid;
  String createdBy;
  String createdByName;
  int createdAt;
  bool deleted;

  String? bookId;

  Recipe({
    String? id,
    this.category = RecipeCategory.primi,
    this.title = '',
    this.intro = '',
    this.coverPhoto,
    this.difficulty = Difficulty.easy,
    this.cost = Cost.low,
    this.prepMinutes = 0,
    this.cookMinutes = 0,
    this.servings = 4,
    List<Ingredient>? ingredients,
    List<RecipeStep>? steps,
    this.tips = '',
    List<String>? courses,
    int? updatedAt,
    this.updatedBy = '',
    this.updatedByUid = '',
    this.createdBy = '',
    this.createdByName = '',
    this.createdAt = 0,
    this.deleted = false,
    this.bookId,
  })  : id = id ?? newId(),
        ingredients = ingredients ?? [],
        steps = steps ?? [],
        courses = courses ?? [],
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  String get displayTitle => title.trim().isEmpty ? tr('recipe.untitled') : title.trim();

  int get totalMinutes => prepMinutes + cookMinutes;

  /// Tutte le foto usate dalla ricetta (copertina e passaggi).
  Set<String> get photoIds => {
        if (coverPhoto != null && coverPhoto!.isNotEmpty) coverPhoto!,
        for (final s in steps) ...s.photos,
      };

  /// Prima foto disponibile, per le anteprime.
  String? get thumbnail {
    if (coverPhoto != null && coverPhoto!.isNotEmpty) return coverPhoto;
    for (final s in steps.reversed) {
      if (s.photos.isNotEmpty) return s.photos.last;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category.name,
        'title': title,
        'intro': intro,
        'cover': coverPhoto,
        'difficulty': difficulty.name,
        'cost': cost.name,
        'prep': prepMinutes,
        'cook': cookMinutes,
        'servings': servings,
        'ingredients': ingredients.map((i) => i.toJson()).toList(),
        'steps': steps.map((s) => s.toJson()).toList(),
        'tips': tips,
        'courses': courses,
        'updatedAt': updatedAt,
        'updatedBy': updatedBy,
        'updatedByUid': updatedByUid,
        'createdBy': createdBy,
        'createdByName': createdByName,
        'createdAt': createdAt,
        'deleted': deleted,
        'bookId': bookId,
      };

  factory Recipe.fromJson(Map<String, dynamic> j) => Recipe(
        id: _optStr(j['id']),
        category: categoryFrom(_optStr(j['category'])),
        title: _str(j['title']),
        intro: _str(j['intro']),
        coverPhoto: _optStr(j['cover']),
        difficulty: difficultyFrom(_optStr(j['difficulty'])),
        cost: costFrom(_optStr(j['cost'])),
        prepMinutes: _int(j['prep']),
        cookMinutes: _int(j['cook']),
        servings: _int(j['servings']),
        ingredients: _maps(j['ingredients']).map(Ingredient.fromJson).toList(),
        steps: _maps(j['steps']).map(RecipeStep.fromJson).toList(),
        tips: _str(j['tips']),
        courses: _strings(j['courses']),
        updatedAt: _int(j['updatedAt']),
        updatedBy: _str(j['updatedBy']),
        updatedByUid: _str(j['updatedByUid']),
        createdBy: _str(j['createdBy']),
        createdByName: _str(j['createdByName']),
        createdAt: _int(j['createdAt']),
        deleted: j['deleted'] == true,
        bookId: _optStr(j['bookId']),
      );

  Recipe copy() => Recipe.fromJson(toJson());

  /// Lapide della ricetta eliminata: restano solo i dati che servono alla sincronizzazione.
  Recipe tombstone({required int at, required String by, required String byUid}) => Recipe(
        id: id,
        category: category,
        title: title,
        createdBy: createdBy,
        createdByName: createdByName,
        createdAt: createdAt,
        updatedAt: at,
        updatedBy: by,
        updatedByUid: byUid,
        deleted: true,
        bookId: bookId,
      );

  /// Testo usato dalla ricerca.
  String get searchText => foldForSearch([
        title,
        intro,
        tips,
        ...ingredients.map((i) => i.name),
      ].join(' '));

  /// Tutte le parole cercate compaiono (in qualunque ordine), senza badare ad accenti e maiuscole:
  /// «torta mele» trova «Torta di mele», «tiramisu» trova «Tiramisù».
  bool matchesSearch(String query) {
    final words = foldForSearch(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return true;
    final text = searchText;
    return words.every(text.contains);
  }
}

const Map<String, String> _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ç': 'c', 'ñ': 'n', 'ß': 'ss', 'œ': 'oe', 'æ': 'ae',
};

/// Testo per la ricerca: minuscolo, senza accenti, spazi semplici.
String foldForSearch(String s) {
  final low = s.toLowerCase();
  final b = StringBuffer();
  for (final ch in low.split('')) {
    b.write(_accents[ch] ?? ch);
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ');
}

enum GroupRole { admin, editor, viewer }

String groupRoleLabel(GroupRole r) => tr('role.${r.name}');

class FamilyGroup {
  final String id;
  String name;
  String ownerUid;

  Map<String, String> members;

  Set<String> admins;

  Set<String> viewers;

  FamilyGroup({
    required this.id,
    required this.name,
    this.ownerUid = '',
    Map<String, String>? members,
    Set<String>? admins,
    Set<String>? viewers,
  })  : members = members ?? {},
        admins = admins ?? {},
        viewers = viewers ?? {};

  GroupRole roleOf(String? uid) {
    if (uid == null) return GroupRole.viewer;
    if (uid == ownerUid || admins.contains(uid)) return GroupRole.admin;
    if (viewers.contains(uid)) return GroupRole.viewer;
    return GroupRole.editor;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ownerUid': ownerUid,
        'members': members,
        'admins': admins.toList(),
        'viewers': viewers.toList(),
      };

  factory FamilyGroup.fromJson(Map<String, dynamic> j) => FamilyGroup(
        id: j['id'] as String, // senza id è un errore: meglio nessun gruppo che un gruppo fantasma
        name: _optStr(j['name']) ?? tr('family.defaultName'),
        ownerUid: _str(j['ownerUid']),
        members: j['members'] is Map
            ? {for (final e in (j['members'] as Map).entries) '${e.key}': '${e.value}'}
            : <String, String>{},
        admins: _strings(j['admins']).toSet(),
        viewers: _strings(j['viewers']).toSet(),
      );

  /// Costruisce il gruppo dal documento Firestore `books/{id}`.
  factory FamilyGroup.fromDoc(String id, Map<String, dynamic> data) {
    final emails = data['memberEmails'] is Map ? data['memberEmails'] as Map : const {};
    final members = <String, String>{};
    for (final uid in _strings(data['members'])) {
      members[uid] = (emails[uid] ?? uid).toString();
    }
    return FamilyGroup(
      id: id,
      name: (_optStr(data['name'])) ?? tr('family.defaultName'),
      ownerUid: (_optStr(data['ownerUid'])) ?? '',
      members: members,
      admins: _strings(data['admins']).toSet(),
      viewers: _strings(data['viewers']).toSet(),
    );
  }
}

/// Pasti della giornata, in ordine. Pranzo e cena ci sono sempre; gli altri quattro si aggiungono a scelta
/// (così la settimana ha al massimo 6 pasti al giorno, anche nel PDF e nel file Excel).
enum Meal { colazione, spuntino, pranzo, merenda, cena, dopocena }

const Set<Meal> baseMeals = {Meal.pranzo, Meal.cena};

Meal? mealFrom(String? s) => Meal.values.asNameMap()[s];

String mealLabel(Meal m) => tr('meal.${m.name}');

/// Una ricetta in un pasto, con le porzioni da preparare.
class PlanEntry {
  String recipeId;
  int servings;

  PlanEntry({required this.recipeId, this.servings = 2});

  Map<String, dynamic> toJson() => {'recipe': recipeId, 'servings': servings};

  static PlanEntry? fromJson(Map<String, dynamic> j) {
    final id = _optStr(j['recipe']);
    if (id == null || id.isEmpty) return null;
    final n = _int(j['servings']);
    return PlanEntry(recipeId: id, servings: n < 1 ? 1 : (n > 99 ? 99 : n));
  }
}

/// Giorno nel formato del piano: "2026-11-30".
String planDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Lunedì della settimana di [d] (a mezzanotte).
DateTime weekStart(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

/// Pianificazione dei pasti: per giorno e pasto, le ricette con le porzioni.
class MealPlan {
  /// Pasti in più rispetto a pranzo e cena (colazione e spuntini) mostrati nel piano.
  Set<Meal> extraMeals;

  /// giorno ("2026-11-30") → pasto → ricette.
  Map<String, Map<Meal, List<PlanEntry>>> days;

  MealPlan({Set<Meal>? extraMeals, Map<String, Map<Meal, List<PlanEntry>>>? days})
      : extraMeals = extraMeals ?? {},
        days = days ?? {};

  /// Pasti mostrati, in ordine.
  List<Meal> get meals => [for (final m in Meal.values) if (baseMeals.contains(m) || extraMeals.contains(m)) m];

  List<PlanEntry> entries(String day, Meal meal) => days[day]?[meal] ?? const [];

  void add(String day, Meal meal, PlanEntry e) => ((days[day] ??= {})[meal] ??= []).add(e);

  void remove(String day, Meal meal, int index) {
    final l = days[day]?[meal];
    if (l == null || index < 0 || index >= l.length) return;
    l.removeAt(index);
    if (l.isEmpty) days[day]!.remove(meal);
    if (days[day]!.isEmpty) days.remove(day);
  }

  /// Tutte le voci dei giorni da [from] (compreso) per [count] giorni, con giorno e pasto.
  List<({String day, Meal meal, PlanEntry entry})> range(DateTime from, int count) => [
        for (var i = 0; i < count; i++)
          for (final m in Meal.values)
            for (final e in entries(planDay(from.add(Duration(days: i))), m)) (day: planDay(from.add(Duration(days: i))), meal: m, entry: e),
      ];

  Map<String, dynamic> toJson() => {
        'extra': [for (final m in extraMeals) m.name],
        'days': {
          for (final d in days.entries)
            d.key: {for (final m in d.value.entries) m.key.name: [for (final e in m.value) e.toJson()]},
        },
      };

  factory MealPlan.fromJson(Object? v) {
    final p = MealPlan();
    if (v is! Map) return p;
    for (final m in _strings(v['extra'])) {
      final meal = mealFrom(m);
      if (meal != null && !baseMeals.contains(meal)) p.extraMeals.add(meal);
    }
    final days = v['days'];
    if (days is Map) {
      for (final d in days.entries) {
        if (d.key is! String || d.value is! Map) continue;
        for (final m in (d.value as Map).entries) {
          final meal = mealFrom('${m.key}');
          if (meal == null) continue;
          for (final e in _maps(m.value)) {
            final entry = PlanEntry.fromJson(e);
            if (entry != null) p.add(d.key as String, meal, entry);
          }
        }
      }
    }
    return p;
  }
}

class UserData {
  List<Recipe> recipes;

  String? personalBookId;
  List<FamilyGroup> groups;

  /// Foto già caricate online, come "bookId/photoId".
  Set<String> uploaded;

  /// Pianificazione dei pasti (solo su questo telefono).
  MealPlan plan;

  UserData({
    List<Recipe>? recipes,
    this.personalBookId,
    List<FamilyGroup>? groups,
    Set<String>? uploaded,
    MealPlan? plan,
  })  : recipes = recipes ?? [],
        groups = groups ?? [],
        uploaded = uploaded ?? {},
        plan = plan ?? MealPlan();

  FamilyGroup? groupById(String? id) => groups.where((g) => g.id == id).firstOrNull;

  Map<String, dynamic> toJson() => {
        'recipes': recipes.map((r) => r.toJson()).toList(),
        'personalBookId': personalBookId,
        'groups': groups.map((g) => g.toJson()).toList(),
        'uploaded': uploaded.toList(),
        'plan': plan.toJson(),
      };

  factory UserData.fromJson(Map<String, dynamic> j) => UserData(
        recipes: _maps(j['recipes']).map(Recipe.fromJson).toList(),
        personalBookId: _optStr(j['personalBookId']),
        groups: [
          for (final g in _maps(j['groups']))
            if (g['id'] is String) FamilyGroup.fromJson(g),
        ],
        uploaded: _strings(j['uploaded']).toSet(),
        plan: MealPlan.fromJson(j['plan']),
      );
}

enum AccountMode { local, cloud }

class Session {
  final AccountMode mode;

  final String key;
  final String displayName;
  final String? email;

  Session({
    required this.mode,
    required this.key,
    required this.displayName,
    this.email,
  });

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'key': key,
        'displayName': displayName,
        'email': email,
      };

  static Session? fromJson(Map<String, dynamic>? j) {
    final key = j?['key'];
    if (j == null || key is! String || key.isEmpty) return null;
    final name = j['displayName'];
    final email = j['email'];
    return Session(
      mode: j['mode'] == 'cloud' ? AccountMode.cloud : AccountMode.local,
      key: key,
      displayName: name is String ? name : '',
      email: email is String ? email : null,
    );
  }

  /// Nome dei file di questo account. Per i nomi con caratteri non semplici (punti, spazi, accenti,
  /// altri alfabeti) si aggiunge un'impronta del nome, così «mario.rossi» e «mario_rossi» (o due nomi
  /// cinesi) non finiscono nello stesso file.
  String get storageKey {
    final safe = key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    if (safe == key) return '${mode.name}_$key';
    return '${mode.name}_${safe}_${_fingerprint(key)}';
  }

  /// Come [storageKey] prima della 1.10.1 (solo per recuperare i file già salvati).
  String get legacyStorageKey => '${mode.name}_${key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';

  /// Impronta breve e stabile (FNV-1a a 32 bit sui caratteri UTF-16), in esadecimale.
  static String _fingerprint(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }
}
