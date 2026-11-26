import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../models.dart';
import '../version.dart';

/// Contenuto di un backup: ricette (con il ricettario di provenienza), foto e preferiti.
///
/// Nei backup `.zip` (dalla 1.10.2) le foto restano nel file e si leggono una alla volta con [photo]:
/// così anche un ricettario con centinaia di foto si ripristina senza riempire la memoria del telefono.
class BackupData {
  final DateTime at;
  final String reason;
  final List<Recipe> recipes;
  final Map<String, Uint8List> photos;
  final Set<String> favorites;

  /// Pianificazione dei pasti (null nei backup senza).
  final MealPlan? plan;

  /// File `.zip` da cui leggere le foto (null per i backup `.json` di prima, con le foto dentro).
  final String? zipPath;

  const BackupData(this.at, this.reason, this.recipes, this.photos, this.favorites, {this.zipPath, this.plan});

  Future<Uint8List?> photo(String id) async {
    final m = photos[id];
    if (m != null) return m;
    final zip = zipPath;
    if (zip == null || !BackupService.safePhotoId(id)) return null;
    return Isolate.run(() => BackupService.zipPhotoSync(zip, id));
  }
}

class BackupInfo {
  final File file;
  final DateTime at;
  final int recipes;
  final String reason;
  const BackupInfo(this.file, this.at, this.recipes, this.reason);

  String get name => file.uri.pathSegments.last;
}

/// Copie complete delle ricette sul telefono (le ultime [keep]) e in file da conservare altrove.
///
/// Formato attuale: `.zip` con `backup.json` (ricette e preferiti) e `photos/<id>.jpg`, scritto e letto una
/// foto alla volta. Si leggono ancora i `.json` delle versioni 1.9–1.10.1 (foto in base64 nel file), fino a
/// [maxBytes]: oltre, decodificarli tutti insieme può esaurire la memoria del telefono.
class BackupService {
  static const int keep = 3;
  static const int maxBytes = 60 * 1024 * 1024;
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
    MealPlan? plan,
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
        if (plan != null) 'plan': plan.toJson(),
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

  static BackupData? decode(Uint8List bytes, {String? zipPath}) {
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
      return BackupData(_at(m['at']), m['reason'] is String ? m['reason'] as String : '', recipes, photos,
          zipPath: zipPath, plan: m['plan'] is Map ? MealPlan.fromJson(m['plan']) : null, {
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

  static bool _isZip(List<int> head) => head.length >= 4 && head[0] == 0x50 && head[1] == 0x4B;

  static List<int> _head(String path) {
    final raf = File(path).openSync();
    try {
      return raf.readSync(4);
    } finally {
      raf.closeSync();
    }
  }

  /// `backup.json` di un backup `.zip` (senza toccare le foto).
  static Uint8List? _zipJsonSync(String path) {
    final input = InputFileStream(path);
    try {
      final f = ZipDecoder().decodeStream(input).findFile('backup.json');
      return f?.readBytes();
    } catch (_) {
      return null;
    } finally {
      input.closeSync();
    }
  }

  /// Una foto di un backup `.zip`.
  static Uint8List? zipPhotoSync(String path, String id) {
    final input = InputFileStream(path);
    try {
      return ZipDecoder().decodeStream(input).findFile('photos/$id.jpg')?.readBytes();
    } catch (_) {
      return null;
    } finally {
      input.closeSync();
    }
  }

  static Future<({BackupData? data, String why})> readFile(String path) => Isolate.run(() {
        if (_isZip(_head(path))) {
          final json = _zipJsonSync(path);
          if (json == null) return (data: null, why: 'zip');
          final d = decode(json, zipPath: path);
          return (data: d, why: d == null ? diagnose(json) : '');
        }
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
        if (_isZip(bytes)) {
          // Il file è già tutto in memoria (scelto senza percorso): si estraggono anche le foto.
          try {
            final arc = ZipDecoder().decodeBytes(bytes);
            final json = arc.findFile('backup.json')?.readBytes();
            final d = json == null ? null : decode(json);
            if (d == null) return (data: null, why: 'zip');
            for (final f in arc.files) {
              final m = RegExp(r'^photos/([A-Za-z0-9_-]{1,64})\.jpg$').firstMatch(f.name);
              final b = m == null ? null : f.readBytes();
              if (m != null && b != null) d.photos[m[1]!] = b;
            }
            return (data: d, why: '');
          } catch (_) {
            return (data: null, why: 'zip');
          }
        }
        final d = decode(bytes);
        return (data: d, why: d == null ? diagnose(bytes) : '');
      });

  static String fileName(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'FamilyRecipes_backup_${at.year}-${two(at.month)}-${two(at.day)}_${two(at.hour)}${two(at.minute)}${two(at.second)}.json';
  }

  static String zipName(DateTime at) => fileName(at).replaceFirst(RegExp(r'\.json$'), '.zip');

  /// Scrive un backup `.zip` sul telefono una foto alla volta ([photo] la legge o la scarica) e tiene gli
  /// ultimi [keep] backup, più [protect].
  static Future<File> saveZip(
    String user, {
    required List<Recipe> recipes,
    required Set<String> favorites,
    required String reason,
    required DateTime at,
    required Future<Uint8List?> Function(Recipe r, String photoId) photo,
    File? protect,
    MealPlan? plan,
  }) async {
    final d = await _dir(user);
    var f = File('${d.path}/${zipName(at)}');
    var i = 2;
    while (await f.exists()) {
      f = File('${d.path}/${zipName(at).replaceFirst('.zip', '_$i.zip')}');
      i++;
    }
    final tmp = File('${f.path}.tmp');
    final enc = ZipFileEncoder()..create(tmp.path);
    try {
      final live = [for (final r in recipes) if (!r.deleted) r];
      enc.addArchiveFile(
          ArchiveFile.bytes('backup.json', encode(recipes: live, photos: const {}, favorites: favorites, reason: reason, at: at, plan: plan)));
      final done = <String>{};
      for (final r in live) {
        for (final p in r.photoIds) {
          if (!safePhotoId(p) || !done.add(p)) continue;
          Uint8List? b;
          try {
            b = await photo(r, p);
          } catch (_) {}
          if (b == null) continue;
          // Le foto sono già JPEG: si salvano senza ricomprimerle.
          enc.addArchiveFile(ArchiveFile.bytes('photos/$p.jpg', b)..compression = CompressionType.none);
        }
      }
    } finally {
      await enc.close();
    }
    await tmp.rename(f.path);
    await _prune(d, {f.path, if (protect != null) protect.path});
    return f;
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
      if (e is! File || !(e.path.endsWith('.json') || e.path.endsWith('.zip'))) continue;
      final path = e.path;
      // Legge solo l'intestazione (data, motivo, numero di ricette), senza decodificare le foto.
      final r = await Isolate.run(() {
        final bytes = path.endsWith('.zip') ? _zipJsonSync(path) : File(path).readAsBytesSync();
        final m = bytes == null ? null : _root(bytes);
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
