import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import '../models.dart';
import 'local_store.dart';

/// Foto delle ricette: file JPEG sul telefono (`foto/{id}.jpg`), scaricati da
/// Firestore la prima volta che servono.
class PhotoStore {
  final LocalStore store;
  PhotoStore(this.store);

  /// Scarica la foto `photoId` dal ricettario `bookId`; null se non c'è.
  Future<Uint8List?> Function(String bookId, String photoId)? downloader;

  final LinkedHashMap<String, Uint8List> _mem = LinkedHashMap();
  final Map<String, Future<Uint8List?>> _loading = {};
  static const int _memMax = 40;

  Future<File> file(String id) async => File('${(await store.photosDir()).path}/$id.jpg');

  Future<bool> exists(String id) async => (await file(id)).exists();

  Uint8List? cached(String id) => _mem[id];

  void _remember(String id, Uint8List b) {
    _mem.remove(id);
    _mem[id] = b;
    while (_mem.length > _memMax) {
      _mem.remove(_mem.keys.first);
    }
  }

  Future<String> add(Uint8List bytes) async {
    final id = newId(14);
    await (await file(id)).writeAsBytes(bytes, flush: true);
    _remember(id, bytes);
    return id;
  }

  Future<Uint8List?> read(String id) async {
    final m = _mem[id];
    if (m != null) return m;
    try {
      final f = await file(id);
      if (await f.exists()) {
        final b = await f.readAsBytes();
        _remember(id, b);
        return b;
      }
    } catch (_) {}
    return null;
  }

  /// Legge la foto dal telefono o, se manca, la scarica dal ricettario.
  Future<Uint8List?> load(String id, {String? bookId}) {
    final m = _mem[id];
    if (m != null) return Future.value(m);
    return _loading.putIfAbsent(id, () async {
      try {
        final local = await read(id);
        if (local != null) return local;
        final dl = downloader;
        if (dl == null || bookId == null) return null;
        final b = await dl(bookId, id);
        if (b == null) return null;
        await (await file(id)).writeAsBytes(b, flush: true);
        _remember(id, b);
        return b;
      } catch (_) {
        return null;
      } finally {
        _loading.remove(id);
      }
    });
  }

  Future<void> delete(String id) async {
    _mem.remove(id);
    try {
      final f = await file(id);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
