import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/state/auth_controller.dart';
import '../../auth/state/session_provider.dart';
import '../../master_data/state/heartbeat_provider.dart';
import '../../master_data/state/master_data_providers.dart';
import '../../mqtt/data/mqtt_test.dart';
import '../../settings/state/settings_provider.dart';
import '../../shared/presentation/online_status_badge.dart';
import '../../theme/state/theme_mode_provider.dart';
import '../state/orders_providers.dart';
import 'table_select_screen.dart' show precacheTableSelectSvgs;

/// The waiter's main hub after login: signed-in user, online status, pending
/// orders, and entry points to ordering and reporting. Auto-resends queued
/// orders whenever the connection comes back. Mirrors the reference client's
/// `CashRegisterScreen`.
class CashRegisterScreen extends ConsumerStatefulWidget {
  const CashRegisterScreen({super.key});

  @override
  ConsumerState<CashRegisterScreen> createState() =>
      _CashRegisterScreenState();
}

class _CashRegisterScreenState extends ConsumerState<CashRegisterScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(heartbeatProvider.notifier).start();
      _resendPending();
      // Warm the floor-plan SVGs now so the first open of "Odabir stola" from
      // the "Unos narudžbe" menu doesn't hitch while compiling them.
      precacheTableSelectSvgs();
    });
  }

  @override
  void dispose() {
    ref.read(heartbeatProvider.notifier).stop();
    super.dispose();
  }

  Future<void> _resendPending() async {
    final sent = await ref.read(orderRepositoryProvider).sendPendingOrders();
    if (sent > 0 && mounted) {
      ref.invalidate(pendingOrdersCountProvider);
    }
  }

  /// Pull-to-refresh on the menu: refresh the Online/Offline state, re-download
  /// master data (users, groups, articles, tables), and flush any queued orders.
  Future<void> _onRefresh() async {
    await ref.read(heartbeatProvider.notifier).pingNow();
    await ref.read(masterDataRepositoryProvider).syncAll();
    if (!mounted) return;
    await _resendPending();
    if (mounted) ref.invalidate(pendingOrdersCountProvider);
  }

  /// One-shot MQTT connectivity probe against the Pelion broker.
  Future<void> _runMqttTest() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('MQTT: spajanje…')),
    );
    final result = await MqttTestService.instance.connectAndSend();
    if (!mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(result)));
  }

  Future<void> _logout() async {
    final scheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        // Icon-forward M3 dialog with stacked full-width buttons; red accent to
        // match the logout action.
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.logout_rounded,
              color: scheme.onErrorContainer, size: 26),
        ),
        title: const Text('Odjava'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Jeste li sigurni da se želite odjaviti?',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Odjava'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onSurface,
                ),
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Odustani'),
              ),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    // Signing out clears the session; the router's auth redirect
    // (refreshListenable on currentUser) then moves us to /login automatically.
    // Navigating here as well double-triggers the route change and crashes the
    // shell route with an element-lifecycle assertion — so let the redirect do it.
    await ref.read(authControllerProvider).logout();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final pending = ref.watch(pendingOrdersCountProvider).valueOrNull ?? 0;
    final businessName = ref.watch(settingsProvider).businessName;
    final theme = Theme.of(context);

    // Auto-resend the queue whenever the connection comes back up.
    ref.listen(heartbeatProvider, (prev, next) {
      if (prev != true && next == true) _resendPending();
    });

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: _SettingsDrawer(onLogout: _logout),
      appBar: AppBar(
        // Online status moved to the user card, so the venue name gets the full
        // title width and can wrap to up to 3 lines before ellipsizing.
        toolbarHeight: 88,
        title: Text(
          (businessName != null && businessName.isNotEmpty)
              ? businessName
              : 'Blagajna',
          maxLines: 3,
          softWrap: true,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Postavke',
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              // Always scrollable so the drag-down refresh works even when the
              // menu doesn't fill the screen.
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        (user?.username.isNotEmpty ?? false)
                            ? user!.username.characters.first.toUpperCase()
                            : '?',
                      ),
                    ),
                    title: Text(user?.username ?? 'Nepoznat korisnik'),
                    subtitle: Text(user?.superuser == true
                        ? 'Voditelj (superuser)'
                        : 'Konobar'),
                    trailing: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const OnlineStatusBadge(),
                        if (pending > 0) ...[
                          const SizedBox(height: 6),
                          Chip(
                            label: Text('$pending na čekanju'),
                            backgroundColor:
                                theme.colorScheme.tertiaryContainer,
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _MenuButton(
                  icon: Icons.add_shopping_cart,
                  label: 'Unos narudžbe',
                  onTap: () async {
                    await context.push('/table-select');
                    if (mounted) ref.invalidate(pendingOrdersCountProvider);
                  },
                ),
                _MenuButton(
                  icon: Icons.table_restaurant,
                  label: 'Pregled stolova',
                  onTap: () => context.push('/tables-overview'),
                ),
                _MenuButton(
                  icon: Icons.receipt_long,
                  label: 'Narudžbe',
                  onTap: () async {
                    await context.push('/orders-overview');
                    if (mounted) ref.invalidate(pendingOrdersCountProvider);
                  },
                ),
                _MenuButton(
                  icon: Icons.wifi_tethering,
                  label: 'MQTT test',
                  onTap: _runMqttTest,
                ),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(icon, color: color),
          title: Text(label, style: TextStyle(color: color)),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Right-side settings drawer (opened from the app-bar cog), holding the
/// light/dark theme switch — mirrors the ikasa app's settings drawer.
class _SettingsDrawer extends ConsumerWidget {
  const _SettingsDrawer({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final scheme = Theme.of(context).colorScheme;
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Text(
                'Postavke',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(height: 1),
            _ThemeRow(
              mode: mode,
              onChanged: (m) =>
                  ref.read(themeModeProvider.notifier).setThemeMode(m),
            ),
            const Spacer(),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.logout, color: scheme.error),
              title: Text('Odjava', style: TextStyle(color: scheme.error)),
              onTap: () {
                Navigator.of(context).pop(); // close the drawer
                onLogout();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Light/dark theme picker: a "Tema" label with a compact day/night pill
/// toggle on the right.
class _ThemeRow extends StatelessWidget {
  const _ThemeRow({required this.mode, required this.onChanged});

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 14),
      child: Row(
        children: [
          Text('Tema', style: tt.bodyLarge),
          const Spacer(),
          _ThemePill(mode: mode, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// A compact day/night toggle pill: [ ☀ | 🌙 ] — the active mode is filled.
class _ThemePill extends StatelessWidget {
  const _ThemePill({required this.mode, required this.onChanged});

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = mode == ThemeMode.dark;

    Widget seg(IconData icon, bool selected, ThemeMode target, String tip) =>
        InkWell(
          onTap: () => onChanged(target),
          borderRadius: BorderRadius.circular(18),
          child: Tooltip(
            message: tip,
            child: Container(
              width: 40,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? scheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                icon,
                size: 18,
                color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg(Icons.light_mode_outlined, !dark, ThemeMode.light, 'Svijetla'),
          seg(Icons.dark_mode_outlined, dark, ThemeMode.dark, 'Tamna'),
        ],
      ),
    );
  }
}
