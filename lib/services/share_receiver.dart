import 'package:flutter/services.dart';

/// Testi condivisi da altre app (es. il link di una ricetta dal browser), dal codice Android
/// di MainActivity: quello che ha aperto l'app e quelli che arrivano dopo.
class ShareReceiver {
  static const MethodChannel _channel = MethodChannel('familyrecipes/share');

  static Future<void> listen(void Function(String text) onText) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shared' && call.arguments is String) onText(call.arguments as String);
    });
    try {
      final first = await _channel.invokeMethod<String>('initialText');
      if (first != null && first.trim().isNotEmpty) onText(first);
    } on MissingPluginException {
      // Non su Android (o nei test).
    } on PlatformException {
      // Nessun testo condiviso.
    }
  }
}
