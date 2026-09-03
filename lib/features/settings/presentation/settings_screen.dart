import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../master_data/state/master_data_providers.dart';
import '../../mqtt/data/mqtt_service.dart';
import '../../mqtt/models/mqtt_connection_config.dart';
import '../../profiles/models/api_entry.dart';
import '../../profiles/state/profiles_provider.dart';
import '../../shared/presentation/app_bottom_sheet.dart';
import '../../shared/presentation/bottom_sheet_safe_area.dart';
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesProvider);
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Postavke uređaja')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, screenContentBottomPadding(context, extra: 24)),
        children: [
          // ── Podatci za prijavu (disabled: login now uses MQTT users) ──────
          if (_showProfileCard) ...[
            _SettingsCard(
              header: 'Podatci za prijavu',
              child: profiles.entries.isEmpty
                  ? _NoProfile(onAdd: () => _openEditor(context, ref))
                  : _ProfileRow(
                      entry: profiles.entries.first,
                      onEdit: () => _openEditor(context, ref,
                          entry: profiles.entries.first),
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
                Text('Veličina prikaza stolova',
                    style: theme.textTheme.bodyLarge),
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
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Slanje narudžbe ──────────────────────────────────────────────
          _SettingsCard(
            header: 'Slanje narudžbe',
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Grupiraj artikle pri slanju',
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
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
          ),
          const SizedBox(height: 16),

          // ── QR skener ────────────────────────────────────────────────────
          const _QrSkenerCard(),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, ApiEntry entry) async {
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

  Future<void> _openEditor(BuildContext context, WidgetRef ref,
      {ApiEntry? entry}) async {
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

/// QR skener section: scan a code (`<licenca>-ORDERMAN-<n>`), parse the licenca
/// out of it, and show the MQTT connection payload that would be used to
/// connect. Display-only for now — nothing is stored or sent yet.
class _QrSkenerCard extends StatefulWidget {
  const _QrSkenerCard();

  @override
  State<_QrSkenerCard> createState() => _QrSkenerCardState();
}

// TEMP (testing): pre-seed a config from the real venue's QR string so we can
// connect with one tap ("Spoji se") without scanning. licenca = the part before
// the first '-' = 53B5079F96A188F16127D962 (matches the KASA that publishes the
// menu). Remove this and let the scan set the config once testing is done.
const _kTempTestQrCode = '53B5079F96A188F16127D962-ORDERMAN-1';

class _QrSkenerCardState extends State<_QrSkenerCard> {
  String? _rawCode = _kTempTestQrCode;
  MqttConnectionConfig? _config =
      MqttConnectionConfig.fromScannedCode(_kTempTestQrCode);
  bool _connecting = false;

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (!mounted || code == null || code.isEmpty) return;
    setState(() {
      _rawCode = code;
      _config = MqttConnectionConfig.fromScannedCode(code);
    });
  }

  Future<void> _connect() async {
    final config = _config;
    if (config == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _connecting = true);
    messenger.showSnackBar(const SnackBar(content: Text('MQTT: spajanje…')));
    final result = await MqttService.instance.connectAndSend(config);
    if (!mounted) return;
    setState(() => _connecting = false);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(result)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final config = _config;

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
          if (config != null) ...[
            const SizedBox(height: 14),
            Text('Skenirano',
                style: tt.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            SelectableText(_rawCode ?? '', style: tt.bodySmall),
            const SizedBox(height: 8),
            Text('Licenca: ${config.licenca}',
                style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            Text('Podaci za MQTT vezu',
                style: tt.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: SelectableText(
                config.toPrettyJson(),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _connecting ? null : _connect,
                icon: _connecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering),
                label: Text(_connecting ? 'Spajanje…' : 'Spoji se na MQTT'),
              ),
            ),
          ],
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
  late final TextEditingController _name =
      TextEditingController(text: widget.entry?.name ?? '');
  late final TextEditingController _ip =
      TextEditingController(text: widget.entry?.ip ?? '');
  late final TextEditingController _apiKey =
      TextEditingController(text: widget.entry?.apiKey ?? '');

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
    final result = (widget.entry ??
            const ApiEntry(id: 0, name: '', ip: '', apiKey: ''))
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
            child: FilledButton(
              onPressed: _save,
              child: const Text('Spremi'),
            ),
          ),
        ],
      ),
    );
  }
}
