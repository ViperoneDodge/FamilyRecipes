import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../l10n.dart';
import '../models.dart';

class GroupException implements Exception {
  final String message;
  GroupException(this.message);
  @override
  String toString() => message;
}

String cloudErrorMessage(Object e) {
  if (e is GroupException) return e.message;
  if (e is TimeoutException) return tr('cloud.offline');
  if (e is FirebaseException) {
    switch (e.code) {
      case 'permission-denied':
        return tr('cloud.permissionDenied');
      case 'not-found':
        return (e.message ?? '').contains('database')
            ? tr('cloud.noDatabase')
            : tr('family.badCode');
      case 'unavailable':
      case 'deadline-exceeded':
        return tr('cloud.offline');
      case 'unauthenticated':
        return tr('cloud.unauthenticated');
      default:
        return tr('cloud.generic', {'code': e.code});
    }
  }
  return tr('cloud.generic', {'code': e.toString()});
}

/// Struttura su Firestore:
///   books/{uid}                  ricettario personale
///   books/{groupId}              ricettario di un gruppo (membri, admin, sola lettura)
///   books/{id}/recipes/{id}      ricette (solo testo)
///   books/{id}/photos/{id}       foto in JPEG base64, un documento per foto
class SyncService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _books => _db.collection('books');

  static const Duration _timeout = Duration(seconds: 20);

  StreamSubscription? _groupsSub;
  final Map<String, StreamSubscription> _recipeSubs = {};
  final Set<String> _initialPushDone = {};

  Future<String> ensurePersonal(Session s) async {
    final ref = _books.doc(s.key);
    final snap = await ref.get(const GetOptions(source: Source.server));
    if (!snap.exists) {
      await ref.set({
        'personal': true,
        'name': 'Le mie ricette',
        'ownerUid': s.key,
        'members': [s.key],
        'memberEmails': {s.key: s.email ?? s.displayName},
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
    }
    return s.key;
  }

  Future<FamilyGroup> createGroup(Session s, String name) async {
    final id = newId(10);
    final email = s.email ?? s.displayName;
    await _books.doc(id).set({
      'personal': false,
      'name': name,
      'ownerUid': s.key,
      'members': [s.key],
      'memberEmails': {s.key: email},
      'admins': [s.key],
      'viewers': [],
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    }).timeout(_timeout);
    return FamilyGroup(id: id, name: name, ownerUid: s.key, members: {s.key: email}, admins: {s.key});
  }

  Future<FamilyGroup> joinGroup(Session s, String code) async {
    final id = code.trim().toUpperCase().replaceAll(' ', '');
    if (id.isEmpty || id == s.key) throw GroupException(tr('family.badCode'));
    final ref = _books.doc(id);
    final snap = await ref.get(const GetOptions(source: Source.server)).timeout(_timeout);
    final data = snap.data();
    if (!snap.exists || data == null || data['personal'] == true) {
      throw GroupException(tr('family.badCode'));
    }
    final already = ((data['members'] as List?) ?? const []).contains(s.key);
    if (!already) {
      await ref.update({
        'members': FieldValue.arrayUnion([s.key]),
        'memberEmails.${s.key}': s.email ?? s.displayName,
        'viewers': FieldValue.arrayUnion([s.key]),
      }).timeout(_timeout);
    }
    return FamilyGroup(
      id: id,
      name: (data['name'] as String?) ?? tr('family.defaultName'),
      ownerUid: (data['ownerUid'] as String?) ?? '',
      viewers: already ? {} : {s.key},
    );
  }

  Future<void> saveProfile(Session s) => _db.collection('users').doc(s.key).set({
        'name': s.displayName,
        'email': s.email ?? '',
        'seenAt': DateTime.now().millisecondsSinceEpoch,
      }, SetOptions(merge: true)).timeout(_timeout);

  // ---- Amministrazione ----

  Stream<List<Map<String, dynamic>>> watchAllUsers() => _db
      .collection('users')
      .snapshots()
      .map((q) => q.docs.map((d) => {...d.data(), 'uid': d.id}..remove('tokens')).toList());

  Stream<List<Map<String, dynamic>>> watchAllBooks() =>
      _books.snapshots().map((q) => q.docs.map((d) => {...d.data(), 'id': d.id}).toList());

  Stream<List<Recipe>> watchAllRecipes() => _db.collectionGroup('recipes').snapshots().map((q) {
        final out = <Recipe>[];
        for (final d in q.docs) {
          final book = d.reference.parent.parent?.id;
          if (book == null) continue;
          try {
            final r = Recipe.fromJson(d.data())..bookId = book;
            if (!r.deleted) out.add(r);
          } catch (_) {}
        }
        return out;
      });

  /// L'amministratore cambia l'autore di una ricetta. Una ricetta personale passa
  /// nel ricettario personale del nuovo autore (foto comprese).
  Future<void> reassignRecipe(Recipe r, String toUid, String toName,
      {required bool personal, required Session admin}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final from = r.bookId!;
    final updated = Recipe.fromJson(r.toJson())
      ..createdBy = toUid
      ..createdByName = toName
      ..updatedAt = now
      ..updatedBy = admin.displayName
      ..updatedByUid = admin.key
      ..bookId = null;
    if (!personal) {
      await _recipes(from).doc(r.id).set(updated.toJson()).timeout(_timeout);
      return;
    }
    final moved = updated..id = newId();
    for (final p in r.photoIds) {
      final snap = await _photos(from).doc(p).get().timeout(_timeout);
      final data = snap.data();
      if (data != null) {
        await _photos(toUid).doc(p).set({...data, 'recipeId': moved.id}).timeout(_timeout);
      }
    }
    final tomb = _tombstone(r, now, admin);
    final batch = _db.batch()
      ..set(_recipes(toUid).doc(moved.id), moved.toJson())
      ..set(_recipes(from).doc(r.id), tomb.toJson());
    await batch.commit().timeout(_timeout);
    for (final p in r.photoIds) {
      _photos(from).doc(p).delete().catchError((_) {});
    }
  }

  Recipe _tombstone(Recipe r, int now, Session by) => Recipe(
        id: r.id,
        category: r.category,
        title: r.title,
        createdBy: r.createdBy,
        createdByName: r.createdByName,
        createdAt: r.createdAt,
        updatedAt: now,
        updatedBy: by.displayName,
        updatedByUid: by.key,
        deleted: true,
      );

  Future<void> deleteAllData(Session s, List<FamilyGroup> groups) async {
    final uid = s.key;
    Future<void> wipe(String bookId) async {
      for (final col in [_recipes(bookId), _photos(bookId)]) {
        final q = await col.get(const GetOptions(source: Source.server)).timeout(_timeout);
        for (final d in q.docs) {
          await d.reference.delete().timeout(_timeout);
        }
      }
    }

    for (final g in groups) {
      if (g.ownerUid == uid) {
        await wipe(g.id);
        await _books.doc(g.id).delete().timeout(_timeout);
      } else {
        await leaveGroup(s, g.id).timeout(_timeout);
      }
    }
    await wipe(uid);
    await _books.doc(uid).delete().timeout(_timeout);
    await _db.collection('users').doc(uid).delete().timeout(_timeout);
  }

  Future<void> leaveGroup(Session s, String id) => _books.doc(id).update({
        'members': FieldValue.arrayRemove([s.key]),
        'memberEmails.${s.key}': FieldValue.delete(),
        'viewers': FieldValue.arrayRemove([s.key]),
        'admins': FieldValue.arrayRemove([s.key]),
      });

  Future<void> removeMember(String groupId, String uid) => _books.doc(groupId).update({
        'members': FieldValue.arrayRemove([uid]),
        'memberEmails.$uid': FieldValue.delete(),
        'viewers': FieldValue.arrayRemove([uid]),
      });

  Future<void> setRole(String groupId, String uid, GroupRole role) {
    final Map<String, dynamic> change;
    switch (role) {
      case GroupRole.admin:
        change = {'admins': FieldValue.arrayUnion([uid]), 'viewers': FieldValue.arrayRemove([uid])};
        break;
      case GroupRole.editor:
        change = {'admins': FieldValue.arrayRemove([uid]), 'viewers': FieldValue.arrayRemove([uid])};
        break;
      case GroupRole.viewer:
        change = {'admins': FieldValue.arrayRemove([uid]), 'viewers': FieldValue.arrayUnion([uid])};
        break;
    }
    return _books.doc(groupId).update(change).timeout(_timeout);
  }

  /// Elimina il gruppo: prima ricette e foto, poi il documento del gruppo.
  Future<void> deleteGroup(String id) async {
    for (final col in [_recipes(id), _photos(id)]) {
      try {
        final q = await col.get().timeout(_timeout);
        for (final d in q.docs) {
          await d.reference.delete();
        }
      } catch (_) {}
    }
    await _books.doc(id).delete();
  }

  Future<void> renameGroup(String id, String name) => _books.doc(id).update({'name': name});

  // ---- Ricette e foto ----

  CollectionReference<Map<String, dynamic>> _recipes(String bookId) =>
      _books.doc(bookId).collection('recipes');

  CollectionReference<Map<String, dynamic>> _photos(String bookId) =>
      _books.doc(bookId).collection('photos');

  void start({
    required Session session,
    required String personalId,
    required void Function(List<FamilyGroup> groups) onGroups,
    required void Function(String bookId, List<Recipe> remote, bool fromServer) onRecipes,
    required List<Recipe> Function(String bookId) localRecipes,
    required void Function(String bookId, Recipe r) pushRecipe,
  }) {
    stop();
    _listenRecipes(personalId, onRecipes, localRecipes, pushRecipe);
    _groupsSub = _books.where('members', arrayContains: session.key).snapshots().listen((snap) {
      final groups = <FamilyGroup>[];
      for (final d in snap.docs) {
        final data = d.data();
        if (data['personal'] == true) continue;
        groups.add(FamilyGroup.fromDoc(d.id, data));
      }
      final wanted = {personalId, ...groups.map((g) => g.id)};
      for (final id in _recipeSubs.keys.toList()) {
        if (!wanted.contains(id)) {
          _recipeSubs.remove(id)?.cancel();
          _initialPushDone.remove(id);
        }
      }
      for (final g in groups) {
        _listenRecipes(g.id, onRecipes, localRecipes, pushRecipe);
      }
      if (!snap.metadata.isFromCache) onGroups(groups);
    }, onError: (_) {});
  }

  void _listenRecipes(
    String bookId,
    void Function(String, List<Recipe>, bool) onRecipes,
    List<Recipe> Function(String) localRecipes,
    void Function(String, Recipe) pushRecipe,
  ) {
    if (_recipeSubs.containsKey(bookId)) return;
    _recipeSubs[bookId] = _recipes(bookId).snapshots(includeMetadataChanges: true).listen((snap) {
      final remote = <Recipe>[];
      for (final d in snap.docs) {
        try {
          remote.add(Recipe.fromJson(d.data())..bookId = bookId);
        } catch (_) {}
      }
      final fromServer = !snap.metadata.isFromCache;
      onRecipes(bookId, remote, fromServer);
      if (fromServer && !_initialPushDone.contains(bookId)) {
        _initialPushDone.add(bookId);
        final byId = {for (final r in remote) r.id: r};
        for (final r in localRecipes(bookId)) {
          final rem = byId[r.id];
          if (rem == null || r.updatedAt > rem.updatedAt) pushRecipe(bookId, r);
        }
      }
    }, onError: (_) {});
  }

  void push(String bookId, Recipe r) {
    final data = r.toJson()..remove('bookId');
    _recipes(bookId).doc(r.id).set(data).catchError((_) {});
  }

  /// Carica una foto. Le scritture restano in coda se si è offline.
  Future<void> uploadPhoto(String bookId, String photoId, String recipeId, Uint8List bytes) =>
      _photos(bookId).doc(photoId).set({
        'b64': base64Encode(bytes),
        'recipeId': recipeId,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });

  void deletePhoto(String bookId, String photoId) {
    _photos(bookId).doc(photoId).delete().catchError((_) {});
  }

  Future<Uint8List?> downloadPhoto(String bookId, String photoId) async {
    final snap = await _photos(bookId).doc(photoId).get().timeout(_timeout);
    final b64 = snap.data()?['b64'] as String?;
    if (b64 == null || b64.isEmpty) return null;
    return base64Decode(b64);
  }

  void stop() {
    _groupsSub?.cancel();
    _groupsSub = null;
    for (final s in _recipeSubs.values) {
      s.cancel();
    }
    _recipeSubs.clear();
    _initialPushDone.clear();
  }
}
