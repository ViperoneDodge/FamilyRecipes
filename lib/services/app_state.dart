import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../l10n.dart';
import '../models.dart';
import '../theme.dart';
import 'auth_service.dart';
import 'backup_service.dart';
import 'group_watch.dart';
import 'local_store.dart';
import 'notification_service.dart';
import 'photo_store.dart';
import 'pro_service.dart';
import 'push_service.dart';
import 'sync_service.dart';
import 'update_service.dart';

enum SyncStatus { off, connecting, online, offline }

class AppState extends ChangeNotifier {
  final LocalStore store = LocalStore();
  late final AuthService auth = AuthService(store);
  late final PhotoStore photos = PhotoStore(store);
  final NotificationService notifications = NotificationService();
  final SyncService sync = SyncService();
  final PushService push = PushService();
  final ProService pro = ProService();

  GroupWatchState watch = GroupWatchState();

  /// Amministratore dell'app: vede e gestisce ricette e gruppi di tutti.
  static const String adminEmail = 'appmyfleetmanager@gmail.com';

  bool get isAdmin => isCloud && session?.email?.toLowerCase() == adminEmail;

  bool loading = true;
  ThemeSettings theme = ThemeSettings();
  Session? session;
  UserData data = UserData();
  SyncStatus syncStatus = SyncStatus.off;
  Timer? _retry;

  bool get isCloud => session?.mode == AccountMode.cloud;

  /// true = prima le più recenti, false = in ordine alfabetico.
  bool sortNewestFirst = false;

  /// Preferiti (su questo telefono): ricette scelte una per una e gruppi interi.
  Set<String> favRecipes = {};
  Set<String> favGroups = {};

  /// L'app si apre sulla pagina dei Preferiti invece che su Le mie.
  bool startOnFavorites = false;

  String? langPref;

  // ---- Ricette visibili ----

  List<Recipe> get recipes => data.recipes.where((r) => !r.deleted).toList();

  bool isPersonal(Recipe r) => r.bookId == null || r.bookId == data.personalBookId;

  bool isMine(Recipe r) {
    if (!isCloud) return true;
    if (r.createdBy.isNotEmpty) return r.createdBy == session?.key;
    return isPersonal(r);
  }

  GroupRole roleIn(String? bookId) {
    if (isAdmin || bookId == null || bookId == data.personalBookId) return GroupRole.admin;
    final g = data.groupById(bookId);
    return g == null ? GroupRole.viewer : g.roleOf(session?.key);
  }

  /// Può modificarla e spostarla: ruolo nel ricettario e, senza Pro, entro i limiti della versione gratuita.
  bool canEdit(Recipe r) => canDelete(r) && withinFree(r);

  /// Può eliminarla (anche se è oltre i limiti della versione gratuita: così libera posto).
  bool canDelete(Recipe r) => roleIn(isPersonal(r) ? null : r.bookId) != GroupRole.viewer;

  bool canAddTo(String? bookId) => roleIn(bookId) != GroupRole.viewer;

  // ---- Versione Pro ----

  /// Acquistata su questo telefono (o ripristinata dallo store).
  bool purchasedPro = false;

  bool get isPro => purchasedPro || isAdmin;

  /// Versione gratuita: solo queste categorie, al massimo [freeLimit] ricette ciascuna in ogni ricettario.
  static const Set<RecipeCategory> freeCategories = {
    RecipeCategory.aperitivi,
    RecipeCategory.primi,
    RecipeCategory.secondi,
    RecipeCategory.dolci,
  };
  static const int freeLimit = 3;

  bool categoryOpen(RecipeCategory c) => isPro || freeCategories.contains(c);

  String _bookKey(Recipe r) => isPersonal(r) ? '' : r.bookId!;

  /// Per ricettario e categoria: gli id delle prime [freeLimit] ricette (le più vecchie), le sole usabili
  /// senza Pro. Ricalcolato a ogni cambiamento.
  Map<String, Set<String>>? _freeIds;

