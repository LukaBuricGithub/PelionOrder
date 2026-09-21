import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../master_data/state/master_data_providers.dart';
import '../../mqtt/data/mqtt_service.dart';
import '../../mqtt/models/mqtt_connection_config.dart';
import '../../mqtt/models/mqtt_device_status.dart';
import '../../mqtt/state/mqtt_config_provider.dart';
import '../../profiles/models/api_entry.dart';
import '../../profiles/state/profiles_provider.dart';
import '../../shared/presentation/app_bottom_sheet.dart';
import '../../shared/presentation/bottom_sheet_safe_area.dart';
import '../models/menu_view_size.dart';
import '../models/table_view_size.dart';
import '../state/settings_provider.dart';
import 'qr_scanner_screen.dart';

/// Device + connection configuration, laid out as cards: the (single) server
/// profile, the table-tile size, and the "group identical articles when
/// sending" toggle.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  /// The server-profile "Podatci za prijavu" flow is disabled — login now uses
  /// the MQTT staff list. Kept intact; flip to true to bring the card (and its
  /// editor/delete) back.
  bool get _showProfileCard => false;

  /// "Slanje narudžbe" (Grupiraj artikle pri slanju / Automatsko ponovno
  /// slanje) is hidden for now — the waiter can't change either setting, so
  /// both keep their stored value (off by default). Everything behind them is
  /// untouched: flip this to true to bring the card back.
  bool get _showSendingCard => false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesProvider);
    final settings = ref.watch(settingsProvider);
    final config = ref.watch(mqttConfigProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Postavke uređaja')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          screenContentBottomPadding(context, extra: 24),
        ),
        children: [
          // ── Podatci za prijavu (disabled: login now uses MQTT users) ──────
          if (_showProfileCard) ...[
            _SettingsCard(
              header: 'Podatci za prijavu',
              child: profiles.entries.isEmpty
                  ? _NoProfile(onAdd: () => _openEditor(context, ref))
                  : _ProfileRow(
                      entry: profiles.entries.first,
                      onEdit: () => _openEditor(
                        context,
                        ref,
                        entry: profiles.entries.first,
                      ),
                      onDelete: () =>
                          _confirmDelete(context, ref, profiles.entries.first),
                    ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Prikaz ───────────────────────────────────────────────────────
          _SettingsCard(
            header: 'Prikaz',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Veličina prikaza stolova',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<TableViewSize>(
                    // Hide the selected check-mark (it steals width and pushes
                    // longer labels like "Srednje" onto a second line), keep the
                    // labels to one line, and shrink-to-fit on narrow screens.
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      textStyle: const TextStyle(fontSize: 13),
                      selectedBackgroundColor: theme.colorScheme.primary,
                      selectedForegroundColor: theme.colorScheme.onPrimary,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: TableViewSize.small,
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Male', maxLines: 1),
                        ),
                      ),
                      ButtonSegment(
                        value: TableViewSize.medium,
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Srednje', maxLines: 1),
                        ),
                      ),
                      ButtonSegment(
                        value: TableViewSize.large,
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Velike', maxLines: 1),
                        ),
                      ),
                    ],
                    selected: {settings.tableViewSize},
                    onSelectionChanged: (s) => ref
                        .read(settingsProvider.notifier)
                        .setTableViewSize(s.first),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Veličina prikaza artikala',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<MenuViewSize>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      textStyle: const TextStyle(fontSize: 13),
                      selectedBackgroundColor: theme.colorScheme.primary,
                      selectedForegroundColor: theme.colorScheme.onPrimary,
                    ),
                    segments: [
                      for (final size in MenuViewSize.values)
                        ButtonSegment(
                          value: size,
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(size.label, maxLines: 1),
                          ),
                        ),
                    ],
                    selected: {settings.menuViewSize},
                    onSelectionChanged: (s) => ref
                        .read(settingsProvider.notifier)
                        .setMenuViewSize(s.first),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Slanje narudžbe (hidden, see _showSendingCard) ────────────────
          if (_showSendingCard) ...[
            _SettingsCard(
              header: 'Slanje narudžbe',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Grupiraj artikle pri slanju',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Switch(
                        value: settings.shouldGroupArticles,
                        onChanged: (v) => ref
                            .read(settingsProvider.notifier)
                            .setShouldGroupArticles(v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Automatsko ponovno slanje',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Neposlane narudžbe šalju se same kad glavni '
                              'program ponovno prima narudžbe, najkasnije 9 minuta '
                              'od prvog slanja.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Switch(
                        value: settings.shouldAutoResend,
                        onChanged: (v) => ref
                            .read(settingsProvider.notifier)
                            .setShouldAutoResend(v),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Veza (once the device has a code) ─────────────────────────────
          if (config != null) ...[
            _ConnectionCard(config: config),
            const SizedBox(height: 16),
          ],

          // ── QR skener ────────────────────────────────────────────────────
          const _QrSkenerCard(),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ApiEntry entry,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Obriši profil'),
          content: Text('Obrisati profil "${entry.name}"?'),
          actions: [
            // Quiet cancel so a mis-tap defaults to the safe option.
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Odustani'),
            ),
            // Red confirm — signals the destructive action.
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Obriši'),
            ),
          ],
        );
      },
    );
    if (ok == true) {
      await ref.read(profilesProvider.notifier).delete(entry.id);
      // Deleting the (single) profile disconnects from the venue: wipe the
      // cached master data and any queued orders so stale users can't be used
      // to sign in afterwards, and drop the stale venue name.
      if (ref.read(profilesProvider).entries.isEmpty) {
        await ref.read(masterDataRepositoryProvider).clearAll();
        await ref.read(settingsProvider.notifier).setBusinessName(null);
      }
    }
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    ApiEntry? entry,
  }) async {
    final result = await showAppBottomSheet<ApiEntry>(
      context: context,
      sheetBuilder: (ctx) => _ProfileEditorSheet(entry: entry),
    );
    if (result != null) {
      await ref.read(profilesProvider.notifier).save(result);
    }
  }
}

