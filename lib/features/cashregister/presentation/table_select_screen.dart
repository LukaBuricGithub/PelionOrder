import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../master_data/models/venue_table.dart';
import '../../settings/models/table_view_size.dart';
import '../../settings/state/settings_provider.dart';
import '../../shared/presentation/online_status_badge.dart';
import '../state/table_select_controller.dart';

// ── SVG assets (see assets/table_select) ───────────────────────────────────
// Two theme-specific chair sprites, each with its own per-part colours
// (body / seat / back / outline). Edit those SVGs to recolour the chair parts.
const _kSprite = 'assets/table_select/table_sprite.svg'; // light theme
const _kSpriteDark = 'assets/table_select/table_sprite_dark.svg'; // dark theme
const _kWalls = 'assets/table_select/walls';

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

/// The SVG assets (walls + chairs) are drawn in fixed light greys, which read as
/// bright white on the dark floor. In dark mode we multiply them down to a dark
/// grey so they look like dark walls/chairs. (The status colour of a table top
/// is NOT tinted by this — it's drawn as a theme-correct Flutter overlay.)
const _kDarkAssetTint =
    ColorFilter.mode(Color(0xFF434A53), BlendMode.modulate);

/// Choose a terrace/zone, then a table to work. Tables are drawn as a flat
/// top-down floor plan: a walled room (nine-slice SVG frame) with a scrolling
/// grid of table sprites, colour-coded by status. The size setting picks the
/// column count (small 4 / medium 3 / large 2). Selecting an openable table
/// reserves it and opens the ordering screen.
class TableSelectScreen extends ConsumerStatefulWidget {
  const TableSelectScreen({super.key});

  @override
  ConsumerState<TableSelectScreen> createState() => _TableSelectScreenState();
}

class _TableSelectScreenState extends ConsumerState<TableSelectScreen> {
  int _columns(TableViewSize s) => switch (s) {
        TableViewSize.small => 4,
        TableViewSize.medium => 3,
        TableViewSize.large => 2,
      };

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tableSelectControllerProvider);
    final controller = ref.read(tableSelectControllerProvider.notifier);
    final size = ref.watch(settingsProvider).tableViewSize;
    final columns = _columns(size);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Odabir stola'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(child: OnlineStatusBadge()),
          ),
        ],
      ),
      body: SafeArea(
        child: state.loading
            ? const Center(child: CircularProgressIndicator())
            : state.terraces.isEmpty
                ? const _EmptyTables()
                : _buildBody(state, controller, columns),
      ),
    );
  }

  Widget _buildBody(
    TableSelectState state,
    TableSelectController controller,
    int columns,
  ) {
    final tables = state.tablesForCurrentTerrace;

    return Column(
      children: [
        // Zone (terrace) selector — pick which zone's tables to show.
        _ZoneChips(state: state, controller: controller),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
            child: _WallFrame(
              floor: _floorColor(context),
              child: RefreshIndicator(
                onRefresh: controller.reload,
                child: tables.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 80),
                          Center(child: Text('Nema stolova u ovoj zoni.')),
                        ],
                      )
                    : GridView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(6),
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          childAspectRatio: 1,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                        ),
                        itemCount: tables.length,
                        itemBuilder: (context, i) {
                          final table = tables[i];
                          return _TableCell(
                            table: table,
                            status: controller.statusFor(table),
                            showName: columns < 4, // drop naziv at "small"
                            onTap: () => _onTap(context, controller, table),
                          );
                        },
                      ),
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

  Future<void> _onTap(
    BuildContext context,
    TableSelectController controller,
    VenueTable table,
  ) async {
    if (!controller.canOpen(table)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stol je zauzet od drugog konobara.')),
      );
      return;
    }
    final ok = await controller.reserve(table);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nije moguće rezervirati stol.')),
      );
      return;
    }
    await context.push('/new-order/${table.code}');
    // Returning from the order flow — refresh table ownership.
    controller.reload();
  }
}

/// Status → (table-top fill, text) colours. Free adapts to the theme; the
/// others are fixed brand-ish tints applied to the sprite's `currentColor`.
(Color, Color) _statusColors(TableStatus s, Brightness b) {
  final dark = b == Brightness.dark;
  switch (s) {
    case TableStatus.free:
      return dark
          ? (const Color(0xFF3A4756), const Color(0xFFC9D3DE))
          : (const Color(0xFFD8DEE4), const Color(0xFF37424E));
    case TableStatus.other:
      return (const Color(0xFFD46A5A), Colors.white);
    case TableStatus.mine:
      return (const Color(0xFF4A78B4), Colors.white);
    case TableStatus.pendingMine:
      return (const Color(0xFFE0A94A), const Color(0xFF3A2600));
  }
}

/// Croatian plural for "stavka" (0/…5+ → stavki, 1 → stavka, 2–4 → stavke).
String _stavkeLabel(int n) {
  final mod10 = n % 10, mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return '$n stavka';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return '$n stavke';
  }
  return '$n stavki';
}

/// One table cell: the table sprite (tinted by status) with the number, name
/// and item count drawn on the table top (central 60% of the square).
class _TableCell extends StatelessWidget {
  const _TableCell({
    required this.table,
    required this.status,
    required this.showName,
    required this.onTap,
  });

  final VenueTable table;
  final TableStatus status;
  final bool showName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (fill, fg) = _statusColors(status, Theme.of(context).brightness);
    final hasName = showName && table.name.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          return Stack(
            fit: StackFit.expand,
            children: [
              // Chairs — a theme-specific sprite (per-part colours baked into
              // each asset). The status colour of the table top is NOT from the
              // sprite; it's the overlay below, so it stays theme-correct.
              SvgPicture.asset(dark ? _kSpriteDark : _kSprite),
              // Status-coloured table top (central 60%) + its text.
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
                      color: Colors.black
                          .withValues(alpha: dark ? 0.28 : 0.05),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: w * 0.04),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${table.code}',
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
                            table.name,
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
                        SizedBox(height: w * 0.02),
                        Text(
                          _stavkeLabel(table.itemCount),
                          maxLines: 1,
                          style: TextStyle(
                            color: fg.withValues(alpha: 0.85),
                            fontSize: w * 0.072,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (status == TableStatus.pendingMine)
                Positioned(
                  top: w * 0.22,
                  right: w * 0.22,
                  child: Icon(Icons.sync, size: w * 0.11, color: fg),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The walled room: a fixed nine-slice SVG frame (corners + tiling edges) with
/// the scrolling [child] inset inside it, over the flat [floor] colour.
class _WallFrame extends StatelessWidget {
  const _WallFrame({required this.child, required this.floor});

  final Widget child;
  final Color floor;

  static const double _wall = 18; // wall thickness (matches corner arm)
  static const double _corner = 52; // corner piece size

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
          // Scrolling content, inset so it sits inside the walls.
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(_wall),
              child: ClipRect(child: child),
            ),
          ),
          // Edges (stretch between the corners).
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
          // Corners (fixed).
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

/// Status filter chips (Svi / Slobodni / Zauzeti / Vaši).
/// Horizontal chips to pick which zone (terrace) to show tables for.
class _ZoneChips extends StatelessWidget {
  const _ZoneChips({required this.state, required this.controller});

  final TableSelectState state;
  final TableSelectController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: state.terraces.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final selected = i == state.selectedTerrace;
          final t = state.terraces[i];
          return ChoiceChip(
            label: Text(t.code),
            selected: selected,
            onSelected: (_) => controller.selectTerrace(i),
          );
        },
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
              'Nema podataka o stolovima. Ažurirajte podatke na ekranu za '
              'prijavu.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
