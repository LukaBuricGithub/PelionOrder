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
/// deletes them, one table at a time.
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Neposlane narudžbe'),
        actions: [
          if (orders.any((o) => o.status == MqttOutboxStatus.waiting))
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Pošalji odmah',
              onPressed: () => ref.read(mqttOutboxProvider.notifier).retryNow(),
            ),
        ],
      ),
      body: orders.isEmpty
          ? const _Empty()
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                _Intro(connected: MqttService.instance.isConnected),
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
          stol,
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

class _Intro extends StatelessWidget {
  const _Intro({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
      child: Text(
        connected
            ? 'Narudžbe koje čekaju potvrdu šalju se automatski. Odbijene i '
                  'istekle pošaljite ponovno ili obrišite.'
            : 'Nema veze s kasom. Narudžbe koje čekaju potvrdu poslat će se '
                  'automatski kad se veza vrati.',
        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
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
              ],
            ),
            for (final o in orders)
              _OrderBlock(order: o, byCode: byCode, remarkName: remarkName),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                  label: Text('Obriši', style: TextStyle(color: scheme.error)),
                ),
                if (canResend) ...[
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: onResend,
                    icon: const Icon(Icons.send, size: 18),
                    label: const Text('Pošalji ponovno'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
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
    final t = order.createdAt;
    final time =
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';

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
