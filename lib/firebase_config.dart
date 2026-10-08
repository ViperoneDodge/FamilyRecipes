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
