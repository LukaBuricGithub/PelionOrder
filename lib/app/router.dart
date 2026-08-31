import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/pin_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/auth/state/session_provider.dart';
import '../features/cashregister/presentation/cash_register_screen.dart';
import '../features/cashregister/presentation/new_order_screen.dart';
import '../features/cashregister/presentation/order_details_screen.dart';
import '../features/cashregister/presentation/orders_overview_screen.dart';
import '../features/cashregister/presentation/table_details_screen.dart';
import '../features/cashregister/presentation/table_select_screen.dart';
import '../features/cashregister/presentation/tables_overview_screen.dart';
import '../features/settings/presentation/settings_screen.dart';

/// App router with a redirect-based auth gate, mirroring ikasa's approach.
///
/// Flow: `/splash` while the session restores → `/login` (with `/pin` and
/// `/settings` reachable while logged out) → `/cash-register` once a waiter is
/// signed in. The cash-register and traffic sub-routes are added as those
/// features land.
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

      // Restore finished — leave the splash immediately.
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
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/cash-register',
        builder: (context, state) => const CashRegisterScreen(),
      ),
      GoRoute(
        path: '/table-select',
        builder: (context, state) => const TableSelectScreen(),
      ),
      GoRoute(
        path: '/new-order/:tableCode',
        builder: (context, state) {
          final code =
              int.tryParse(state.pathParameters['tableCode'] ?? '') ?? 0;
          return NewOrderScreen(tableCode: code);
        },
      ),
      GoRoute(
        path: '/order-details/:orderId',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['orderId'] ?? '') ?? 0;
          return OrderDetailsScreen(orderId: id);
        },
      ),
      GoRoute(
        path: '/tables-overview',
        builder: (context, state) => const TablesOverviewScreen(),
      ),
      GoRoute(
        path: '/table-details/:tableCode/:userCode',
        builder: (context, state) {
          final code =
              int.tryParse(state.pathParameters['tableCode'] ?? '') ?? 0;
          final userCode = state.pathParameters['userCode'] ?? '';
          return TableDetailsScreen(tableCode: code, userCode: userCode);
        },
      ),
      GoRoute(
        path: '/orders-overview',
        builder: (context, state) => const OrdersOverviewScreen(),
      ),
    ],
  );
});
