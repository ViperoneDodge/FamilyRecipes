import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class SupportService {
  static const String email = 'appmyfleetmanager@gmail.com';

  static const String privacyUrl = 'https://viperonedodge.github.io/FamilyRecipes/privacy.html';

  static Future<String> deviceDescription() async {
    try {
      if (Platform.isAndroid) {
        final a = await DeviceInfoPlugin().androidInfo;
        return '${a.manufacturer} ${a.model} · Android ${a.version.release} (API ${a.version.sdkInt})';
      }
      if (Platform.isIOS) {
        final i = await DeviceInfoPlugin().iosInfo;
        return '${i.utsname.machine} · iOS ${i.systemVersion}';
      }
    } catch (_) {}
    return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
  }

  static Future<bool> openEmail({required String subject, required String body}) async {
    return _open(Uri.parse('mailto:$email'
        '?subject=${Uri.encodeComponent(subject)}'
        '&body=${Uri.encodeComponent(body)}'));
  }

  static Future<bool> openPrivacy() => _open(Uri.parse(privacyUrl));

  /// Apre l'indirizzo in un'altra app; false se non si può.
  static Future<bool> _open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
