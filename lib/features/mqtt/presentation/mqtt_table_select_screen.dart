import 'dart:async';
import 'dart:math' as math;

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../auth/state/session_provider.dart';
import '../../settings/models/table_view_size.dart';
import '../../settings/presentation/settings_drawer.dart';
import '../../settings/state/settings_provider.dart';
import '../../shared/presentation/system_bars.dart';
import '../models/mqtt_tables.dart';
import '../state/mqtt_orders_provider.dart';
import '../state/mqtt_outbox_provider.dart';
import '../state/mqtt_pending_transfers_provider.dart';
import '../data/mqtt_service.dart';
import '../data/mqtt_table_lock_sender.dart';
import '../models/mqtt_table_lock.dart';
import '../state/mqtt_table_lock_keeper.dart';
import '../state/mqtt_tables_provider.dart';
import '../state/mqtt_users_provider.dart';
import 'mqtt_outbox_summary_bar.dart';

// ── SVG assets (see assets/table_select) ───────────────────────────────────
// Two theme-specific chair sprites, each with its own per-part colours
// (body / seat / back / outline). Edit those SVGs to recolour the chair parts.
const _kSprite = 'assets/table_select/table_sprite.svg'; // light theme
const _kSpriteDark = 'assets/table_select/table_sprite_dark.svg'; // dark theme
const _kWalls = 'assets/table_select/walls';
const _kDarkAssetTint =
    ColorFilter.mode(Color(0xFF434A53), BlendMode.modulate);

/// How long a table tile takes to change colour, icon or badge — long enough
/// to read as one smooth change, short enough never to lag behind the state.
const _kTileAnimation = Duration(milliseconds: 250);

const _kTableSelectSvgs = <String>[
  _kSprite,
  _kSpriteDark,
  '$_kWalls/corner_tl.svg',
  '$_kWalls/corner_tr.svg',
  '$_kWalls/corner_bl.svg',
  '$_kWalls/corner_br.svg',
  '$_kWalls/edge_top.svg',
  '$_kWalls/edge_bottom.svg',
  '$_kWalls/edge_left.svg',
  '$_kWalls/edge_right.svg',
];

/// Warms the flutter_svg cache for the floor-plan assets so the first open of
/// this screen doesn't hitch while compiling the SVGs. Safe to call repeatedly
/// (a no-op once cached). Call it from the screen shown just before this one.
Future<void> precacheTableSelectSvgs() async {
  for (final asset in _kTableSelectSvgs) {
    final loader = SvgAssetLoader(asset);
    await svg.cache.putIfAbsent(
      loader.cacheKey(null),
      () => loader.loadBytes(null),
    );
  }
}

/// How a table tile is presented / behaves.
enum _TileStatus {
  free, // openable → new order
  order, // your unsent local items (on any table) → openable, editable
  occupiedMine, // yours (or your order is arriving) → order screen, read-only lines
  occupiedOther, // occupied by a colleague → openable only with pravo 008
}

/// "Jesu li poslane sve narudžbe sa stola" — drawn as a corner badge, kept
/// separate from [_TileStatus] so the answer never competes with the tile's
/// colour for the same pixels.
enum _SendMark {
  /// No badge: nothing ordered here, or only an unsent draft (which the blue
  /// tile already shows on a free table) — neither on its way nor arrived.
  none,

  /// On its way: sent and waiting for the kasa's confirmation, or accepted by
  /// the kasa but not yet on the table — "šalje se". Amber ↑.
  pending,

  /// Everything sent from this device has reached the table. Green ✓.
  sent,

  /// An order in "Neposlane narudžbe" that didn't get through (not sent,
  /// refused, too old). Red !, and it wins over every other mark: it is the
  /// one a waiter must act on or at least know about.
  unsent,
}

/// MQTT floor plan: pick a zone (terasa), then a table to open its menu.
/// Tables/zones come from `podaci/stolovi` and occupancy from
/// `podaci/stolovi_stanje`. A colleague's table is red, and openable only for a
/// waiter holding pravo 008.
class MqttTableSelectScreen extends ConsumerStatefulWidget {
  const MqttTableSelectScreen({super.key});

  @override
  ConsumerState<MqttTableSelectScreen> createState() =>
      _MqttTableSelectScreenState();
}

