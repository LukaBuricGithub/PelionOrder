import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/pin_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/auth/state/session_provider.dart';
import '../features/cashregister/presentation/cash_register_screen.dart';
import '../features/mqtt/presentation/mqtt_order_screen.dart';
import '../features/mqtt/presentation/mqtt_outbox_screen.dart';
import '../features/mqtt/presentation/mqtt_table_select_screen.dart';
import '../features/settings/presentation/settings_screen.dart';

/// App router with a redirect-based auth gate, mirroring ikasa's approach.
///
/// Flow: `/splash` while the session restores → `/login` (with `/pin` and
/// `/settings` reachable while logged out) → `/cash-register` once a waiter is
/// signed in. The menu is the signed-in home ("Unos narudžbe", "Neposlane
/// narudžbe"); back from it signs the waiter out.
final routerProvider = Provider<GoRouter>((ref) {
  // Re-evaluate redirects whenever the session or bootstrap flag changes.
  final notifier = ValueNotifier(0);
  ref.listen(currentUserProvider, (_, _) => notifier.value++);
  ref.listen(isBootstrappingProvider, (_, _) => notifier.value++);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    refreshListenable: notifier,
    initialLocation: '/splash',
    redirect: (context, state) {
      final bootstrapping = ref.read(isBootstrappingProvider);
      final path = state.uri.path;
      final isSplash = path == '/splash';

      // Stay on the splash until the persisted session is restored.
      if (bootstrapping) return isSplash ? null : '/splash';

      final loggedIn = ref.read(currentUserProvider) != null;
      final isLogin = path == '/login';
      final isPin = path == '/pin';
      final isSettings = path == '/settings';

      // Restore finished — leave the splash immediately. A signed-in waiter
      // lands on the menu.
      if (isSplash) return loggedIn ? '/cash-register' : '/login';

      if (!loggedIn) {
        // Logged out: login, PIN entry and settings are reachable.
        if (isLogin || isPin || isSettings) return null;
        return '/login';
      }

      // Logged in: keep the user out of the login flow.
      if (isLogin || isPin) return '/cash-register';
      return null;
    },
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Greška u navigaciji')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          state.error?.toString() ?? 'Nepoznata greška u navigaciji.',
        ),
      ),
    ),
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      // Login + PIN paint the same hero background and use NO page transition,
      // so switching between them is an instant, seamless swap (no fade / no
      // background re-render animation).
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: LoginScreen()),
      ),
      GoRoute(
        path: '/pin',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: PinScreen()),
      ),
      GoRoute(
        path: '/settings',
        // A cross-fade instead of the default slide/zoom: the settings screen
        // fades in over the (static) login and fades back out on return. Opacity
        // only — no sliding page to reveal both screens at once, so no flicker
        // of the other screen on a fast back.
        pageBuilder: (context, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          transitionDuration: const Duration(milliseconds: 220),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
            child: child,
          ),
          child: const SettingsScreen(),
        ),
      ),
      GoRoute(
        path: '/cash-register',
        builder: (context, state) => const CashRegisterScreen(),
      ),
      GoRoute(
        path: '/mqtt-tables',
        builder: (context, state) => const MqttTableSelectScreen(),
      ),
      GoRoute(
        path: '/mqtt-outbox',
        builder: (context, state) => const MqttOutboxScreen(),
      ),
      GoRoute(
        path: '/mqtt-menu/:broj',
        builder: (context, state) {
          final broj = int.tryParse(state.pathParameters['broj'] ?? '');
          return MqttOrderScreen(
            tableBroj: broj,
            tableNaziv: state.uri.queryParameters['naziv'],
          );
        },
      ),
    ],
  );
});
