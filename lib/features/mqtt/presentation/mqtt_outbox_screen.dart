import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/session_provider.dart';
import '../../settings/state/settings_provider.dart';
import '../data/mqtt_service.dart';
import '../models/mqtt_menu.dart';
import '../state/mqtt_cart.dart';
import '../state/mqtt_menu_provider.dart';
import '../state/mqtt_outbox_provider.dart';
import '../state/mqtt_users_provider.dart';
import 'mqtt_existing_items.dart'
    show MqttExistingStatus, mqttExistingStatusStyle;
import 'mqtt_qty_pad.dart' show formatQtyWithUnit;

/// "Neposlane narudžbe": every order the kasa hasn't definitely answered,
/// grouped by table.
///
/// A waiter sees their own orders; pravo 008 sees all. Waiting orders need
/// nothing — they are resent automatically as themselves. Refused and expired
/// orders wait here for the waiter, who sends them again (as new orders) or
/// deletes them — per table, or all of them at once from the bottom bar.
class MqttOutboxScreen extends ConsumerWidget {
  const MqttOutboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);
    final allTables = me?.allTablesOpenRight ?? false;
    bool allowed(MqttOutboxOrder o) =>
        mqttOutboxVisibleTo(o, cuser: me?.code, allTables: allTables);

    final orders = [
      for (final o in ref.watch(mqttOutboxProvider))
        if (allowed(o)) o,
    ];
    final menu = ref.watch(mqttMenuProvider);
    final byCode = <int, MqttArticle>{
      for (final g in menu.groups)
        for (final a in g.articles) a.code: a,
    };
    final names = {
      for (final u in ref.watch(mqttUsersProvider)) u.code: u.name,
    };

    // By table, in the order each table's oldest unsent order was placed.
    final byTable = <int, List<MqttOutboxOrder>>{};
    for (final o in orders) {
      byTable.putIfAbsent(o.stol, () => []).add(o);
    }

    // Everything the waiter could send again right now, across all tables.
    final resendable = [
      for (final o in orders)
        if (o.needsWaiter) o,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Neposlane narudžbe')),
      // One tap for several tables — only worth a bar once there is more than
      // one order to send; a single one has its own button on its table.
      bottomNavigationBar: resendable.length < 2
          ? null
          : _ResendAllBar(
              count: resendable.length,
              onPressed: () =>
                  _confirmResendAll(context, ref, resendable, allowed),
            ),
      body: orders.isEmpty
          ? const _Empty()
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                // Only the bubble listens to the connection: when it drops or
                // comes back, the bubble alone rebuilds.
                ValueListenableBuilder<bool>(
                  valueListenable: MqttService.instance.connected,
                  builder: (context, connected, _) =>
                      _Intro(connected: connected),
                ),
                for (final entry in byTable.entries)
                  _TableCard(
                    stol: entry.key,
                    orders: entry.value,
                    byCode: byCode,
                    remarkName: menu.remarkName,
                    names: names,
                    onResend: () =>
                        _confirmResend(context, ref, entry.key, allowed),
                    onDelete: () =>
                        _confirmDelete(context, ref, entry.key, entry.value),
                  ),
              ],
            ),
    );
  }

  Future<void> _confirmResend(
    BuildContext context,
    WidgetRef ref,
    int stol,
    bool Function(MqttOutboxOrder) allowed,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Stol $stol'),
        content: const Text(
          'Kasa ove narudžbe nije zaprimila. Poslati ih ponovno kao nove '
          'narudžbe?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Odustani'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send, size: 18),
            label: const Text('Pošalji ponovno'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    ref
        .read(mqttOutboxProvider.notifier)
        .resendAsNew(
          stol: stol,
          allowed: allowed,
          groupArticles: ref.read(settingsProvider).shouldGroupArticles,
        );
  }

  Future<void> _confirmResendAll(
    BuildContext context,
    WidgetRef ref,
    List<MqttOutboxOrder> resendable,
    bool Function(MqttOutboxOrder) allowed,
  ) async {
    final count = resendable.length;
    final tables = {for (final o in resendable) o.stol}.toList()..sort();
    final where = tables.length == 1
        ? 'stol ${tables.first}'
        : 'stolovi ${tables.join(', ')}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pošalji sve ponovno'),
        content: Text(
          'Kasa nije zaprimila $count ${_narudzbuForm(count)} ($where). '
          'Poslati ih ponovno kao nove narudžbe?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Odustani'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send, size: 18),
            label: const Text('Pošalji sve'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    ref
        .read(mqttOutboxProvider.notifier)
        .resendAsNew(
          allowed: allowed,
          groupArticles: ref.read(settingsProvider).shouldGroupArticles,
        );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    int stol,
    List<MqttOutboxOrder> orders,
  ) async {
    // A waiting order that has left the phone may already be booked: the kasa
    // neither confirmed nor refused it. Deleting it here does not undo that.
    final risky = orders.any(
      (o) => o.status == MqttOutboxStatus.waiting && o.published,
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text('Obrisati narudžbe za stol $stol?'),
          content: Text(
            risky
                ? 'Kasa je možda već zaprimila neku od ovih narudžbi — nije je '
                      'ni potvrdila ni odbila. Brisanjem se narudžba NE poništava '
                      'na kasi.\n\nObrišite samo ako ste provjerili da je nema na '
                      'stolu.'
                : 'Kasa ove narudžbe nije zaprimila. Stavke će biti trajno '
                      'obrisane s uređaja.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Odustani'),
            ),
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
    if (ok != true || !context.mounted) return;
    ref.read(mqttOutboxProvider.notifier).remove({
      for (final o in orders) o.msgId,
    });
  }
}

