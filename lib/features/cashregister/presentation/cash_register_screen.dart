import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/state/auth_controller.dart';
import '../../auth/state/session_provider.dart';
import '../../settings/presentation/settings_drawer.dart';
import '../../mqtt/presentation/mqtt_table_select_screen.dart'
    show precacheTableSelectSvgs;
import '../../mqtt/state/mqtt_config_provider.dart';
import '../../mqtt/state/mqtt_orders_provider.dart';
import '../../mqtt/state/mqtt_outbox_provider.dart';

/// "Izbornik", the waiter's main hub after login: the signed-in user and the
/// entry points to ordering and to "Neposlane narudžbe". Everything on it
/// comes over MQTT — nothing here talks to the old REST server.
class CashRegisterScreen extends ConsumerStatefulWidget {
  const CashRegisterScreen({super.key});

  @override
  ConsumerState<CashRegisterScreen> createState() => _CashRegisterScreenState();
}

class _CashRegisterScreenState extends ConsumerState<CashRegisterScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    // Warm the floor-plan SVGs now so the first open of "Odabir stola" from
    // the "Unos narudžbe" menu doesn't hitch while compiling them.
    Future.microtask(precacheTableSelectSvgs);
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
    final venue = ref.watch(mqttConfigProvider)?.naziv.trim() ?? '';
    final theme = Theme.of(context);
    // Unsent orders this waiter may see — their own, or all with pravo 008.
    final unsentCount =
        ref
            .watch(mqttOutboxProvider)
            .where(
              (o) => mqttOutboxVisibleTo(
                o,
                cuser: user?.code,
                allTables: user?.allTablesOpenRight ?? false,
              ),
            )
            .length +
        // Plus tables with items added on this phone and not sent yet.
        ref.watch(mqttVisibleDraftsProvider).length;

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
          // What the screen is: the list of things the waiter can do. (It used
          // to show the venue name from the old REST server, else "Blagajna".)
          title: const Text('Izbornik'),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Postavke',
              onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // The venue this phone belongs to — the name from the
                        // kasa's QR code — above the signed-in waiter.
                        if (venue.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                            child: Text(
                              venue,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                        ],
                        ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              (user?.username.isNotEmpty ?? false)
                                  ? user!.username.characters.first
                                        .toUpperCase()
                                  : '?',
                            ),
                          ),
                          title: Text(user?.username ?? 'Nepoznat korisnik'),
                          subtitle: Text(
                            user?.superuser == true
                                ? 'Voditelj (superuser)'
                                : 'Konobar',
                          ),
                        ),
                      ],
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
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
