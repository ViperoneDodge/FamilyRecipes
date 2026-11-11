import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';

/// Valori del progetto Firebase (da `google-services.json`).
/// Finché sono vuoti l'app funziona solo in locale, sul telefono.
class FirebaseConfig {
  static const String apiKey = 'AIzaSyDZX2_c3Ec48MTLzE9O-60Ygu0yKSyfPr4';
  static const String appId = '1:524842949858:android:3fc43e55f28b1e430b12bb';
  static const String messagingSenderId = '524842949858';
  static const String projectId = 'familyrecipes-46e1a';
  static const String storageBucket = 'familyrecipes-46e1a.firebasestorage.app';

  /// "Web client ID" (OAuth client di tipo 3) per l'accesso con Google.
  static const String googleWebClientId =
      '524842949858-l83kjtgbi8kt1sukjjclacuk78v5q722.apps.googleusercontent.com';

  // ---- iPhone ----
  // Dalla console Firebase → Impostazioni progetto → app iOS (it.familyrecipes.familyrecipes):
  // API_KEY, GOOGLE_APP_ID e CLIENT_ID del file GoogleService-Info.plist. Finché sono vuoti, su iPhone l'app
  // funziona solo in locale. tool/patch_ios.py legge CLIENT_ID da qui per lo schema URL di Google.
  static const String iosApiKey = 'AIzaSyD5qdmzpxdYby-N6SE2wZ2hQM6TAbsMn8M';
  static const String iosAppId = '1:524842949858:ios:8d851ac1fb98d4de0b12bb';
  static const String iosClientId =
      '524842949858-rs203bkcajijr453acnggdgn69jj7fbb.apps.googleusercontent.com';
  static const String iosBundleId = 'it.familyrecipes.familyrecipes';

  static bool get _ios {
    try {
      return Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  static bool get isConfigured =>
      apiKey.isNotEmpty && projectId.isNotEmpty && (_ios ? iosAppId.isNotEmpty : appId.isNotEmpty);

  static FirebaseOptions get options => FirebaseOptions(
        apiKey: _ios ? iosApiKey : apiKey,
        appId: _ios ? iosAppId : appId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
        storageBucket: storageBucket,
        iosClientId: iosClientId.isEmpty ? null : iosClientId,
        iosBundleId: iosBundleId,
      );

  /// Avvia Firebase con `google-services.json` o, se manca, con i valori qui sopra.
  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
    } catch (_) {
      try {
        await Firebase.initializeApp(options: options);
      } catch (_) {}
    }
  }
}