  Map<String, Set<String>> get _free {
    final cached = _freeIds;
    if (cached != null) return cached;
    final by = <String, List<Recipe>>{};
    for (final r in data.recipes) {
      if (r.deleted || !freeCategories.contains(r.category)) continue;
      by.putIfAbsent('${_bookKey(r)}|${r.category.name}', () => []).add(r);
    }
    final out = <String, Set<String>>{};
    by.forEach((k, list) {
      list.sort((a, b) {
        final c = a.createdAt.compareTo(b.createdAt);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
      out[k] = {for (final r in list.take(freeLimit)) r.id};
    });
    return _freeIds = out;
  }

  @override
  void notifyListeners() {
    _freeIds = null;
    super.notifyListeners();
  }

  /// Rientra nella versione gratuita (o c'è Pro).
  bool withinFree(Recipe r) => isPro || (_free['${_bookKey(r)}|${r.category.name}']?.contains(r.id) ?? false);

  /// Si può aprire: nei limiti, oppure è una propria ricetta (oltre i limiti resta in sola lettura).
  bool canOpen(Recipe r) => withinFree(r) || isMine(r);

  int _countIn(String book, RecipeCategory c) =>
      data.recipes.where((r) => !r.deleted && r.category == c && _bookKey(r) == book).length;

  /// La ricetta può stare (nuova, o con categoria/ricettario cambiati) nel suo ricettario e categoria.
  bool canPlace(Recipe r) {
    if (isPro) return true;
    if (!freeCategories.contains(r.category)) return false;
    final old = recipeById(r.id);
    if (old != null && old.category == r.category && _bookKey(old) == _bookKey(r)) return withinFree(old);
    return _countIn(_bookKey(r), r.category) < freeLimit;
  }

  /// C'è ancora posto per almeno una ricetta nel ricettario (null = le mie).
  bool hasFreeSlot(String? bookId) {
    if (isPro) return true;
    final book = bookId == null || bookId == data.personalBookId ? '' : bookId;
    return freeCategories.any((c) => _countIn(book, c) < freeLimit);
  }

  /// Acquisto rimborsato o annullato (lo dice Google Play): Pro si spegne su questo telefono.
  Future<void> _revokePro() async {
    if (!purchasedPro) return;
    purchasedPro = false;
    notifyListeners();
    await _writeSettings();
  }

  Future<void> _setPro() async {
    if (purchasedPro) return;
    purchasedPro = true;
    notifyListeners();
    await _writeSettings();
  }

  bool canManage(FamilyGroup g) => isAdmin || g.roleOf(session?.key) == GroupRole.admin;

  List<Recipe> sortedForList(Iterable<Recipe> list) {
    final out = list.toList()
      ..sort((a, b) {
        if (sortNewestFirst) {
          final c = b.createdAt.compareTo(a.createdAt);
          if (c != 0) return c;
        }
        final t = a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase());
        return t != 0 ? t : a.id.compareTo(b.id);
      });
    return out;
  }

  List<Recipe> get myRecipes => sortedForList(recipes.where(isMine));

  List<Recipe> get allRecipes => sortedForList(recipes);

  List<Recipe> groupRecipes(String groupId) => sortedForList(recipes.where((r) => r.bookId == groupId));

  String bookLabel(Recipe r) =>
      isPersonal(r) ? tr('book.mine') : (data.groupById(r.bookId)?.name ?? tr('family.defaultName'));

  String? bookOf(Recipe r) => r.bookId ?? data.personalBookId;

  Recipe? recipeById(String id) => data.recipes.where((r) => r.id == id && !r.deleted).firstOrNull;

  /// Ricette che si possono inserire in un menù dello stesso ricettario.
  List<Recipe> menuCandidates(Recipe menu) => sortedForList(recipes.where((r) =>
      r.id != menu.id &&
      r.category != RecipeCategory.menu &&
      (isPersonal(menu) ? isPersonal(r) || isMine(r) : r.bookId == menu.bookId)));

  // ---- Avvio, accesso, uscita ----

  Future<void> init() async {
    final settings = await store.readSettings();
    try {
      theme = ThemeSettings.fromJson(settings);
    } catch (_) {
      theme = ThemeSettings();
    }
    final lang = settings?['lang'];
    langPref = lang is String ? lang : null;
    sortNewestFirst = settings?['sortNewest'] == true;
    Set<String> ids(Object? v) => {if (v is List) for (final e in v) '$e'};
    favRecipes = ids(settings?['favRecipes']);
    favGroups = ids(settings?['favGroups']);
    startOnFavorites = settings?['start'] == 'plan'; // pagina iniziale: la pianificazione
    purchasedPro = settings?['pro'] == true;
    photos.downloader = (book, id) => isCloud ? sync.downloadPhoto(book, id) : Future.value(null);
    notifyListeners();
    try {
      await notifications.init();
    } catch (_) {}
    try {
      final s = await store.readSession();
      if (s != null && (s.mode != AccountMode.cloud || auth.cloudSessionValid(s))) await _open(s);
    } catch (_) {
      // Un file rovinato non deve bloccare l'app sulla schermata iniziale: si riparte dall'accesso.
      session = null;
      data = UserData();
    }
    loading = false;
    notifyListeners();
    UpdateService.instance.start(pushAvailable: auth.cloudAvailable);
    pro.init(onOwned: _setPro, onChanged: notifyListeners, onRevoked: _revokePro);
  }

  Future<void> login(Session s) async {
    await store.writeSession(s);
    await _open(s);
    notifications.requestPermission();
    notifyListeners();
  }

  Future<void> _open(Session s) async {
    session = s;
    data = await store.readUserData(s);
    if (s.mode == AccountMode.cloud) {
      sync.saveProfile(s).catchError((_) {});
      await _loadWatch(s);
      _startSync();
      startPush();
    }
  }

  Future<void> _loadWatch(Session s) async {
    watch = await GroupWatchState.load();
    if (watch.uid != s.key) watch = GroupWatchState(uid: s.key);
    watch.groups = {for (final g in data.groups) g.id: g.name};
    await watch.save();
    await scheduleGroupWatch(_watchNeeded);
  }

  bool get _watchNeeded => watch.enabled && watch.groups.isNotEmpty;

  Future<void> _watchChain = Future.value();

  bool get groupAlerts => watch.enabled;

  Future<void> setGroupAlerts(bool on) async {
    watch.enabled = on;
    notifyListeners();
    await watch.save();
    await scheduleGroupWatch(_watchNeeded);
    if (on) notifications.requestPermission();
  }

  Future<void> _checkGroupActivity(String bookId, List<Recipe> remote, Set<String> existedBefore) async {
    final s = session;
    if (s == null || !isCloud) return;
    final fresh = await GroupWatchState.load();
    if (fresh.uid == s.key) {
      watch.seen = fresh.seen;
      watch.known = fresh.known;
    }
    final since = watch.seen[bookId];
    var maxTs = since ?? 0;
    for (final r in remote) {
      if (r.updatedAt > maxTs) maxTs = r.updatedAt;
    }
    Future<void> markSeen(int ts) async {
      watch.seen[bookId] = ts;
      for (final r in remote) {
        if (!r.deleted) watch.remember(r.id);
      }
      await watch.save();
    }

    // Prima volta: si prende nota di quello che c'è, senza avvisi.
    if (since == null) return markSeen(remote.isEmpty ? DateTime.now().millisecondsSinceEpoch : maxTs);
    if (maxTs <= since) return;
    final acts = findActivities(
      groupName: data.groupById(bookId)?.name ?? tr('family.defaultName'),
      me: s.key,
      myName: s.displayName,
      since: since,
      remote: remote,
      existed: (id) => existedBefore.contains(id) || watch.known.contains(id),
    );
    await markSeen(maxTs);
    if (watch.enabled && acts.isNotEmpty) await showActivities(notifications, acts);
  }

  Future<void> startPush() async {
    final s = session;
    if (s == null || s.mode != AccountMode.cloud || !auth.cloudAvailable) return;
    await push.start(s.key, onForeground: notifications.showRemote);
    notifyListeners();
  }

  Future<void> logout() async {
    sync.stop();
    await scheduleGroupWatch(false);
    watch = GroupWatchState();
    await watch.save();
    _retry?.cancel();
    if (isCloud) await push.stop();
    await auth.logout(session);
    await store.writeSession(null);
    session = null;
    data = UserData();
    syncStatus = SyncStatus.off;
    notifyListeners();
  }

  Future<bool> deleteCloudAccount() async {
    final s = session;
    if (s == null || !isCloud) return true;
    sync.stop();
    _retry?.cancel();
    await push.stop();
    try {
      await sync.deleteAllData(s, List.of(data.groups));
    } catch (_) {
      _startSync();
      startPush();
      rethrow;
    }
    var complete = true;
    try {
      await auth.deleteCloudAccount();
    } on AuthException {
      complete = false;
    }
    for (final r in data.recipes) {
      for (final p in r.photoIds) {
        await photos.delete(p);
      }
    }
    await store.deleteUserData(s);
    await logout();
    return complete;
  }

  Future<void> _persist() async {
    final s = session;
    if (s == null) return;
    await store.writeUserData(s, data);
  }

  // ---- Salvataggio ricette ----

  Future<String> addPhoto(Uint8List bytes) => photos.add(bytes);

  Future<void> saveRecipe(Recipe r) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final me = session;
    r.updatedAt = now;
    r.updatedBy = me?.displayName ?? '';
    r.updatedByUid = me?.key ?? '';
    final existing = recipeById(r.id);
    if (existing == null) {
      if (r.createdBy.isEmpty) r.createdBy = me?.key ?? '';
      if (r.createdByName.isEmpty) r.createdByName = me?.displayName ?? '';
      if (r.createdAt == 0) r.createdAt = now;
    }
    if (r.bookId == data.personalBookId) r.bookId = null;
    r.ingredients.removeWhere((i) => i.isEmpty);
    r.steps.removeWhere((s) => s.isEmpty);

    final i = data.recipes.indexWhere((x) => x.id == r.id);
    if (i >= 0) {
      final old = data.recipes[i];
      for (final p in old.photoIds.difference(r.photoIds)) {
        await photos.delete(p);
        _deleteCloudPhoto(old, p);
      }
    }
    if (i >= 0 && data.recipes[i].bookId != r.bookId && isCloud) {
      // Spostata in un altro ricettario: lapide nel vecchio, copia nel nuovo.
      final old = data.recipes[i];
      final tomb = _tombstone(old, now);
      data.recipes[i] = tomb;
      _pushIfCloud(tomb);
      for (final p in r.photoIds) {
        _deleteCloudPhoto(old, p);
      }
      final moved = r.copy()..id = newId();
      data.recipes.add(moved);
      if (favRecipes.remove(old.id)) {
        favRecipes.add(moved.id);
        _writeSettings();
      }
      r = moved;
    } else if (i >= 0) {
      data.recipes[i] = r;
    } else {
      data.recipes.add(r);
    }
    await _persist();
    _pushIfCloud(r);
    notifyListeners();
  }