/// A titled settings card: a blue uppercase header over its content.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.header, required this.child});

  final String header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            header.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// "Veza": who this phone is, which kasa it talks to, and whether the
/// connection is up — live, from the connection and the devices' statuses.
class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.config});

  final MqttConnectionConfig config;

  static const duration = Duration(milliseconds: 250);

  /// "53B5…-PELIONORDER-3" → "PELIONORDER-3"; "53B5…-POS-5" → "POS-5".
  static String _suffix(String id, String licenca) =>
      id.startsWith('$licenca-') ? id.substring(licenca.length + 1) : id;

  @override
  Widget build(BuildContext context) {
    final svc = MqttService.instance;
    return _SettingsCard(
      header: 'Veza',
      child: ListenableBuilder(
        listenable: Listenable.merge([
          svc.connected,
          svc.statusesReady,
          svc.devices,
        ]),
        builder: (context, _) {
          final connected = svc.connected.value;
          final known = connected && svc.statusesReady.value;
          final kase = [
            for (final e in svc.devices.value.entries)
              if (e.value.isKasa) e,
          ]..sort((a, b) => a.key.compareTo(b.key));
          // The device's id from the QR code without the licence, as issued
          // by the kasa: "PELIONORDER-10".
          final ownName = _suffix(config.uredaj, config.licenca);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatusLine(
                state: connected ? _Dot.ok : _Dot.bad,
                text: connected
                    ? 'Spojeno'
                    : 'Nije spojeno, pokušava se ponovno spojiti.',
              ),
              const SizedBox(height: 14),
              _InfoRow(
                icon: Icons.smartphone,
                label: 'Ovaj uređaj',
                title: ownName,
                subtitle: '',
              ),
              const SizedBox(height: 12),
              AnimatedSize(
                duration: duration,
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!known)
                      const _InfoRow(
                        icon: Icons.point_of_sale,
                        label: 'Glavni program',
                        title: 'Nepoznato stanje',
                        subtitle: '',
                        dot: _Dot.unknown,
                      )
                    else if (kase.isEmpty)
                      const _InfoRow(
                        icon: Icons.point_of_sale,
                        label: 'Glavni program',
                        title: 'Glavni program nije pronađen',
                        subtitle: '',
                        dot: _Dot.bad,
                      )
                    else
                      for (final (i, e) in kase.indexed) ...[
                        if (i > 0) const SizedBox(height: 10),
                        _kasaRow(
                          _suffix(e.key, config.licenca),
                          e.value,
                          first: i == 0,
                        ),
                      ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _kasaRow(String id, MqttDeviceStatus kasa, {required bool first}) {
    final (dot, state) = !kasa.isOnline
        ? (_Dot.bad, 'Nije spojen')
        : kasa.prima
        ? (_Dot.ok, 'Spojen, u blagajni')
        : (_Dot.warn, 'Spojen, nije u blagajni');
    return _InfoRow(
      icon: Icons.point_of_sale,
      label: first ? 'Glavni program' : '',
      title: kasa.naziv.isEmpty ? id : kasa.naziv,
      subtitle: '$id · $state',
      dot: dot,
    );
  }
}

/// ok — green, warn — amber, bad — red, unknown — grey (the phone can't
/// tell: it isn't connected itself).
enum _Dot { ok, warn, bad, unknown }

Color _dotColor(_Dot dot, bool dark) => switch (dot) {
  _Dot.ok => dark ? const Color(0xFF4FC98A) : const Color(0xFF2E9E5B),
  _Dot.warn => dark ? const Color(0xFFF4A83A) : const Color(0xFFE8890C),
  _Dot.bad => dark ? const Color(0xFFFF7B72) : const Color(0xFFD64541),
  _Dot.unknown => dark ? const Color(0xFF9AA6B8) : const Color(0xFF8A94A3),
};

/// A coloured dot with a soft halo; its colour changes smoothly.
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.state, this.size = 10});

  final _Dot state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = _dotColor(state, dark);
    return AnimatedContainer(
      duration: _ConnectionCard.duration,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 6),
        ],
      ),
    );
  }
}

