import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../auth/state/session_provider.dart';
import '../../settings/models/menu_view_size.dart';
import '../../settings/state/settings_provider.dart';
import '../data/mqtt_order_sender.dart';
import '../data/mqtt_service.dart';
import '../models/mqtt_menu.dart';
import '../models/mqtt_tables.dart';
import '../state/mqtt_cart.dart';
import '../state/mqtt_menu_provider.dart';
import '../state/mqtt_orders_provider.dart';
import '../state/mqtt_pending_transfers_provider.dart';
import '../state/mqtt_table_contents.dart';
import '../state/mqtt_tables_provider.dart';
import 'mqtt_existing_items.dart';
import 'mqtt_napomene.dart';
import 'mqtt_order_details_screen.dart';
import 'mqtt_qty_pad.dart';

/// Tile label size derived from the tile's ACTUAL width.
///
/// One rule instead of a font size per density level: it stays right for every
/// column count AND every device, and a new level needs no new constant. The
/// ratio is the current 4-column look (≈9.5pt on an ≈89px tile) carried
/// forward, so the densest setting renders exactly as it does today.
double _tileFontSize(double tileWidth, {double min = 9, double max = 17}) =>
    (tileWidth * 0.107).clamp(min, max);

/// Width of one tile in a grid of [columns], given the row's padding and gaps.
double _tileWidth(double maxWidth, int columns, double hPad, double spacing) =>
    (maxWidth - hPad * 2 - spacing * (columns - 1)) / columns;

/// Screen-size-driven UI scale (identical to the New Order screen): 1.0 ≈ a
/// typical phone (~928 dp diagonal). Every size is multiplied by this.
double _screenScale(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final diagonal = math.sqrt(
    size.width * size.width + size.height * size.height,
  );
  return (diagonal / 928.0).clamp(0.9, 1.4);
}

/// Order-entry screen ("Stol X") for the MQTT menu, backed by an in-memory
/// [MqttCart] built from the MQTT groups/articles. Send publishes the order to
/// the kasa over MQTT and applies the reply (see `MqttOrderSender`).
class MqttOrderScreen extends ConsumerStatefulWidget {
  const MqttOrderScreen({super.key, this.tableBroj, this.tableNaziv});

  final int? tableBroj;
  final String? tableNaziv;

  @override
  ConsumerState<MqttOrderScreen> createState() => _MqttOrderScreenState();
}

class _MqttOrderScreenState extends ConsumerState<MqttOrderScreen> {
  final _money = NumberFormat.currency(locale: 'hr_HR', symbol: '€');
  final _cart = MqttCart();
  final _searchController = TextEditingController();

  int? _selectedGroupId;
  String _query = '';
  bool _searching = false;

  /// True while an order is in flight (publish + up to 5 reply waits).
  bool _sending = false;

  /// What is already on this table, from the kasa. Null for a table with no
  /// existing order — then there is nothing to load and nothing to show.
  MqttTableContents? _contents;

  /// The kasa accepted the order and the ✓ is showing. From here the screen is
  /// on its way out: input is ignored and it no longer changes.
  bool _confirmed = false;

  /// The first frame built after [_confirmed], returned as-is by every later
  /// build — so nothing that happens next (dropping the draft, lines moving to
  /// "šalje se") can be seen before the screen has left.
  Widget? _frozen;

  /// Leaving after a send has started — guards against leaving twice.
  bool _leaving = false;

  /// What a successful send still has to apply once the screen is leaving.
  _SendCommit? _pendingCommit;

  // Captured in initState: the send is applied while the screen is leaving,
  // when `ref` may no longer be used.
  late final MqttOrdersNotifier _ordersNotifier;
  late final MqttPendingTransfersNotifier _transfersNotifier;

  // Rebuilt each build from the current menu — maps article code → article.
  final _byCode = <int, MqttArticle>{};
  MqttMenu _menu = MqttMenu.empty;

  /// Predefined remarks available for the article (global "sve" remarks + the
  /// ones the article lists by id). Codes (`cnap`) are what gets ordered.
  List<MqttRemark> _remarksFor(int code) {
    final a = _byCode[code];
    return a == null ? const [] : _menu.remarksFor(a);
  }