  Recipe _tombstone(Recipe r, int now) =>
      r.tombstone(at: now, by: session?.displayName ?? '', byUid: session?.key ?? '');

  Future<void> deleteRecipe(String id) async {
    final i = data.recipes.indexWhere((x) => x.id == id);
    if (i < 0) return;
    final r = data.recipes[i];
    for (final p in r.photoIds) {
      await photos.delete(p);
      _deleteCloudPhoto(r, p);
    }
    final tomb = _tombstone(r, DateTime.now().millisecondsSinceEpoch);
    data.recipes[i] = tomb;
    await _persist();
    _pushIfCloud(tomb);
    notifyListeners();
  }

  Future<void> moveRecipe(String id, String? bookId) async {
    final r = recipeById(id);
    if (r == null) return;
    await saveRecipe(r.copy()..bookId = bookId);
  }

  /// Duplica una ricetta (per esempio da un gruppo tra le proprie).
  Future<Recipe?> duplicateRecipe(Recipe src, String? bookId) async {
    final c = Recipe.fromJson(src.toJson())
      ..id = newId()
      ..bookId = bookId
      ..createdBy = ''
      ..createdByName = ''
      ..createdAt = 0
      ..courses = [];
    final map = <String, String>{};
    Future<String?> clone(String? p) async {
      if (p == null || p.isEmpty) return null;
      if (map.containsKey(p)) return map[p];
      final b = await photos.load(p, bookId: bookOf(src));
      if (b == null) return null;
      return map[p] = await photos.add(b);
    }

    c.coverPhoto = await clone(src.coverPhoto);
    for (final s in c.steps) {
      final out = <String>[];
      for (final p in s.photos) {
        final n = await clone(p);
        if (n != null) out.add(n);
      }
      s.photos = out;
    }
    await saveRecipe(c);
    return c;
  }

