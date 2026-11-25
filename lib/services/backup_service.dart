import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../models.dart';
import '../version.dart';

/// Contenuto di un backup: ricette (con il ricettario di provenienza), foto e preferiti.
class BackupData {
  final DateTime at;
  final String reason;
  final List<Recipe> recipes;
  final Map<String, Uint8List> photos;
  final Set<String> favorites;

  const BackupData(this.at, this.reason, this.recipes, this.photos, this.favorites);
}

class BackupInfo {
  final File file;
  final DateTime at;
  final int recipes;
  final String reason;
  const BackupInfo(this.file, this.at, this.recipes, this.reason);

  String get name => file.uri.pathSegments.last;
}

/// Copie complete delle ricette sul telefono (le ultime [keep]) e in file `.json` da conservare altrove.
class BackupService {
  static const int keep = 3;
  static const int maxBytes = 200 * 1024 * 1024;
  static const String _app = 'FamilyRecipes';
  static const String _kind = 'backup';

  static Directory? baseOverride;

  static Future<Directory> _dir(String user) async {
    final base = baseOverride ?? await getApplicationDocumentsDirectory();
    final safe = user.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final d = Directory('${base.path}/backups/${safe.isEmpty ? '_device' : safe}');
    await d.create(recursive: true);
    return d;
  }

  static Uint8List encode({
    required List<Recipe> recipes,
    required Map<String, Uint8List> photos,
    required Set<String> favorites,
    required String reason,
    DateTime? at,
  }) =>
      Uint8List.fromList(utf8.encode(jsonEncode({
        'app': _app,
        'kind': _kind,
        'v': 1,
        'at': (at ?? DateTime.now()).toUtc().toIso8601String(),
        'reason': reason,
        'version': appVersion,
        'recipes': [
          for (final r in recipes)
            if (!r.deleted) r.toJson()
        ],
        'photos': {for (final e in photos.entries) e.key: base64Encode(e.value)},
        'favorites': favorites.toList(),
      })));

