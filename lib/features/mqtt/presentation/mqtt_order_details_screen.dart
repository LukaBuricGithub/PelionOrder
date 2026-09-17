import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../shared/presentation/bottom_sheet_safe_area.dart';
import '../data/mqtt_service.dart';
import '../models/mqtt_menu.dart';
import '../state/mqtt_cart.dart';
import '../state/mqtt_outbox_provider.dart';
import '../state/mqtt_pending_transfers_provider.dart';
import '../state/mqtt_send_gate_provider.dart';
import '../state/mqtt_table_contents.dart';
import '../state/mqtt_tables_provider.dart';
import 'mqtt_existing_items.dart';
import 'mqtt_napomene.dart';
import 'mqtt_qty_pad.dart';
import 'mqtt_send_gate_bar.dart';

double _screenScale(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final diagonal =
      math.sqrt(size.width * size.width + size.height * size.height);
  return (diagonal / 928.0).clamp(0.9, 1.4);
}

/// Fixed width reserved for the line amount ("9.999,99 €"), so amounts stay in a
/// right-aligned column and the name never collides with them.
const double _kAmountBaseWidth = 88;

/// How long the ✓ stays on the send button after the kasa accepts, before the
/// screen leaves. Long enough to register, short enough not to feel slow.
const kMqttSendConfirmHold = Duration(milliseconds: 350);

/// Details view for the MQTT order ("Stol X — detalji narudžbe"): the cart's
/// lines with per-line quantity and napomene, operating on the shared
/// [MqttCart]. "Pošalji narudžbu" delegates to [onSend] (owned by the order
/// screen); on success this screen pops with `'sent'`.
class MqttOrderDetailsScreen extends ConsumerStatefulWidget {
  const MqttOrderDetailsScreen({
    super.key,
    required this.cart,
    required this.byCode,
    required this.remarks,
    required this.money,
    this.tableBroj,
    this.tableNaziv,
    this.onSend,
    this.onSent,
    this.contents,
    this.sendingMsgId,
  });

  final MqttCart cart;
  final Map<int, MqttArticle> byCode;
  final List<MqttRemark> remarks;
  final NumberFormat money;
  final int? tableBroj;
  final String? tableNaziv;

  /// Sends the order (owned by the order screen). Returns true when the kasa
  /// accepted it — this screen then pops with `'sent'`.
  final Future<bool> Function()? onSend;

  /// The table's existing order (owned by the order screen), shown read-only
  /// above the editable lines. Null when the table had no order.
  /// The table's existing order, as the order screen has it right now —
  /// it may only start loading while this screen is open.
  final MqttTableContents? Function()? contents;

  /// Called after a successful send, once the ✓ has been shown. The order
  /// screen uses it to close both screens in one step and apply the send.
  final VoidCallback? onSent;

  /// The msg_id of the order being sent right now (owned by the order screen).
  /// Its lines are still this cart, so its outbox copy is not listed again.
  final String? Function()? sendingMsgId;

  @override
  ConsumerState<MqttOrderDetailsScreen> createState() =>
      _MqttOrderDetailsScreenState();
}

