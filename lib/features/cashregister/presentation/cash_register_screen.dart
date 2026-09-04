import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/state/auth_controller.dart';
import '../../auth/state/session_provider.dart';
import '../../master_data/state/heartbeat_provider.dart';
import '../../master_data/state/master_data_providers.dart';
import '../../settings/state/settings_provider.dart';
import '../../theme/state/theme_mode_provider.dart';
import '../../mqtt/presentation/mqtt_table_select_screen.dart'
    show precacheTableSelectSvgs;

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
      endDrawer: const _SettingsDrawer(),
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
                  icon: Icons.table_restaurant,
                  label: 'Pregled stolova',
                  onTap: () => context.push('/tables-overview'),
                ),
                _MenuButton(
                  icon: Icons.fastfood,
                  label: 'Unos narudžbe',
                  onTap: () => context.push('/mqtt-tables'),
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
  const _SettingsDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
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
