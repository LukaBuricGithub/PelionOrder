import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_theme.dart';
import 'app/router.dart';
import 'features/auth/state/auth_controller.dart';
import 'features/mqtt/data/mqtt_service.dart';
import 'features/mqtt/models/mqtt_connection_config.dart';
import 'features/mqtt/state/mqtt_table_lock_keeper.dart';
import 'features/mqtt/state/mqtt_config_provider.dart';
import 'features/mqtt/state/mqtt_outbox_provider.dart';
import 'features/shared/presentation/update_required_gate.dart';
import 'features/shared/services/crash_reporting.dart';
import 'features/shared/state/shared_preferences_provider.dart';
import 'features/theme/state/theme_mode_provider.dart';

/// The whole app runs inside one guarded zone, so an async error that nothing
/// catches — a Future thrown far from the call that started it — still reaches
/// Crashlytics instead of disappearing into the console. See [CrashReporting].
void main() {
  runZonedGuarded(_start, CrashReporting.record);
}

Future<void> _start() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();

  // Inter is bundled in assets/google_fonts/, so nothing should ever be fetched
  // from fonts.gstatic.com. In debug we forbid fetching outright: if a weight is
  // ever used that isn't bundled, google_fonts throws here instead of quietly
  // downloading it (or falling back to Roboto on a device with no internet, the
  // failure mode this bundling exists to prevent). Release keeps fetching
  // allowed purely as a safety net — a missing glyph must never crash a waiter
  // mid-service.
  GoogleFonts.config.allowRuntimeFetching = !kDebugMode;

  // Keep the OS splash on screen until we've restored the session and the
  // first real screen has painted (removed in _OrdermanAppState). This hides
  // the brief in-app spinner so startup looks like one continuous splash.
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  // Before anything that can fail, so a crash during startup is reported
  // too. Never throws: without Firebase the app simply runs unreported.
  await CrashReporting.init();

  // Resolve SharedPreferences up front so the rest of the app can read it
  // synchronously via [sharedPreferencesProvider].
  final prefs = await SharedPreferences.getInstance();

  // POS floor use is portrait-only, matching the ikasa app.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
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
    // Tag crash reports with the venue/device this phone is provisioned for,
    // and keep the tag current (see _syncCrashVenue / _syncCrashConnection).
    MqttService.instance.connected.addListener(_syncCrashConnection);
    _syncCrashConnection();
    Future.microtask(() {
      final config = ref.read(mqttConfigProvider);
      _syncCrashVenue(config);
      if (config != null) MqttService.instance.ensureConnected(config);
    });
    // Start "Neposlane narudžbe" at launch, so a confirmation for an order sent
    // before the app was closed is applied even before anyone logs in.
    Future.microtask(() => ref.read(mqttOutboxProvider));
    // Restore the persisted session (looks up the saved user in the cache),
    // then clear the bootstrapping flag so the router leaves the splash.
    Future.microtask(() async {
      await ref.read(authControllerProvider).bootstrap();
      if (!mounted) return;
      // bootstrap() flips isBootstrapping to false, so the router redirects off
      // /splash on the next frame. Lift the native splash only after that frame
      // has painted the destination screen, so the Dart spinner never shows.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => FlutterNativeSplash.remove(),
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MqttService.instance.connected.removeListener(_syncCrashConnection);
    super.dispose();
  }

  /// Venue context for crash reports. A device with no scanned code clears
  /// the keys rather than leaving the previous venue's on them.
  void _syncCrashVenue(MqttConnectionConfig? config) {
    if (config == null) {
      CrashReporting.clearVenueContext();
      return;
    }
    CrashReporting.setVenueContext(
      licenca: config.licenca,
      uredaj: config.uredaj,
      naziv: config.naziv,
    );
  }

  void _syncCrashConnection() =>
      CrashReporting.setConnected(MqttService.instance.connected.value);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        MqttService.instance.onAppResumed();
        // Claim the open table again (the `izlaz` below gave it up).
        MqttTableLockKeeper.refreshAfterResume();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // Free the open table BEFORE disconnecting: a clean disconnect means
        // the broker never publishes our last will, so the kasa would keep
        // the lock until it expires (10 min).
        MqttTableLockKeeper.releaseForBackground();
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

    // A new QR code (or a wipe) re-tags crash reports straight away.
    ref.listen<MqttConnectionConfig?>(
      mqttConfigProvider,
      (_, next) => _syncCrashVenue(next),
    );

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
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.0)),
          // The app's background under every page, so a screen fading in
          // or out shows this colour behind it rather than black.
          child: ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            // Above every page: if the store has a newer build, the waiter
            // has to update before working on (see UpdateRequiredGate).
            child: UpdateRequiredGate(child: child!),
          ),
        );
      },
      routerConfig: router,
    );
  }
}