class _MqttTableSelectScreenState extends ConsumerState<MqttTableSelectScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedZone = 0;

  /// Tables that dropped out of `stolovi_stanje` a moment ago, still drawn with
  /// their last entry until `until`.
  ///
  /// The floor plan combines two live sources that update independently —
  /// `stolovi_stanje` from the kasa and our own transfer watch — so a table
  /// can briefly be in NEITHER while one has changed and the other hasn't yet.
  /// Drawn as-is, that gap is a flash: teal → grey → teal, ✓ → nothing → ✓.
  /// A short hold bridges it; a table that really was closed turns free a few
  /// seconds late, which nobody can see.
  final _heldOccupied = <int, ({MqttTableState state, DateTime until})>{};

  /// Tables whose order has just landed but that `stolovi_stanje` doesn't list
  /// yet — drawn as ours with ✓ until it does (or until the time runs out).
  final _heldLanded = <int, DateTime>{};

  Timer? _holdTimer;

  /// The floating message at the bottom ("Stol je zauzet — …"), or null.
  /// Drawn by this screen itself — snackbars don't show on every phone.
  String? _notice;
  Timer? _noticeTimer;
  static const _noticeFor = Duration(milliseconds: 2200);

  /// Bumped per table to make its tile shake once.
  final _shakes = <int, int>{};

  /// The table whose lock we are asking the kasa for right now — its tile
  /// shows a spinner and nothing else can be opened meanwhile. Usually well
  /// under a second.
  int? _opening;

  static const _goneGrace = Duration(seconds: 3);
  static const _landedGrace = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    // Like Stol X: no navigation bar unless the user swipes it in.
    SystemBars.hideNavigation();
    precacheTableSelectSvgs();
    // Listened to (not only watched) so a hold starts in the same moment the
    // source changes — before the frame that would otherwise show the gap.
    ref.listenManual<Map<int, MqttTableState>>(
      mqttOccupiedProvider,
      _onOccupancy,
    );
    ref.listenManual<Map<int, List<MqttInTransitOrder>>>(
      mqttPendingTransfersProvider,
      _onTransfers,
    );
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _noticeTimer?.cancel();
    SystemBars.releaseNavigation();
    super.dispose();
  }

  void _onOccupancy(
    Map<int, MqttTableState>? prev,
    Map<int, MqttTableState> next,
  ) {
    final until = DateTime.now().add(_goneGrace);
    for (final entry in (prev ?? const <int, MqttTableState>{}).entries) {
      if (!next.containsKey(entry.key)) {
        _heldOccupied[entry.key] = (state: entry.value, until: until);
      }
    }
    // Back in stolovi_stanje: the live entry takes over.
    _heldOccupied.removeWhere((stol, _) => next.containsKey(stol));
    _heldLanded.removeWhere((stol, _) => next.containsKey(stol));
    _scheduleHoldExpiry();
  }

  void _onTransfers(
    Map<int, List<MqttInTransitOrder>>? prev,
    Map<int, List<MqttInTransitOrder>> next,
  ) {
    final transfers = ref.read(mqttPendingTransfersProvider.notifier);
    final occupied = ref.read(mqttOccupiedProvider);
    final until = DateTime.now().add(_landedGrace);
    for (final stol in (prev ?? const <int, List<MqttInTransitOrder>>{}).keys) {
      // Only a watch that ended by LANDING is held — one we gave up on has
      // nothing to show as arrived.
      if (!next.containsKey(stol) &&
          !occupied.containsKey(stol) &&
          transfers.justLanded(stol)) {
        _heldLanded[stol] = until;
      }
    }
    _heldLanded.removeWhere((stol, _) => next.containsKey(stol));
    _scheduleHoldExpiry();
  }

  /// Redraws when the earliest hold runs out, so an expired hold never waits
  /// for some unrelated change to disappear.
  void _scheduleHoldExpiry() {
    _holdTimer?.cancel();
    final times = [
      for (final h in _heldOccupied.values) h.until,
      ..._heldLanded.values,
    ];
    if (times.isEmpty) return;
    final first = times.reduce((a, b) => a.isBefore(b) ? a : b);
    _holdTimer = Timer(
      first.difference(DateTime.now()) + const Duration(milliseconds: 20),
      () {
        if (!mounted) return;
        final now = DateTime.now();
        setState(() {
          _heldOccupied.removeWhere((_, h) => !h.until.isAfter(now));
          _heldLanded.removeWhere((_, until) => !until.isAfter(now));
        });
        _scheduleHoldExpiry();
      },
    );
  }

  int _columns(TableViewSize s) => switch (s) {
        TableViewSize.small => 4,
        TableViewSize.medium => 3,
        TableViewSize.large => 2,
      };

  @override
  Widget build(BuildContext context) {
    final zones = ref.watch(mqttTablesProvider);
    // Occupancy as DRAWN: live stolovi_stanje, plus tables that dropped out of
    // it a moment ago (see [_heldOccupied]). Live entries win.
    final liveOccupied = ref.watch(mqttOccupiedProvider);
    final occupied = _heldOccupied.isEmpty
        ? liveOccupied
        : {
            for (final e in _heldOccupied.entries) e.key: e.value.state,
            ...liveOccupied,
          };
    // Orders that just landed on a table stolovi_stanje doesn't list yet.
    final landed = _heldLanded.keys.toSet();
    // Tables with unsent items this waiter may see — coloured blue.
    final drafts = ref.watch(mqttVisibleDraftsProvider);
    final withOrders = drafts.keys.toSet();
    // Tables the kasa has accepted an order for but not yet applied it to.
    final pendingTransfer =
        ref.watch(mqttPendingTransfersProvider).keys.toSet();
    final me = ref.watch(currentUserProvider);
    final myCuser = me?.code;
    // Our own short name as the kasa shows it (naziv), for a table whose order
    // is still arriving and so isn't in stolovi_stanje yet.
    final userNames = {
      for (final u in ref.watch(mqttUsersProvider)) u.code: u.name,
    };
    final myName = userNames[myCuser];
    // Pravo 008: may open a table held by another waiter.
    final canOpenAll = me?.allTablesOpenRight ?? false;
    // Tables with an order in "Neposlane narudžbe" this waiter may see — their
    // own, or all with pravo 008 — and who placed it: those that didn't get
    // through ("red"), and those with the broker, waiting for the kasa
    // ("amber").
    final visibleOutbox = [
      for (final o in ref.watch(mqttOutboxProvider))
        if (mqttOutboxVisibleTo(o, cuser: myCuser, allTables: canOpenAll)) o,
    ];
    final unsentBy = <int, String>{};
    final sendingBy = <int, String>{};
    for (final o in visibleOutbox) {
      (o.isProblem ? unsentBy : sendingBy).putIfAbsent(o.stol, () => o.cuser);
    }
    final summary = MqttOutboxSummary.of(visibleOutbox, drafts: drafts.length);
    // Tables the kasa has locked ("brave stolova") — a cashier inside a table,
    // or another orderman. Our own lock is left out: we hold it, so the table
    // must keep looking the way it otherwise would.
    final ourTag = MqttService.instance.clientId == null
        ? ''
        : lockTagFor(MqttService.instance.clientId!);
    final lockedBy = {
      for (final e in ref.watch(mqttLockedProvider).entries)
        if (e.value != ourTag) e.key: e.value,
    };
    final columns = _columns(ref.watch(settingsProvider).tableViewSize);

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: const SettingsDrawer(),
      appBar: AppBar(
        title: const Text('Odabir stola'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Postavke',
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Column(
                children: [
                  // Always there, always the same height — the floor plan
                  // below is laid out for the space that is left.
                  MqttOutboxStatusBar(
                    summary: summary,
                    onTap: () => context.push('/mqtt-outbox'),
                  ),
                  Expanded(
                    child: zones.isEmpty
                        ? const _EmptyTables()
                        : _buildBody(zones, occupied, withOrders,
                            pendingTransfer, landed, unsentBy, sendingBy,
                            userNames, myCuser, myName, canOpenAll, columns,
                            lockedBy),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 24,
              child: IgnorePointer(child: _FloatingNotice(text: _notice)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    List<MqttTerrace> zones,
    Map<int, MqttTableState> occupied,
    Set<int> withOrders,
    Set<int> pendingTransfer,
    Set<int> landed,
    Map<int, String> unsentBy,
    Map<int, String> sendingBy,
    Map<String, String> userNames,
    String? myCuser,
    String? myName,
    bool canOpenAll,
    int columns,
    Map<int, String> lockedBy,
  ) {
    final selected = _selectedZone.clamp(0, zones.length - 1);
    final tables = zones[selected].tables;

    return Column(
      children: [
        _ZoneChips(
          zones: zones,
          selected: selected,
          onSelect: (i) => setState(() => _selectedZone = i),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
            child: _WallFrame(
              floor: _floorColor(context),
              child: tables.isEmpty
                  ? const Center(child: Text('Nema stolova u ovoj zoni.'))
                  : _PagedTableGrid(
                      tables: tables,
                      occupied: occupied,
                      withOrders: withOrders,
                      pendingTransfer: pendingTransfer,
                      landed: landed,
                      unsentBy: unsentBy,
                      sendingBy: sendingBy,
                      userNames: userNames,
                      myCuser: myCuser,
                      myName: myName,
                      canOpenAll: canOpenAll,
                      columns: columns,
                      showName: columns < 4, // drop naziv at "small"
                      shakes: _shakes,
                      opening: _opening,
                      lockedBy: lockedBy,
                      onTapTable: _onTap,
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Color _floorColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF10151C)
          : const Color(0xFFF4F6F8);

  void _onTap(MqttTable table, _TileStatus status, String? occupant) {
    // Locked by the kasa or another orderman: `ulaz` would refuse it anyway,
    // and the waiter is better off seeing that before the wait.
    final lock = ref.read(mqttLockedProvider)[table.broj];
    final ourTag = MqttService.instance.clientId == null
        ? ''
        : lockTagFor(MqttService.instance.clientId!);
    if (lock != null && lock != ourTag) {
      _refuse(table, '', message: mqttLockHolderText(lock));
      return;
    }
    switch (status) {
      case _TileStatus.occupiedOther:
        // Pravo 008 turns a colleague's table from blocked into openable —
        // treated exactly like your own from here on.
        if (ref.read(currentUserProvider)?.allTablesOpenRight ?? false) {
          _openOrder(table);
          return;
        }
        _refuse(table, occupant?.trim() ?? '');
      case _TileStatus.occupiedMine:
      case _TileStatus.free:
      case _TileStatus.order:
        _openOrder(table);
    }
  }

  /// A colleague's table without pravo 008: the tile shakes, the phone
  /// thumps, and a message names who has the table — the moment the waiter
  /// actually asks, with room the tile doesn't have.
  void _refuse(MqttTable table, String konobar, {String? message}) {
    HapticFeedback.heavyImpact();
    _noticeTimer?.cancel();
    setState(() {
      _shakes[table.broj] = (_shakes[table.broj] ?? 0) + 1;
      _notice =
          message ??
          (konobar.isEmpty
              ? 'Stol je zauzet od drugog konobara.'
              : 'Stol je zauzet — $konobar.');
    });
    _noticeTimer = Timer(_noticeFor, () {
      if (mounted) setState(() => _notice = null);
    });
  }

  /// Every openable table goes straight into the order screen — but only
  /// after the kasa has given us its lock ("brave stolova"): the kasa and a
  /// phone must never work on the same table at once.
  ///
  /// Without an answer (kasa off, no connection) the table opens anyway: the
  /// waiter can still add items, and the order screen keeps announcing `ulaz`,
  /// so the table is claimed as soon as the kasa is back.
  Future<void> _openOrder(MqttTable table) async {
    if (_opening != null) return;
    setState(() => _opening = table.broj);
    final result = await MqttTableLockSender.instance.enter(table.broj);
    if (!mounted) return;
    setState(() => _opening = null);

    if (result.outcome == MqttLockOutcome.zauzeto) {
      _refuse(table, '', message: result.message);
      return;
    }
    if (result.isOk) MqttTableLockKeeper.noteGranted(table.broj);

    final q = table.naziv.isEmpty
        ? ''
        : '?naziv=${Uri.encodeComponent(table.naziv)}';
    if (mounted) context.push('/mqtt-menu/${table.broj}$q');
  }
}

/// A horizontally-paged grid of tables (same paging logic as Odabir stola).
class _PagedTableGrid extends StatelessWidget {
  const _PagedTableGrid({
    required this.tables,
    required this.occupied,
    required this.withOrders,
    required this.pendingTransfer,
    required this.landed,
    required this.unsentBy,
    required this.sendingBy,
    required this.userNames,
    required this.myCuser,
    required this.myName,
    required this.canOpenAll,
    required this.columns,
    required this.showName,
    required this.shakes,
    required this.opening,
    required this.lockedBy,
    required this.onTapTable,
  });

  final List<MqttTable> tables;
  final Map<int, MqttTableState> occupied;
  final Set<int> withOrders;

  /// Tables whose accepted order the kasa has not yet moved onto the table.
  final Set<int> pendingTransfer;

  /// Tables whose order has just landed but that stolovi_stanje doesn't list
  /// yet — drawn as ours with ✓, exactly as they will look once it does.
  final Set<int> landed;

  /// Tables with an order in "Neposlane narudžbe", with the waiter who placed
  /// it (only orders this waiter may see).
  final Map<int, String> unsentBy;

  /// Tables with an order sent from this phone that the broker holds, waiting
  /// for the kasa's confirmation (also "Nije potvrđena"), with the waiter who
  /// placed it.
  final Map<int, String> sendingBy;

  /// Waiter name by user code, for an unsent order's table.
  final Map<String, String> userNames;
  final String? myCuser;

  /// Our own naziv — shown on a table whose order is still arriving.
  final String? myName;

  /// Whether this waiter holds pravo 008 (may open colleagues' tables).
  final bool canOpenAll;
  final int columns;
  final bool showName;

  /// Per table, a counter that shakes its tile once whenever it grows.
  final Map<int, int> shakes;

  /// The table whose lock is being asked for right now, if any.
  final int? opening;

  /// Tables the kasa has locked for someone ELSE, and who holds them
  /// (`CORD3`, or a kasa's tag). Our own lock is not in here.
  final Map<int, String> lockedBy;
  final void Function(MqttTable table, _TileStatus status, String? occupant)
      onTapTable;

  _TileStatus _statusFor(MqttTable table) {
    // Locked by the kasa or another orderman: shown as taken and not
    // openable, even when it holds nothing — a cashier standing in an empty
    // table is exactly the case that isn't in `zauzeti` at all.
    if (lockedBy.containsKey(table.broj)) return _TileStatus.occupiedOther;
    // Items added on this phone and not sent yet: blue, whatever else the
    // table is — also an occupied one, ours or (with pravo 008) a colleague's.
    // Once they are sent or removed, the table shows its usual colour again.
    if (withOrders.contains(table.broj)) return _TileStatus.order;
    final occ = occupied[table.broj];
    if (occ != null) {
      return occ.cuser == myCuser
          ? _TileStatus.occupiedMine
          : _TileStatus.occupiedOther;
    }
    // Sent from this phone and accepted, but the kasa hasn't put it on the table
    // yet, so it isn't in stolovi_stanje. Show it as ours straight away — the
    // amber ↑ says it is still arriving — so that when it lands only the badge
    // changes, instead of a grey "free" table suddenly turning teal.
    if (pendingTransfer.contains(table.broj) || landed.contains(table.broj)) {
      return _TileStatus.occupiedMine;
    }
    // An unconfirmed order: the table belongs to whoever placed it, even though
    // the kasa doesn't list it (yet).
    final unsentCuser = unsentBy[table.broj] ?? sendingBy[table.broj];
    if (unsentCuser != null) {
      return unsentCuser == myCuser
          ? _TileStatus.occupiedMine
          : _TileStatus.occupiedOther;
    }
    return _TileStatus.free;
  }

  /// The corner badge — independent of [_statusFor], so it answers a different
  /// question from the tile's colour: where is the order on its journey?
  ///
  /// Amber ↑ only while the kasa has an order but hasn't put it on the table;
  /// green ✓ once everything has landed. An unsent draft gets NO badge: nothing
  /// is on its way, so ↑ would suggest something was sent — and it must also
  /// stop an occupied table falling through to ✓, which would claim an unsent
  /// addition had arrived.
  _SendMark _markFor(MqttTable table) {
    if (unsentBy.containsKey(table.broj)) return _SendMark.unsent;
    if (sendingBy.containsKey(table.broj) ||
        pendingTransfer.contains(table.broj)) {
      return _SendMark.pending;
    }
    if (withOrders.contains(table.broj)) return _SendMark.none;
    // Everything on the table has landed — but only mark a table that actually
    // has an order; an empty table has nothing to report.
    return occupied.containsKey(table.broj) || landed.contains(table.broj)
        ? _SendMark.sent
        : _SendMark.none;
  }

  static const double _pad = 6;
  static const double _spacing = 6;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // The room the tables get: whatever is left under the status bar and
        // the zones, for the chosen size (Male 4 / Srednje 3 / Velike 2
        // columns).
        final availW = c.maxWidth - _pad * 2;
        final availH = c.maxHeight - _pad * 2;
        // Tile size follows the width…
        var cell = (availW - _spacing * (columns - 1)) / columns;
        // …but never taller than the room: at least one whole row, never half
        // a tile (large tiles on a short screen shrink to fit).
        if (cell > availH) cell = math.max(availH, 0);
        final rows = ((availH + _spacing) / (cell + _spacing))
            .floor()
            .clamp(1, 999);
        // Height the rows don't use is spread evenly above, between and below
        // them, instead of collecting as a strip under the last row.
        final leftover = availH - rows * cell - (rows - 1) * _spacing;
        final extra = math.max(0.0, leftover - 1) / (rows + 1);
        // Shrunk tiles leave width over: centre the columns.
        final hPad =
            (c.maxWidth - columns * cell - _spacing * (columns - 1)) / 2;
        final perPage = columns * rows;
        final pageCount = (tables.length + perPage - 1) ~/ perPage;

        return PageView.builder(
          itemCount: pageCount,
          itemBuilder: (context, page) {
            final start = page * perPage;
            final end = (start + perPage).clamp(0, tables.length);
            final pageItems = tables.sublist(start, end);
            return GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: hPad,
                vertical: _pad + extra,
              ),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                childAspectRatio: 1,
                crossAxisSpacing: _spacing,
                mainAxisSpacing: _spacing + extra,
              ),
              itemCount: pageItems.length,
              itemBuilder: (context, i) {
                final table = pageItems[i];
                final status = _statusFor(table);
                // While our order is still arriving the table isn't in
                // stolovi_stanje yet, so show our own name — the one the kasa
                // will show once it lands, so nothing changes then.
                final lockedTag = lockedBy[table.broj];
                // A locked table says only "Zauzeto" — who holds it is in the
                // message shown when it is tapped, where there is room for it.
                final occupant = (lockedTag != null ? 'Zauzeto' : null) ??
                    occupied[table.broj]?.konobar ??
                    (pendingTransfer.contains(table.broj) ||
                            landed.contains(table.broj)
                        ? myName
                        : userNames[unsentBy[table.broj] ??
                              sendingBy[table.broj]]);
                return _Shake(
                  // Keyed by table, so switching zones builds fresh tiles
                  // instead of animating one table's colour into another's.
                  key: ValueKey(table.broj),
                  trigger: shakes[table.broj] ?? 0,
                  child: _TableCell(
                    table: table,
                    status: status,
                    showName: showName,
                    occupantName: occupant,
                    canOpenAll: canOpenAll,
                    mark: _markFor(table),
                    opening: opening == table.broj,
                    locked: lockedTag != null,
                    // One table at a time: while the kasa is being asked, the
                    // others don't react either.
                    onTap: opening != null
                        ? null
                        : () => onTapTable(table, status, occupant),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

/// A waiter's name shortened to fit a table tile: "Ana Horvat" → "Ana H.",
/// "Ana" → "Ana".
///
/// Shortening the STRING rather than shrinking the font is the point: the tile
/// has a fixed ~52-94px of width, and a full name only fits there by scaling the
/// type down past the point anyone can read it at arm's length. This form fits
/// at full size, and keeps the surname initial that tells two Anas apart.
String _shortName(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '';
  if (parts.length == 1) return parts.first;
  return '${parts.first} ${parts[1].characters.first.toUpperCase()}.';
}

/// One table cell: the chairs sprite with a status-coloured top (red = occupied,
/// neutral = free) drawn on the central 60%.
class _TableCell extends StatelessWidget {
  const _TableCell({
    required this.table,
    required this.status,
    required this.showName,
    required this.occupantName,
    required this.canOpenAll,
    required this.mark,
    required this.opening,
    required this.locked,
    required this.onTap,
  });

  final MqttTable table;
  final _TileStatus status;
  final bool showName;

  /// The waiter holding the table (`konobar` from `stolovi_stanje`), or null
  /// when it is free.
  final String? occupantName;

  /// Pravo 008 — decides whether a colleague's table shows as locked or as
  /// openable.
  final bool canOpenAll;

  /// Whether everything ordered for this table has reached the kasa.
  ///
  /// Drawn as a MARK rather than a colour so it is independent of the status
  /// hue: it has to be visible on a free table and on an occupied one alike,
  /// and red/teal already carry a different meaning.
  final _SendMark mark;

  /// The kasa is being asked for this table's lock right now.
  final bool opening;

  /// The kasa has this table locked for someone else.
  final bool locked;

  /// Null while another table is being opened — then nothing reacts.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Colour + corner icon per status. Each state gets its own hue so it reads
    // at a glance: someone else's table → red + lock (blocked), your own
    // occupied table → teal + eye (open, read-only), your unsent order → blue,
    // free → neutral. Red is reserved for "you cannot go in here".
    final (Color fill, Color fg, IconData? corner) = switch (status) {
      // Red always means "another waiter holds this" — but the icon says
      // whether that BLOCKS you: a lock without pravo 008, an eye with it.
      _TileStatus.occupiedOther => (
          const Color(0xFFD46A5A),
          Colors.white,
          // A locked table can't be entered by anyone on a phone, not even
          // with pravo 008 — the kasa refuses the `ulaz`.
          locked || !canOpenAll ? Icons.lock : Icons.visibility,
        ),
      _TileStatus.occupiedMine =>
        (const Color(0xFF3E8E7E), Colors.white, Icons.visibility),
      _TileStatus.order => (const Color(0xFF4A78B4), Colors.white, null),
      _TileStatus.free => dark
          ? (const Color(0xFF3A4756), const Color(0xFFC9D3DE), null)
          : (const Color(0xFFD8DEE4), const Color(0xFF37424E), null),
    };
    // The second line carries the WAITER when the table is occupied, and the
    // table's naziv otherwise: the naziv is static (a waiter learns it in a
    // day), the occupant is the fact that changes. Same line, no extra space.
    //
    // The waiter shows at EVERY size, including the small tiles where the naziv
    // is dropped — who holds a table is worth the small type, a table's name is
    // not.
    final konobar = _shortName(occupantName ?? '');
    final secondLine =
        konobar.isNotEmpty ? konobar : (showName ? table.naziv : '');
    final hasSecondLine = secondLine.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          return Stack(
            fit: StackFit.expand,
            children: [
              SvgPicture.asset(dark ? _kSpriteDark : _kSprite),
              Positioned(
                left: w * 0.2,
                top: w * 0.2,
                width: w * 0.6,
                height: w * 0.6,
                child: AnimatedContainer(
                  duration: _kTileAnimation,
                  curve: Curves.easeInOut,
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(w * 0.075),
                    border: Border.all(
                      color:
                          Colors.black.withValues(alpha: dark ? 0.28 : 0.05),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: w * 0.04),
                    // The text colour animates together with the fill, so a
                    // status change reads as one recolour of the whole tile.
                    child: AnimatedDefaultTextStyle(
                      duration: _kTileAnimation,
                      curve: Curves.easeInOut,
                      style: DefaultTextStyle.of(context)
                          .style
                          .copyWith(color: fg),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${table.broj}',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: w * 0.20,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                          // The name line comes and goes smoothly: it fades,
                          // and the number glides to its new centre.
                          AnimatedSize(
                            duration: _kTileAnimation,
                            curve: Curves.easeInOut,
                            child: AnimatedSwitcher(
                              duration: _kTileAnimation,
                              child: hasSecondLine
                                  ? Column(
                                      key: ValueKey(secondLine),
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(height: w * 0.02),
                                        AutoSizeText(
                                          secondLine,
                                          maxLines: 1,
                                          // Floor is proportional (80% of the
                                          // intended size), not a fixed 7pt: on
                                          // a large tile that let text shrink
                                          // to less than half its size before
                                          // ellipsizing, which is unreadable
                                          // rather than helpful. Past this
                                          // point, ellipsis is the honest
                                          // answer.
                                          //
                                          // MUST be a whole number:
                                          // AutoSizeText asserts minFontSize is
                                          // a multiple of stepGranularity
                                          // (default 1), and a fractional value
                                          // throws during layout for every
                                          // tile.
                                          minFontSize: (w * 0.068)
                                              .clamp(6.0, 24.0)
                                              .roundToDouble(),
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: w * 0.085,
                                            fontWeight: FontWeight.w500,
                                            height: 1,
                                          ),
                                        ),
                                      ],
                                    )
                                  : const SizedBox.shrink(
                                      key: ValueKey('no-second-line'),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // While the kasa is asked for this table's lock: the tile dims
              // and shows a spinner, so the wait (usually well under a
              // second) is visible and the tap clearly registered.
              Positioned(
                left: w * 0.2,
                top: w * 0.2,
                width: w * 0.6,
                height: w * 0.6,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: opening ? 1 : 0,
                    duration: _kTileAnimation,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(w * 0.075),
                      ),
                      child: Center(
                        child: SizedBox(
                          width: w * 0.22,
                          height: w * 0.22,
                          child: CircularProgressIndicator(
                            strokeWidth: w * 0.03,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Swapped with a fade, never popped in or out.
              Positioned(
                top: w * 0.22,
                right: w * 0.22,
                child: AnimatedSwitcher(
                  duration: _kTileAnimation,
                  child: corner == null
                      ? SizedBox(
                          key: const ValueKey('no-corner'),
                          width: w * 0.11,
                          height: w * 0.11,
                        )
                      : Icon(
                          corner,
                          key: ValueKey(corner),
                          size: w * 0.11,
                          color: fg,
                        ),
                ),
              ),
              // "Jesu li poslane sve narudžbe" — bottom-right, the corner the
              // status icon never uses, so the two never compete. Both badges
              // are ringed so they read against every status fill (red, teal,
              // blue, grey) — the green one especially, since it sits on a teal
              // tile whenever the table is yours.
              Positioned(
                right: w * 0.17,
                bottom: w * 0.17,
                // A badge appearing, going, or turning from ↑ into ✓ scales and
                // fades, so it visibly updates instead of blinking.
                child: AnimatedSwitcher(
                  duration: _kTileAnimation,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  ),
                  child: mark == _SendMark.none
                      ? SizedBox(
                          key: const ValueKey(_SendMark.none),
                          width: w * 0.17,
                          height: w * 0.17,
                        )
                      : _badge(w, dark),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The send-state badge: red ! not confirmed by the kasa, amber ↑ still
  /// arriving, green ✓ arrived.
  Widget _badge(double w, bool dark) {
    final (Color fill, IconData icon, double size, Color darkFg) =
        switch (mark) {
      _SendMark.unsent => (
          dark ? const Color(0xFFFF7B72) : const Color(0xFFD64541),
          Icons.priority_high,
          w * 0.11,
          const Color(0xFF3A0B08),
        ),
      _SendMark.pending => (
          dark ? const Color(0xFFF4A83A) : const Color(0xFFE8890C),
          Icons.arrow_upward,
          w * 0.10,
          const Color(0xFF3A2600),
        ),
      _ => (
          dark ? const Color(0xFF4FC98A) : const Color(0xFF2E9E5B),
          Icons.check,
          w * 0.11,
          const Color(0xFF063020),
        ),
    };
    return Container(
      key: ValueKey(mark),
      width: w * 0.17,
      height: w * 0.17,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(
          color: dark ? const Color(0xFF1B2430) : Colors.white,
          width: w * 0.018,
        ),
      ),
      // The shape carries the meaning as well as the colour (! / ↑ / ✓), so the
      // states stay distinguishable at a glance — and for anyone who reads the
      // colours as similar hues.
      child: Icon(icon, size: size, color: dark ? darkFg : Colors.white),
    );
  }
}

/// The walled room: nine-slice SVG frame around the [child], over the [floor].
class _WallFrame extends StatelessWidget {
  const _WallFrame({required this.child, required this.floor});

  final Widget child;
  final Color floor;

  static const double _wall = 18;
  static const double _corner = 52;

  Widget _svg(String name, ColorFilter? filter) => SvgPicture.asset(
        '$_kWalls/$name',
        fit: BoxFit.fill,
        colorFilter: filter,
      );

  @override
  Widget build(BuildContext context) {
    final filter = Theme.of(context).brightness == Brightness.dark
        ? _kDarkAssetTint
        : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: floor)),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(_wall),
              child: ClipRect(child: child),
            ),
          ),
          Positioned(
              top: 0, left: _corner, right: _corner, height: _wall,
              child: _svg('edge_top.svg', filter)),
          Positioned(
              bottom: 0, left: _corner, right: _corner, height: _wall,
              child: _svg('edge_bottom.svg', filter)),
          Positioned(
              left: 0, top: _corner, bottom: _corner, width: _wall,
              child: _svg('edge_left.svg', filter)),
          Positioned(
              right: 0, top: _corner, bottom: _corner, width: _wall,
              child: _svg('edge_right.svg', filter)),
          Positioned(
              top: 0, left: 0, width: _corner, height: _corner,
              child: _svg('corner_tl.svg', filter)),
          Positioned(
              top: 0, right: 0, width: _corner, height: _corner,
              child: _svg('corner_tr.svg', filter)),
          Positioned(
              bottom: 0, left: 0, width: _corner, height: _corner,
              child: _svg('corner_bl.svg', filter)),
          Positioned(
              bottom: 0, right: 0, width: _corner, height: _corner,
              child: _svg('corner_br.svg', filter)),
        ],
      ),
    );
  }
}

/// Horizontal chips to pick which zone (terasa) to show.
class _ZoneChips extends StatelessWidget {
  const _ZoneChips({
    required this.zones,
    required this.selected,
    required this.onSelect,
  });

  final List<MqttTerrace> zones;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: zones.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => ChoiceChip(
          label: Text(zones[i].label),
          showCheckmark: false,
          selected: i == selected,
          onSelected: (_) => onSelect(i),
        ),
      ),
    );
  }
}

class _EmptyTables extends StatelessWidget {
  const _EmptyTables();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.table_restaurant_outlined,
                size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            const Text('Stolovi nisu učitani', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Shakes its child sideways once each time [trigger] changes — the same
/// damped swing as a wrong PIN.
class _Shake extends StatefulWidget {
  const _Shake({super.key, required this.trigger, required this.child});

  final int trigger;
  final Widget child;

  @override
  State<_Shake> createState() => _ShakeState();
}

class _ShakeState extends State<_Shake> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void didUpdateWidget(_Shake old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        final dx = math.sin(t * math.pi * 4) * 8 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: widget.child,
    );
  }
}

/// A dark rounded message that slides up from the bottom and fades away —
/// drawn by the screen itself, so it shows on every phone.
class _FloatingNotice extends StatelessWidget {
  const _FloatingNotice({required this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    final text = this.text;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.4),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: text == null
          ? const SizedBox(key: ValueKey('none'), width: double.infinity)
          : Center(
              key: ValueKey(text),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 20, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2633).withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock, color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