  void _deleteCloudPhoto(Recipe r, String photoId) {
    final book = bookOf(r);
    if (!isCloud || book == null) return;
    data.uploaded.remove('$book/$photoId');
    sync.deletePhoto(book, photoId);
  }

  Future<void> _uploadPhotos(String book, Recipe r) async {
    for (final p in r.photoIds) {
      final key = '$book/$p';
      if (data.uploaded.contains(key)) continue;
      final bytes = await photos.read(p);
      if (bytes == null) continue;
      data.uploaded.add(key);
      sync.uploadPhoto(book, p, r.id, bytes).catchError((_) {
        data.uploaded.remove(key);
      });
    }
  }

  void _pushIfCloud(Recipe r) {
    final book = bookOf(r);
    if (!isCloud || book == null) return;
    _pushTo(book, r);
  }

  void _pushTo(String book, Recipe r) {
    _uploadPhotos(book, r).whenComplete(() {
      sync.push(book, r);
      _persist();
    });
  }

  // ---- Impostazioni ----

  Future<void> updateTheme(ThemeSettings t) async {
    theme = t;
    notifyListeners();
    await _writeSettings();
  }

  Future<void> setSortNewestFirst(bool on) async {
    sortNewestFirst = on;
    notifyListeners();
    await _writeSettings();
  }

