import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/state/auth_controller.dart';
import '../../auth/state/session_provider.dart';
import '../../master_data/state/heartbeat_provider.dart';
import '../../master_data/state/master_data_providers.dart';
import '../../settings/state/settings_provider.dart';
import '../../settings/presentation/settings_drawer.dart';
import '../../mqtt/presentation/mqtt_table_select_screen.dart'
    show precacheTableSelectSvgs;
import '../../mqtt/state/mqtt_outbox_provider.dart';

/// The waiter's main hub after login: signed-in user and the entry points to
/// ordering (over MQTT) and the table overview.
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

  /// Pull-to-refresh on the menu: refresh the Online/Offline state and
  /// re-download master data (users, groups, articles, tables).
  Future<void> _onRefresh() async {
    await ref.read(heartbeatProvider.notifier).pingNow();
    await ref.read(masterDataRepositoryProvider).syncAll();
  }

  /// Back on the hub forgets the current waiter: clears the session (and the
  /// saved user code), which returns the user to the login screen rather than
  /// closing the app. The router's auth redirect (refreshListenable on
  /// currentUser) does the navigation — we must NOT navigate here as well, or
  /// the route change double-triggers and crashes with an element-lifecycle
  /// assertion. The saved server profile is left intact (only the waiter is
  /// forgotten), so the login screen just needs the PIN again.
  Future<void> _forgetSession() async {
    await ref.read(authControllerProvider).logout();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final businessName = ref.watch(settingsProvider).businessName;
    // Unsent orders this waiter may see — their own, or all with pravo 008.
    final unsentCount = ref
        .watch(mqttOutboxProvider)
        .where((o) => mqttOutboxVisibleTo(
              o,
              cuser: user?.code,
              allTables: user?.allTablesOpenRight ?? false,
            ))
        .length;

    return PopScope(
      // The hub is the top of the logged-in area. Back must NOT close the app —
      // it forgets the current waiter and drops back to the login screen (the
      // auth redirect handles the actual navigation once the session clears).
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _forgetSession();
      },
      child: Scaffold(
      key: _scaffoldKey,
      endDrawer: const SettingsDrawer(),
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
                  ),
                ),
                const SizedBox(height: 8),
                _MenuButton(
                  icon: Icons.fastfood,
                  label: 'Unos narudžbe',
                  onTap: () => context.push('/mqtt-tables'),
                ),
                _MenuButton(
                  icon: Icons.schedule_send_outlined,
                  label: 'Neposlane narudžbe',
                  count: unsentCount,
                  onTap: () => context.push('/mqtt-outbox'),
                ),
              ],
            ),
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
    this.count = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Shown as a red pill when above zero.
  final int count;

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
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (count > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: scheme.onError,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right),
            ],
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}
