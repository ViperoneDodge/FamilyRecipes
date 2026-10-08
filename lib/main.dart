import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'firebase_config.dart';
import 'l10n.dart';
import 'screens/home_screen.dart';
import 'screens/intro_screen.dart';
import 'screens/login_screen.dart';
import 'services/app_state.dart';
import 'services/group_watch.dart';
import 'services/local_store.dart';
import 'theme.dart';

late final AppState appState;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final settings = await LocalStore().readSettings();
    await L10n.load(L10n.resolve(settings?['lang'] as String?));
  } catch (_) {
    await L10n.load('en');
  }
  if (FirebaseConfig.isConfigured) {
    try {
      await Firebase.initializeApp();
    } catch (_) {
      try {
        await Firebase.initializeApp(options: FirebaseConfig.options);
      } catch (_) {}
    }
  }
  await initGroupWatch();
  await applyOrientationLock();
  appState = AppState();
  runApp(const FamilyRecipesApp());
  appState.init();
}

/// Sotto questo lato minimo (in dp) lo schermo è un telefono.
const double phoneMaxShortestSide = 600;

bool? _portraitLocked;

/// Sui telefoni l'app resta sempre verticale; su tablet e pieghevoli aperti ruota liberamente.
Future<void> applyOrientationLock() async {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) return;
  final v = views.first;
  if (v.physicalSize.isEmpty) return;
  final phone = (v.physicalSize / v.devicePixelRatio).shortestSide < phoneMaxShortestSide;
  if (_portraitLocked == phone) return;
  _portraitLocked = phone;
  await SystemChrome.setPreferredOrientations(
      phone ? const [DeviceOrientation.portraitUp] : const <DeviceOrientation>[]);
}

class FamilyRecipesApp extends StatefulWidget {
  const FamilyRecipesApp({super.key});

  @override
  State<FamilyRecipesApp> createState() => _FamilyRecipesAppState();
}

class _FamilyRecipesAppState extends State<FamilyRecipesApp> with WidgetsBindingObserver {
  bool _introDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.delayed(const Duration(milliseconds: 2300), () {
      if (mounted) setState(() => _introDone = true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Un pieghevole che si apre o si chiude cambia dimensione: si ricontrolla il blocco.
  @override
  void didChangeMetrics() => applyOrientationLock();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && appState.syncStatus == SyncStatus.offline) {
      appState.retrySync();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final t = appState.theme;
        final supported = [for (final c in L10n.available) Locale(c)];
        final current = Locale(L10n.code);
        return MaterialApp(
          title: 'FamilyRecipes',
          debugShowCheckedModeBanner: false,
          locale: supported.contains(current) ? current : const Locale('en'),
          supportedLocales: supported,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          themeMode: t.mode,
          theme: buildTheme(t, Brightness.light),
          darkTheme: buildTheme(t, Brightness.dark),
          home: AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: (!_introDone || appState.loading)
                ? const IntroScreen(key: ValueKey('intro'))
                : appState.session == null
                    ? const LoginScreen(key: ValueKey('login'))
                    : const HomeScreen(key: ValueKey('home')),
          ),
        );
      },
    );
  }
}