  Future<void> _writeSettings() => store.writeSettings({
        ...theme.toJson(),
        if (langPref != null) 'lang': langPref,
        'sortNewest': sortNewestFirst,
        'favRecipes': favRecipes.toList(),
        'favGroups': favGroups.toList(),
        if (startOnFavorites) 'start': 'plan',
        if (purchasedPro) 'pro': true,
      });

  // ---- Preferiti ----

  /// Nei preferiti da sola o perché il suo gruppo è tra i preferiti.
  bool isFavorite(Recipe r) => favRecipes.contains(r.id) || (r.bookId != null && favGroups.contains(r.bookId));

  List<Recipe> get favoriteRecipes => sortedForList(recipes.where(isFavorite));

  Future<void> toggleFavorite(Recipe r) async {
    if (!favRecipes.remove(r.id)) favRecipes.add(r.id);
    notifyListeners();
    await _writeSettings();
  }

  Future<void> toggleFavoriteGroup(String groupId) async {
    if (!favGroups.remove(groupId)) favGroups.add(groupId);
    notifyListeners();
    await _writeSettings();
  }

  Future<void> setStartOnFavorites(bool on) async {
    startOnFavorites = on;
    notifyListeners();
    await _writeSettings();
  }

  Future<void> setLanguage(String? code) async {
    langPref = code;
    await L10n.load(L10n.resolve(code));
    notifyListeners();
    await _writeSettings();
    try {
      await notifications.refreshChannels();
    } catch (_) {}
  }