  @override
  void initState() {
    super.initState();
    _ordersNotifier = ref.read(mqttOrdersProvider.notifier);
    _transfersNotifier = ref.read(mqttPendingTransfersProvider.notifier);
    // Restore any in-progress order for this table (kept for the session), then
    // start listening so subsequent edits are saved back.
    final broj = widget.tableBroj;
    if (broj != null) {
      final orders = ref.read(mqttOrdersProvider.notifier);
      final stored = orders.linesFor(broj);
      if (stored.isNotEmpty) _cart.loadFrom(stored);
      // Restore the pending msg_id AFTER loadFrom (which clears it), so a retry
      // of an already-sent order reuses the same id instead of duplicating it.
      _cart.pendingMsgId = orders.msgIdFor(broj);
    }
    // A table that already has an order — or one this phone just sent to —
    // shows its existing lines above the new ones, read-only.
    if (broj != null &&
        (ref.read(mqttOccupiedProvider).containsKey(broj) ||
            ref.read(mqttPendingTransfersProvider).containsKey(broj))) {
      _contents = MqttTableContents(broj)..addListener(_onContents);
      Future.microtask(() => _contents?.refresh());
    }
    _cart.addListener(_onCart);
    // Match the New Order screen: hide the Android nav bar (keep the status
    // bar) and lock to portrait while ordering.
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  @override
  void dispose() {
    // Left some other way during the ✓ hold (e.g. back): the send still stands,
    // so apply it — after this frame, since providers must not change while the
    // widget tree is being torn down.
    final commit = _pendingCommit;
    if (commit != null) {
      _pendingCommit = null;
      final orders = _ordersNotifier;
      final transfers = _transfersNotifier;
      Future.microtask(() {
        orders.clear(commit.broj);
        transfers.watchTable(commit.broj, commit.sent);
      });
    }
    _contents?.removeListener(_onContents);
    _contents?.dispose();
    _cart.removeListener(_onCart);
    _cart.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _searchController.dispose();
    super.dispose();
  }

  void _onCart() {
    // Persist the order for this table so it survives leaving the screen and
    // colours the table in the floor plan.
    final broj = widget.tableBroj;
    if (broj != null) {
      ref
          .read(mqttOrdersProvider.notifier)
          .save(broj, _cart.lines, _cart.pendingMsgId);
    }
    if (mounted) setState(() {});
  }

  void _onContents() {
    if (!mounted) return;
    final broj = widget.tableBroj;
    final reply = _contents?.reply;
    // A fresh answer may show our travelling lines have landed — clear them
    // from the watch at once, so they are never listed twice.
    if (broj != null && reply != null) {
      ref.read(mqttPendingTransfersProvider.notifier).applyReply(broj, reply);
    }
    setState(() {});
  }

  double _priceFor(int code) => _byCode[code]?.price ?? 0;

  /// Value of the lines being added now (the existing order is added on top).
  double get _cartTotal =>
      _cart.lines.fold(0.0, (sum, l) => sum + _priceFor(l.code) * l.qty);

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchController.clear();
        _query = '';
      }
    });
  }

  /// Sends the order to the kasa and applies the outcome. Returns true when the
  /// kasa accepted it. Shared by the Send button and the details screen.
  Future<bool> _sendOrder() async {
    if (_sending) return false;
    final broj = widget.tableBroj;
    final user = ref.read(currentUserProvider);
    final messenger = ScaffoldMessenger.of(context);

    if (broj == null || user == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Nije poznat stol ili konobar.')),
      );
      return false;
    }

    // Generate the msg_id once and persist it immediately, so a retry — even
    // after leaving the screen — reuses it instead of booking a duplicate.
    final msgId = _cart.pendingMsgId ?? newMsgId();
    _cart.pendingMsgId = msgId;
    final orders = ref.read(mqttOrdersProvider.notifier);
    orders.save(broj, _cart.lines, msgId);

    setState(() => _sending = true);
    final result = await MqttOrderSender.instance.send(
      stol: broj,
      cuser: user.code,
      lines: _cart.lines,
      msgId: msgId,
      groupArticles: ref.read(settingsProvider).shouldGroupArticles,
    );
    if (!mounted) return result.isOk;
    setState(() {
      _sending = false;
      // The ✓ replaces the spinner in the same frame, so there is no flash of
      // the plain send icon between "sending" and "sent". Setting it also
      // freezes the screen (see build) until it has left.
      _confirmed = result.isOk;
    });

    if (result.isOk) {
      // Keep what was sent: until the kasa moves these lines onto the table its
      // query reply only COUNTS them, so this copy is the only way to show them
      // as "šalje se".
      final sent = MqttInTransitOrder(
        msgId: msgId,
        lines: [for (final l in _cart.lines) l.copy()],
        sentLineCount: ref.read(settingsProvider).shouldGroupArticles
            ? groupCartLines(_cart.lines).length
            : _cart.lines.length,
      );
      // Nothing changes on screen yet: the draft is dropped and the transfer
      // watched only once the screen is leaving — see [_commitSend].
      _pendingCommit = _SendCommit(broj, sent);
      // No snackbar on success: the ✓ on the button is the confirmation. A
      // light tap goes with it — clearly below the article-tile thump.
      HapticFeedback.lightImpact();
    } else if (result.needsNewMsgId) {
      // Expired / never sent: the next attempt must be a NEW order.
      _cart.pendingMsgId = null;
      orders.save(broj, _cart.lines, null);
    } else {
      // Rejected or unreachable — keep the id so an unchanged retry stays
      // idempotent (editing the cart clears it automatically).
      orders.save(broj, _cart.lines, msgId);
    }

    // Failures still speak: they are the cases the waiter cannot see for
    // themselves and may need to act on.
    if (!result.isOk) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(result.message)));
    }
    return result.isOk;
  }

  Future<void> _send() async {
    final ok = await _sendOrder();
    if (!mounted || !ok) return;
    // Let the ✓ register — an instant jump straight after a network wait is
    // what reads as a glitch — then leave.
    await Future<void>.delayed(kMqttSendConfirmHold);
    if (!mounted) return;
    _leave();
  }

  /// Returns to the floor plan in ONE step — closing the details screen too if
  /// it is open, instead of two pops in a row — and only then applies the send.
  /// Both screens are frozen by now, so the change is never seen on them.
  void _leave() {
    if (_leaving) return;
    _leaving = true;
    Navigator.of(context).popUntil((route) => route.isFirst);
    _commitSend();
  }

  /// Applies a successful send: drops the table's draft and starts watching the
  /// transfer. Deliberately deferred until the screen is leaving — doing it at
  /// the moment of success is what made the lines jump into the existing
  /// section and turn amber before the screen left.
  void _commitSend() {
    final commit = _pendingCommit;
    if (commit == null) return;
    _pendingCommit = null;
    _ordersNotifier.clear(commit.broj);
    _transfersNotifier.watchTable(commit.broj, commit.sent);
  }

  /// Opens the details screen on the same cart (edit quantities/remarks/delete).
  void _openDetails() {
    // Details is a normal screen: restore the nav bar while it's shown, re-hide
    // it on return (this screen hides it).
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Navigator.of(context)
        .push(
          MaterialPageRoute<String>(
            builder: (_) => MqttOrderDetailsScreen(
              cart: _cart,
              byCode: _byCode,
              remarks: ref.read(mqttMenuProvider).remarks,
              money: _money,
              tableBroj: widget.tableBroj,
              tableNaziv: widget.tableNaziv,
              onSend: _sendOrder,
              onSent: _leave,
              contents: _contents,
            ),
          ),
        )
        .then((result) {
          // Already leaving after a send from details: both screens close
          // together, so leave the nav bar alone on the way out.
          if (!mounted || _leaving) return;
          // Sent from details but closed before the ✓ finished (e.g. back): the
          // send stands, so finish leaving from here rather than sit on a
          // frozen screen.
          if (_confirmed) {
            _leave();
            return;
          }
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: [SystemUiOverlay.top],
          );
        });
  }

  Future<void> _confirmClear() async {
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
    if (ok == true) _cart.clear();
  }

  List<MqttArticle> _visibleArticles(List<MqttArticleGroup> groups) {
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      return [
        for (final g in groups)
          ...g.articles.where((a) => a.name.toLowerCase().contains(q)),
      ];
    }
    if (groups.isEmpty) return const [];
    final id = _selectedGroupId ?? groups.first.id;
    final group = groups.firstWhere(
      (g) => g.id == id,
      orElse: () => groups.first,
    );
    return group.articles;
  }

  @override
  Widget build(BuildContext context) {
    // After a successful send the screen shows its ✓ frame until it has left.
    final frozen = _frozen;
    if (frozen != null) return frozen;
    _menu = ref.watch(mqttMenuProvider);
    final groups = _menu.groups;
    _byCode
      ..clear()
      ..addEntries([
        for (final g in groups)
          for (final a in g.articles) MapEntry(a.code, a),
      ]);

    // Grid density ("Veličina artikala u narudžbi" in Postavke uređaja).
    final menuSize = ref.watch(settingsProvider).menuViewSize;

    // The table's existing order: lines already on it (from the kasa) plus lines
    // this phone sent that are still travelling.
    final tableBroj = widget.tableBroj;
    final inTransit = tableBroj == null
        ? const <MqttInTransitOrder>[]
        : (ref.watch(mqttPendingTransfersProvider)[tableBroj] ??
              const <MqttInTransitOrder>[]);
    final existing = MqttExistingItems.compute(
      contents: _contents,
      inTransit: inTransit,
      byCode: _byCode,
      remarkName: _menu.remarkName,
      od: MqttService.instance.clientId,
      // Already on the device, so the total is right before the kasa answers.
      seedTotal: tableBroj == null
          ? null
          : ref.watch(mqttOccupiedProvider)[tableBroj]?.iznos,
    );
    // Re-ask when the kasa announces a change on this table.
    if (_contents != null) {
      ref.listen<Map<int, MqttTableState>>(mqttOccupiedProvider, (prev, next) {
        final before = prev?[tableBroj];
        final after = next[tableBroj];
        if (before?.stavki != after?.stavki ||
            before?.iznos != after?.iznos ||
            before?.cuser != after?.cuser) {
          _contents?.refresh(refill: true);
        }
      });
    }

    final broj = widget.tableBroj;
    final naziv = widget.tableNaziv;
    final title = broj == null
        ? 'Narudžba'
        : (naziv != null && naziv.isNotEmpty
              ? 'Stol $broj · $naziv'
              : 'Stol $broj');

    final hasItems = _cart.isNotEmpty;
    final selectedId =
        _selectedGroupId ?? (groups.isEmpty ? null : groups.first.id);
    final articles = _visibleArticles(groups);

    final screen = MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
      ),
      // Once the kasa has accepted, nothing may be tapped: the ✓ is showing and
      // the screen is about to leave.
      child: IgnorePointer(
        ignoring: _confirmed,
        child: Scaffold(
          appBar: AppBar(title: Text(title)),
          body: groups.isEmpty
              ? const _EmptyMenu()
              : SafeArea(
                  child: Column(
                    children: [
                      // ── Order (cart) + actions ──────────────────────────────
                      Expanded(
                        flex: 5,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _CartCard(
                                  cart: _cart,
                                  byCode: _byCode,
                                  money: _money,
                                  remarksFor: _remarksFor,
                                  existing: existing,
                                  onRetryExisting: () =>
                                      _contents?.refresh(refill: true),
                                ),
                              ),
                              const SizedBox(width: 10),
                              _ActionColumn(
                                sending: _sending,
                                confirmed: _confirmed,
                                onClear: hasItems && !_sending
                                    ? _confirmClear
                                    : null,
                                // Details also opens on the existing order alone,
                                // to read it — sending still needs new lines.
                                onDetails:
                                    (hasItems || existing.rows.isNotEmpty) &&
                                        !_sending
                                    ? _openDetails
                                    : null,
                                onSend: hasItems && !_sending ? _send : null,
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ── Total (+ search toggle) ─────────────────────────────
                      _TotalBar(
                        // The whole table: what is on it, what is travelling,
                        // and what is about to be sent.
                        total: _money.format(existing.total + _cartTotal),
                        searching: _searching,
                        onToggleSearch: _toggleSearch,
                      ),

                      // ── Article picker ──────────────────────────────────────
                      Expanded(
                        flex: 6,
                        child: Column(
                          children: [
                            _PickerBar(
                              groups: groups,
                              size: menuSize,
                              selectedId: selectedId,
                              searching: _searching,
                              searchController: _searchController,
                              onSelectGroup: (id) => setState(() {
                                _selectedGroupId = id;
                                _query = '';
                              }),
                              onQuery: (q) => setState(() => _query = q),
                            ),
                            Expanded(
                              child: _ArticleGrid(
                                articles: articles,
                                size: menuSize,
                                onAdd: _cart.addLine,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
    // The first frame showing the ✓ is kept and returned by every later build.
    if (_confirmed) _frozen = screen;
    return screen;
  }
}

/// The running order as a card: the table's existing lines first (read-only,
/// coloured by status), then the lines being added now (editable). Auto-scrolls
/// to the newest line when one is added.
class _CartCard extends StatefulWidget {
  const _CartCard({
    required this.cart,
    required this.byCode,
    required this.money,
    required this.remarksFor,
    required this.existing,
    required this.onRetryExisting,
  });

  final MqttCart cart;
  final Map<int, MqttArticle> byCode;
  final NumberFormat money;
  final List<MqttRemark> Function(int code) remarksFor;

  /// The table's existing order, shown read-only above the new lines.
  final MqttExistingItems existing;
  final VoidCallback onRetryExisting;

  @override
  State<_CartCard> createState() => _CartCardState();
}

class _CartCardState extends State<_CartCard> {
  final _scroll = ScrollController();
  int _lastCount = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lines = widget.cart.lines;
    final s = _screenScale(context);

    // The cart list is mutated in place (same reference), so compare against the
    // last-built count to detect a newly added line and scroll to it.
    if (lines.length > _lastCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      });
    }
    _lastCount = lines.length;

    final dark = Theme.of(context).brightness == Brightness.dark;
    final existing = widget.existing;
    // Existing order first (read-only, oldest at the top), then the lines being
    // added now — so a new line always lands at the bottom, where the
    // auto-scroll above takes the waiter.
    final children = <Widget>[
      if (existing.loading)
        MqttExistingNoticeTile(
          scale: s,
          busy: true,
          text: 'Učitavanje stavki sa stola…',
        ),
      if (existing.error != null)
        MqttExistingNoticeTile(
          scale: s,
          icon: Icons.cloud_off,
          text: 'Stavke sa stola nisu dostupne. Dodirnite za ponovni pokušaj.',
          onTap: widget.onRetryExisting,
        ),
      for (final row in existing.rows)
        MqttExistingItemTile(
          key: ValueKey(row.id),
          row: row,
          money: widget.money,
          scale: s,
        ),
      if (existing.othersPending > 0)
        MqttExistingNoticeTile(
          scale: s,
          icon: Icons.arrow_upward,
          color: mqttExistingStatusStyle(MqttExistingStatus.naPutu, dark).$1,
          text: mqttOthersPendingText(existing.othersPending),
        ),
      if (existing.hasContent && lines.isNotEmpty)
        MqttOrderSectionLabel(text: 'Nove stavke', scale: s),
      for (var i = 0; i < lines.length; i++)
        _CartLineTile(
          key: ValueKey('cartline_${lines[i].code}_$i'),
          index: i,
          line: lines[i],
          cart: widget.cart,
          name: widget.byCode[lines[i].code]?.name ?? 'Artikl ${lines[i].code}',
          unit: widget.byCode[lines[i].code]?.unit ?? '',
          lineTotal: widget.money.format(
            (widget.byCode[lines[i].code]?.price ?? 0) * lines[i].qty,
          ),
          available: widget.remarksFor(lines[i].code),
        ),
    ];

    return Material(
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14 * s),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      // While the kasa's first answer is on its way the card stays blank: the
      // items are coming, and saying "Nema stavki" for a moment is exactly the
      // flash we don't want. The empty text only appears once that is true.
      child: children.isEmpty && existing.awaiting
          ? const SizedBox.shrink()
          : children.isEmpty
          ? Center(
              child: Text(
                'Nema stavki u narudžbi',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          : ListView.separated(
              controller: _scroll,
              padding: EdgeInsets.only(bottom: 2 * s),
              itemCount: children.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => children[i],
            ),
    );
  }
}

/// One cart line: name + ✕ on top, then the two editors (quantity, napomene)
/// and the line total.
///
/// Both editors are explicit buttons opening a sheet — there is no hidden
/// tap-the-row gesture and no inline expansion. That keeps every row the same
/// height (so the list never reflows under the waiter's finger) and makes the
/// napomene editor discoverable, which a tap target with no affordance wasn't.
class _CartLineTile extends StatefulWidget {
  const _CartLineTile({
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
  State<_CartLineTile> createState() => _CartLineTileState();
}

class _CartLineTileState extends State<_CartLineTile> {
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

  void _editRemarks() {
    showMqttRemarksSheet(
      context: context,
      available: widget.available,
      selectedCodes: widget.line.remarkCodes,
      customNotes: widget.line.customNotes,
      onToggleCode: (c) => widget.cart.toggleRemarkCode(widget.index, c),
      onAddNote: (n) => widget.cart.addCustomNote(widget.index, n),
      onRemoveNote: (n) => widget.cart.removeCustomNote(widget.index, n),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = widget.line;
    final s = _screenScale(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(12 * s, 3 * s, 6 * s, 4 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.name,
                  style: TextStyle(
                    fontSize: 14 * s,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // Big invisible hit area on the top-right so removing is easy —
              // the ✕ icon itself stays the same size. With the − button gone
              // this is the way to delete a line (typing 0 also works). The
              // zone continues down the right-hand side over the price; see the
              // second row.
              GestureDetector(
                onTap: () => widget.cart.removeLine(widget.index),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24 * s, 6 * s, 8 * s, 14 * s),
                  child: Icon(Icons.close, size: 18 * s, color: scheme.error),
                ),
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.only(right: 2 * s, top: 2 * s),
            child: Row(
              children: [
                MqttQtyButton(
                  qty: line.qty,
                  unit: widget.unit,
                  scale: s,
                  onTap: _editQty,
                ),
                SizedBox(width: 6 * s),
                _NoteButton(
                  count: line.remarkCodes.length + line.customNotes.length,
                  onTap: _editRemarks,
                ),
                // Inert gap: the space beside the napomene button must NOT
                // delete anything — it sits right under the thumb that just
                // pressed that button.
                const Spacer(),
                // The ✕ hit area continues down to the price itself, with a
                // small lead-in so the glyph doesn't have to be hit exactly.
                // Flexible (not Expanded) keeps the zone tight to the text and
                // still lets it shrink rather than overflow on a narrow row.
                Flexible(
                  child: GestureDetector(
                    onTap: () => widget.cart.removeLine(widget.index),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: 14 * s,
                        top: 6 * s,
                        bottom: 10 * s,
                      ),
                      child: Text(
                        widget.lineTotal,
                        maxLines: 1,
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13 * s,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The napomene control. It carries the line's napomene count and fills in when
/// there is at least one: with the editor behind a sheet, this badge is the
/// only way to see at a glance which lines carry an instruction for the kitchen.
class _NoteButton extends StatelessWidget {
  const _NoteButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = _screenScale(context);
    final has = count > 0;

    return Material(
      color: has ? scheme.secondaryContainer : scheme.surface,
      borderRadius: BorderRadius.circular(8 * s),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8 * s),
        child: Container(
          height: 28 * s,
          padding: EdgeInsets.symmetric(horizontal: 8 * s),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8 * s),
            border: Border.all(
              color: has ? Colors.transparent : scheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                has ? Icons.sticky_note_2 : Icons.sticky_note_2_outlined,
                size: 16 * s,
                color: has
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
              ),
              if (has) ...[
                SizedBox(width: 4 * s),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12 * s,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The stacked action buttons to the right of the cart (Clear / Details / Send).
class _ActionColumn extends StatelessWidget {
  const _ActionColumn({
    required this.sending,
    required this.confirmed,
    required this.onClear,
    required this.onDetails,
    required this.onSend,
  });

  final bool sending;

  /// The kasa accepted the order — the send button shows ✓.
  final bool confirmed;
  final VoidCallback? onClear;
  final VoidCallback? onDetails;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final s = _screenScale(context);
    final width = 64.0 * s;
    final gap = 8.0 * s;
    final naturalBtn = 60.0 * s;
    return SizedBox(
      width: width,
      child: LayoutBuilder(
        builder: (context, c) {
          final btn = c.maxHeight.isFinite
              ? math.min(naturalBtn, (c.maxHeight - gap * 2) / 3)
              : naturalBtn;
          final roomy =
              c.maxHeight.isFinite &&
              c.maxHeight > naturalBtn * 3 + gap * 2 + 1;
          return Column(
            children: [
              _ActionButton(
                icon: Icons.delete_outline,
                tone: _Tone.danger,
                onTap: onClear,
                width: width,
                height: btn,
              ),
              SizedBox(height: gap),
              _ActionButton(
                icon: Icons.list_alt,
                tone: _Tone.neutral,
                onTap: onDetails,
                width: width,
                height: btn,
              ),
              roomy ? const Spacer() : SizedBox(height: gap),
              _ActionButton(
                icon: Icons.send,
                tone: _Tone.primary,
                busy: sending,
                confirmed: confirmed,
                onTap: onSend,
                width: width,
                height: btn,
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _Tone { primary, neutral, danger }

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tone,
    required this.onTap,
    required this.width,
    required this.height,
    this.busy = false,
    this.confirmed = false,
  });

  final IconData icon;
  final _Tone tone;
  final VoidCallback? onTap;
  final double width;
  final double height;
  final bool busy;
  final bool confirmed;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s = _screenScale(context);
    final iconSize = math.min(26.0 * s, height * 0.46);
    final (bg, fg) = switch (tone) {
      _Tone.primary =>
        dark
            ? (const Color(0xFF1FA9B6), const Color(0xFF052A2E))
            : (const Color(0xFF0E9AA7), Colors.white),
      _Tone.neutral =>
        dark
            ? (const Color(0xFF8677E8), const Color(0xFF140A3A))
            : (const Color(0xFF6A57D8), Colors.white),
      _Tone.danger =>
        dark
            ? (const Color(0xFF5A2A2A), const Color(0xFFF0B5B5))
            : (const Color(0xFFF4D7D7), const Color(0xFF8A2E2E)),
    };
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(14 * s),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: width,
            height: height,
            // spinner → ✓ is a small scale-in, so the confirmation reads as the
            // button finishing its job rather than an icon being swapped.
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: busy
                  ? Center(
                      key: const ValueKey('busy'),
                      child: SizedBox(
                        width: iconSize * 0.85,
                        height: iconSize * 0.85,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: fg,
                        ),
                      ),
                    )
                  : Icon(
                      confirmed ? Icons.check : icon,
                      key: ValueKey(confirmed ? 'done' : 'idle'),
                      color: fg,
                      size: iconSize,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TotalBar extends StatelessWidget {
  const _TotalBar({
    required this.total,
    required this.searching,
    required this.onToggleSearch,
  });

  final String total;
  final bool searching;
  final VoidCallback onToggleSearch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = _screenScale(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(14 * s, 0, 4 * s, 2 * s),
      child: Row(
        children: [
          Text(
            'Ukupno',
            style: TextStyle(
              fontSize: 15 * s,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          SizedBox(width: 10 * s),
          Text(
            total,
            style: TextStyle(
              fontSize: 21 * s,
              fontWeight: FontWeight.w800,
              color: scheme.primary,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(searching ? Icons.close : Icons.search, size: 24 * s),
            tooltip: searching ? 'Zatvori pretragu' : 'Pretraži artikle',
            onPressed: onToggleSearch,
          ),
        ],
      ),
    );
  }
}

/// Group picker above the article grid: a paged grid of group cards — at most
/// two rows, with as many columns as the density setting gives it (swipe for
/// more) — or the search field when search is active.
class _PickerBar extends StatelessWidget {
  const _PickerBar({
    required this.groups,
    required this.size,
    required this.selectedId,
    required this.searching,
    required this.searchController,
    required this.onSelectGroup,
    required this.onQuery,
  });

  final List<MqttArticleGroup> groups;
  final MenuViewSize size;
  final int? selectedId;
  final bool searching;
  final TextEditingController searchController;
  final ValueChanged<int> onSelectGroup;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) {
    if (searching) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
        child: TextField(
          controller: searchController,
          autofocus: true,
          onChanged: onQuery,
          decoration: const InputDecoration(
            isDense: true,
            hintText: 'Pretraži artikle…',
            border: OutlineInputBorder(),
          ),
        ),
      );
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final selectedFill = dark
        ? const Color(0xFFF4A83A)
        : const Color(0xFFE8890C);
    final selectedText = dark ? const Color(0xFF3A2600) : Colors.white;
    final unselectedFill = dark
        ? const Color(0xFF403322)
        : const Color(0xFFF3E4CC);
    final unselectedText = dark
        ? const Color(0xFFE4C89A)
        : const Color(0xFF6B4E1E);

    final s = _screenScale(context);
    final spacing = 6.0 * s;
    final hPad = 8.0 * s;
    final rowHeight = size.groupRowHeight * s;
    final vPad = 4.0 * s;
    final columns = size.groupColumns;
    final perPage = columns * 2; // always at most two rows of groups
    // Only reserve a second row when the first one is full — otherwise a
    // single row of groups leaves an empty row (the gap above the articles).
    final rows = groups.length > columns ? 2 : 1;
    final pageCount = (groups.length + perPage - 1) ~/ perPage;

    return Padding(
      padding: EdgeInsets.only(bottom: 2 * s),
      child: SizedBox(
        height: rowHeight * rows + spacing * (rows - 1) + vPad * 2,
        child: LayoutBuilder(
          builder: (context, c) {
            final groupFontSize = _tileFontSize(
              _tileWidth(c.maxWidth, columns, hPad, spacing),
            );
            return PageView.builder(
              itemCount: pageCount,
              itemBuilder: (context, page) {
                final start = page * perPage;
                final end = (start + perPage).clamp(0, groups.length);
                final pageItems = groups.sublist(start, end);
                return GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: hPad,
                    vertical: vPad,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: rowHeight,
                    crossAxisSpacing: spacing,
                    mainAxisSpacing: spacing,
                  ),
                  itemCount: pageItems.length,
                  itemBuilder: (context, i) {
                    final g = pageItems[i];
                    final selected = g.id == selectedId;
                    return Material(
                      color: selected ? selectedFill : unselectedFill,
                      borderRadius: BorderRadius.circular(8 * s),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => onSelectGroup(g.id),
                        child: Container(
                          alignment: Alignment.center,
                          padding: EdgeInsets.symmetric(
                            horizontal: 4 * s,
                            vertical: 2 * s,
                          ),
                          child: Text(
                            g.name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: groupFontSize,
                              fontWeight: FontWeight.w600,
                              color: selected ? selectedText : unselectedText,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// The article grid — tap a tile to add its own line to the order.
class _ArticleGrid extends StatelessWidget {
  const _ArticleGrid({
    required this.articles,
    required this.onAdd,
    required this.size,
  });

  final List<MqttArticle> articles;
  final ValueChanged<int> onAdd;
  final MenuViewSize size;

  @override
  Widget build(BuildContext context) {
    if (articles.isEmpty) {
      return const Center(child: Text('Nema artikala.'));
    }

    final s = _screenScale(context);
    final spacing = 6.0 * s;
    final hPad = 8.0 * s;
    final vPad = 4.0 * s;
    final tileHeight = size.articleTileHeight * s;
    final columns = size.articleColumns;
    final perPage = size.articlesPerPage;
    final pageCount = (articles.length + perPage - 1) ~/ perPage;

    return LayoutBuilder(
      builder: (context, c) {
        final fontSize = _tileFontSize(
          _tileWidth(c.maxWidth, columns, hPad, spacing),
        );
        return PageView.builder(
          itemCount: pageCount,
          itemBuilder: (context, page) {
            final start = page * perPage;
            final end = (start + perPage).clamp(0, articles.length);
            final pageItems = articles.sublist(start, end);
            return GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisExtent: tileHeight,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
              ),
              itemCount: pageItems.length,
              itemBuilder: (context, i) {
                final a = pageItems[i];
                return _ArticleTile(
                  name: a.name,
                  fontSize: fontSize,
                  onTap: () => onAdd(a.code),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ArticleTile extends StatelessWidget {
  const _ArticleTile({
    required this.name,
    required this.fontSize,
    required this.onTap,
  });

  final String name;

  /// Proportional to the tile width — the label grows with the tile instead of
  /// leaving a big square with small text.
  final double fontSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Items already in the order are NOT coloured — every tile is neutral. The
    // only colour is a brief blue tint while the tile is pressed (feedback).
    final fill = dark ? const Color(0xFF25303C) : const Color(0xFFE4EBF3);
    final textColor = dark ? const Color(0xFFC5D2DF) : const Color(0xFF2C3E52);
    final press = dark ? const Color(0xFF3E6CA6) : const Color(0xFF4A78B4);
    final s = _screenScale(context);
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(10 * s),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // A thump per added item: the tile's colour flash is easy to miss when
        // the eyes are on the guest rather than the phone. Medium, not heavy —
        // heavy stays reserved for the wrong-PIN rejection, so the two never
        // feel like the same event.
        onTap: () {
          HapticFeedback.mediumImpact();
          onTap();
        },
        splashColor: press.withValues(alpha: 0.35),
        highlightColor: press.withValues(alpha: 0.22),
        child: Padding(
          padding: EdgeInsets.all(3 * s),
          child: Center(
            // One size for every tile: a grid where each label picks its own
            // size reads as untidy, so long names wrap and ellipsize exactly as
            // before — only the size itself now follows the tile.
            child: Text(
              name,
              textAlign: TextAlign.center,
              softWrap: true,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyMenu extends StatelessWidget {
  const _EmptyMenu();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.fastfood_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            const Text(
              'Nema artikala. Spojite se na MQTT u "Postavke uređaja".',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// The part of a successful send that is applied only once the order screen is
/// leaving: drop the table's draft and start watching the transfer.
class _SendCommit {
  const _SendCommit(this.broj, this.sent);

  final int broj;
  final MqttInTransitOrder sent;
}
