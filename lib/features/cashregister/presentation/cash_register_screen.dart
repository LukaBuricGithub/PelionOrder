import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/state/auth_controller.dart';
import '../../master_data/models/user.dart';
import '../../auth/state/session_provider.dart';
import '../../settings/presentation/settings_drawer.dart';
import '../../mqtt/presentation/mqtt_table_select_screen.dart'
    show precacheTableSelectSvgs;
import '../../mqtt/data/mqtt_service.dart';
import '../../mqtt/state/mqtt_config_provider.dart';
import '../../mqtt/state/mqtt_orders_provider.dart';
import '../../mqtt/state/mqtt_outbox_provider.dart';
import '../../mqtt/state/mqtt_tables_provider.dart';

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

  /// Back on the hub — or the Odjava row at the bottom of the user card —
  /// forgets the current waiter: clears the session (and the
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

    // Tables the kasa reports as having an open bill. Deliberately NOT the
    // locked ones (`zakljucani`): a lock only means somebody is standing in
    // the table right now — another orderman or a cashier on the till — and
    // it comes and goes every few seconds. This number is about money owed.
    final zauzeto = ref.watch(mqttOccupiedProvider).length;

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
        // No AppBar: the header below IS the top of the screen — it carries
        // the venue, the waiter, Odjava and the settings button, so a second
        // bar above it would only repeat what it already says.
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ShiftHeader(
              venue: venue,
              user: user,
              onSettings: () => _scaffoldKey.currentState?.openEndDrawer(),
              onLogout: _forgetSession,
            ),
            _ShiftStatusStrip(zauzeto: zauzeto),
            Expanded(
              child: SafeArea(
                top: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                      children: [
                        _ActionCard(
                          icon: Icons.fastfood,
                          label: 'Unos narudžbe',
                          onTap: () => context.push('/mqtt-tables'),
                        ),
                        const SizedBox(height: 12),
                        _ActionCard(
                          icon: Icons.schedule_send_outlined,
                          label: 'Neposlane narudžbe',
                          count: unsentCount,
                          tone: _CardTone.alert,
                          onTap: () => context.push('/mqtt-outbox'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The header's own colours.
///
/// Not from the ColorScheme: this is a filled panel that has to stay darker
/// than everything under it in BOTH themes, which no single scheme role does
/// (`primary` is a button colour, `surface` disappears into the page). The
/// values are the app's own blues — the dark theme's scaffold family — so the
/// panel reads as part of the app rather than a borrowed accent.
const _headerLight = Color(0xFF1E3A5C);
const _headerDark = Color(0xFF16253C);
const _stripLight = Color(0xFF16304F);
const _stripDark = Color(0xFF101C2E);
const _onHeader = Color(0xFFFFFFFF);
const _onHeaderMuted = Color(0xFFA9C4E4);
const _headerOutline = Color(0xFF5A7FA8);
const _avatarFill = Color(0xFF2F5681);

/// Venue, waiter, Odjava and Postavke, in one filled panel at the top.
///
/// Both names are shown IN FULL, wrapping onto as many lines as they need:
/// the venue comes from the kasa's QR code and the waiter from the staff
/// list, and neither is length-capped at the source. The two buttons keep
/// their size while the text reflows around them.
class _ShiftHeader extends StatelessWidget {
  const _ShiftHeader({
    required this.venue,
    required this.user,
    required this.onSettings,
    required this.onLogout,
  });

  final String venue;
  final User? user;
  final VoidCallback onSettings;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final name = (user?.username ?? '').trim();
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';

    return Material(
      color: dark ? _headerDark : _headerLight,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 8, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10, right: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'LOKAL',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.4,
                              color: _onHeaderMuted,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            venue.isEmpty ? 'Uređaj nije skeniran' : venue,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                              color: _onHeader,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onSettings,
                    tooltip: 'Postavke',
                    icon: const Icon(Icons.settings_outlined),
                    color: const Color(0xFFDCE7F5),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: _avatarFill,
                      child: Text(
                        initial,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          color: _onHeader,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          name.isEmpty ? 'Nepoznat korisnik' : name,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                            height: 1.2,
                            color: _onHeader,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Odjava: forgets the waiter and returns to Prijava. The
                    // phone stays activated and connected to MQTT; only the
                    // person changes — which is why it is an outline rather
                    // than anything that reads as destructive.
                    OutlinedButton.icon(
                      onPressed: onLogout,
                      icon: const Icon(Icons.logout, size: 16),
                      label: const Text('Odjava'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDCE7F5),
                        side: const BorderSide(color: _headerOutline),
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The thin line under the header: whether this phone is on the broker, and
/// how many tables have an open bill.
///
/// The connection is the same value "Postavke uređaja" shows — this phone's
/// link to the broker, not the kasa's own state, which is a separate thing
/// read from the devices' status topics.
class _ShiftStatusStrip extends ConsumerWidget {
  const _ShiftStatusStrip({required this.zauzeto});

  final int zauzeto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: dark ? _stripDark : _stripLight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        child: ValueListenableBuilder<bool>(
          valueListenable: MqttService.instance.connected,
          builder: (context, connected, _) {
            return Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    // Colour never carries it alone — the word beside it says
                    // the same thing.
                    color: connected
                        ? const Color(0xFF5FCF8E)
                        : const Color(0xFFFF8A80),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    connected
                        ? 'Spojeno · ${_zauzetoTekst(zauzeto)}'
                        : 'Nije spojeno, pokušava se ponovno spojiti.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: _onHeaderMuted,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// "1 stol zauzet", "4 stola zauzeta", "7 stolova zauzeto" — Croatian counts
/// three ways, and a POS that says "4 stolova" looks like a machine wrote it.
String _zauzetoTekst(int n) {
  if (n == 0) return 'nema zauzetih stolova';
  final zadnje = n % 10;
  final zadnjeDvije = n % 100;
  if (zadnje == 1 && zadnjeDvije != 11) return '$n stol zauzet';
  if (zadnje >= 2 && zadnje <= 4 && (zadnjeDvije < 12 || zadnjeDvije > 14)) {
    return '$n stola zauzeta';
  }
  return '$n stolova zauzeto';
}

enum _CardTone { normal, alert }

/// One thing the waiter can do: a tinted icon tile, the name, and either the
/// unsent count or a chevron.
///
/// No subtitle. The two actions are the only ones on the screen and their
/// names say exactly what they do; a line of explanation under each would be
/// read once and then be in the way for the rest of the shift.
class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
    this.count = 0,
    this.tone = _CardTone.normal,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Shown as a red pill when above zero.
  final int count;

  /// [_CardTone.alert] tints the icon tile in the error colours — used by
  /// "Neposlane narudžbe", whose icon means something is waiting.
  final _CardTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final alert = tone == _CardTone.alert;
    // The icon tile: error container for the alert card, a blue tint of the
    // header for the ordinary one, each with its matching foreground.
    final tileColor = alert
        ? scheme.errorContainer
        : (dark ? const Color(0xFF223B57) : const Color(0xFFD8E6F7));
    final iconColor = alert
        ? scheme.onErrorContainer
        : (dark ? const Color(0xFFCFE0F5) : _headerLight);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: tileColor,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, size: 26, color: iconColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (count > 0)
                Container(
                  constraints: const BoxConstraints(minWidth: 26),
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.error,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: scheme.onError,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
