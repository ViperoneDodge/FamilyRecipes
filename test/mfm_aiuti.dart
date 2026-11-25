// Aiuti comuni ai test «mfm_*» (adattati dalla suite del tester cattivo di MyFleetManager).
// Non è un file di test: niente main(), lo importano gli altri.
import 'dart:convert';
import 'dart:io';

import 'package:familyrecipes/models.dart';
import 'package:familyrecipes/services/app_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cartella dei documenti finta: path_provider risponde con una cartella temporanea (niente telefono,
/// niente rete). Va chiamata dentro main() dopo TestWidgetsFlutterBinding.ensureInitialized().
Directory cartellaDocumentiFinta(String nome) {
  final docs = Directory.systemTemp.createTempSync(nome);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), (call) async => docs.path);
  return docs;
}

/// Stato dell'app senza Firebase: sessione locale (o «cloud» finta, senza sincronizzazione).
AppState statoFinto({
  List<Recipe> ricette = const [],
  List<FamilyGroup> gruppi = const [],
  String key = 'mario',
  AccountMode mode = AccountMode.local,
  String? personale,
}) {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  final s = AppState()
    ..session = Session(mode: mode, key: key, displayName: key, email: '$key@example.com')
    ..data = UserData(recipes: List.of(ricette), groups: List.of(gruppi), personalBookId: personale);
  debugDefaultTargetPlatformOverride = null;
  return s;
}

Uint8List byte(String s) => Uint8List.fromList(utf8.encode(s));

/// File di backup scritto a mano (come lo farebbe un utente con il Blocco note o una versione futura).
Uint8List backupAMano(List<Object?> ricette, {Map<String, Object?> extra = const {}}) => byte(jsonEncode({
      'app': 'FamilyRecipes',
      'kind': 'backup',
      'v': 1,
      'at': '2026-11-20T10:00:00.000Z',
      'reason': 'manual',
      'recipes': ricette,
      ...extra,
    }));

/// Carica i caratteri veri (Roboto, icone Material e quelli dell'app) al posto di quello finto dei test,
/// così gli overflow trovati sono quelli che vedrebbe l'utente e non un effetto del carattere «a quadratini».
Future<void> caricaCaratteriVeri() async {
  Future<void> f(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final p in files) {
      if (File(p).existsSync()) l.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
    }
    await l.load();
  }

  // flutter_tester sta in <flutter>/bin/cache/artifacts/engine/…: da lì si risale alla cartella dei font Material.
  final exe = Platform.resolvedExecutable;
  final i = exe.indexOf('/bin/cache/');
  final root = Platform.environment['FLUTTER_ROOT'] ?? (i > 0 ? exe.substring(0, i) : '');
  final mf = '$root/bin/cache/artifacts/material_fonts';
  await f('Roboto', ['$mf/Roboto-Regular.ttf', '$mf/Roboto-Bold.ttf', '$mf/Roboto-Medium.ttf']);
  await f('MaterialIcons', ['$mf/MaterialIcons-Regular.otf']);
  await f('PatrickHand', ['assets/fonts/PatrickHand-Regular.ttf']);
}
