import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../shared/presentation/bottom_sheet_safe_area.dart';
import '../data/mqtt_service.dart';
import '../models/mqtt_menu.dart';
import '../state/mqtt_cart.dart';
import '../state/mqtt_kasa_silence_provider.dart';
import '../state/mqtt_outbox_provider.dart';
import '../state/mqtt_pending_transfers_provider.dart';
import '../state/mqtt_send_gate_provider.dart';
import '../state/mqtt_table_contents.dart';
import '../state/mqtt_tables_provider.dart';
import 'mqtt_existing_items.dart';
import 'mqtt_kasa_silent_bar.dart';
import 'mqtt_napomene.dart';
import 'mqtt_qty_pad.dart';
import 'mqtt_reorder_handle.dart';
import 'mqtt_send_gate_bar.dart';

double _screenScale(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final diagonal = math.sqrt(
    size.width * size.width + size.height * size.height,
  );
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
    this.queuedForLater,
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

  /// Whether the last send only FROZE the order ("Čeka slanje") instead of
  /// publishing it — the send button then shows that mark, not the ✓.
  final bool Function()? queuedForLater;

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

  final _scroll = ScrollController();

  /// The order has been shown once. It is not listed from the top: the list
  /// opens at its end — the lines about to be sent, the ones to review — the
  /// same as Stol X (see [_land]).
  bool _landed = false;

  /// The list is hidden while it is being placed at its end — the frame or
  /// two it takes the list to learn its true length — and fades in there.
  bool _landing = false;

  /// When the loader first showed; it then stays at least
  /// [MqttExistingLoader.minVisible].
  DateTime? _loaderSince;

  /// The order is in, but the loader is still finishing its minimum time.
  bool _holdingLoader = false;
  Timer? _loaderTimer;

  @override
  void dispose() {
    _loaderTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// Places the hidden list at its end, then shows it. A jump, not a glide.
  /// The list only knows its true length once the rows near the end have been
  /// built, so it jumps again on the next frame(s) until it is there.
  void _land([int attempt = 0]) {
    if (!mounted) return;
    if (_scroll.hasClients && attempt < 4) {
      final position = _scroll.position;
      if (position.maxScrollExtent - position.pixels > 0.5) {
        _scroll.jumpTo(position.maxScrollExtent);
        WidgetsBinding.instance.addPostFrameCallback((_) => _land(attempt + 1));
        return;
      }
    }
    setState(() => _landing = false);
  }

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
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
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
    // Orders in a row the kasa hasn't answered — the same strip as on Stol X,
    // because Pošalji is on this screen too.
    final silence = ref.watch(mqttKasaSilenceProvider);
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
          // Waiting for the table's order: a short loader in place of the
          // list, exactly as on Stol X. The lines about to be sent wait behind
          // it and appear together with the order.
          final waiting =
              !_landed &&
              existing.rows.isEmpty &&
              existing.error == null &&
              (existing.awaiting ||
                  existing.loading ||
                  existing.placeholders > 0);
          if (waiting) _loaderSince ??= DateTime.now();
          // The order came in quickly: keep the loader up for the rest of its
          // minimum time before the order is shown.
          if (!_landed &&
              !waiting &&
              _loaderSince != null &&
              _loaderTimer == null) {
            final left =
                MqttExistingLoader.minVisible -
                DateTime.now().difference(_loaderSince!);
            if (left > Duration.zero) {
              _holdingLoader = true;
              _loaderTimer = Timer(left, () {
                if (mounted) setState(() => _holdingLoader = false);
              });
            }
          }
          final showLoader = waiting || _holdingLoader;
          // Everything is here: don't list it — hide the list, put it at its
          // end once this frame is laid out, and show it there.
          if (!_landed && !showLoader) {
            _landed = true;
            _landing = true;
            WidgetsBinding.instance.addPostFrameCallback((_) => _land());
          }
          // The existing order renders first and read-only. It is never part of
          // the reorder list, the clear action or what gets sent. One block,
          // with an animated height for anything that changes after it is
          // shown.
          final existingWidgets = <Widget>[
            if (existing.hasContent)
              MqttExistingSection(
                // Built fresh once the order is shown: its rows are then
                // simply there, at full height — no cascade, no growing
                // block — so the list's end is final at once. Later arrivals
                // in it still fade in on their own.
                key: ValueKey(_landed ? 'existing-landed' : 'existing'),
                // The loader stands in for the list while waiting, so the
                // section never shows placeholder rows.
                showPlaceholders: false,
                placeholders: const [],
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
                // Why sending is locked, right under the title — only while it
                // is; otherwise, when the kasa has stopped confirming, that.
                bottom: !sendGate.isOpen
                    ? MqttSendGateBar(gate: sendGate)
                    : (silence >= MqttKasaSilenceNotifier.threshold
                          ? MqttKasaSilentBar(count: silence)
                          : null),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      titleTop,
                      style:
                          Theme.of(context).appBarTheme.titleTextStyle ??
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
                        icon: Icon(
                          Icons.delete_sweep_outlined,
                          color: Theme.of(context).colorScheme.error,
                        ),
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
                        // The row being dragged is drawn in the nearest
                        // Overlay, and the app's own one spans the screen — so
                        // a row could be dragged up over the app bar and down
                        // over the total. Overlay.wrap puts an Overlay around
                        // this list alone, clipping the lift to the list.
                        //
                        // Overlay.wrap, NOT a hand-built Overlay with
                        // initialEntries: those entries are taken once, so the
                        // list would keep rendering the order it had on its
                        // first build and the rearranging would be lost.
                        // Overlay.wrap rebuilds its entry on every build. The
                        // same pairing is in Stol X's `_ReorderList`.
                        ? Overlay.wrap(
                            clipBehavior: Clip.hardEdge,
                            child: ReorderableListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                              // The handle drags at once; the rest of a row
                              // after a long press — so a plain vertical swipe
                              // on a row still scrolls a long order.
                              buildDefaultDragHandles: false,
                              itemCount: lines.length,
                              onReorderStart: (_) =>
                                  HapticFeedback.selectionClick(),
                              onReorder: cart.moveLine,
                              // The lifted row keeps its own rounded shape: the
                              // default lift is a plain rectangle that also
                              // covers the gap under the row.
                              proxyDecorator: (child, index, animation) =>
                                  _ReorderProxy(
                                    animation: animation,
                                    child: child,
                                  ),
                              itemBuilder: (context, i) {
                                final line = lines[i];
                                return _ReorderTile(
                                  key: ObjectKey(line),
                                  index: i,
                                  name: _name(line.code),
                                );
                              },
                            ),
                          )
                        : showLoader
                        ? MqttExistingLoader(scale: s)
                        // Hidden at once while it is being placed at its end,
                        // then faded in there — the order appears already
                        // scrolled to its last line.
                        : AnimatedOpacity(
                            opacity: _landing ? 0 : 1,
                            duration: _landing
                                ? Duration.zero
                                : const Duration(milliseconds: 160),
                            curve: Curves.easeOut,
                            child: ListView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                              itemCount:
                                  existingWidgets.length + lines.length + 1,
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
                                  // Keyed on the line OBJECT, not the index, so
                                  // a row keeps its identity through a move or
                                  // a delete and nothing it owns — an open
                                  // napomene sheet among it — follows the
                                  // wrong line.
                                  key: ObjectKey(line),
                                  index: i,
                                  line: line,
                                  cart: cart,
                                  name: _name(line.code),
                                  unit: byCode[line.code]?.unit ?? '',
                                  lineTotal: money.format(
                                    _price(line.code) * line.qty,
                                  ),
                                  available: _remarksFor(line.code),
                                );
                              },
                            ),
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
                      // Also while sending is locked for a passing reason —
                      // the order is frozen as "Čeka slanje" instead.
                      canSend:
                          lines.isNotEmpty &&
                          !_sending &&
                          widget.onSend != null &&
                          (sendGate.isOpen || sendGate.canQueue),
                      onSend: _send,
                      confirmed: _confirmed,
                      queuedForLater: widget.queuedForLater?.call() ?? false,
                      willQueue: !sendGate.isOpen && sendGate.canQueue,
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

/// One item row: name · line total, then quantity · napomene · ✕.
///
/// Nothing is hidden behind a disclosure. This is the review-before-sending
/// surface, so the napomene — the thing a waiter opens it to check — are on the
/// row, and so is the ✕ that removes the item. The row used to collapse to a
/// chevron that revealed both; removing an item then cost two taps, the first
/// of which did not look like deleting.
///
/// Height is unchanged for a line with no napomene: "Dodaj napomenu" rides the
/// control line in its compact form. A line that HAS them spends one more line
/// showing them, which is the right place for it.
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
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = widget.line;
    final s = _screenScale(context);
    // The line's napomene, each with how to take it off. Empty is the common
    // case and decides the whole row: no chips line, and the compact "Dodaj
    // napomenu" sits beside the quantity instead.
    final chips = [
      for (final c in line.remarkCodes)
        MqttNoteChip(
          label: _nameFor(c),
          onRemove: () => widget.cart.toggleRemarkCode(widget.index, c),
        ),
      for (final n in line.customNotes)
        MqttNoteChip(
          label: n,
          onRemove: () => widget.cart.removeCustomNote(widget.index, n),
        ),
    ];
    final hasNotes = chips.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: 8 * s),
      child: Material(
        color: scheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12 * s),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                12 * s,
                7 * s,
                6 * s,
                (hasNotes ? 8 : 4) * s,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          widget.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15 * s,
                            fontWeight: FontWeight.w600,
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
                              fontSize: 14 * s,
                              fontWeight: FontWeight.w700,
                            ),
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
                      if (!hasNotes) ...[
                        SizedBox(width: 6 * s),
                        MqttAddNoteButton(
                          scale: s,
                          onTap: () => _editRemarks(context),
                        ),
                      ],
                      const Spacer(),
                      // Where the chevron was, so the right end of this line
                      // stays the row's own action — but on a full touch
                      // target rather than the chevron's compact one, and
                      // widened a little, which the row has the room for.
                      IconButton(
                        onPressed: () => widget.cart.removeLine(widget.index),
                        tooltip: 'Ukloni stavku',
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(
                          minWidth: 54 * s,
                          minHeight: 48 * s,
                        ),
                        icon: Icon(
                          Icons.close,
                          size: 22 * s,
                          color: scheme.error,
                        ),
                      ),
                    ],
                  ),
                  // The napomene themselves, on the row: this screen exists to
                  // be read before sending, and a note hidden behind a tap is
                  // a note nobody checks.
                  if (hasNotes)
                    Padding(
                      padding: EdgeInsets.only(top: 6 * s, right: 4 * s),
                      child: MqttNoteRow(
                        chips: chips,
                        onOpen: () => _editRemarks(context),
                      ),
                    ),
                ],
              ),
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
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
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

