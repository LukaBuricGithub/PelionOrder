import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../auth/state/session_provider.dart';
import '../../cashregister/presentation/table_select_screen.dart'
    show precacheTableSelectSvgs;
import '../../settings/models/table_view_size.dart';
import '../../settings/state/settings_provider.dart';
import '../models/mqtt_tables.dart';
import '../state/mqtt_orders_provider.dart';
import '../state/mqtt_tables_provider.dart';
import 'mqtt_table_view_screen.dart';

// SVG assets (shared with the Odabir stola screen).
const _kSprite = 'assets/table_select/table_sprite.svg';
const _kSpriteDark = 'assets/table_select/table_sprite_dark.svg';
const _kWalls = 'assets/table_select/walls';
const _kDarkAssetTint =
    ColorFilter.mode(Color(0xFF434A53), BlendMode.modulate);

/// How a table tile is presented / behaves.
enum _TileStatus {
  free, // openable → new order
  order, // your in-progress local order → openable, editable
  occupiedMine, // occupied by you → openable, read-only summary
  occupiedOther, // occupied by someone else → blocked
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
  int _selectedZone = 0;

  @override
  void initState() {
    super.initState();
    precacheTableSelectSvgs();
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
    final myCuser = ref.watch(currentUserProvider)?.code;
    final columns = _columns(ref.watch(settingsProvider).tableViewSize);

    return Scaffold(
      appBar: AppBar(title: const Text('Odabir stola (MQTT)')),
      body: SafeArea(
        child: zones.isEmpty
            ? const _EmptyTables()
            : _buildBody(zones, occupied, withOrders, myCuser, columns),
      ),
    );
  }

  Widget _buildBody(
    List<MqttTerrace> zones,
    Map<int, MqttTableState> occupied,
    Set<int> withOrders,
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stol je zauzet od drugog konobara.')),
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
    required this.myCuser,
    required this.columns,
    required this.showName,
    required this.onTapTable,
  });

  final List<MqttTable> tables;
  final Map<int, MqttTableState> occupied;
  final Set<int> withOrders;
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

/// One table cell: the chairs sprite with a status-coloured top (red = occupied,
/// neutral = free) drawn on the central 60%.
class _TableCell extends StatelessWidget {
  const _TableCell({
    required this.table,
    required this.status,
    required this.showName,
    required this.onTap,
  });

  final MqttTable table;
  final _TileStatus status;
  final bool showName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Colour + corner icon per status: occupied → red (lock = blocked,
    // eye = yours/viewable), your order → blue, free → neutral.
    final (Color fill, Color fg, IconData? corner) = switch (status) {
      _TileStatus.occupiedOther =>
        (const Color(0xFFD46A5A), Colors.white, Icons.lock),
      _TileStatus.occupiedMine =>
        (const Color(0xFFD46A5A), Colors.white, Icons.visibility),
      _TileStatus.order => (const Color(0xFF4A78B4), Colors.white, null),
      _TileStatus.free => dark
          ? (const Color(0xFF3A4756), const Color(0xFFC9D3DE), null)
          : (const Color(0xFFD8DEE4), const Color(0xFF37424E), null),
    };
    final hasName = showName && table.naziv.isNotEmpty;

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
                        if (hasName) ...[
                          SizedBox(height: w * 0.02),
                          AutoSizeText(
                            table.naziv,
                            maxLines: 1,
                            minFontSize: 7,
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
