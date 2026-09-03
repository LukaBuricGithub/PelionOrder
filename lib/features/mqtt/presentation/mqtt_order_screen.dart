import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/mqtt_menu.dart';
import '../state/mqtt_cart.dart';
import '../state/mqtt_menu_provider.dart';
import 'mqtt_order_details_screen.dart';

/// Screen-size-driven UI scale (identical to the New Order screen): 1.0 ≈ a
/// typical phone (~928 dp diagonal). Every size is multiplied by this.
double _screenScale(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final diagonal =
      math.sqrt(size.width * size.width + size.height * size.height);
  return (diagonal / 928.0).clamp(0.9, 1.4);
}

String _fmtQty(double q) =>
    q == q.roundToDouble() ? q.toInt().toString() : q.toString();

/// Order-entry screen for the MQTT menu — a visual clone of the New Order
/// ("Stol X") screen, backed by a local in-memory [MqttCart] built from the MQTT
/// groups/articles. NOTE: the Send button is intentionally a no-op here.
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

  // Rebuilt each build from the current menu — maps article code → article.
  final _byCode = <int, MqttArticle>{};

  @override
  void initState() {
    super.initState();
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
    _cart.removeListener(_onCart);
    _cart.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _searchController.dispose();
    super.dispose();
  }

  void _onCart() {
    if (mounted) setState(() {});
  }

  double _priceFor(int code) => _byCode[code]?.price ?? 0;

  double get _total =>
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

  /// Send is intentionally inert on this screen.
  void _send() {}

  /// Opens the details screen on the same cart (edit quantities/remarks/delete).
  void _openDetails() {
    // Details is a normal screen: restore the nav bar while it's shown, re-hide
    // it on return (this screen hides it).
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
      builder: (_) => MqttOrderDetailsScreen(
        cart: _cart,
        byCode: _byCode,
        remarks: ref.read(mqttMenuProvider).remarks,
        money: _money,
        tableBroj: widget.tableBroj,
        tableNaziv: widget.tableNaziv,
      ),
    ))
        .then((_) {
      if (!mounted) return;
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
    final group =
        groups.firstWhere((g) => g.id == id, orElse: () => groups.first);
    return group.articles;
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(mqttMenuProvider).groups;
    _byCode
      ..clear()
      ..addEntries([
        for (final g in groups)
          for (final a in g.articles) MapEntry(a.code, a)
      ]);

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

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
      ),
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
                                lines: _cart.lines,
                                byCode: _byCode,
                                money: _money,
                                onRemove: _cart.removeLine,
                                onMinus: _cart.decrementLine,
                                onPlus: _cart.incrementLine,
                              ),
                            ),
                            const SizedBox(width: 10),
                            _ActionColumn(
                              onClear: hasItems ? _confirmClear : null,
                              onDetails: hasItems ? _openDetails : null,
                              onSend: hasItems ? _send : null,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Total (+ search toggle) ─────────────────────────────
                    _TotalBar(
                      total: _money.format(_total),
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
                              qtyFor: _cart.qtyFor,
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
    );
  }
}

/// The running order as a card of compact lines (name, quantity, line total,
/// remove ✕). Auto-scrolls to the newest line when one is added.
class _CartCard extends StatefulWidget {
  const _CartCard({
    required this.lines,
    required this.byCode,
    required this.money,
    required this.onRemove,
    required this.onMinus,
    required this.onPlus,
  });

  final List<MqttCartLine> lines;
  final Map<int, MqttArticle> byCode;
  final NumberFormat money;
  final ValueChanged<int> onRemove;
  final ValueChanged<int> onMinus;
  final ValueChanged<int> onPlus;

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
    final lines = widget.lines;
    final money = widget.money;
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

