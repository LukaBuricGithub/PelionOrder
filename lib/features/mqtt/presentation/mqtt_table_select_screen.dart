import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../auth/state/auth_controller.dart';
import '../../auth/state/session_provider.dart';
import '../../settings/models/table_view_size.dart';
import '../../settings/presentation/settings_drawer.dart';
import '../../settings/state/settings_provider.dart';
import '../models/mqtt_tables.dart';
import '../state/mqtt_orders_provider.dart';
import '../state/mqtt_pending_transfers_provider.dart';
import '../state/mqtt_tables_provider.dart';
import 'mqtt_table_view_screen.dart';

// ── SVG assets (see assets/table_select) ───────────────────────────────────
// Two theme-specific chair sprites, each with its own per-part colours
// (body / seat / back / outline). Edit those SVGs to recolour the chair parts.
const _kSprite = 'assets/table_select/table_sprite.svg'; // light theme
const _kSpriteDark = 'assets/table_select/table_sprite_dark.svg'; // dark theme
const _kWalls = 'assets/table_select/walls';
const _kDarkAssetTint =
    ColorFilter.mode(Color(0xFF434A53), BlendMode.modulate);

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
  order, // your in-progress local order → openable, editable
  occupiedMine, // occupied by you → openable, read-only summary
  occupiedOther, // occupied by someone else → blocked
}

/// "Jesu li poslane sve narudžbe sa stola" — drawn as a corner badge, kept
/// separate from [_TileStatus] so the answer never competes with the tile's
/// colour for the same pixels.
enum _SendMark {
  /// Nothing ordered here — nothing to report.
  none,

  /// Something is outstanding: a local draft that was never accepted, or an
  /// accepted order the kasa has not yet moved onto the table.
  pending,

  /// Everything this device knows about has reached the table.
  sent,
}

/// MQTT floor plan: pick a zone (terasa), then a free table to open its menu.
/// Same visuals as "Odabir stola", but tables/zones come from `podaci/stolovi`
/// and occupancy from `podaci/stolovi_stanje` — occupied tables are red and
/// cannot be opened.
class MqttTableSelectScreen extends ConsumerStatefulWidget {
  const MqttTableSelectScreen({super.key});

  @override
  ConsumerState<MqttTableSelectScreen> createState() =>
      _MqttTableSelectScreenState();
}

class _MqttTableSelectScreenState extends ConsumerState<MqttTableSelectScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedZone = 0;

  @override
  void initState() {
    super.initState();
    precacheTableSelectSvgs();
  }

  /// Back here forgets the current waiter: this is the top of the signed-in
  /// area, so back must NOT close the app — it clears the session and the
  /// router's auth redirect drops us on the login screen. We must not navigate
  /// ourselves as well, or the route change double-fires.
  Future<void> _forgetSession() async {
    await ref.read(authControllerProvider).logout();
  }

  int _columns(TableViewSize s) => switch (s) {
        TableViewSize.small => 4,
        TableViewSize.medium => 3,
        TableViewSize.large => 2,
      };

  @override
  Widget build(BuildContext context) {
    final zones = ref.watch(mqttTablesProvider);
    final occupied = ref.watch(mqttOccupiedProvider);
    // Tables with a local (in-progress) order — coloured "yours" and reopenable.
    final withOrders = ref.watch(mqttOrdersProvider).keys.toSet();
    // Tables the kasa has accepted an order for but not yet applied it to.
    final pendingTransfer = ref.watch(mqttPendingTransfersProvider);
    final myCuser = ref.watch(currentUserProvider)?.code;
    final columns = _columns(ref.watch(settingsProvider).tableViewSize);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _forgetSession();
      },
      child: Scaffold(
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
          child: zones.isEmpty
              ? const _EmptyTables()
              : _buildBody(zones, occupied, withOrders, pendingTransfer,
                  myCuser, columns),
        ),
      ),
    );
  }

  Widget _buildBody(
    List<MqttTerrace> zones,
    Map<int, MqttTableState> occupied,
    Set<int> withOrders,
    Set<int> pendingTransfer,
    String? myCuser,
    int columns,
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
                      myCuser: myCuser,
                      columns: columns,
                      showName: columns < 4, // drop naziv at "small"
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

  void _onTap(MqttTable table, _TileStatus status, MqttTableState? occ) {
    switch (status) {
      case _TileStatus.occupiedOther:
        // Name them here: this is the moment the waiter actually asks who has
        // the table, and the snackbar has room the tile doesn't.
        final konobar = occ?.konobar.trim() ?? '';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(konobar.isEmpty
                  ? 'Stol je zauzet od drugog konobara.'
                  : 'Stol je zauzet — $konobar.'),
            ),
          );
      case _TileStatus.occupiedMine:
        // Read-only summary of the table (occupied by the current user).
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => MqttTableViewScreen(
            state: occ!,
            tableBroj: table.broj,
            tableNaziv: table.naziv.isEmpty ? null : table.naziv,
          ),
        ));
      case _TileStatus.free:
      case _TileStatus.order:
        final q = table.naziv.isEmpty
            ? ''
            : '?naziv=${Uri.encodeComponent(table.naziv)}';
        context.push('/mqtt-menu/${table.broj}$q');
    }
  }
}

/// A horizontally-paged grid of tables (same paging logic as Odabir stola).
class _PagedTableGrid extends StatelessWidget {
  const _PagedTableGrid({
    required this.tables,
    required this.occupied,
    required this.withOrders,
    required this.pendingTransfer,
    required this.myCuser,
    required this.columns,
    required this.showName,
    required this.onTapTable,
  });

