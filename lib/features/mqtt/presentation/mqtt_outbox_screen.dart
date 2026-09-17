import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/state/session_provider.dart';
import '../../settings/state/settings_provider.dart';
import '../models/mqtt_menu.dart';
import '../state/mqtt_cart.dart';
import '../state/mqtt_menu_provider.dart';
import '../state/mqtt_orders_provider.dart';
import '../state/mqtt_outbox_provider.dart';
import '../state/mqtt_send_gate_provider.dart';
import '../state/mqtt_tables_provider.dart';
import '../state/mqtt_users_provider.dart';
import 'mqtt_existing_items.dart'
    show mqttExistingStatusForOutbox, mqttExistingStatusStyle;
import 'mqtt_outbox_summary_bar.dart' show mqttDraftColor;
import 'mqtt_qty_pad.dart' show formatQtyWithUnit;

/// "Neposlane narudžbe": everything on its way to the kasa, grouped by table,
/// in the same colours as the floor plan:
///
/// * blue — items added on this phone and not sent yet: they can be opened
///   ("Otvori stol") or deleted;
/// * amber — with the broker, waiting for the kasa (also "Nije potvrđena"):
///   nothing to do, they can be neither sent again nor deleted;
/// * red — didn't get through (not sent, refused, too old): "Pošalji
///   ponovno" (per table, or all at once from the bottom bar) or delete.
///
/// A waiter sees their own; pravo 008 sees all.
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
    final drafts = ref.watch(mqttVisibleDraftsProvider);
    final tableNames = {
      for (final z in ref.watch(mqttTablesProvider))
        for (final t in z.tables) t.broj: t.naziv,
    };

    // By table, in the order each table's oldest unsent order was placed.
    final byTable = <int, List<MqttOutboxOrder>>{};
    for (final o in orders) {
      byTable.putIfAbsent(o.stol, () => []).add(o);
    }
    // Then tables that only have unsent items.
    final tables = [
      ...byTable.keys,
      for (final stol in drafts.keys.toList()..sort())
        if (!byTable.containsKey(stol)) stol,
    ];

    // Every red order the waiter could send again right now, across all
    // tables.
    final resendable = [
      for (final o in orders)
        if (o.canResend) o,
    ];
    // §11.4: resending is only possible while the kasa takes orders.
    final sendGate = ref.watch(mqttSendGateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Neposlane narudžbe')),
      // One tap for several tables — only worth a bar once there is more than
      // one order to send; a single one has its own button on its table.
      bottomNavigationBar: resendable.length < 2
          ? null
          : _ResendAllBar(
              count: resendable.length,
              onPressed: sendGate.isOpen
                  ? () => _confirmResendAll(context, ref, resendable, allowed)
                  : null,
            ),
      body: tables.isEmpty
          ? const _Empty()
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                _Intro(gate: sendGate),
                for (final stol in tables)
                  _TableCard(
                    stol: stol,
                    orders: byTable[stol] ?? const [],
                    draft: drafts[stol],
                    byCode: byCode,
                    remarkName: menu.remarkName,
                    names: names,
                    canSend: sendGate.isOpen,
                    onResend: () =>
                        _confirmResend(context, ref, stol, allowed),
                    onDelete: () => _confirmDelete(context, ref, stol, [
                      for (final o in byTable[stol] ?? const <MqttOutboxOrder>[])
                        if (o.isProblem) o,
                    ]),
                    onOpenTable: () =>
                        _openTable(context, stol, tableNames[stol] ?? ''),
                    onDeleteDraft: () =>
                        _confirmDeleteDraft(context, ref, stol),
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
          'Poslati ponovno narudžbe za ovaj stol? Glavni program ih '
          'prepoznaje po broju, narudžba koja je već ispisana neće se '
          'ispisati ponovno.',
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
    // §11.5: check again right before sending — the kasa may have left the
    // sales screen while the dialog was open.
    final gate = ref.read(mqttSendGateProvider);
    if (!gate.isOpen) {
      await _showLocked(context, gate);
      return;
    }
    ref
        .read(mqttOutboxProvider.notifier)
        .resend(
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
          'Poslati ponovno $count ${_narudzbuForm(count)} ($where)? Glavni '
          'program ih prepoznaje po broju, narudžba koja je već ispisana neće se '
          'ispisati ponovno.',
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
    // §11.5: check again right before sending — the kasa may have left the
    // sales screen while the dialog was open.
    final gate = ref.read(mqttSendGateProvider);
    if (!gate.isOpen) {
      await _showLocked(context, gate);
      return;
    }
    ref
        .read(mqttOutboxProvider.notifier)
        .resend(
          allowed: allowed,
          groupArticles: ref.read(settingsProvider).shouldGroupArticles,
        );
  }

  Future<void> _showLocked(BuildContext context, MqttSendGate gate) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slanje je zaključano'),
        content: Text(
          '${gate.message}. Narudžbe su ostale na popisu, pošaljite ih kad se '
          'slanje otključa.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('U redu'),
          ),
        ],
      ),
    );
  }

  /// Opens the table's order screen, where its unsent items are waiting.
  void _openTable(BuildContext context, int stol, String naziv) {
    final q = naziv.isEmpty ? '' : '?naziv=${Uri.encodeComponent(naziv)}';
    context.push('/mqtt-menu/$stol$q');
  }

  Future<void> _confirmDeleteDraft(
    BuildContext context,
    WidgetRef ref,
    int stol,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text('Obrisati neposlane stavke za stol $stol?'),
          content: const Text(
            'Ove stavke nisu poslane u glavni program. Bit će obrisane s '
            'uređaja.',
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
    ref.read(mqttOrdersProvider.notifier).clear(stol);
  }

  /// Deletes the table's red orders — amber ones are never deleted here.
  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    int stol,
    List<MqttOutboxOrder> orders,
  ) async {
    if (orders.isEmpty) return;
    // An order that may have reached the broker may already be printed.
    // Deleting it here does not undo that.
    final risky = orders.any((o) => o.mayBePrinted);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text('Obrisati narudžbe za stol $stol?'),
          content: Text(
            risky
                ? 'Glavni program je možda već zaprimio neku od ovih narudžbi, '
                      'nije je ni potvrdio ni odbio. Brisanjem se narudžba NE '
                      'poništava u glavnom programu.\n\nObrišite samo ako ste '
                      'provjerili da je nema na stolu.'
                : 'Glavni program ove narudžbe nije zaprimio. Stavke će biti '
                      'trajno '
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

/// The bottom bar sending every red order (not sent, refused, too old) again
/// at once.
class _ResendAllBar extends StatelessWidget {
  const _ResendAllBar({required this.count, required this.onPressed});

  final int count;

  /// Null while sending is locked — the button shows but can't be pressed.
  final VoidCallback? onPressed;

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

/// The explanation at the top of the list, as an information bubble. While
/// sending is locked (§11.4) it turns amber and says why — then it is news,
/// not just a hint.
class _Intro extends StatelessWidget {
  const _Intro({required this.gate});

  final MqttSendGate gate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final open = gate.isOpen;
    final accent = open
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
            open ? Icons.info_outline : Icons.lock_outline,
            size: 20,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              open
                  ? 'Plavo: stavke koje još niste poslali. Narančasto: čeka '
                        'potvrdu glavnog programa, ne treba ništa raditi. Crveno: '
                        'nije stiglo do glavnog programa, pošaljite ponovno '
                        'ili obrišite.'
                  : '${gate.message}, slanje je zaključano. Crvene narudžbe '
                        'možete poslati ponovno kad se slanje otključa.',
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

/// One table: its orders on their way, its unsent items, and the actions.
class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.stol,
    required this.orders,
    required this.draft,
    required this.byCode,
    required this.remarkName,
    required this.names,
    required this.canSend,
    required this.onResend,
    required this.onDelete,
    required this.onOpenTable,
    required this.onDeleteDraft,
  });

  final int stol;
  final List<MqttOutboxOrder> orders;

  /// Items added on this phone and not sent yet (blue).
  final MqttStoredOrder? draft;
  final Map<int, MqttArticle> byCode;
  final String Function(String cnap) remarkName;
  final Map<String, String> names;

  /// Sending is open (§11.4) — otherwise "Pošalji ponovno" can't be pressed.
  final bool canSend;
  final VoidCallback onResend;
  final VoidCallback onDelete;
  final VoidCallback onOpenTable;
  final VoidCallback onDeleteDraft;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final draftCuser = draft?.cuser;
    final waiters = {
      for (final o in orders) names[o.cuser] ?? o.cuser,
      if (draftCuser != null) names[draftCuser] ?? draftCuser,
    }.join(', ');
    // Only red orders can be sent again or deleted; amber ones wait for the
    // kasa and get no buttons at all.
    final hasProblems = orders.any((o) => o.isProblem);

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
                // Delete (red orders only): a small icon with a big invisible
                // hit area filling the card's top-right corner — easy to hit,
                // like the ✕ on a cart line in Stol X — and well away from
                // "Pošalji ponovno".
                if (hasProblems)
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
                  )
                else
                  // Same height as the delete target, so every card's header
                  // lines up.
                  const SizedBox(height: 46),
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
                  if (draft case final d?)
                    _DraftBlock(
                      draft: d,
                      byCode: byCode,
                      remarkName: remarkName,
                      onOpen: onOpenTable,
                      onDelete: onDeleteDraft,
                    ),
                  if (hasProblems)
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 4),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: canSend ? onResend : null,
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
    final (color, label, icon) = mqttExistingStatusStyle(
      mqttExistingStatusForOutbox(order.status),
      dark,
    );
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

  Widget _line(MqttCartLine l, ColorScheme scheme) =>
      _lineTile(l, scheme, byCode, remarkName);
}

