import 'dart:async';

import 'package:flutter/foundation.dart';

import '../l10n.dart';
import '../models.dart';
import '../theme.dart';
import 'auth_service.dart';
import 'group_watch.dart';
import 'local_store.dart';
import 'notification_service.dart';
import 'photo_store.dart';
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

  bool canEdit(Recipe r) => roleIn(isPersonal(r) ? null : r.bookId) != GroupRole.viewer;

  bool canAddTo(String? bookId) => roleIn(bookId) != GroupRole.viewer;

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

  List<Recipe> groupRecipes(String groupId) =>
      sortedForList(recipes.where((r) => r.bookId == groupId));

  String bookLabel(Recipe r) =>
      isPersonal(r) ? tr('book.mine') : (data.groupById(r.bookId)?.name ?? tr('family.defaultName'));

  String? bookOf(Recipe r) => r.bookId ?? data.personalBookId;

  Recipe? recipeById(String id) {
    for (final r in data.recipes) {
      if (r.id == id && !r.deleted) return r;
    }
    return null;
  }

  /// Ricette che si possono inserire in un menù dello stesso ricettario.
  List<Recipe> menuCandidates(Recipe menu) => sortedForList(recipes.where((r) =>
      r.id != menu.id &&
      r.category != RecipeCategory.menu &&
      (isPersonal(menu) ? isPersonal(r) || isMine(r) : r.bookId == menu.bookId)));

  // ---- Avvio, accesso, uscita ----

  Future<void> init() async {
    final settings = await store.readSettings();
    theme = ThemeSettings.fromJson(settings);
    langPref = settings?['lang'] as String?;
    sortNewestFirst = settings?['sortNewest'] == true;
    photos.downloader = (book, id) => isCloud ? sync.downloadPhoto(book, id) : Future.value(null);
    notifyListeners();
    try {
      await notifications.init();
    } catch (_) {}
    var s = await store.readSession();
    if (s != null && s.mode == AccountMode.cloud && !auth.cloudSessionValid(s)) {
      s = null;
    }
    if (s != null) {
      await _open(s);
    }
    loading = false;
    notifyListeners();
    UpdateService.instance.start(pushAvailable: auth.cloudAvailable);
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
    if (since == null) {
      watch.seen[bookId] = remote.isEmpty ? DateTime.now().millisecondsSinceEpoch : maxTs;
      for (final r in remote) {
        if (!r.deleted) watch.remember(r.id);
      }
      await watch.save();
      return;
    }
    if (maxTs <= since) return;
    final acts = findActivities(
      groupName: data.groupById(bookId)?.name ?? tr('family.defaultName'),
      me: s.key,
      myName: s.displayName,
      since: since,
      remote: remote,
      existed: (id) => existedBefore.contains(id) || watch.known.contains(id),
    );
    watch.seen[bookId] = maxTs;
    for (final r in remote) {
      if (!r.deleted) watch.remember(r.id);
    }
    await watch.save();
    if (watch.enabled && acts.isNotEmpty) {
      await showActivities(notifications, acts);
    }
  }

  Future<void> startPush() async {
    final s = session;
    if (s == null || s.mode != AccountMode.cloud || !auth.cloudAvailable) return;
    await push.start(s.key, onForeground: (title, body) {
      notifications.showRemote(title, body);
    });
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
      final gone = old.photoIds.difference(r.photoIds);
      for (final p in gone) {
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

  Recipe _tombstone(Recipe r, int now) => Recipe(
        id: r.id,
        category: r.category,
        title: r.title,
        createdBy: r.createdBy,
        createdByName: r.createdByName,
        createdAt: r.createdAt,
        updatedAt: now,
        updatedBy: session?.displayName ?? '',
        updatedByUid: session?.key ?? '',
        deleted: true,
        bookId: r.bookId,
      );

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
      });

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
    if (isCloud) {
      if (!push.registered) startPush();
      await _startSync();
    }
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
    for (final r in remote) {
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

  Future<FamilyGroup> createGroup(String name) async {
    final g = await sync.createGroup(session!, name);
    if (data.groupById(g.id) == null) data.groups.add(g);
    await _persist();
    notifyListeners();
    return g;
  }

  Future<FamilyGroup> joinGroup(String code) async {
    final g = await sync.joinGroup(session!, code);
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
}
