import 'package:firebase_core/firebase_core.dart';

/// Valori del progetto Firebase (da `google-services.json`).
/// Finché sono vuoti l'app funziona solo in locale, sul telefono.
class FirebaseConfig {
  static const String apiKey = '';
  static const String appId = '';
  static const String messagingSenderId = '';
  static const String projectId = '';
  static const String storageBucket = '';

  /// "Web client ID" (OAuth client di tipo 3) per l'accesso con Google.
  static const String googleWebClientId = '';

  static bool get isConfigured =>
      apiKey.isNotEmpty && appId.isNotEmpty && projectId.isNotEmpty;

  static FirebaseOptions get options => const FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
        storageBucket: storageBucket,
      );
}
