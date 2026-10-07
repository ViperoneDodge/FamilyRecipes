import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models.dart';

class LocalStore {
  Directory? _dir;

  Future<Directory> _base() async {
    _dir ??= await getApplicationDocumentsDirectory();
    return _dir!;
  }

  Future<File> _file(String name) async => File('${(await _base()).path}/$name');

  Future<Map<String, dynamic>?> _readJson(String name) async {
    try {
      final f = await _file(name);
      if (!await f.exists()) return null;
      final txt = await f.readAsString();
      if (txt.trim().isEmpty) return null;
      return Map<String, dynamic>.from(jsonDecode(txt) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeJson(String name, Map<String, dynamic> data) async {
    final f = await _file(name);
    final tmp = await _file('$name.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(f.path);
  }

  Future<Map<String, dynamic>> readAccounts() async =>
      await _readJson('accounts.json') ?? <String, dynamic>{};

  Future<void> writeAccounts(Map<String, dynamic> a) =>
      _writeJson('accounts.json', a);

  Future<Session?> readSession() async =>
      Session.fromJson(await _readJson('session.json'));

  Future<void> writeSession(Session? s) async {
    if (s == null) {
      final f = await _file('session.json');
      if (await f.exists()) await f.delete();
      return;
    }
    await _writeJson('session.json', s.toJson());
  }

  Future<Map<String, dynamic>?> readSettings() => _readJson('settings.json');

  Future<void> writeSettings(Map<String, dynamic> s) => _writeJson('settings.json', s);

  Future<Directory> photosDir() async {
    final d = Directory('${(await _base()).path}/foto');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<UserData> readUserData(Session s) async {
    final j = await _readJson('data_${s.storageKey}.json');
    return j == null ? UserData() : UserData.fromJson(j);
  }

  Future<void> deleteUserData(Session s) async {
    try {
      final f = await _file('data_${s.storageKey}.json');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<void> writeUserData(Session s, UserData d) =>
      _writeJson('data_${s.storageKey}.json', d.toJson());
}
