import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../l10n.dart';

/// Notifiche locali: avvisi sulle novità nei gruppi (nuove ricette, modifiche).
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const String channelId = 'famiglia';
  static const Color _color = Color(0xFFB4532A);

  Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@drawable/ic_stat_notify');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(const InitializationSettings(android: android, iOS: ios));
    _ready = true;
    await refreshChannels();
  }

  Future<void> refreshChannels() async {
    if (!_ready) return;
    await _android?.createNotificationChannel(AndroidNotificationChannel(
      channelId,
      tr('channel.family'),
      description: tr('channel.familyDesc'),
      importance: Importance.high,
    ));
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => Platform.isAndroid
      ? _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      : null;

  Future<bool> enabled() async {
    await init();
    final a = _android;
    if (a == null) return true;
    try {
      return await a.areNotificationsEnabled() ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> requestPermission() async {
    await init();
    if (Platform.isAndroid) {
      try {
        await _android?.requestNotificationsPermission();
      } catch (_) {}
    } else if (Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  static NotificationDetails get _details => NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          tr('channel.family'),
          channelDescription: tr('channel.familyDesc'),
          importance: Importance.high,
          priority: Priority.high,
          color: _color,
        ),
        iOS: const DarwinNotificationDetails(),
      );

  Future<void> showRemote(String? title, String? body) async {
    await init();
    await _plugin.show(
      100000 + DateTime.now().millisecondsSinceEpoch % 800000,
      title ?? 'FamilyRecipes',
      body,
      _details,
    );
  }

  Future<void> showTest() async {
    await init();
    await _plugin.show(0, tr('notify.testTitle'), tr('notify.testBody'), _details);
  }
}
