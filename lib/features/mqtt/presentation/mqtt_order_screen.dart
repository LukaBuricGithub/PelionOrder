import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../auth/state/session_provider.dart';
import '../../settings/models/menu_view_size.dart';
import '../../settings/state/settings_provider.dart';
import '../../shared/presentation/system_bars.dart';
import '../data/mqtt_service.dart';
import '../models/mqtt_menu.dart';
import '../models/mqtt_table_lock.dart';
import '../models/mqtt_tables.dart';
import '../state/mqtt_cart.dart';
import '../state/mqtt_menu_provider.dart';
import '../state/mqtt_orders_provider.dart';
import '../state/mqtt_outbox_provider.dart';
import '../state/mqtt_pending_transfers_provider.dart';
import '../state/mqtt_send_gate_provider.dart';
import '../state/mqtt_table_contents.dart';
import '../state/mqtt_table_lock_keeper.dart';
import '../state/mqtt_tables_provider.dart';
import 'mqtt_existing_items.dart';
import 'mqtt_napomene.dart';
import 'mqtt_order_details_screen.dart';
import 'mqtt_qty_pad.dart';
import 'mqtt_send_gate_bar.dart';

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

  /// True while an order is being published — until it has left the phone.
  bool _sending = false;

  /// What is already on this table, from the kasa. Null for a table with no
  /// existing order — then there is nothing to load and nothing to show.
  MqttTableContents? _contents;

  /// The order has left the phone and the ✓ is showing. From here the screen
  /// is on its way out: input is ignored and it no longer changes.
  bool _confirmed = false;

  /// The first frame built after [_confirmed], returned as-is by every later
  /// build — so nothing that happens next (dropping the draft, lines moving to
  /// "šalje se") can be seen before the screen has left.
  Widget? _frozen;

  /// Leaving after a send has started — guards against leaving twice.
  bool _leaving = false;

  /// The order this screen froze and is sending. Its lines are still the cart
  /// on screen, so its outbox copy is left out of the existing list.
  String? _submittedMsgId;

  /// The order couldn't be published: it is in "Neposlane narudžbe" and this
  /// screen is on its way out — frozen, exactly like after ✓.
  bool _queued = false;

  /// The details screen is open on top: it shows its own ✓ and closes both.
  bool _detailsOpen = false;

  /// The table holds another waiter's unsent items this waiter can't see:
  /// the first edit here replaces them with this waiter's own.
  bool _takeOverDraft = false;

  /// This screen is freezing its own order into the outbox right now — that
  /// order is not a reason to start loading the table.
  bool _freezing = false;

  /// Holds this table's lock while the screen is open (§"Brave stolova"):
  /// announces `ulaz` every two minutes and releases it with `izlaz`.
  MqttTableLockKeeper? _lock;

  /// False from the moment the screen leaves the tree. `mounted` is still
  /// true then, but reading a provider through `ref` throws ("deactivated
  /// widget's ancestor") — and that exception broke the teardown, so
  /// `dispose()`, and with it the table's `izlaz`, never ran.
  bool _inTree = true;

  /// The kasa took the table away (a cashier entered it) — the screen closes
  /// with its message; guarded so it happens once.
  bool _lockLost = false;

  // Captured in initState: used while the screen is leaving, when `ref` may
  // no longer be used.
  late final MqttOrdersNotifier _ordersNotifier;
  late final MqttOutboxNotifier _outboxNotifier;

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
    _outboxNotifier = ref.read(mqttOutboxProvider.notifier);
    // Restore any in-progress order for this table (kept for the session), then
    // start listening so subsequent edits are saved back. Only items this
    // waiter may see are restored; another waiter's starts from an empty cart.
    final broj = widget.tableBroj;
    if (broj != null) {
      final orders = ref.read(mqttOrdersProvider.notifier);
      if (ref.read(mqttVisibleDraftsProvider).containsKey(broj)) {
        final stored = orders.linesFor(broj);
        if (stored.isNotEmpty) _cart.loadFrom(stored);
        // Restore the pending msg_id AFTER loadFrom (which clears it), so a
        // retry of an already-sent order reuses the same id instead of
        // duplicating it.
        _cart.pendingMsgId = orders.msgIdFor(broj);
      } else {
        _takeOverDraft = ref.read(mqttOrdersProvider).containsKey(broj);
      }
    }
    // A table that already has an order — or one an order is on its way to —
    // shows its existing lines above the new ones, read-only.
    //
    // Not decided only once: a table opened while its first order is still
    // waiting for the kasa isn't occupied yet, and once that order lands its
    // lines must come from the kasa. So the table is watched while the screen
    // is open, and loading starts the moment there is something to load.
    if (broj != null) {
      _ensureContents(initial: true);
      ref.listenManual(mqttOccupiedProvider, (_, _) {
        if (_inTree) _ensureContents();
      });
      ref.listenManual(mqttPendingTransfersProvider, (_, _) {
        if (_inTree) _ensureContents();
      });
      ref.listenManual(mqttOutboxProvider, (_, _) {
        if (_inTree) _ensureContents();
      });
      // Items can be added while the kasa is offline; what is already on the
      // table is loaded once it can be asked.
      ref.listenManual<MqttSendGate>(mqttSendGateProvider, (prev, next) {
        if (!_inTree) return;
        if (next.canReachKasa != (prev?.canReachKasa ?? false)) {
          _loadContents();
          // The kasa is reachable again: claim the table now rather than
          // waiting for the next refresh.
          if (next.canReachKasa) _lock?.refreshNow();
        }
      });
      // The kasa republishes `stolovi_stanje` the moment a lock changes, so
      // a cashier entering this table is seen at once — no waiting for the
      // next `ulaz`.
      ref.listenManual<Map<int, String>>(mqttLockedProvider, (_, next) {
        if (!_inTree) return;
        final tag = next[broj];
        if (tag == null || tag.isEmpty) return;
        final ours = MqttService.instance.clientId;
        if (ours != null && tag == lockTagFor(ours)) return;
        _onLockLost(mqttLockHolderText(tag));
      });
      // Hold the table while this screen is open. The floor plan already
      // announced `ulaz` before opening it; opening from elsewhere ("Otvori
      // stol") announces it here.
      _lock = MqttTableLockKeeper(
        stol: broj,
        alreadyGranted: MqttTableLockKeeper.grantedRecently(broj),
        onLost: _onLockLost,
      );
    }
    _cart.addListener(_onCart);
    // Hide the Android nav bar (keep the status bar) and lock to portrait
    // while ordering.
    SystemBars.hideNavigation();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  @override
  void deactivate() {
    _inTree = false;
    super.deactivate();
  }

  @override
  void dispose() {
    _inTree = false;
    // Leaving the table: `izlaz` frees it for the kasa and the other phones.
    _lock?.release();
    _contents?.removeListener(_onContents);
    _contents?.dispose();
    _cart.removeListener(_onCart);
    _cart.dispose();
    SystemBars.releaseNavigation();
    // Back to the app's own rule (portrait only, set in main.dart) — NOT
    // every orientation, or the whole app would rotate once a table had been
    // opened.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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
          .save(
            broj,
            _cart.lines,
            _cart.pendingMsgId,
            cuser: ref.read(currentUserProvider)?.code,
            takeOver: _takeOverDraft,
          );
      _takeOverDraft = false;
    }
    if (mounted) setState(() {});
  }

  /// The kasa gave the table to someone else while this screen was open. The
  /// waiter's items stay saved on the table (blue), but the screen closes —
  /// working on a table held by the cashier is exactly what the lock prevents.
  Future<void> _onLockLost(String message) async {
    if (!_inTree || !mounted || _lockLost || _leaving) return;
    _lockLost = true;
    await _showSendProblem(
      'Stol je zauzet',
      message.isEmpty ? 'Stol je otvoren na drugom uređaju.' : message,
    );
    if (mounted) _leave();
  }

  /// Whether the table has anything to load from the kasa: it is occupied,
  /// an accepted order is travelling to it, or an order for it is on its way
  /// (other than the one this screen is sending).
  bool _tableHasOrder(int broj) =>
      ref.read(mqttOccupiedProvider).containsKey(broj) ||
      ref.read(mqttPendingTransfersProvider).containsKey(broj) ||
      ref
          .read(mqttOutboxProvider)
          .any((o) => o.stol == broj && o.msgId != _submittedMsgId);

  /// Starts loading the table's existing order as soon as it has one — once.
  void _ensureContents({bool initial = false}) {
    final broj = widget.tableBroj;
    if (broj == null || _contents != null) return;
    if (_freezing) return;
    if (!initial &&
        (!_inTree || !mounted || _leaving || _confirmed || _queued)) {
      return;
    }
    if (!_tableHasOrder(broj)) return;
    _contents = MqttTableContents(broj)..addListener(_onContents);
    Future.microtask(_loadContents);
    if (!initial) setState(() {});
  }

  /// Asks the kasa what is on the table — or, while it can't be reached, says
  /// so instead of waiting for a query that can't be answered.
  void _loadContents() {
    final contents = _contents;
    if (!_inTree || !mounted || contents == null) return;
    final gate = ref.read(mqttSendGateProvider);
    if (gate.canReachKasa) {
      contents.refresh(refill: true);
    } else {
      contents.markUnreachable(
        'Stavke sa stola učitat će se kad glavni program bude dostupan',
      );
    }
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

  /// Sends the cart as an order. Returns true once it has left the phone —
  /// the kasa's confirmation is NOT waited for here: the outbox waits for it in
  /// the background, and its outcome shows on the floor plan and in "Neposlane
  /// narudžbe". Shared by the Send button and the details screen.
  ///
  /// The order is FROZEN into "Neposlane narudžbe" before anything is
  /// published, and the table's draft is dropped: from here these items ARE
  /// that order, never an editable draft again. If it isn't printed, it waits
  /// in "Neposlane narudžbe" and is sent again from there, with the same
  /// number (§11.6) — entering the same items again would give them a new
  /// number and could print them twice (§11.7).
  Future<bool> _sendOrder() async {
    if (_sending || _confirmed || _queued) return false;
    final broj = widget.tableBroj;
    final user = ref.read(currentUserProvider);
    if (broj == null || user == null) {
      await _showSendProblem(
        'Narudžba nije poslana',
        'Nije poznat stol ili konobar.',
      );
      return false;
    }
    // §11.5: check the send state again right before sending — it may have
    // changed since the button was drawn (the kasa left the sales screen, the
    // connection dropped). Nothing is frozen or sent then; the cart stays.
    final sendGate = ref.read(mqttSendGateProvider);
    if (!sendGate.isOpen) {
      await _showSendProblem(
        'Slanje je zaključano',
        '${sendGate.message}. Narudžba nije poslana, stavke su ostale u '
            'narudžbi.',
      );
      return false;
    }

    _freezing = true;
    final frozen = _outboxNotifier.freeze(
      stol: broj,
      cuser: user.code,
      lines: _cart.lines,
      groupArticles: ref.read(settingsProvider).shouldGroupArticles,
    );
    final order = frozen.order;
    _freezing = false;
    if (order == null) {
      // Failed our own checks — nothing was saved or sent.
      await _showSendProblem(
        'Narudžba nije poslana',
        frozen.problem?.message ?? 'Narudžbu nije moguće poslati.',
      );
      return false;
    }
    _submittedMsgId = order.msgId;
    _ordersNotifier.clear(broj);
    setState(() => _sending = true);

    final delivered = await _outboxNotifier.sendNow(order);
    // Closed meanwhile: the outbox carries on with the order regardless.
    if (!mounted) return delivered;

    if (delivered) {
      setState(() {
        _sending = false;
        // The ✓ replaces the spinner in the same frame; this also freezes the
        // screen (see build) until it has left.
        _confirmed = true;
      });
      // No snackbar on success: the ✓ on the button is the confirmation. A
      // light tap goes with it — clearly below the article-tile thump.
      HapticFeedback.lightImpact();
      // The details screen, when open, shows its own ✓ and then closes both
      // screens. Otherwise leave from here once the ✓ has registered — also
      // when details was closed during the spinner.
      if (!_detailsOpen) {
        Future<void>.delayed(kMqttSendConfirmHold, () {
          if (mounted) _leave();
        });
      }
      return true;
    }

    // It didn't reach the broker. The order stays frozen in "Neposlane
    // narudžbe" and only goes out from there, under the same number; this
    // screen freezes too, so the same items can't be sent again as a new
    // order.
    final auto = ref.read(settingsProvider).shouldAutoResend;
    setState(() {
      _sending = false;
      _queued = true;
    });
    await _showSendProblem(
      'Nije poslana',
      auto
          ? 'Narudžba nije stigla do poslužitelja (veza je loša ili '
                'prekinuta). Spremljena je u „Neposlane narudžbe" i poslat '
                'će se sama kad veza i glavni program budu dostupni.'
          : 'Narudžba nije stigla do poslužitelja (veza je loša ili '
                'prekinuta). Pošaljite je ponovno iz „Neposlane narudžbe" '
                'kad se veza vrati. Ne unosite iste stavke ponovno.',
    );
    if (mounted) _leave();
    return false;
  }

  Future<void> _send() => _sendOrder();

  /// A send problem the waiter must see: a dialog, not a snackbar — it has to
  /// be acknowledged, and snackbars don't show on every device.
  Future<void> _showSendProblem(String title, String message) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('U redu'),
          ),
        ],
      ),
    );
  }

  /// Returns to the floor plan in ONE step — closing the details screen too if
  /// it is open, instead of two pops in a row.
  void _leave() {
    if (_leaving) return;
    _leaving = true;
    // Pop back to this screen (closing details if it is open), then this
    // screen itself — the floor plan below is not the first route any more,
    // the menu is.
    final navigator = Navigator.of(context);
    final self = ModalRoute.of(context);
    navigator.popUntil((route) => route == self);
    navigator.pop();
  }

  /// Opens the details screen on the same cart (edit quantities/remarks/delete).
  void _openDetails() {
    // Details is a normal screen: the nav bar shows while it is open.
    SystemBars.showNavigation();
    _detailsOpen = true;
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
              // Read on every build: the table may only start loading
              // while details is open.
              contents: () => _contents,
              sendingMsgId: () => _submittedMsgId,
            ),
          ),
        )
        .then((result) {
          _detailsOpen = false;
          SystemBars.releaseShowNavigation();
          if (!mounted || _leaving) return;
          // Sent from details but closed before the ✓ finished (e.g. back): the
          // send stands, so finish leaving from here rather than sit on a
          // frozen screen.
          if (_confirmed) {
            _leave();
            return;
          }
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
    // The kasa's summary of this table from stolovi_stanje — already on the
    // device, so the total and the number of placeholder rows are right before
    // the kasa answers.
    final seed = tableBroj == null
        ? null
        : ref.watch(mqttOccupiedProvider)[tableBroj];
    // Orders for this table frozen in "Neposlane narudžbe" — except the one
    // this screen is sending right now, whose lines are still the cart.
    final unsent = tableBroj == null
        ? const <MqttOutboxOrder>[]
        : [
            for (final o in ref.watch(mqttOutboxProvider))
              if (o.stol == tableBroj && o.msgId != _submittedMsgId) o,
          ];
    final existing = MqttExistingItems.compute(
      contents: _contents,
      inTransit: inTransit,
      byCode: _byCode,
      remarkName: _menu.remarkName,
      od: MqttService.instance.clientId,
      seedTotal: seed?.iznos,
      seedLineCount: seed?.stavki,
      unsent: unsent,
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
    // §11.4: whether the kasa takes orders right now, and why not.
    final sendGate = ref.watch(mqttSendGateProvider);
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
        // Also while sending: the cart on screen IS the frozen order until the
        // kasa answers, so it must not change underneath it.
        ignoring: _confirmed || _sending || _queued,
        child: Scaffold(
          appBar: AppBar(
            title: Text(title),
            // Why sending is locked, right under the title — only while it is.
            bottom: sendGate.isOpen ? null : MqttSendGateBar(gate: sendGate),
          ),
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
                                onSend: hasItems && !_sending && sendGate.isOpen
                                    ? _send
                                    : null,
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
    if (_confirmed || _queued) _frozen = screen;
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

class _CartCardState extends State<_CartCard>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  int _lastCount = 0;

  /// Keep the end of the order in view — where the newest lines are. On from
  /// the start, so opening a table lands on the end of its order; switched
  /// off the moment the waiter touches the list, and on again when they add a
  /// line.
  bool _followEnd = true;

  /// The table's order has been shown once. Its first arrival is not listed:
  /// the list is placed straight at its end (see [_land]). Later changes — a
  /// colleague's line landing, ours turning "Poslano" — still fade in.
  bool _landed = false;

  /// The list is hidden while it is being placed at its end — the frame or
  /// two it takes the list to learn its true length — and fades in there.
  bool _landing = false;

  /// Lines already in the cart when the table was opened — this phone's
  /// unsent items, restored. They belong to the load: hidden behind the
  /// loader with the kasa's order, and shown together with it at the end.
  late final int _restoredLines;

  /// The waiter added a line while the table was still loading. From then on
  /// the list is shown (with a loading row on top), so what they tap never
  /// disappears behind the loader.
  bool _addedWhileLoading = false;

  /// When the loader first showed.
  DateTime? _loaderSince;

  /// The order is in, but the loader is still finishing its [_minLoader].
  bool _holdingLoader = false;
  Timer? _loaderTimer;

  /// Drives every automatic scroll of this list.
  ///
  /// Not `animateTo` a fixed offset: that end keeps moving — the list only
  /// ESTIMATES the height of rows it hasn't built yet, and the existing order
  /// grows while its rows cascade in — so a fixed target is reached too early
  /// and has to be chased again, which is exactly the stop-and-go this avoids.
  /// Instead every frame moves toward wherever the end is NOW, in one motion.
  ///
  /// Built in [initState], NOT as a `late final`: on a table where nothing
  /// ever scrolled, the first access would be `dispose()` itself — and
  /// creating an AnimationController while the widget is leaving the tree
  /// throws ("deactivated widget's ancestor"). That exception broke the whole
  /// teardown, so the order screen's `dispose()` never ran and the table's
  /// `izlaz` was never sent: the kasa kept the table locked.
  late final AnimationController _glide;
  double _glideFrom = 0;
  Curve _glideCurve = Curves.easeOutCubic;

  @override
  void initState() {
    super.initState();
    _restoredLines = widget.cart.lines.length;
    // Restored lines are not "new": they don't count as added while loading.
    _lastCount = _restoredLines;
    _glide = AnimationController(vsync: this)
      ..addListener(_onGlideTick)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _catchUp());
        }
      });
  }

  @override
  void dispose() {
    _loaderTimer?.cancel();
    _glide.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onGlideTick() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final end = position.maxScrollExtent;
    final t = _glideCurve.transform(_glide.value);
    final target = (_glideFrom + (end - _glideFrom) * t).clamp(
      position.minScrollExtent,
      end,
    );
    if ((target - position.pixels).abs() > 0.1) _scroll.jumpTo(target);
  }

  /// Glides to the end of the list: holds still for [delay], then moves over
  /// [duration] — re-reading where the end is on every frame.
  void _glideToEnd({
    required Duration duration,
    Duration delay = Duration.zero,
    Curve curve = Curves.easeOutCubic,
  }) {
    if (!mounted || !_followEnd || !_scroll.hasClients) return;
    final total = delay + duration;
    _glideFrom = _scroll.position.pixels;
    _glideCurve = Interval(
      delay.inMicroseconds / total.inMicroseconds,
      1,
      curve: curve,
    );
    _glide.duration = total;
    _glide.forward(from: 0);
  }

  /// A short glide to the end when it has moved away — unless a glide is
  /// already on its way there (it will reach the new end by itself), or the
  /// placeholders are still standing in for the rows (there is no real end).
  void _catchUp() {
    if (!mounted || !_followEnd || _landing || _glide.isAnimating) return;
    if (widget.existing.placeholders > 0 || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.maxScrollExtent - position.pixels < 0.5) return;
    _glideToEnd(duration: const Duration(milliseconds: 260));
  }

  /// Places the hidden list at its end, then shows it. A jump, not a glide —
  /// the waiter never sees the order being listed. The list only knows its
  /// true length once the rows near the end have been built, so it jumps
  /// again on the next frame(s) until it is there (a few frames at most).
  void _land([int attempt = 0]) {
    if (!mounted) return;
    if (_followEnd && _scroll.hasClients && attempt < 4) {
      final position = _scroll.position;
      if (position.maxScrollExtent - position.pixels > 0.5) {
        _scroll.jumpTo(position.maxScrollExtent);
        WidgetsBinding.instance.addPostFrameCallback((_) => _land(attempt + 1));
        return;
      }
    }
    setState(() => _landing = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lines = widget.cart.lines;
    final s = _screenScale(context);

    // The cart list is mutated in place (same reference), so compare against the
    // last-built count to detect a newly added line and scroll to it.
    if (lines.length > _lastCount) {
      _followEnd = true;
      if (!_landed) _addedWhileLoading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _catchUp());
    }
    _lastCount = lines.length;

    final dark = Theme.of(context).brightness == Brightness.dark;
    final existing = widget.existing;
    final loadingNotice = MqttExistingNoticeTile(
      scale: s,
      busy: true,
      text: 'Učitavanje stavki sa stola…',
    );
    // The existing order's entries, each with a stable id (see
    // [MqttExistingSection]).
    final existingItems = <(String, Widget)>[
      if (existing.loading && existing.placeholders == 0)
        ('loading', loadingNotice),
      if (existing.error != null)
        (
          'error',
          MqttExistingNoticeTile(
            scale: s,
            icon: Icons.cloud_off,
            text: existing.offline
                ? existing.error!
                : 'Stavke sa stola nisu dostupne. Dodirnite za ponovni '
                      'pokušaj.',
            onTap: existing.offline ? null : widget.onRetryExisting,
          ),
        ),
      for (final row in existing.rows)
        (row.id, MqttExistingItemTile(row: row, money: widget.money, scale: s)),
      if (existing.othersPending > 0)
        (
          'others',
          MqttExistingNoticeTile(
            scale: s,
            icon: Icons.arrow_upward,
            color: mqttExistingStatusStyle(MqttExistingStatus.naPutu, dark).$1,
            text: mqttOthersPendingText(existing.othersPending),
          ),
        ),
    ];

    // Waiting for the table's order: a short loader instead of placeholder
    // rows. It shows from the first frame the screen is waiting.
    final waiting =
        !_landed &&
        existing.rows.isEmpty &&
        existing.error == null &&
        (existing.awaiting || existing.loading || existing.placeholders > 0);
    if (waiting) _loaderSince ??= DateTime.now();
    // The order came in quickly: keep the loader up for the rest of its
    // minimum time before the order is shown.
    if (!_landed &&
        !waiting &&
        existing.rows.isNotEmpty &&
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

    // The table's order has arrived and the loader is done — or there was
    // nothing to load, but this phone's unsent lines were restored: don't list
    // it — hide the list, put it at its end once this frame is laid out, and
    // show it there.
    if (!_landed &&
        !showLoader &&
        existing.placeholders == 0 &&
        (existing.rows.isNotEmpty || _restoredLines > 0)) {
      _landed = true;
      _landing = true;
      _glide.stop();
      WidgetsBinding.instance.addPostFrameCallback((_) => _land());
    }

    // Existing order first (read-only, oldest at the top), then the lines being
    // added now — so a new line always lands at the bottom, where the
    // auto-scroll above takes the waiter.
    final children = <Widget>[
      // The existing order as one block: a single loading row while the kasa
      // is asked (only seen when new lines are already below it — otherwise
      // the card shows the centred loader), then the order itself, with an
      // animated height so the new lines below slide down instead of jumping.
      if (existing.hasContent || showLoader)
        MqttExistingSection(
          // A fresh section once the order has landed: its rows are then
          // simply there, at full height — no cascade, no growing block —
          // so the list's end is final at once. Later arrivals in it still
          // fade in on their own.
          key: ValueKey(_landed ? 'existing-landed' : 'existing'),
          showPlaceholders: showLoader,
          separator: const Divider(height: 1),
          placeholders: [
            MqttFadeIn(key: const ValueKey('loading'), child: loadingNotice),
          ],
          items: existingItems,
        ),
      if ((existing.hasContent || showLoader) && lines.isNotEmpty)
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
      // While the table's order is being loaded, the card shows a short
      // loader — restored unsent lines wait behind it and appear with the
      // order. Only a line added during the load shows the list early.
      // Otherwise, while the kasa's first answer is on its way the card stays
      // blank: saying "Nema stavki" for a moment is exactly the flash we don't
      // want. The empty text only appears once that is true.
      child: showLoader && !_addedWhileLoading
          ? MqttExistingLoader(scale: s)
          : children.isEmpty && existing.awaiting
          ? const SizedBox.shrink()
          : children.isEmpty
          ? Center(
              child: Text(
                'Nema stavki u narudžbi',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          // Hidden at once while it is being placed at its end, then faded in
          // there — the order appears already scrolled to its last line.
          : AnimatedOpacity(
              opacity: _landing ? 0 : 1,
              duration: _landing
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              child: NotificationListener<ScrollMetricsNotification>(
                // The list's extent changed (rows built, a row added or
                // grown): if we are following the end, catch up with it.
                // Deferred a frame — this arrives during layout.
                onNotification: (_) {
                  if (_followEnd) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _catchUp(),
                    );
                  }
                  return false;
                },
                child: Listener(
                  // The waiter took over — a scroll, or a tap that can grow a
                  // row (expanding its napomene): stop pulling the list to the
                  // end.
                  onPointerDown: (_) {
                    _followEnd = false;
                    _glide.stop();
                  },
                  child: ListView.separated(
                    controller: _scroll,
                    padding: EdgeInsets.only(bottom: 2 * s),
                    itemCount: children.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) => children[i],
                  ),
                ),
              ),
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
          // Article names are not dictionary words: the keyboard must not
          // "correct" them (iOS does on space), and its suggestion strip would
          // take room from the item grid.
          autocorrect: false,
          enableSuggestions: false,
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
            const Text('Cjenik nije učitan', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