/// Items added on this phone and not sent yet — blue, like their table.
class _DraftBlock extends StatelessWidget {
  const _DraftBlock({
    required this.draft,
    required this.byCode,
    required this.remarkName,
    required this.onOpen,
    required this.onDelete,
  });

  final MqttStoredOrder draft;
  final Map<int, MqttArticle> byCode;
  final String Function(String cnap) remarkName;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = mqttDraftColor(dark);
    final tagFg = dark ? const Color(0xFF10151C) : Colors.white;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.16 : 0.09),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                Icon(Icons.edit_note, size: 12, color: tagFg),
                const SizedBox(width: 3),
                Text(
                  'Neposlano',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: tagFg,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Stavke dodane na uređaju, još nisu poslane u glavni program.',
              style: TextStyle(fontSize: 13, color: scheme.onSurface),
            ),
          ),
          const SizedBox(height: 4),
          for (final l in draft.lines)
            _lineTile(l, scheme, byCode, remarkName),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Obriši'),
              ),
              const SizedBox(width: 4),
              FilledButton.tonalIcon(
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Otvori stol'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One line of an order: quantity, article and its napomene.
Widget _lineTile(
  MqttCartLine l,
  ColorScheme scheme,
  Map<int, MqttArticle> byCode,
  String Function(String cnap) remarkName,
) {
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