/// "narudžbu / narudžbe / narudžbi" for [n], as it follows a number in the
/// accusative: 1 narudžbu, 2–4 narudžbe, 5+ narudžbi (11–14 take the 5+ form).
String _narudzbuForm(int n) {
  final last = n % 10;
  final lastTwo = n % 100;
  if (last == 1 && lastTwo != 11) return 'narudžbu';
  if (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)) {
    return 'narudžbe';
  }
  return 'narudžbi';
}

/// The bottom bar sending every refused / expired order again at once.
class _ResendAllBar extends StatelessWidget {
  const _ResendAllBar({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.send),
              label: Text(
                'Pošalji sve ponovno ($count)',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_done_outlined, size: 56, color: scheme.outline),
            const SizedBox(height: 12),
            const Text(
              'Nema neposlanih narudžbi.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// The explanation at the top of the list, as an information bubble. Tinted
/// amber while there is no connection: then it is news, not just a hint.
class _Intro extends StatelessWidget {
  const _Intro({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = connected
        ? scheme.primary
        : (dark ? const Color(0xFFF4A83A) : const Color(0xFFE8890C));
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 4, 0, 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: dark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            connected ? Icons.info_outline : Icons.wifi_off_rounded,
            size: 20,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              connected
                  ? 'Narudžbe koje čekaju potvrdu šalju se automatski. '
                        'Odbijene i istekle pošaljite ponovno ili obrišite.'
                  : 'Nema veze s kasom. Narudžbe koje čekaju potvrdu poslat '
                        'će se automatski kad se veza vrati.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.3,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One table: its unsent orders, and the actions for all of them together.
class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.stol,
    required this.orders,
    required this.byCode,
    required this.remarkName,
    required this.names,
    required this.onResend,
    required this.onDelete,
  });

  final int stol;
  final List<MqttOutboxOrder> orders;
  final Map<int, MqttArticle> byCode;
  final String Function(String cnap) remarkName;
  final Map<String, String> names;
  final VoidCallback onResend;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final waiters = {
      for (final o in orders) names[o.cuser] ?? o.cuser,
    }.join(', ');
    final canResend = orders.any((o) => o.needsWaiter);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        // No top/right padding: the delete target reaches the card's corner
        // and pads its own icon.
        padding: const EdgeInsets.only(left: 14, bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Stol $stol',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    waiters,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                // Delete: a small icon with a big invisible hit area filling
                // the card's top-right corner — easy to hit, like the ✕ on a
                // cart line in Stol X — and well away from "Pošalji ponovno".
                Semantics(
                  button: true,
                  label: 'Obriši narudžbe za stol $stol',
                  child: GestureDetector(
                    onTap: onDelete,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 12, 14, 12),
                      child: Icon(
                        Icons.delete_outline,
                        size: 22,
                        color: scheme.error,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final o in orders)
                    _OrderBlock(
                      order: o,
                      byCode: byCode,
                      remarkName: remarkName,
                    ),
                  if (canResend)
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 4),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: onResend,
                          icon: const Icon(Icons.send, size: 18),
                          label: const Text('Pošalji ponovno'),
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// When an order was placed: just the time for today, with the day and date
/// otherwise — "pet 12.9. 13:52" — so an order from Friday can't pass for one
/// from this morning. The year is added only when it isn't this year.
String _placedAt(DateTime t, DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(t.hour)}:${two(t.minute)}';
  if (t.year == now.year && t.month == now.month && t.day == now.day) {
    return time;
  }
  const days = ['pon', 'uto', 'sri', 'čet', 'pet', 'sub', 'ned'];
  final year = t.year == now.year ? '' : '${t.year}.';
  return '${days[t.weekday - 1]} ${t.day}.${t.month}.$year $time';
}

/// One frozen order: its state, when it was placed, the kasa's reason if it
/// refused, and its lines.
class _OrderBlock extends StatelessWidget {
  const _OrderBlock({
    required this.order,
    required this.byCode,
    required this.remarkName,
  });

  final MqttOutboxOrder order;
  final Map<int, MqttArticle> byCode;
  final String Function(String cnap) remarkName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final status = switch (order.status) {
      MqttOutboxStatus.waiting => MqttExistingStatus.neposlano,
      MqttOutboxStatus.rejected => MqttExistingStatus.odbijeno,
      MqttOutboxStatus.expired => MqttExistingStatus.isteklo,
    };
    final (color, label, icon) = mqttExistingStatusStyle(status, dark);
    final tagFg = dark ? const Color(0xFF10151C) : Colors.white;
    final time = _placedAt(order.createdAt, DateTime.now());

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.16 : 0.09),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 12, color: tagFg),
                    const SizedBox(width: 3),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: tagFg,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                time,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          if (order.reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                order.reason,
                style: TextStyle(fontSize: 13, color: scheme.onSurface),
              ),
            ),
          const SizedBox(height: 4),
          for (final l in order.lines) _line(l, scheme),
        ],
      ),
    );
  }

  Widget _line(MqttCartLine l, ColorScheme scheme) {
    final a = byCode[l.code];
    final notes = [...l.remarkCodes.map(remarkName), ...l.customNotes];
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${formatQtyWithUnit(l.qty, a?.unit ?? '')}   '
            '${a?.name ?? 'Artikl ${l.code}'}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          if (notes.isNotEmpty)
            Text(
              notes.join(', '),
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