  static Map<String, dynamic>? _root(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes) return null;
    try {
      var t = utf8.decode(bytes, allowMalformed: true);
      if (t.startsWith('﻿')) t = t.substring(1);
      final j = jsonDecode(t.replaceFirst(RegExp(r'[\u0000\s]+$'), ''));
      if (j is! Map || j['app'] != _app || j['kind'] != _kind || j['recipes'] is! List) return null;
      return Map<String, dynamic>.from(j);
    } catch (_) {
      return null;
    }
  }

  /// Id di foto usabile come nome di file (niente «../», barre o caratteri strani).
  static bool safePhotoId(String id) => RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(id);

  static DateTime _at(Object? v) =>
      (DateTime.tryParse(v is String ? v : '') ?? DateTime.fromMillisecondsSinceEpoch(0)).toLocal();

  static BackupData? decode(Uint8List bytes) {
    final m = _root(bytes);
    if (m == null) return null;
    try {
      final recipes = <Recipe>[];
      for (final e in m['recipes'] as List) {
        if (e is! Map) continue;
        try {
          final j = Map<String, dynamic>.from(e);
          // Senza id: uno stabile ricavato dal contenuto, così ripristinare due volte non crea doppioni.
          if (j['id'] is! String || (j['id'] as String).isEmpty) {
            j['id'] = 'r${sha1.convert(utf8.encode(jsonEncode(j))).toString().substring(0, 24)}';
          }
          final r = Recipe.fromJson(j);
          if (!r.deleted) recipes.add(r);
        } catch (_) {
          // Una ricetta rovinata non deve impedire di ripristinare le altre.
        }
      }
      final photos = <String, Uint8List>{};
      final p = m['photos'];
      if (p is Map) {
        p.forEach((k, v) {
          if (k is! String || v is! String || !safePhotoId(k)) return;
          try {
            photos[k] = base64Decode(v);
          } catch (_) {}
        });
      }
      final fav = m['favorites'];
      return BackupData(_at(m['at']), m['reason'] is String ? m['reason'] as String : '', recipes, photos, {
        if (fav is List)
          for (final f in fav)
            if (f is String) f
      });
    } catch (_) {
      return null;
    }
  }

  /// Breve spiegazione di un file non valido (mostrata accanto all'errore).
  static String diagnose(Uint8List bytes) {
    final mb = (bytes.length / 1048576).toStringAsFixed(1);
    if (bytes.isEmpty) return '0 MB';
    if (bytes.length > maxBytes) return '$mb MB > ${maxBytes ~/ 1048576} MB';
    try {
      var t = utf8.decode(bytes, allowMalformed: true);
      if (t.startsWith('﻿')) t = t.substring(1);
      final j = jsonDecode(t.replaceFirst(RegExp(r'[\u0000\s]+$'), ''));
      if (j is! Map) return '$mb MB, type';
      if (j['app'] != _app) return '$mb MB, app';
      if (j['kind'] != _kind) return '$mb MB, export';
      return '$mb MB, recipes';
    } on FormatException catch (e) {
      return '$mb MB, json@${e.offset ?? '?'}';
    } catch (_) {
      return '$mb MB';
    }
  }

  static Future<({BackupData? data, String why})> readFile(String path) => Isolate.run(() {
        final f = File(path);
        final len = f.lengthSync();
        if (len > maxBytes) {
          return (data: null, why: '${(len / 1048576).toStringAsFixed(1)} MB > ${maxBytes ~/ 1048576} MB');
        }
        final b = f.readAsBytesSync();
        final d = decode(b);
        return (data: d, why: d == null ? diagnose(b) : '');
      });

  static Future<({BackupData? data, String why})> readBytes(Uint8List bytes) => Isolate.run(() {
        final d = decode(bytes);
        return (data: d, why: d == null ? diagnose(bytes) : '');
      });

  static String fileName(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'FamilyRecipes_backup_${at.year}-${two(at.month)}-${two(at.day)}_${two(at.hour)}${two(at.minute)}${two(at.second)}.json';
  }

  static Future<File> save(String user, Uint8List bytes, DateTime at, {File? protect}) async {
    if (bytes.length > maxBytes) throw const FileSystemException('backup too large');
    final d = await _dir(user);
    var f = File('${d.path}/${fileName(at)}');
    var i = 2;
    while (await f.exists()) {
      f = File('${d.path}/${fileName(at).replaceFirst('.json', '_$i.json')}');
      i++;
    }
    await f.writeAsBytes(bytes, flush: true);
    await _prune(d, {f.path, if (protect != null) protect.path});
    return f;
  }

  static Future<List<BackupInfo>> _read(Directory d) async {
    final out = <BackupInfo>[];
    await for (final e in d.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      final path = e.path;
      // Legge solo l'intestazione (data, motivo, numero di ricette), senza decodificare le foto.
      final r = await Isolate.run(() {
        final m = _root(File(path).readAsBytesSync());
        return m == null ? null : (at: _at(m['at']), n: (m['recipes'] as List).length, reason: m['reason'] is String ? m['reason'] as String : '');
      });
      out.add(BackupInfo(e, r?.at ?? DateTime.fromMillisecondsSinceEpoch(0), r?.n ?? -1, r?.reason ?? ''));
    }
    out.sort((a, b) {
      final c = b.at.compareTo(a.at);
      return c != 0 ? c : b.file.path.compareTo(a.file.path);
    });
    return out;
  }

  static Future<void> _prune(Directory d, Set<String> keepPaths) async {
    final all = await _read(d);
    var room = keep - keepPaths.length;
    for (final b in all) {
      if (keepPaths.contains(b.file.path)) continue;
      if (b.recipes >= 0 && room > 0) {
        room--;
        continue;
      }
      try {
        await b.file.delete();
      } catch (_) {}
    }
  }

  static Future<List<BackupInfo>> list(String user) async {
    final d = await _dir(user);
    return [
      for (final b in await _read(d))
        if (b.recipes >= 0) b
    ];
  }
}