class _MqttOrderDetailsScreenState
    extends ConsumerState<MqttOrderDetailsScreen> {
  bool _sending = false;

  /// The kasa accepted the order and the ✓ is showing — see [_frozen].
  bool _confirmed = false;

  /// The first frame built after [_confirmed], returned as-is by every later
  /// build, so nothing on this screen changes while it leaves.
  Widget? _frozen;

  /// Reorder mode: rows collapse to one compact line with a drag handle and
  /// every editing control is hidden. Keeping it a separate mode is what makes
  /// dragging safe here — the normal row's tap-to-expand and its small +/−/✕
  /// targets would otherwise fight the drag gesture.
  bool _reordering = false;

  MqttCart get cart => widget.cart;
  Map<int, MqttArticle> get byCode => widget.byCode;
  List<MqttRemark> get remarks => widget.remarks;
  NumberFormat get money => widget.money;
  int? get tableBroj => widget.tableBroj;
  String? get tableNaziv => widget.tableNaziv;

  Future<void> _send() async {
    final send = widget.onSend;
    if (send == null || _sending) return;
    setState(() => _sending = true);
    final ok = await send();
    if (!mounted) return;
    setState(() {
      _sending = false;
      // ✓ in the same frame the spinner goes — and from here this screen is
      // frozen (see build) until it has left.
      _confirmed = ok;
    });
    if (!ok) return;
    // Let the ✓ register, then hand back to the order screen, which closes
    // both screens in one step and only then applies the send.
    await Future<void>.delayed(kMqttSendConfirmHold);
    if (!mounted) return;
    final onSent = widget.onSent;
    if (onSent != null) {
      onSent();
    } else {
      Navigator.of(context).pop('sent');
    }
  }

  String _name(int code) => byCode[code]?.name ?? 'Artikl $code';
  double _price(int code) => byCode[code]?.price ?? 0;

  /// Predefined remarks available for the article: every global ("sve") remark
  /// plus the ones the article lists by id. Codes (`cnap`) are what gets sent.
  List<MqttRemark> _remarksFor(int code) {
    final a = byCode[code];
    if (a == null) return const [];
    return [
      for (final r in remarks)
        if (r.sve || a.napomene.contains(r.cnap)) r,
    ];
  }

  /// Value of the lines being added now (the existing order is added on top).
  double get _cartTotal =>
      cart.lines.fold(0.0, (s, l) => s + _price(l.code) * l.qty);

  String _remarkName(String cnap) {
    for (final r in remarks) {
      if (r.cnap == cnap) return r.naziv;
    }
    return cnap;
  }

  /// Card chrome for a read-only existing line, matching the editable rows.
  Widget _existingCard(BuildContext context, Widget child, double s) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: 8 * s),
      child: Material(
        color: scheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12 * s),
          side:
              BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final broj = tableBroj;
    final naziv = tableNaziv;
    final titleTop = broj == null
        ? 'Narudžba'
        : (naziv != null && naziv.isNotEmpty
            ? 'Stol $broj · $naziv'
            : 'Stol $broj');

    // Watched here rather than inside the builder below: travelling lines come
    // from a provider, and a provider must be read in this widget's own build.
    final inTransit = broj == null
        ? const <MqttInTransitOrder>[]
        : (ref.watch(mqttPendingTransfersProvider)[broj] ??
            const <MqttInTransitOrder>[]);
    // The kasa's summary of this table from stolovi_stanje — already on the
    // device, so Ukupno and the placeholder rows are right before the first
    // query answer arrives.
    final seed = broj == null ? null : ref.watch(mqttOccupiedProvider)[broj];
    final outbox = ref.watch(mqttOutboxProvider);
    // §11.4: whether the kasa takes orders right now, and why not.
    final sendGate = ref.watch(mqttSendGateProvider);
    final contents = widget.contents?.call();

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
      ),
      child: ListenableBuilder(
        listenable: Listenable.merge([cart, ?contents]),
        builder: (context, _) {
          // After a successful send this screen shows its ✓ frame until gone.
          final frozen = _frozen;
          if (frozen != null) return frozen;
          final lines = cart.lines;
          final existing = MqttExistingItems.compute(
            contents: contents,
            inTransit: inTransit,
            byCode: byCode,
            remarkName: _remarkName,
            od: MqttService.instance.clientId,
            seedTotal: seed?.iznos,
            seedLineCount: seed?.stavki,
            unsent: [
              for (final o in outbox)
                if (o.stol == broj && o.msgId != widget.sendingMsgId?.call()) o,
            ],
          );
          // The whole table: what is on it, what is travelling, and what is
          // about to be sent.
          final total = existing.total + _cartTotal;
          final s = _screenScale(context);
          final dark = Theme.of(context).brightness == Brightness.dark;
          final loadingCard = _existingCard(
            context,
            MqttExistingNoticeTile(
              scale: s,
              busy: true,
              text: 'Učitavanje stavki sa stola…',
            ),
            s,
          );
          // The existing order renders first and read-only. It is never part of
          // the reorder list, the clear action or what gets sent. One animated
          // block, exactly as on Stol X: placeholders until the kasa answers,
          // a cross-fade into the real rows, and an animated height.
          final existingWidgets = <Widget>[
            if (existing.hasContent)
              MqttExistingSection(
                key: const ValueKey('existing'),
                showPlaceholders: existing.placeholders > 0,
                placeholders: [
                  if (existing.loading)
                    MqttFadeIn(
                        key: const ValueKey('loading'), child: loadingCard),
                  for (var i = 0; i < existing.placeholders; i++)
                    KeyedSubtree(
                      key: ValueKey('ph$i'),
                      child: _existingCard(
                        context,
                        MqttExistingSkeletonTile(index: i, scale: s),
                        s,
                      ),
                    ),
                ],
                items: [
                  if (existing.loading && existing.placeholders == 0)
                    ('loading', loadingCard),
                  if (existing.error != null)
                    (
                      'error',
                      _existingCard(
                        context,
                        MqttExistingNoticeTile(
                          scale: s,
                          icon: Icons.cloud_off,
                          text: existing.offline
                              ? existing.error!
                              : 'Stavke sa stola nisu dostupne. '
                                    'Dodirnite za ponovni pokušaj.',
                          onTap: existing.offline
                              ? null
                              : () => contents?.refresh(refill: true),
                        ),
                        s,
                      ),
                    ),
                  for (final row in existing.rows)
                    (
                      row.id,
                      _existingCard(
                        context,
                        MqttExistingItemTile(
                          row: row,
                          money: money,
                          scale: s,
                          // The review screen: every napomena, wrapped.
                          compact: false,
                        ),
                        s,
                      ),
                    ),
                  if (existing.othersPending > 0)
                    (
                      'others',
                      _existingCard(
                        context,
                        MqttExistingNoticeTile(
                          scale: s,
                          icon: Icons.arrow_upward,
                          color: mqttExistingStatusStyle(
                            MqttExistingStatus.naPutu,
                            dark,
                          ).$1,
                          text: mqttOthersPendingText(existing.othersPending),
                        ),
                        s,
                      ),
                    ),
                ],
              ),
            if (existing.hasContent && lines.isNotEmpty)
              MqttOrderSectionLabel(
                text: 'Nove stavke',
                scale: s,
                horizontalPadding: 2,
              ),
          ];
          // Once the kasa has accepted, nothing may be tapped: the ✓ is showing
          // and the screen is about to leave.
          final scaffold = IgnorePointer(
            // Also while sending: the cart IS the frozen order until the kasa
            // answers, so it must not change underneath it.
            ignoring: _confirmed || _sending,
            child: Scaffold(
            appBar: AppBar(
              titleSpacing: 0,
              // Why sending is locked, right under the title — only while it is.
              bottom:
                  sendGate.isOpen ? null : MqttSendGateBar(gate: sendGate),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    titleTop,
                    style: Theme.of(context).appBarTheme.titleTextStyle ??
                        Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    _reordering ? 'Presloži stavke' : 'Detalji narudžbe',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              actions: [
                if (_reordering)
                  TextButton.icon(
                    onPressed: () => setState(() => _reordering = false),
                    icon: const Icon(Icons.check),
                    label: const Text('Gotovo'),
                  )
                else ...[
                  // Nothing to reorder with a single line.
                  if (lines.length > 1)
                    IconButton(
                      icon: const Icon(Icons.swap_vert),
                      tooltip: 'Presloži stavke',
                      onPressed: () => setState(() => _reordering = true),
                    ),
                  if (lines.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.delete_sweep_outlined,
                          color: Theme.of(context).colorScheme.error),
                      tooltip: 'Isprazni narudžbu',
                      onPressed: () => _confirmClear(context),
                    ),
                ],
              ],
            ),
            body: Column(
              children: [
                Expanded(
                  child: _reordering
                      ? ReorderableListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                          // The handle drags at once; the rest of a row after a
                          // long press — so a plain vertical swipe on a row
                          // still scrolls a long order.
                          buildDefaultDragHandles: false,
                          itemCount: lines.length,
                          onReorderStart: (_) => HapticFeedback.selectionClick(),
                          onReorder: cart.moveLine,
                          // The lifted row keeps its own rounded shape: the
                          // default lift is a plain rectangle that also covers
                          // the gap under the row.
                          proxyDecorator: (child, index, animation) =>
                              _ReorderProxy(animation: animation, child: child),
                          itemBuilder: (context, i) {
                            final line = lines[i];
                            return _ReorderTile(
                              key: ObjectKey(line),
                              index: i,
                              name: _name(line.code),
                              qty: line.qty,
                              lineTotal:
                                  money.format(_price(line.code) * line.qty),
                            );
                          },
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                          itemCount: existingWidgets.length + lines.length + 1,
                          itemBuilder: (context, index) {
                            // Existing order first, read-only.
                            if (index < existingWidgets.length) {
                              return existingWidgets[index];
                            }
                            final i = index - existingWidgets.length;
                            if (i == lines.length) {
                              return _AddItemButton(
                                onTap: () => Navigator.of(context).pop(),
                              );
                            }
                            final line = lines[i];
                            return _LineTile(
                              // Keyed on the line OBJECT, not the index: the
                              // tile owns its expanded state, so an index key
                              // would leave the wrong row open after a move or
                              // a delete.
                              key: ObjectKey(line),
                              index: i,
                              line: line,
                              cart: cart,
                              name: _name(line.code),
                              unit: byCode[line.code]?.unit ?? '',
                              lineTotal:
                                  money.format(_price(line.code) * line.qty),
                              available: _remarksFor(line.code),
                            );
                          },
                        ),
                ),
                if (_reordering)
                  _ReorderDoneBar(
                    total: money.format(total),
                    onDone: () => setState(() => _reordering = false),
                  )
                else
                  _BottomBar(
                    total: money.format(total),
                    sending: _sending,
                    canSend: lines.isNotEmpty &&
                        !_sending &&
                        widget.onSend != null &&
                        sendGate.isOpen,
                    onSend: _send,
                    confirmed: _confirmed,
                  ),
              ],
            ),
            ),
          );
          // The first frame showing the ✓ is kept and returned by every later
          // build, so nothing on this screen changes while it leaves.
          if (_confirmed) _frozen = scaffold;
          return scaffold;
        },
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Isprazni narudžbu'),
          content: const Text('Ukloniti sve stavke iz narudžbe?'),
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
              label: const Text('Isprazni'),
            ),
          ],
        );
      },
    );
    if (ok == true) cart.clear();
  }
}