/// One row in reorder mode: the article's full name · drag handle.
///
/// Everything editable is deliberately absent — dragging is the only gesture on
/// the row, so there is nothing for a drag to be confused with. So are the
/// quantity and the amount: while the order is being rearranged the only
/// question is which article goes where, and the same row in the order screen's
/// grid layout carries nothing else either.
///
/// The handle is a strip over the row's full height (drags at once); the rest
/// of the row drags after a long press.
class _ReorderTile extends StatelessWidget {
  const _ReorderTile({
    super.key,
    required this.index,
    required this.name,
  });

  final int index;
  final String name;

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
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: ReorderableDelayedDragStartListener(
          index: index,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      12 * s,
                      14 * s,
                      12 * s,
                      14 * s,
                    ),
                    // The whole name, over as many lines as it needs: it is
                    // the only thing left on the row, and a cut name is
                    // exactly what stops a waiter telling two similar
                    // articles apart while rearranging them.
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 15 * s,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                MqttReorderHandle(index: index, scale: s),
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
        padding: EdgeInsets.fromLTRB(
          16 * s,
          12 * s,
          16 * s,
          screenContentBottomPadding(context, extra: 12 * s),
        ),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ukupno',
                  style: TextStyle(
                    fontSize: 12 * s,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  total,
                  style: TextStyle(
                    fontSize: 20 * s,
                    fontWeight: FontWeight.w800,
                  ),
                ),
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
    this.queuedForLater = false,
    this.willQueue = false,
  });

  final String total;
  final bool sending;
  final bool canSend;
  final VoidCallback onSend;

  /// The kasa accepted the order — the send button shows ✓.
  final bool confirmed;

  /// [confirmed], but the order was only frozen: the button says "Čeka
  /// slanje" instead, because a ✓ would mean the kitchen has it.
  final bool queuedForLater;

  /// Sending is locked for a passing reason — pressing freezes the order, so
  /// the button is plum with a clock before it is pressed too.
  final bool willQueue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s = _screenScale(context);
    // Plum while sending is locked: pressing this freezes the order for
    // later rather than sending it. Same pair as the order screen's column.
    final sendBg = willQueue
        ? (dark ? const Color(0xFFC58BAE) : const Color(0xFF7A3F63))
        : (dark ? const Color(0xFF1FA9B6) : const Color(0xFF0E9AA7));
    final sendFg = willQueue
        ? (dark ? const Color(0xFF1E0C17) : Colors.white)
        : (dark ? const Color(0xFF052A2E) : Colors.white);
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16 * s,
          12 * s,
          16 * s,
          screenContentBottomPadding(context, extra: 12 * s),
        ),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ukupno',
                  style: TextStyle(
                    fontSize: 12 * s,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  total,
                  style: TextStyle(
                    fontSize: 20 * s,
                    fontWeight: FontWeight.w800,
                  ),
                ),
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
                          strokeWidth: 2,
                          color: sendFg,
                        ),
                      )
                    : Icon(
                        confirmed
                            ? (queuedForLater
                                  ? Icons.schedule_send
                                  : Icons.check)
                            : (willQueue ? Icons.schedule_send : Icons.send),
                        key: ValueKey(confirmed ? 'done' : 'idle'),
                      ),
              ),
              label: Text(
                confirmed && queuedForLater
                    ? 'Čeka slanje'
                    : 'Pošalji narudžbu',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