/// The connection's own state: a dot and a word, both changing smoothly.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.state, required this.text});

  final _Dot state;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        _StatusDot(state: state, size: 12),
        const SizedBox(width: 10),
        Expanded(
          child: AnimatedSwitcher(
            duration: _ConnectionCard.duration,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.centerLeft,
              children: [...previous, ?current],
            ),
            child: Text(
              text,
              key: ValueKey(text),
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One line of the "Veza" card: an icon, a small label, a name and details —
/// with a state dot in front of the details for a kasa.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.title,
    required this.subtitle,
    this.dot,
  });

  final IconData icon;
  final String label;
  final String title;
  final String subtitle;
  final _Dot? dot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dot = this.dot;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: scheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label.isNotEmpty)
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              Row(
                children: [
                  // No details line: the state dot goes before the name.
                  if (dot != null && subtitle.isEmpty) ...[
                    _StatusDot(state: dot, size: 8),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: dot == _Dot.unknown
                            ? _dotColor(
                                _Dot.unknown,
                                theme.brightness == Brightness.dark,
                              )
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
              if (subtitle.isNotEmpty)
                Row(
                  children: [
                    if (dot != null) ...[
                      _StatusDot(state: dot, size: 8),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// QR skener section: scan the code issued by the kasa
/// (`{"lic","id","naziv","grupa"}`) and connect with it.
///
/// Scanning **provisions the device**: the code is persisted (see
/// [mqttConfigProvider]) and the broker connection is established right away.
/// From then on the app connects on its own at every launch and on resume, and
/// keeps retrying in the background — there is no manual connect button.
class _QrSkenerCard extends ConsumerStatefulWidget {
  const _QrSkenerCard();

  @override
  ConsumerState<_QrSkenerCard> createState() => _QrSkenerCardState();
}

class _QrSkenerCardState extends ConsumerState<_QrSkenerCard> {
  Future<void> _scan() async {
    final code = await Navigator.of(
      context,
    ).push<String>(QrScannerScreen.route());
    if (!mounted || code == null || code.isEmpty) return;
    // Remember the provisioning, then connect with it immediately. A code that
    // isn't a valid orderman code from the kasa is refused and changes nothing,
    // so a wrong scan can't replace a working provisioning.
    final saved = await ref.read(mqttConfigProvider.notifier).saveScanned(code);
    if (!mounted) return;
    if (!saved) {
      // A dialog, not a snackbar: it must be seen, on every device.
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Neispravan QR kod'),
          content: const Text('Ovo nije QR kod za Pelion Order.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('U redu'),
            ),
          ],
        ),
      );
      return;
    }
    final config = ref.read(mqttConfigProvider);
    if (config != null) await _connect(config);
  }

  /// Connects with a freshly scanned code, in a small card that shows the
  /// attempt: moving dots while it runs, then a green check or a red X. If
  /// this first attempt fails, the service keeps retrying on its own.
  ///
  /// The service's own lines ("MQTT: …") only go to the debug console.
  Future<void> _connect(MqttConnectionConfig config) async {
    debugPrint('MQTT: spajanje…');
    // A new QR replaces the old provisioning — drop the live session first, or
    // connectAndSend would keep the previous licenca ("already connected").
    if (MqttService.instance.isConnected) MqttService.instance.disconnect();
    final attempt = MqttService.instance.connectAndSend(config).then((result) {
      debugPrint(result);
      if (MqttService.instance.isConnected) return _ConnectOutcome.connected;
      if (result.startsWith('MQTT: broker je odbio')) {
        return _ConnectOutcome.refused;
      }
      if (result.startsWith('MQTT: nije spojeno')) {
        return _ConnectOutcome.failed;
      }
      // Already in progress, interrupted, not provisioned: nothing to show.
      return _ConnectOutcome.none;
    });
    if (!mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Spajanje',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, _, _) => _ConnectCard(attempt: attempt),
      transitionBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(mqttConfigProvider);

    return _SettingsCard(
      header: 'QR skener',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(
                config == null ? 'Skeniraj QR kod' : 'Skeniraj ponovno',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The single server profile row: avatar, full name + address (both wrap), and
/// edit / delete actions.
class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });

  final ApiEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: scheme.primary.withValues(alpha: 0.1),
          child: Icon(Icons.person_outline, color: scheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Full name — wraps to as many lines as needed (no ellipsis).
              Text(
                entry.name.isEmpty ? '(bez naziva)' : entry.name,
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              // Full address — wraps as needed too.
              Text(
                entry.ip,
                style: tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: Icon(Icons.edit_outlined, color: scheme.primary),
          tooltip: 'Uredi',
          onPressed: onEdit,
        ),
        IconButton(
          icon: Icon(Icons.delete_outline, color: scheme.error),
          tooltip: 'Obriši',
          onPressed: onDelete,
        ),
      ],
    );
  }
}

/// Empty state for the profile card when none is configured yet.
class _NoProfile extends StatelessWidget {
  const _NoProfile({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Nema spremljenog profila.'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Dodaj profil'),
        ),
      ],
    );
  }
}

/// Bottom sheet for adding/editing a server profile (name / address / key).
class _ProfileEditorSheet extends StatefulWidget {
  const _ProfileEditorSheet({this.entry});

  final ApiEntry? entry;

  @override
  State<_ProfileEditorSheet> createState() => _ProfileEditorSheetState();
}

class _ProfileEditorSheetState extends State<_ProfileEditorSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.entry?.name ?? '',
  );
  late final TextEditingController _ip = TextEditingController(
    text: widget.entry?.ip ?? '',
  );
  late final TextEditingController _apiKey = TextEditingController(
    text: widget.entry?.apiKey ?? '',
  );

  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    _ip.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final result =
        (widget.entry ?? const ApiEntry(id: 0, name: '', ip: '', apiKey: ''))
            .copyWith(
              name: _name.text.trim(),
              ip: _ip.text.trim(),
              apiKey: _apiKey.text.trim(),
            );
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return AppBottomSheetScaffold(
      title: widget.entry == null ? 'Novi profil' : 'Uredi profil',
      body: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Naziv',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Unesite naziv' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _ip,
              decoration: const InputDecoration(
                labelText: 'Adresa (IP ili host)',
                hintText: 'npr. 192.168.1.50 ili 192.168.1.50:8080',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Unesite adresu' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _apiKey,
              decoration: const InputDecoration(
                labelText: 'Pristupni ključ (X-API-KEY)',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Odustani'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(onPressed: _save, child: const Text('Spremi')),
          ),
        ],
      ),
    );
  }
}