/// One compact, expandable item row: quantity button · name · line total ·
/// chevron. The chevron reveals the napomene (remarks) editor + delete.
///
/// Unlike the order screen's cart line, this row keeps its napomene visible
/// inline — this is the review-before-sending surface, and it has the width for
/// it. Only the quantity control is shared with that screen.
class _LineTile extends StatefulWidget {
  const _LineTile({
    super.key,
    required this.index,
    required this.line,
    required this.cart,
    required this.name,
    required this.unit,
    required this.lineTotal,
    required this.available,
  });

  final int index;
  final MqttCartLine line;
  final MqttCart cart;
  final String name;
  final String unit;
  final String lineTotal;
  final List<MqttRemark> available;

  @override
  State<_LineTile> createState() => _LineTileState();
}

class _LineTileState extends State<_LineTile> {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = widget.line;
    final s = _screenScale(context);

    return Padding(
      padding: EdgeInsets.only(bottom: 8 * s),
      child: Material(
        color: scheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12 * s),
          side:
              BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(12 * s, 7 * s, 6 * s, 4 * s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _toggle,
                          behavior: HitTestBehavior.opaque,
                          child: Text(
                            widget.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 15 * s, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      SizedBox(width: 10 * s),
                      Padding(
                        padding: EdgeInsets.only(top: 1 * s, right: 6 * s),
                        child: SizedBox(
                          width: _kAmountBaseWidth * s,
                          child: Text(
                            widget.lineTotal,
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            style: TextStyle(
                                fontSize: 14 * s, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6 * s),
                  Row(
                    children: [
                      MqttQtyButton(
                        qty: line.qty,
                        unit: widget.unit,
                        scale: s,
                        onTap: _editQty,
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _toggle,
                        visualDensity: VisualDensity.compact,
                        icon: AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: Icon(Icons.expand_more,
                              size: 24 * s, color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Padding(
                      padding: EdgeInsets.fromLTRB(12 * s, 0, 10 * s, 6 * s),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MqttNoteRow(
                            chips: [
                              for (final c in line.remarkCodes)
                                MqttNoteChip(
                                  label: _nameFor(c),
                                  onRemove: () => widget.cart
                                      .toggleRemarkCode(widget.index, c),
                                ),
                              for (final n in line.customNotes)
                                MqttNoteChip(
                                  label: n,
                                  onRemove: () => widget.cart
                                      .removeCustomNote(widget.index, n),
                                ),
                            ],
                            onOpen: () => _editRemarks(context),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () =>
                                  widget.cart.removeLine(widget.index),
                              style: TextButton.styleFrom(
                                foregroundColor: scheme.error,
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const Text('Ukloni stavku'),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editQty() async {
    final v = await showMqttQtyPad(
      context: context,
      articleName: widget.name,
      unit: widget.unit,
      initial: widget.line.qty,
    );
    if (v == null || !mounted) return;
    // 0 removes the line — setQuantity already drops a line at <= 0.
    widget.cart.setQuantity(widget.index, v);
  }

  /// Display name for a selected remark code, resolved from this article's
  /// available remarks (falls back to the code itself).
  String _nameFor(String cnap) {
    for (final r in widget.available) {
      if (r.cnap == cnap) return r.naziv;
    }
    return cnap;
  }

  Future<void> _editRemarks(BuildContext context) async {
    await showMqttRemarksSheet(
      context: context,
      available: widget.available,
      selectedCodes: widget.line.remarkCodes,
      customNotes: widget.line.customNotes,
      onToggleCode: (c) => widget.cart.toggleRemarkCode(widget.index, c),
      onAddNote: (n) => widget.cart.addCustomNote(widget.index, n),
      onRemoveNote: (n) => widget.cart.removeCustomNote(widget.index, n),
    );
  }
}

/// "Dodaj stavku" — returns to the order screen's article grid.
class _AddItemButton extends StatelessWidget {
  const _AddItemButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Dodaj stavku'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(46),
        ),
      ),
    );
  }
}

/// How a row looks while it is being dragged: lifted, with a soft shadow in
/// the row's own rounded shape — not under the gap below it.
class _ReorderProxy extends StatelessWidget {
  const _ReorderProxy({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = _screenScale(context);
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(animation.value);
        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              // The shadow, only behind the row (the tile's bottom padding
              // is the gap to the next row).
              Positioned.fill(
                bottom: _kReorderGap * s,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12 * s),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22 * t),
                        blurRadius: 14 * t,
                        offset: Offset(0, 5 * t),
                      ),
                    ],
                  ),
                ),
              ),
              Transform.scale(scale: 1 + 0.02 * t, child: child),
            ],
          ),
        );
      },
    );
  }
}

