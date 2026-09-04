import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_theme.dart';
import 'app/router.dart';
import 'features/auth/state/auth_controller.dart';
import 'features/mqtt/data/mqtt_service.dart';
import 'features/mqtt/state/mqtt_config_provider.dart';
import 'features/shared/state/shared_preferences_provider.dart';
import 'features/theme/state/theme_mode_provider.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();

  // Keep the OS splash on screen until we've restored the session and the
  // first real screen has painted (removed in _OrdermanAppState). This hides
  // the brief in-app spinner so startup looks like one continuous splash.
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  // Resolve SharedPreferences up front so the rest of the app can read it
  // synchronously via [sharedPreferencesProvider].
  final prefs = await SharedPreferences.getInstance();

  // POS floor use is portrait-only, matching the ikasa app.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const OrdermanApp(),
    ),
  );
}

class OrdermanApp extends ConsumerStatefulWidget {
  const OrdermanApp({super.key});

  @override
  ConsumerState<OrdermanApp> createState() => _OrdermanAppState();
}

class _OrdermanAppState extends ConsumerState<OrdermanApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    Intl.defaultLocale = 'hr_HR';
    // Observe app lifecycle so the MQTT connection drops on background and
    // reconnects on resume.
    WidgetsBinding.instance.addObserver(this);
    // If this device has been provisioned (QR scanned at some point), connect to
    // the broker straight away — every cold start comes up already live, and the
    // resume handler above keeps it that way afterwards. Deliberately not
    // awaited: startup must not wait on the network.
    Future.microtask(() {
      final config = ref.read(mqttConfigProvider);
      if (config != null) MqttService.instance.ensureConnected(config);
    });
    // Restore the persisted session (looks up the saved user in the cache),
    // then clear the bootstrapping flag so the router leaves the splash.
    Future.microtask(() async {
      await ref.read(authControllerProvider).bootstrap();
      if (!mounted) return;
      // bootstrap() flips isBootstrapping to false, so the router redirects off
      // /splash on the next frame. Lift the native splash only after that frame
      // has painted the destination screen, so the Dart spinner never shows.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => FlutterNativeSplash.remove());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        MqttService.instance.onAppResumed();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        MqttService.instance.onAppPaused();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Pelion Order',
      locale: const Locale('hr', 'HR'),
      supportedLocales: const [Locale('hr', 'HR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      // Defaults to light; the login screen's toggle switches + persists it.
      themeMode: themeMode,
      builder: (context, child) {
        // Lock text scaling so dense POS layouts stay predictable, matching
        // the ikasa app.
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.0)),
          child: child!,
        );
      },
      routerConfig: router,
    );
  }
}