  /// Passa da un account locale a uno online, portando con sé le ricette.
  Future<int> switchToCloud(Session cloud, {required bool bringRecipes}) async {
    final old = session;
    final oldData = data;
    final target = await store.readUserData(cloud);
    var copied = 0;
    if (bringRecipes && old != null && old.mode == AccountMode.local) {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final r in oldData.recipes.where((r) => !r.deleted)) {
        if (target.recipes.any((x) => x.id == r.id)) continue;
        target.recipes.add(r.copy()
          ..bookId = null
          ..updatedAt = now
          ..updatedBy = cloud.displayName
          ..updatedByUid = cloud.key
          ..createdBy = cloud.key
          ..createdByName = cloud.displayName);
        copied++;
      }
    }
    await store.writeUserData(cloud, target);
    sync.stop();
    _retry?.cancel();
    syncStatus = SyncStatus.off;
    await store.writeSession(cloud);
    await _open(cloud);
    notifications.requestPermission();
    notifyListeners();
    return copied;
  }

  // ---- Sincronizzazione ----

  Future<void> retrySync() async {
    if (!isCloud) return;
    if (!push.registered) startPush();
    await _startSync();
  }

  Future<void> _startSync() async {
    final s = session;
    if (s == null || !auth.cloudAvailable) return;
    _retry?.cancel();
    syncStatus = SyncStatus.connecting;
    notifyListeners();
    if (data.personalBookId == null) {
      try {
        data.personalBookId = await sync.ensurePersonal(s);
        await _persist();
      } catch (_) {
        syncStatus = SyncStatus.offline;
        notifyListeners();
        _retry = Timer(const Duration(minutes: 1), _startSync);
        return;
      }
    }
    _listen();
  }

  void _listen() {
    final s = session;
    final personal = data.personalBookId;
    if (s == null || personal == null) return;
    sync.start(
      session: s,
      personalId: personal,
      localRecipes: (bookId) => data.recipes.where((r) => bookOf(r) == bookId).toList(),
      onRecipes: _mergeRemote,
      onGroups: _onGroups,
      pushRecipe: _pushTo,
    );
  }

  void _onGroups(List<FamilyGroup> groups) {
    data.groups = groups;
    if (isCloud) {
      final names = {for (final g in groups) g.id: g.name};
      final had = _watchNeeded;
      watch.groups = names;
      watch.seen.removeWhere((k, _) => !names.containsKey(k));
      watch.save();
      if (had != _watchNeeded) scheduleGroupWatch(_watchNeeded);
    }
    final valid = {data.personalBookId, ...groups.map((g) => g.id)};
    final gone = data.recipes.where((r) => r.bookId != null && !valid.contains(r.bookId)).toList();
    for (final r in gone) {
      for (final p in r.photoIds) {
        photos.delete(p);
      }
      data.recipes.remove(r);
    }
    data.uploaded.removeWhere((k) => !valid.contains(k.split('/').first));
    syncStatus = SyncStatus.online;
    _persist();
    notifyListeners();
  }

  void _mergeRemote(String bookId, List<Recipe> remote, bool fromServer) {
    var changed = false;
    final personal = bookId == data.personalBookId;
    if (!personal) {
      final existed = data.recipes.where((r) => !r.deleted).map((r) => r.id).toSet();
      final copy = List.of(remote);
      _watchChain = _watchChain.then((_) => _checkGroupActivity(bookId, copy, existed)).catchError((_) {});
    }
    // Una data di modifica nel futuro (orologio sbagliato o scritta apposta) bloccherebbe le modifiche degli
    // altri: oltre un giorno avanti si considera "adesso".
    final limit = DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch;
    for (final r in remote) {
      if (r.updatedAt > limit) r.updatedAt = DateTime.now().millisecondsSinceEpoch;
      r.bookId = personal ? null : bookId;
      final i = data.recipes.indexWhere((x) => x.id == r.id);
      if (i < 0) {
        data.recipes.add(r);
        changed = true;
      } else if (r.updatedAt > data.recipes[i].updatedAt) {
        for (final p in data.recipes[i].photoIds.difference(r.photoIds)) {
          photos.delete(p);
        }
        data.recipes[i] = r;
        changed = true;
      } else {
        continue;
      }
      for (final p in r.photoIds) {
        data.uploaded.add('$bookId/$p');
      }
    }
    if (fromServer && syncStatus != SyncStatus.online) {
      syncStatus = SyncStatus.online;
      changed = true;
    }
    if (changed) {
      _persist();
      notifyListeners();
    }
  }

  // ---- Gruppi ----

  Future<FamilyGroup> createGroup(String name) async => _addGroup(await sync.createGroup(session!, name));

  Future<FamilyGroup> joinGroup(String code) async => _addGroup(await sync.joinGroup(session!, code));

  Future<FamilyGroup> _addGroup(FamilyGroup g) async {
    if (data.groupById(g.id) == null) data.groups.add(g);
    await _persist();
    notifyListeners();
    return g;
  }

  Future<void> leaveGroup(String id) async {
    await sync.leaveGroup(session!, id);
    _onGroups(data.groups.where((g) => g.id != id).toList());
  }

  Future<void> deleteGroup(String id) async {
    await sync.deleteGroup(id);
    _onGroups(data.groups.where((g) => g.id != id).toList());
  }

  Future<void> removeMember(String groupId, String uid) => sync.removeMember(groupId, uid);

  Future<void> setRole(FamilyGroup g, String uid, GroupRole role) async {
    await sync.setRole(g.id, uid, role);
    g.admins.remove(uid);
    g.viewers.remove(uid);
    if (role == GroupRole.admin) g.admins.add(uid);
    if (role == GroupRole.viewer) g.viewers.add(uid);
    await _persist();
    notifyListeners();
  }

  Future<void> renameGroup(String id, String name) async {
    await sync.renameGroup(id, name);
    data.groupById(id)?.name = name;
    await _persist();
    notifyListeners();
  }

  // ---- Backup ----

  /// Copia sul telefono di tutte le ricette visibili (mie e dei gruppi), con le foto e i preferiti, in un
  /// `.zip` scritto una foto alla volta (si tengono le ultime [BackupService.keep]); null se non riesce.
  Future<File?> backupNow([String reason = 'manual', File? protect]) async {
    final s = session;
    if (s == null) return null;
    try {
      return await BackupService.saveZip(
        s.storageKey,
        recipes: data.recipes.where((r) => !r.deleted).toList(),
        favorites: Set<String>.of(favRecipes),
        plan: data.plan,
        reason: reason,
        at: DateTime.now(),
        photo: (r, p) => photos.load(p, bookId: bookOf(r)).timeout(const Duration(seconds: 30)),
        protect: protect,
      );
    } catch (_) {
      return null;
    }
  }

  /// La stessa ricetta con un altro id (dopo uno spostamento): stesso autore, data di creazione e titolo.
  Recipe? _twinOf(Recipe b) {
    if (b.createdAt == 0) return null;
    for (final r in data.recipes) {
      if (r.deleted || r.id == b.id) continue;
      if (r.createdAt == b.createdAt && r.createdBy == b.createdBy && r.title.trim() == b.title.trim()) return r;
    }
    return null;
  }

  /// Riporta le ricette del backup com'erano allora; quelle aggiunte dopo restano. Le ricette di gruppi
  /// che non ci sono più tornano tra le mie; quelle dei gruppi in cui si è in sola lettura si saltano.
  Future<int> restoreBackup(BackupData b, {File? from}) async {
    await backupNow('restore', from);
    var n = 0;
    final seen = <String>{};
    for (final src in b.recipes) {
      if (!seen.add(src.id)) continue;
      var old = data.recipes.where((x) => x.id == src.id).firstOrNull;
      // Spostata in un altro ricettario dopo il backup: qui c'è solo la lapide, la ricetta vive con un id nuovo.
      if (old == null || old.deleted) old = _twinOf(src) ?? old;
      String? book = src.bookId;
      if (book == data.personalBookId || (book != null && data.groupById(book) == null)) book = null;
      if (old != null && !old.deleted) book = isPersonal(old) ? null : old.bookId;
      if (!canAddTo(book)) continue;
      for (final p in src.photoIds) {
        if (await photos.exists(p)) continue;
        final bytes = await b.photo(p);
        if (bytes != null) await photos.put(p, bytes);
      }
      final r = src.copy()
        ..id = old != null && !old.deleted ? old.id : src.id
        ..bookId = book
        ..deleted = false;
      // Tra le mie (anche da un backup di un altro account o di quello senza registrazione): diventa mia.
      if (book == null && session != null) {
        r.createdBy = session!.key;
        if (r.createdByName.isEmpty) r.createdByName = session!.displayName;
      }
      try {
        await saveRecipe(r);
        if (b.favorites.contains(src.id)) favRecipes.add(r.id);
        n++;
      } catch (_) {}
    }
    // Pianificazione: si riprendono i giorni che oggi sono vuoti (quelli già pianificati restano come sono).
    final plan = b.plan;
    if (plan != null) {
      for (final d in plan.days.entries) {
        if (data.plan.days.containsKey(d.key)) continue;
        data.plan.days[d.key] = {for (final m in d.value.entries) m.key: List.of(m.value)};
      }
      data.plan.extraMeals.addAll(plan.extraMeals);
      await _persist();
    }
    if (n > 0 || plan != null) {
      await _writeSettings();
      notifyListeners();
    }
    return n;
  }

  // ---- Pianificazione dei pasti ----

  MealPlan get plan => data.plan;

  Future<void> _savePlan() async {
    notifyListeners();
    await _persist();
  }

  /// Settimane della prova gratuita della pianificazione (senza Pro).
  static const int trialWeeks = 2;

  static String _weekKey(String day) {
    final d = DateTime.tryParse(day);
    return d == null ? day : planDay(weekStart(d));
  }

  /// Si può pianificare la settimana che inizia il lunedì [start]: con Pro sempre; senza, nelle settimane
  /// della prova (al massimo [trialWeeks], scelte da chi la usa).
  bool canPlanWeek(DateTime start) {
    if (isPro) return true;
    final key = planDay(weekStart(start));
    return data.plan.trialWeeks.contains(key) || data.plan.trialWeeks.length < trialWeeks;
  }

  int get trialWeeksUsed => data.plan.trialWeeks.length;

  Future<void> planAdd(String day, Meal meal, PlanEntry e) {
    final d = DateTime.tryParse(day);
    if (d != null && !canPlanWeek(d)) return Future.value();
    if (!isPro) data.plan.trialWeeks.add(_weekKey(day));
    data.plan.add(day, meal, e);
    return _savePlan();
  }

  Future<void> planRemove(String day, Meal meal, int index) {
    data.plan.remove(day, meal, index);
    return _savePlan();
  }

  Future<void> planSetServings(String day, Meal meal, int index, int servings) {
    final l = data.plan.days[day]?[meal];
    if (l != null && index >= 0 && index < l.length) l[index].servings = servings.clamp(1, 99);
    return _savePlan();
  }

  /// Colazione e spuntini in più (pranzo e cena ci sono sempre).
  Future<void> setExtraMeal(Meal meal, bool on) {
    if (baseMeals.contains(meal)) return Future.value();
    on ? data.plan.extraMeals.add(meal) : data.plan.extraMeals.remove(meal);
    return _savePlan();
  }

  /// Svuota i 7 giorni dal lunedì [start].
  Future<void> planClearWeek(DateTime start) {
    for (var i = 0; i < 7; i++) {
      data.plan.days.remove(planDay(start.add(Duration(days: i))));
    }
    return _savePlan();
  }

  /// Aggiunge le voci (per esempio da un file Excel); i pasti in più usati si attivano.
  /// Senza Pro si importano solo le settimane della prova; restituisce le voci saltate.
  Future<int> planImport(List<({String day, Meal meal, PlanEntry entry})> entries) async {
    var skipped = 0;
    for (final e in entries) {
      final d = DateTime.tryParse(e.day);
      if (d == null || !canPlanWeek(d)) {
        skipped++;
        continue;
      }
      if (!isPro) data.plan.trialWeeks.add(_weekKey(e.day));
      data.plan.add(e.day, e.meal, e.entry);
      if (!baseMeals.contains(e.meal)) data.plan.extraMeals.add(e.meal);
    }
    await _savePlan();
    return skipped;
  }
}