/// Space under each row in reorder mode (unscaled).
const double _kReorderGap = 8;

/// One row in reorder mode: drag handle · name · ×qty · line total.
///
/// Everything editable is deliberately absent — dragging is the only gesture
/// on the row, so there is nothing for a drag to be confused with, and the rows
/// stay short and uniform (more of the order on screen, predictable drop
/// targets).
///
/// The handle is a wide strip over the row's full height (drags at once); the
/// rest of the row drags after a long press.
class _ReorderTile extends StatelessWidget {
  const _ReorderTile({
    super.key,
    required this.index,
    required this.name,
    required this.qty,
    required this.lineTotal,
  });

  final int index;
  final String name;
  final double qty;
  final String lineTotal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = _screenScale(context);

    return Padding(
      padding: EdgeInsets.only(bottom: _kReorderGap * s),
      child: Material(
        color: scheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12 * s),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: ReorderableDelayedDragStartListener(
          index: index,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Container(
                    width: 56 * s,
                    color: scheme.primary.withValues(alpha: 0.08),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.drag_handle,
                      size: 26 * s,
                      color: scheme.primary,
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      12 * s,
                      14 * s,
                      12 * s,
                      14 * s,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15 * s,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        SizedBox(width: 8 * s),
                        Text(
                          '×${formatQty(qty)}',
                          style: TextStyle(
                            fontSize: 14 * s,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        SizedBox(width: 10 * s),
                        SizedBox(
                          width: _kAmountBaseWidth * s,
                          child: Text(
                            lineTotal,
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 14 * s,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The bottom bar while reordering: the total stays visible, and "Pošalji
/// narudžbu" is replaced by Gotovo so the order can't be sent mid-rearrange.
class _ReorderDoneBar extends StatelessWidget {
  const _ReorderDoneBar({required this.total, required this.onDone});

  final String total;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = _screenScale(context);
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16 * s, 12 * s, 16 * s,
            screenContentBottomPadding(context, extra: 12 * s)),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Ukupno',
                    style: TextStyle(
                        fontSize: 12 * s, color: scheme.onSurfaceVariant)),
                Text(total,
                    style: TextStyle(
                        fontSize: 20 * s, fontWeight: FontWeight.w800)),
              ],
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: onDone,
              icon: const Icon(Icons.check),
              label: const Text('Gotovo'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.total,
    required this.sending,
    required this.canSend,
    required this.onSend,
    this.confirmed = false,
  });

  final String total;
  final bool sending;
  final bool canSend;
  final VoidCallback onSend;

  /// The kasa accepted the order — the send button shows ✓.
  final bool confirmed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s = _screenScale(context);
    final sendBg = dark ? const Color(0xFF1FA9B6) : const Color(0xFF0E9AA7);
    final sendFg = dark ? const Color(0xFF052A2E) : Colors.white;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16 * s, 12 * s, 16 * s,
            screenContentBottomPadding(context, extra: 12 * s)),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Ukupno',
                    style: TextStyle(
                        fontSize: 12 * s, color: scheme.onSurfaceVariant)),
                Text(total,
                    style: TextStyle(
                        fontSize: 20 * s, fontWeight: FontWeight.w800)),
              ],
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: canSend ? onSend : null,
              style: FilledButton.styleFrom(
                backgroundColor: sendBg,
                foregroundColor: sendFg,
              ),
              // spinner → ✓ is a small scale-in, so the confirmation reads as
              // the button finishing its job rather than an icon being swapped.
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: sending
                    ? SizedBox(
                        key: const ValueKey('busy'),
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: sendFg),
                      )
                    : Icon(
                        confirmed ? Icons.check : Icons.send,
                        key: ValueKey(confirmed ? 'done' : 'idle'),
                      ),
              ),
              label: const Text('Pošalji narudžbu'),
            ),
          ],
        ),
      ),
    );
  }
}