/// How a connection attempt from the QR card ended.
enum _ConnectOutcome { connected, refused, failed, none }

/// The connection attempt after a scan, in one card that changes in place:
/// blue moving dots with "Spajanje…" → a green check with "Spojeno", or a red
/// X with "Prijava odbijena" / "Pogreška pri spajanju". It closes on its own.
///
/// The dots only fade in once the attempt has taken a moment, so a quick
/// connection goes straight to the check without a flash of "Spajanje…".
class _ConnectCard extends StatefulWidget {
  const _ConnectCard({required this.attempt});

  final Future<_ConnectOutcome> attempt;

  @override
  State<_ConnectCard> createState() => _ConnectCardState();
}

class _ConnectCardState extends State<_ConnectCard>
    with SingleTickerProviderStateMixin {
  /// Null while the attempt runs.
  _ConnectOutcome? _outcome;

  /// The attempt has taken long enough to show "Spajanje…".
  bool _slow = false;

  /// Built in [initState], not lazily: dismissing the card while it still
  /// says "Spajanje…" would otherwise make `dispose()` the first access, and
  /// creating a controller during teardown throws.
  late final AnimationController _mark;
  late final _circle = CurvedAnimation(
    parent: _mark,
    curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack),
  );
  late final _stroke = CurvedAnimation(
    parent: _mark,
    curve: const Interval(0.35, 0.8, curve: Curves.easeOutCubic),
  );
  late final _text = CurvedAnimation(
    parent: _mark,
    curve: const Interval(0.55, 1.0, curve: Curves.easeOut),
  );

  static const _slowAfter = Duration(milliseconds: 300);
  static const _holdConnected = Duration(milliseconds: 1800);
  static const _holdError = Duration(milliseconds: 2600);

  @override
  void initState() {
    super.initState();
    _mark = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    Future<void>.delayed(_slowAfter, () {
      if (mounted && _outcome == null) setState(() => _slow = true);
    });
    widget.attempt.then((outcome) {
      if (!mounted) return;
      if (outcome == _ConnectOutcome.none) {
        Navigator.of(context).maybePop();
        return;
      }
      setState(() => _outcome = outcome);
      _mark.forward();
      Future<void>.delayed(
        outcome == _ConnectOutcome.connected ? _holdConnected : _holdError,
        () {
          if (mounted) Navigator.of(context).maybePop();
        },
      );
    });
  }

  @override
  void dispose() {
    _mark.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final outcome = _outcome;
    final ok = outcome == _ConnectOutcome.connected;
    final color = ok
        ? (dark ? const Color(0xFF4FC98A) : const Color(0xFF2E9E5B))
        : (dark ? const Color(0xFFFF7B72) : const Color(0xFFD64541));
    final title = switch (outcome) {
      _ConnectOutcome.connected => 'Spojeno',
      _ConnectOutcome.refused =>
        'Prijava odbijena, skenirajte novi kod u glavnom programu',
      _ => 'Pogreška pri spajanju',
    };

    final Widget body = outcome == null
        ? AnimatedOpacity(
            key: const ValueKey('waiting'),
            opacity: _slow ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 96,
                  height: 96,
                  child: Center(
                    child: _LoadingDots(color: theme.colorScheme.primary),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Spajanje…',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          )
        : Column(
            key: const ValueKey('result'),
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: _circle,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: AnimatedBuilder(
                    animation: _stroke,
                    builder: (context, _) => CustomPaint(
                      painter: ok
                          ? _CheckPainter(progress: _stroke.value)
                          : _CrossPainter(progress: _stroke.value),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FadeTransition(
                opacity: _text,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          );

    // The whole card waits too: a quick connection shows only the check.
    return Center(
      child: AnimatedOpacity(
        opacity: _slow || outcome != null ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Material(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            elevation: 8,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 32, 32, 28),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: body,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three dots rising and falling one after another.
class _LoadingDots extends StatefulWidget {
  const _LoadingDots({required this.color});

  final Color color;

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [for (var i = 0; i < 3; i++) _dot(i)],
      ),
    );
  }

  Widget _dot(int i) {
    // Each dot runs the same bump, a third of a cycle after the previous one.
    final t = (_c.value - i * 0.18) % 1.0;
    final bump = t < 0.5 ? math.sin(t / 0.5 * math.pi) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Transform.translate(
        offset: Offset(0, -10 * bump),
        child: Opacity(
          opacity: 0.45 + 0.55 * bump,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

Paint _markPaint(Size size) => Paint()
  ..color = Colors.white
  ..style = PaintingStyle.stroke
  ..strokeWidth = size.width * 0.085
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

/// Draws [path] up to [progress] (0–1) of its length, contour by contour.
void _drawPartial(Canvas canvas, Path path, double progress, Paint paint) {
  final metrics = path.computeMetrics().toList();
  final total = metrics.fold<double>(0, (sum, m) => sum + m.length);
  var left = total * progress;
  for (final m in metrics) {
    if (left <= 0) break;
    canvas.drawPath(m.extractPath(0, math.min(left, m.length)), paint);
    left -= m.length;
  }
}

/// A white check mark drawn from its short stroke to its long one.
class _CheckPainter extends CustomPainter {
  _CheckPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final path = Path()
      ..moveTo(size.width * 0.28, size.height * 0.52)
      ..lineTo(size.width * 0.44, size.height * 0.67)
      ..lineTo(size.width * 0.73, size.height * 0.36);
    _drawPartial(canvas, path, progress, _markPaint(size));
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress;
}

/// A white X drawn one stroke after the other.
class _CrossPainter extends CustomPainter {
  _CrossPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    const a = 0.33, b = 0.67;
    final path = Path()
      ..moveTo(size.width * a, size.height * a)
      ..lineTo(size.width * b, size.height * b)
      ..moveTo(size.width * b, size.height * a)
      ..lineTo(size.width * a, size.height * b);
    _drawPartial(canvas, path, progress, _markPaint(size));
  }

  @override
  bool shouldRepaint(_CrossPainter old) => old.progress != progress;
}