    return Material(
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14 * s),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: lines.isEmpty
          ? Center(
              child: Text(
                'Nema stavki u narudžbi',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          : ListView.separated(
              controller: _scroll,
              padding: EdgeInsets.only(bottom: 2 * s),
              itemCount: lines.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final line = lines[i];
                final article = widget.byCode[line.code];
                final name = article?.name ?? 'Artikl ${line.code}';
                final unit = article?.unit ?? '';
                final lineTotal = (article?.price ?? 0) * line.qty;
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
                              name,
                              style: TextStyle(
                                fontSize: 14 * s,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          InkResponse(
                            onTap: () => widget.onRemove(i),
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
                              qty: line.qty,
                              unit: unit,
                              onMinus: () => widget.onMinus(i),
                              onPlus: () => widget.onPlus(i),
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
            '${_fmtQty(qty)}$unit',
            style: TextStyle(fontSize: 13 * s, fontWeight: FontWeight.w700),
          ),
        ),
        btn(Icons.add, onPlus),
      ],
    );
  }
}

/// The stacked action buttons to the right of the cart (Clear / Details / Send).
class _ActionColumn extends StatelessWidget {
  const _ActionColumn({
    required this.onClear,
    required this.onDetails,
    required this.onSend,
  });

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
  });

  final IconData icon;
  final _Tone tone;
  final VoidCallback? onTap;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s = _screenScale(context);
    final iconSize = math.min(26.0 * s, height * 0.46);
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
            child: Icon(icon, color: fg, size: iconSize),
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
/// for more), or the search field when search is active.
class _PickerBar extends StatelessWidget {
  const _PickerBar({
    required this.groups,
    required this.selectedId,
    required this.searching,
    required this.searchController,
    required this.onSelectGroup,
    required this.onQuery,
  });

  final List<MqttArticleGroup> groups;
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
    final selectedFill =
        dark ? const Color(0xFFF4A83A) : const Color(0xFFE8890C);
    final selectedText = dark ? const Color(0xFF3A2600) : Colors.white;
    final unselectedFill =
        dark ? const Color(0xFF403322) : const Color(0xFFF3E4CC);
    final unselectedText =
        dark ? const Color(0xFFE4C89A) : const Color(0xFF6B4E1E);

    final s = _screenScale(context);
    final spacing = 6.0 * s;
    final hPad = 8.0 * s;
    final rowHeight = 44.0 * s;
    final vPad = 4.0 * s;
    const perPage = 8; // 4 columns × 2 rows
    final pageCount = (groups.length + perPage - 1) ~/ perPage;

    return Padding(
      padding: EdgeInsets.only(bottom: 2 * s),
      child: SizedBox(
        height: rowHeight * 2 + spacing + vPad * 2,
        child: PageView.builder(
          itemCount: pageCount,
          itemBuilder: (context, page) {
            final start = page * perPage;
            final end = (start + perPage).clamp(0, groups.length);
            final pageItems = groups.sublist(start, end);
            return GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
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

/// The article grid — tap a tile to add its own line to the order.
class _ArticleGrid extends StatelessWidget {
  const _ArticleGrid({
    required this.articles,
    required this.qtyFor,
    required this.onAdd,
  });

  final List<MqttArticle> articles;
  final double Function(int code) qtyFor;
  final ValueChanged<int> onAdd;

  static const _perPage = 16; // 4 columns × 4 rows

  @override
  Widget build(BuildContext context) {
    if (articles.isEmpty) {
      return const Center(child: Text('Nema artikala.'));
    }

    final s = _screenScale(context);
    final spacing = 6.0 * s;
    final hPad = 8.0 * s;
    final vPad = 4.0 * s;
    final tileHeight = 58.0 * s;
    final pageCount = (articles.length + _perPage - 1) ~/ _perPage;

    return PageView.builder(
      itemCount: pageCount,
      itemBuilder: (context, page) {
        final start = page * _perPage;
        final end = (start + _perPage).clamp(0, articles.length);
        final pageItems = articles.sublist(start, end);
        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisExtent: tileHeight,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
          ),
          itemCount: pageItems.length,
          itemBuilder: (context, i) {
            final a = pageItems[i];
            return _ArticleTile(
              name: a.name,
              qty: qtyFor(a.code),
              onTap: () => onAdd(a.code),
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
            Icon(Icons.fastfood_outlined,
                size: 56, color: Theme.of(context).colorScheme.outline),
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
