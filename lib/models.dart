import 'dart:math';

import 'l10n.dart';

String newId([int length = 16]) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = Random.secure();
  return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
}

enum RecipeCategory { aperitivi, antipasti, primi, secondi, contorni, dolci, liquori, conserve, menu }

RecipeCategory categoryFrom(String? s) {
  for (final c in RecipeCategory.values) {
    if (c.name == s) return c;
  }
  return RecipeCategory.primi;
}

String categoryLabel(RecipeCategory c) => tr('cat.${c.name}');

enum Difficulty { veryEasy, easy, medium, hard }

Difficulty difficultyFrom(String? s) {
  for (final d in Difficulty.values) {
    if (d.name == s) return d;
  }
  return Difficulty.easy;
}

String difficultyLabel(Difficulty d) => tr('diff.${d.name}');

enum Cost { veryLow, low, medium, high }

Cost costFrom(String? s) {
  for (final c in Cost.values) {
    if (c.name == s) return c;
  }
  return Cost.low;
}

String costLabel(Cost c) => tr('cost.${c.name}');

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
        name: j['name'] as String? ?? '',
        amount: j['amount'] as String? ?? '',
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
        id: j['id'] as String?,
        text: j['text'] as String? ?? '',
        photos: ((j['photos'] as List?) ?? const []).map((e) => e.toString()).toList(),
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

  static List<Map<String, dynamic>> _maps(Object? l) =>
      ((l as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  factory Recipe.fromJson(Map<String, dynamic> j) => Recipe(
        id: j['id'] as String?,
        category: categoryFrom(j['category'] as String?),
        title: j['title'] as String? ?? '',
        intro: j['intro'] as String? ?? '',
        coverPhoto: j['cover'] as String?,
        difficulty: difficultyFrom(j['difficulty'] as String?),
        cost: costFrom(j['cost'] as String?),
        prepMinutes: (j['prep'] as num?)?.toInt() ?? 0,
        cookMinutes: (j['cook'] as num?)?.toInt() ?? 0,
        servings: (j['servings'] as num?)?.toInt() ?? 0,
        ingredients: _maps(j['ingredients']).map(Ingredient.fromJson).toList(),
        steps: _maps(j['steps']).map(RecipeStep.fromJson).toList(),
        tips: j['tips'] as String? ?? '',
        courses: ((j['courses'] as List?) ?? const []).map((e) => e.toString()).toList(),
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
        updatedBy: j['updatedBy'] as String? ?? '',
        updatedByUid: j['updatedByUid'] as String? ?? '',
        createdBy: j['createdBy'] as String? ?? '',
        createdByName: j['createdByName'] as String? ?? '',
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
        deleted: j['deleted'] as bool? ?? false,
        bookId: j['bookId'] as String?,
      );

  Recipe copy() => Recipe.fromJson(toJson());

  /// Testo usato dalla ricerca.
  String get searchText => [
        title,
        intro,
        tips,
        ...ingredients.map((i) => i.name),
      ].join(' ').toLowerCase();
}

enum GroupRole { admin, editor, viewer }

String groupRoleLabel(GroupRole r) {
  switch (r) {
    case GroupRole.admin:
      return tr('role.admin');
    case GroupRole.editor:
      return tr('role.editor');
    case GroupRole.viewer:
      return tr('role.viewer');
  }
}

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
        id: j['id'] as String,
        name: j['name'] as String? ?? tr('family.defaultName'),
        ownerUid: j['ownerUid'] as String? ?? '',
        members: Map<String, dynamic>.from((j['members'] as Map?) ?? {})
            .map((k, v) => MapEntry(k, v.toString())),
        admins: ((j['admins'] as List?) ?? const []).map((e) => e.toString()).toSet(),
        viewers: ((j['viewers'] as List?) ?? const []).map((e) => e.toString()).toSet(),
      );

  /// Costruisce il gruppo dal documento Firestore `books/{id}`.
  factory FamilyGroup.fromDoc(String id, Map<String, dynamic> data) {
    final emails = Map<String, dynamic>.from((data['memberEmails'] as Map?) ?? {});
    final members = <String, String>{};
    for (final uid in ((data['members'] as List?) ?? const [])) {
      members[uid.toString()] = (emails[uid] ?? uid).toString();
    }
    return FamilyGroup(
      id: id,
      name: (data['name'] as String?) ?? tr('family.defaultName'),
      ownerUid: (data['ownerUid'] as String?) ?? '',
      members: members,
      admins: ((data['admins'] as List?) ?? const []).map((e) => e.toString()).toSet(),
      viewers: ((data['viewers'] as List?) ?? const []).map((e) => e.toString()).toSet(),
    );
  }
}

class UserData {
  List<Recipe> recipes;

  String? personalBookId;
  List<FamilyGroup> groups;

  /// Foto già caricate online, come "bookId/photoId".
  Set<String> uploaded;

  UserData({
    List<Recipe>? recipes,
    this.personalBookId,
    List<FamilyGroup>? groups,
    Set<String>? uploaded,
  })  : recipes = recipes ?? [],
        groups = groups ?? [],
        uploaded = uploaded ?? {};

  FamilyGroup? groupById(String? id) {
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'recipes': recipes.map((r) => r.toJson()).toList(),
        'personalBookId': personalBookId,
        'groups': groups.map((g) => g.toJson()).toList(),
        'uploaded': uploaded.toList(),
      };

  factory UserData.fromJson(Map<String, dynamic> j) => UserData(
        recipes: (j['recipes'] as List?)
                ?.map((e) => Recipe.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            [],
        personalBookId: j['personalBookId'] as String?,
        groups: (j['groups'] as List?)
                ?.map((e) => FamilyGroup.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            [],
        uploaded: ((j['uploaded'] as List?) ?? const []).map((e) => e.toString()).toSet(),
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
    if (j == null || j['key'] == null) return null;
    return Session(
      mode: j['mode'] == 'cloud' ? AccountMode.cloud : AccountMode.local,
      key: j['key'] as String,
      displayName: j['displayName'] as String? ?? '',
      email: j['email'] as String?,
    );
  }

  String get storageKey =>
      '${mode.name}_${key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';
}
