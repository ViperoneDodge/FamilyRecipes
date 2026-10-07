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
    final uri = Uri.parse('mailto:$email'
        '?subject=${Uri.encodeComponent(subject)}'
        '&body=${Uri.encodeComponent(body)}');
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openPrivacy() async {
    try {
      return await launchUrl(Uri.parse(privacyUrl), mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
