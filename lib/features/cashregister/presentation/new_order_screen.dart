import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../state/new_order_controller.dart';

/// Screen-size-driven UI scale: 1.0 ≈ a typical phone (~928 dp diagonal).
/// Every size on this screen — fonts, buttons, tiles, paddings — is multiplied
/// by this so the layout grows on larger devices and shrinks on smaller ones
/// while keeping identical proportions. Clamped so it never gets extreme.
double _screenScale(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final diagonal =
      math.sqrt(size.width * size.width + size.height * size.height);
  return (diagonal / 928.0).clamp(0.9, 1.4);
}

/// The order-entry screen. Top: the running order (each line with quantity,
/// line total and a ✕ to remove) plus an action column and the total. Bottom:
/// the article picker (search + group tabs + grid) — tapping an article adds it.
class NewOrderScreen extends ConsumerStatefulWidget {
  const NewOrderScreen({super.key, required this.tableCode});

  final int tableCode;

  @override
  ConsumerState<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends ConsumerState<NewOrderScreen> {
  final _searchController = TextEditingController();
  final _money =
      NumberFormat.currency(locale: 'hr_HR', symbol: '€', decimalDigits: 2);
  bool _canPop = false;
  bool _searching = false;

  NewOrderController get _controller =>
      ref.read(newOrderControllerProvider(widget.tableCode).notifier);

  static String fmtQty(double q) =>
      q == q.roundToDouble() ? q.toInt().toString() : q.toString();

  @override
  void initState() {
    super.initState();
    // On this screen, hide the Android bottom navigation bar but keep the top
    // status bar (clock/battery). Swiping up from the bottom reveals the nav
    // bar temporarily. No-op on iOS (no system nav bar).
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );
    // Lock this screen to portrait — it's a dense, portrait-designed layout.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  @override
  void dispose() {
    // Restore the normal system bars and free orientation when leaving.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onPopInvoked(bool didPop) async {
    if (didPop) return;
    await _controller.handleBack();
    if (!mounted) return;
    setState(() => _canPop = true);
    if (context.canPop()) context.pop();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchController.clear();
        _controller.setQuery('');
      }
    });
  }

  Future<void> _openDetails() async {
    final id = await _controller.saveDraftAndGetId();
    if (!mounted) return;
    // This screen hides the Android nav bar, but Details (pushed on top) should
    // behave like a normal screen — restore the bar while it's showing.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    final result = await context.push('/order-details/$id');
    if (!mounted) return;
    if (result == 'sent') {
      // We're leaving the order screen entirely — dispose() restores the bars.
      setState(() => _canPop = true);
      if (context.canPop()) context.pop();
    } else {
      // Back on the order screen — hide the nav bar again.
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: [SystemUiOverlay.top],
      );
      await _controller.reloadOrder();
    }
  }

  Future<void> _send() async {
    final ok = await _controller.send();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Narudžba poslana.'
            : 'Nema veze — narudžba je spremljena i bit će poslana automatski.'),
      ),
    );
    setState(() => _canPop = true);
    if (context.canPop()) context.pop();
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
            // Quiet cancel so a mis-tap defaults to the safe option.
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Odustani'),
            ),
            // Red confirm — signals the destructive action.
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
    if (ok == true) _controller.clearItems();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(newOrderControllerProvider(widget.tableCode));
    final controller = _controller;
    final hasItems = !state.isEmptyOrder;

    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, _) => _onPopInvoked(didPop),
      // Honour the device's accessibility font scale, but cap it so a very large
      // system font can't overflow this dense grid.
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler:
              MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
        ),
        child: Scaffold(
        // Let the body resize when the keyboard opens (default) so the picker
        // slides up and the search field stays visible above the keyboard. The
        // action column shrinks to fit (see _ActionColumn) so nothing overflows.
        appBar: AppBar(
          title: Text('Stol ${widget.tableCode}'),
        ),
        body: state.loading
            ? const Center(child: CircularProgressIndicator())
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
                                state: state,
                                controller: controller,
                                money: _money,
                              ),
                            ),
                            const SizedBox(width: 10),
                            _ActionColumn(
                              hasItems: hasItems,
                              sending: state.sending,
                              onClear: hasItems ? _confirmClear : null,
                              onDetails: hasItems ? _openDetails : null,
                              onSend:
                                  (hasItems && !state.sending) ? _send : null,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Total (+ search toggle) ─────────────────────────────
                    _TotalBar(
                      total: _money.format(controller.total),
                      searching: _searching,
                      onToggleSearch: _toggleSearch,
                    ),

                    // ── Article picker ──────────────────────────────────────
                    Expanded(
                      flex: 6,
                      child: Column(
                        children: [
                          _PickerBar(
                            state: state,
                            controller: controller,
                            searching: _searching,
                            searchController: _searchController,
                          ),
                          Expanded(
                            child: _ArticleGrid(
                              state: state,
                              controller: controller,
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
  }
}

/// The running order as a card of compact lines (name, quantity, line total,
/// remove ✕). Auto-scrolls to the newest line when one is added.
class _CartCard extends StatefulWidget {
  const _CartCard({
    required this.state,
    required this.controller,
    required this.money,
  });

  final NewOrderState state;
  final NewOrderController controller;
  final NumberFormat money;

  @override
  State<_CartCard> createState() => _CartCardState();
}

class _CartCardState extends State<_CartCard> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant _CartCard old) {
    super.didUpdateWidget(old);
    // When a new line is added, scroll to the bottom so the latest item is
    // always visible (even past the ~5 that fit on screen).
    final oldCount = old.state.order.items.length;
    final newCount = widget.state.order.items.length;
    if (newCount > oldCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controller = widget.controller;
    final money = widget.money;
    final items = widget.state.order.items;
    final s = _screenScale(context);

    // A real Material (not a plain Container) so the ✕ button's ink ripple is
    // clipped inside this card instead of bleeding onto the Scaffold behind it.
    return Material(
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14 * s),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: items.isEmpty
          ? Center(
              child: Text(
                'Nema stavki u narudžbi',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          : ListView.separated(
              controller: _scroll,
              padding: EdgeInsets.only(bottom: 2 * s),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                // Each tap on an article adds its OWN line, so we render the
                // order line-by-line (duplicates of the same article stay
                // separate); quantity is edited per line with +/−.
                final line = items[i];
                final article = controller.articleFor(line.code);
                final name = article?.name ?? 'Artikl ${line.code}';
                final unit = article?.unit ?? '';
                final lineTotal = controller.priceFor(line.code) * line.quantity;
                return Padding(
                  padding: EdgeInsets.fromLTRB(12 * s, 3 * s, 6 * s, 4 * s),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            // Full name — wraps to new lines rather than being
                            // cut, so the whole article name is visible.
                            child: Text(
                              name,
                              style: TextStyle(
                                fontSize: 14 * s,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          InkResponse(
                            onTap: () => controller.removeLine(i),
                            radius: 18 * s,
                            child: Padding(
                              padding: EdgeInsets.all(4 * s),
                              child: Icon(Icons.close,
                                  size: 18 * s, color: scheme.error),
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: EdgeInsets.only(right: 2 * s, top: 2 * s),
                        child: Row(
                          children: [
                            _QtyStepper(
                              qty: line.quantity,
                              unit: unit,
                              onMinus: () => controller.decrementLine(i),
                              onPlus: () => controller.incrementLine(i),
                            ),
                            const Spacer(),
                            Text(
                              money.format(lineTotal),
                              style: TextStyle(
                                fontSize: 13 * s,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// Compact [−] N unit [+] stepper for a cart line.
class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.qty,
    required this.unit,
    required this.onMinus,
    required this.onPlus,
  });

  final double qty;
  final String unit;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = _screenScale(context);

    Widget btn(IconData icon, VoidCallback onTap) => InkResponse(
          onTap: onTap,
          radius: 20 * s,
          child: Container(
            width: 28 * s,
            height: 28 * s,
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(8 * s),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Icon(icon, size: 16 * s, color: scheme.onSurface),
          ),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.remove, onMinus),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 10 * s),
          child: Text(
            '${_NewOrderScreenState.fmtQty(qty)}$unit',
            style: TextStyle(fontSize: 13 * s, fontWeight: FontWeight.w700),
          ),
        ),
        btn(Icons.add, onPlus),
      ],
    );
  }
}

/// The stacked action buttons to the right of the cart.
class _ActionColumn extends StatelessWidget {
  const _ActionColumn({
    required this.hasItems,
    required this.sending,
    required this.onClear,
    required this.onDetails,
    required this.onSend,
  });

  final bool hasItems;
  final bool sending;
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
      // Size the buttons to the available height so they shrink (rather than
      // overflow / overlap) when the keyboard opens and squeezes the top area.
      child: LayoutBuilder(
        builder: (context, c) {
          // Three buttons + two gaps must fit; cap at the natural size so they
          // don't stretch when there's plenty of room.
          final btn = c.maxHeight.isFinite
              ? math.min(naturalBtn, (c.maxHeight - gap * 2) / 3)
              : naturalBtn;
          // Only push Send to the bottom when there's spare room.
          final roomy = c.maxHeight.isFinite &&
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
  });

  final IconData icon;
  final _Tone tone;
  final VoidCallback? onTap;
  final double width;
  final double height;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s = _screenScale(context);
    // Keep the icon proportional to the (possibly shrunken) button height.
    final iconSize = math.min(26.0 * s, height * 0.46);
    // Own button language, distinct from the amber "groups" / blue "items"
    // content palette: Send = teal, Details = purple, Clear = red.
    final (bg, fg) = switch (tone) {
      _Tone.primary => dark
          ? (const Color(0xFF1FA9B6), const Color(0xFF052A2E))
          : (const Color(0xFF0E9AA7), Colors.white),
      _Tone.neutral => dark
          ? (const Color(0xFF8677E8), const Color(0xFF140A3A))
          : (const Color(0xFF6A57D8), Colors.white),
      _Tone.danger => dark
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
            child: busy
                ? Center(
                    child: SizedBox(
                      width: iconSize * 0.85,
                      height: iconSize * 0.85,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: fg),
                    ),
                  )
                : Icon(icon, color: fg, size: iconSize),
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
    // Plain line below the order items (no card / border). The amount is
    // accent-coloured and larger so the total stands out from the rest; the
    // article search toggle sits at the right edge.
    final scheme = Theme.of(context).colorScheme;
    final s = _screenScale(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(14 * s, 0, 4 * s, 2 * s),
      child: Row(
        children: [
          Text('Ukupno',
              style: TextStyle(
                fontSize: 15 * s,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              )),
          SizedBox(width: 10 * s),
          Text(total,
              style: TextStyle(
                fontSize: 21 * s,
                fontWeight: FontWeight.w800,
                color: scheme.primary,
              )),
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

/// Group picker above the article grid: a paged 2×4 grid of group cards (swipe
/// for more). Search is toggled from the app bar; when active it replaces the
/// grid with the search field.
class _PickerBar extends StatelessWidget {
  const _PickerBar({
    required this.state,
    required this.controller,
    required this.searching,
    required this.searchController,
  });

  final NewOrderState state;
  final NewOrderController controller;
  final bool searching;
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    if (searching) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
        child: TextField(
          controller: searchController,
          autofocus: true,
          onChanged: controller.setQuery,
          decoration: const InputDecoration(
            isDense: true,
            hintText: 'Pretraži artikle…',
            border: OutlineInputBorder(),
          ),
        ),
      );
    }
    // Uniform, same-size group cards in a paged 2×4 grid (8 per page), filled
    // left-to-right / top-to-bottom — same logic as the article grid, but 2×4.
    // Swipe horizontally for the next page. Selected = amber (no check-mark).
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Warm "group" family — amber marks the selected group; a muted sand/brown
    // marks the rest (distinct from the cool price-list item colours).
    final selectedFill =
        dark ? const Color(0xFFF4A83A) : const Color(0xFFE8890C);
    final selectedText = dark ? const Color(0xFF3A2600) : Colors.white;
    final unselectedFill =
        dark ? const Color(0xFF403322) : const Color(0xFFF3E4CC);
    final unselectedText =
        dark ? const Color(0xFFE4C89A) : const Color(0xFF6B4E1E);

    // Match the article grid's horizontal padding & column spacing so the four
    // columns line up vertically between the groups and the price-list items.
    final s = _screenScale(context);
    final spacing = 6.0 * s;
    final hPad = 8.0 * s;
    final rowHeight = 44.0 * s;
    final vPad = 4.0 * s;
    const perPage = 8; // 4 columns × 2 rows
    final pageCount = (state.groups.length + perPage - 1) ~/ perPage;

    return Padding(
      padding: EdgeInsets.only(bottom: 2 * s),
      child: SizedBox(
        // Two rows + inter-row spacing + the grid's top/bottom vertical padding.
        height: rowHeight * 2 + spacing + vPad * 2,
        child: PageView.builder(
          itemCount: pageCount,
          itemBuilder: (context, page) {
            final start = page * perPage;
            final end = (start + perPage).clamp(0, state.groups.length);
            final pageItems = state.groups.sublist(start, end);
            return GridView.builder(
              // Inner grid never scrolls — the PageView owns horizontal paging.
              physics: const NeverScrollableScrollPhysics(),
              padding:
                  EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4, // 4 columns, filled row-major
                mainAxisExtent: rowHeight,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
              ),
              itemCount: pageItems.length,
              itemBuilder: (context, i) {
                final g = pageItems[i];
                final selected = g.code == state.selectedGroupCode;
                return Material(
                  color: selected ? selectedFill : unselectedFill,
                  borderRadius: BorderRadius.circular(8 * s),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => controller.selectGroup(g.code),
                    child: Container(
                      alignment: Alignment.center,
                      padding: EdgeInsets.symmetric(
                          horizontal: 4 * s, vertical: 2 * s),
                      child: Text(
                        g.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9.5 * s,
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
        ),
      ),
    );
  }
}

/// The article grid — tap a tile to add its own line to the order. Each page is
/// a fixed 4×4 grid filled left-to-right, top-to-bottom (16 tiles). When a group
/// has more than 16 articles, swiping horizontally opens the next full page.
class _ArticleGrid extends StatelessWidget {
  const _ArticleGrid({required this.state, required this.controller});

  final NewOrderState state;
  final NewOrderController controller;

  static const _perPage = 16; // 4 columns × 4 rows

  @override
  Widget build(BuildContext context) {
    final articles = state.visibleArticles;
    if (articles.isEmpty) {
      return const Center(child: Text('Nema artikala.'));
    }

    final s = _screenScale(context);
    final spacing = 6.0 * s;
    final hPad = 8.0 * s;
    final vPad = 4.0 * s;
    // Match the group cards' compact height (see _PickerBar) so price-list
    // tiles are the same size as the group cards rather than stretching to
    // fill the whole grid area.
    final tileHeight = 58.0 * s;
    final pageCount = (articles.length + _perPage - 1) ~/ _perPage;

    return PageView.builder(
      itemCount: pageCount,
      itemBuilder: (context, page) {
        final start = page * _perPage;
        final end = (start + _perPage).clamp(0, articles.length);
        final pageItems = articles.sublist(start, end);
        return GridView.builder(
          // Inner grid never scrolls — the PageView owns horizontal paging.
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4, // 4 columns, filled row-major
            mainAxisExtent: tileHeight, // fixed height like the group cards
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
          ),
          itemCount: pageItems.length,
          itemBuilder: (context, i) {
            final a = pageItems[i];
            return _ArticleTile(
              name: a.name,
              qty: controller.qtyFor(a.code),
              onTap: () => controller.addLine(a.code),
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
    required this.qty,
    required this.onTap,
  });

  final String name;
  final double qty;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final inOrder = qty > 0;
    // Cool "item" family — distinct from the warm "group" family, with a
    // saturated blue marking items already in the order.
    final fill = inOrder
        ? (dark ? const Color(0xFF3E6CA6) : const Color(0xFF4A78B4))
        : (dark ? const Color(0xFF25303C) : const Color(0xFFE4EBF3));
    final textColor = inOrder
        ? Colors.white
        : (dark ? const Color(0xFFC5D2DF) : const Color(0xFF2C3E52));
    final s = _screenScale(context);
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(10 * s),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(3 * s),
          child: Center(
            // Uniform font for every price-list item, scaled by device size.
            child: Text(
              name,
              textAlign: TextAlign.center,
              softWrap: true,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5 * s,
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
