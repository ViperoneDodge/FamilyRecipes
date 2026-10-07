import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class PushService {
  String? token;
  String? _uid;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _msgSub;

  bool get registered => token != null;

  Future<void> start(
    String uid, {
    required void Function(String? title, String? body) onForeground,
  }) async {
    _uid = uid;
    try {
      final m = FirebaseMessaging.instance;
      if (Platform.isIOS) {
        await m.requestPermission(alert: true, badge: true, sound: true);
      }
      token = await m.getToken();
      if (token != null) await _save(token!);
      _tokenSub ??= m.onTokenRefresh.listen((t) {
        token = t;
        _save(t);
      });
      _msgSub ??= FirebaseMessaging.onMessage.listen((msg) {
        final n = msg.notification;
        onForeground(
          n?.title ?? msg.data['title']?.toString(),
          n?.body ?? msg.data['body']?.toString(),
        );
      });
    } catch (_) {
    }
  }

  Future<void> _save(String t) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'tokens': {t: DateTime.now().millisecondsSinceEpoch},
        'platform': Platform.isIOS ? 'ios' : 'android',
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> stop() async {
    final uid = _uid;
    final t = token;
    _uid = null;
    if (uid != null && t != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'tokens': {t: FieldValue.delete()},
        }, SetOptions(merge: true));
      } catch (_) {}
    }
    await _tokenSub?.cancel();
    _tokenSub = null;
    await _msgSub?.cancel();
    _msgSub = null;
  }
}
