import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:in_app_update/in_app_update.dart';

class UpdateService with WidgetsBindingObserver {
  static const String topic = 'updates';
  static final UpdateService instance = UpdateService._();
  UpdateService._();

  bool _started = false;
  bool _running = false;
  DateTime? _lastCheck;

  void start({required bool pushAvailable}) {
    if (_started || !Platform.isAndroid) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    if (pushAvailable) {
      FirebaseMessaging.instance.subscribeToTopic(topic).catchError((_) {});
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _lastCheck;
    if (last == null || DateTime.now().difference(last) > const Duration(minutes: 30)) {
      check();
    }
  }

  Future<void> check() async {
    if (_running) return;
    _running = true;
    _lastCheck = DateTime.now();
    try {
      final info = await InAppUpdate.checkForUpdate();
      final available = info.updateAvailability == UpdateAvailability.updateAvailable ||
          info.updateAvailability == UpdateAvailability.developerTriggeredUpdateInProgress;
      if (available && info.immediateUpdateAllowed) {
        final result = await InAppUpdate.performImmediateUpdate();
        if (result == AppUpdateResult.userDeniedUpdate) {
          await SystemNavigator.pop();
        }
      }
    } catch (_) {
    } finally {
      _running = false;
    }
  }
}