  final List<MqttTable> tables;
  final Map<int, MqttTableState> occupied;
  final Set<int> withOrders;

  /// Tables whose accepted order the kasa has not yet moved onto the table.
  final Set<int> pendingTransfer;
  final String? myCuser;
  final int columns;
  final bool showName;
  final void Function(MqttTable table, _TileStatus status, MqttTableState? occ)
      onTapTable;

  _TileStatus _statusFor(MqttTable table) {
    final occ = occupied[table.broj];
    if (occ != null) {
      return occ.cuser == myCuser
          ? _TileStatus.occupiedMine
          : _TileStatus.occupiedOther;
    }
    return withOrders.contains(table.broj)
        ? _TileStatus.order
        : _TileStatus.free;
  }

  /// Independent of [_statusFor]: a draft on an ALREADY OCCUPIED table (added
  /// via "Dodaj stavke") is exactly the case the status colour cannot show,
  /// since occupancy wins there.
  _SendMark _markFor(MqttTable table) {
    if (withOrders.contains(table.broj) ||
        pendingTransfer.contains(table.broj)) {
      return _SendMark.pending;
    }
    // Everything on the table has landed — but only mark a table that actually
    // has an order; an empty table has nothing to report.
    return occupied.containsKey(table.broj) ? _SendMark.sent : _SendMark.none;
  }

  static const double _pad = 6;
  static const double _spacing = 6;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cell =
            (c.maxWidth - _pad * 2 - _spacing * (columns - 1)) / columns;
        final rows = ((c.maxHeight - _pad * 2 + _spacing) / (cell + _spacing))
            .floor()
            .clamp(1, 999);
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
              padding: const EdgeInsets.all(_pad),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                childAspectRatio: 1,
                crossAxisSpacing: _spacing,
                mainAxisSpacing: _spacing,
              ),
              itemCount: pageItems.length,
              itemBuilder: (context, i) {
                final table = pageItems[i];
                final status = _statusFor(table);
                return _TableCell(
                  table: table,
                  status: status,
                  showName: showName,
                  occupantName: occupied[table.broj]?.konobar,
                  mark: _markFor(table),
                  onTap: () =>
                      onTapTable(table, status, occupied[table.broj]),
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
    required this.mark,
    required this.onTap,
  });

  final MqttTable table;
  final _TileStatus status;
  final bool showName;

  /// The waiter holding the table (`konobar` from `stolovi_stanje`), or null
  /// when it is free.
  final String? occupantName;

  /// Whether everything ordered for this table has reached the kasa.
  ///
  /// Drawn as a MARK rather than a colour so it is independent of the status
  /// hue: it has to be visible on a free table and on an occupied one alike,
  /// and red/teal already carry a different meaning.
  final _SendMark mark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Colour + corner icon per status. Each state gets its own hue so it reads
    // at a glance: someone else's table → red + lock (blocked), your own
    // occupied table → teal + eye (open, read-only), your unsent order → blue,
    // free → neutral. Red is reserved for "you cannot go in here".
    final (Color fill, Color fg, IconData? corner) = switch (status) {
      _TileStatus.occupiedOther =>
        (const Color(0xFFD46A5A), Colors.white, Icons.lock),
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
                child: DecoratedBox(
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${table.broj}',
                          maxLines: 1,
                          style: TextStyle(
                            color: fg,
                            fontSize: w * 0.20,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                        if (hasSecondLine) ...[
                          SizedBox(height: w * 0.02),
                          AutoSizeText(
                            secondLine,
                            maxLines: 1,
                            // Floor is proportional (80% of the intended size),
                            // not a fixed 7pt: on a large tile that let text
                            // shrink to less than half its size before
                            // ellipsizing, which is unreadable rather than
                            // helpful. Past this point, ellipsis is the honest
                            // answer.
                            //
                            // MUST be a whole number: AutoSizeText asserts
                            // minFontSize is a multiple of stepGranularity
                            // (default 1), and a fractional value throws during
                            // layout for every tile.
                            minFontSize:
                                (w * 0.068).clamp(6.0, 24.0).roundToDouble(),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: fg,
                              fontSize: w * 0.085,
                              fontWeight: FontWeight.w500,
                              height: 1,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (corner != null)
                Positioned(
                  top: w * 0.22,
                  right: w * 0.22,
                  child: Icon(corner, size: w * 0.11, color: fg),
                ),
              // "Jesu li poslane sve narudžbe" — bottom-right, the corner the
              // status icon never uses, so the two never compete. Both badges
              // are ringed so they read against every status fill (red, teal,
              // blue, grey) — the green one especially, since it sits on a teal
              // tile whenever the table is yours.
              if (mark != _SendMark.none)
                Positioned(
                  right: w * 0.17,
                  bottom: w * 0.17,
                  child: Container(
                    width: w * 0.17,
                    height: w * 0.17,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: mark == _SendMark.pending
                          ? (dark
                              ? const Color(0xFFF4A83A)
                              : const Color(0xFFE8890C))
                          : (dark
                              ? const Color(0xFF4FC98A)
                              : const Color(0xFF2E9E5B)),
                      border: Border.all(
                        color: dark
                            ? const Color(0xFF1B2430)
                            : Colors.white,
                        width: w * 0.018,
                      ),
                    ),
                    child: Icon(
                      Icons.arrow_upward,
                      size: w * 0.10,
                      color: dark
                          ? (mark == _SendMark.pending
                              ? const Color(0xFF3A2600)
                              : const Color(0xFF063020))
                          : Colors.white,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
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
            const Text(
              'Nema stolova. Spojite se na MQTT (Postavke uređaja) da preuzmete '
              'stolove.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
