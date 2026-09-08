import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../auth/state/session_provider.dart';
import '../../settings/models/menu_view_size.dart';
import '../../settings/state/settings_provider.dart';
import '../data/mqtt_order_sender.dart';
import '../models/mqtt_menu.dart';
import '../state/mqtt_cart.dart';
import '../state/mqtt_menu_provider.dart';
import '../state/mqtt_orders_provider.dart';
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
    setState(() => _sending = false);

    if (result.isOk) {
      // Accepted — drop the local order for this table.
      orders.clear(broj);
      _cart.clear();
    } else if (result.needsNewMsgId) {
      // Expired / never sent: the next attempt must be a NEW order.
      _cart.pendingMsgId = null;
      orders.save(broj, _cart.lines, null);
    } else {
      // Rejected or unreachable — keep the id so an unchanged retry stays
      // idempotent (editing the cart clears it automatically).
      orders.save(broj, _cart.lines, msgId);
    }

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(result.message)));
    return result.isOk;
  }

  Future<void> _send() async {
    final ok = await _sendOrder();
    if (!mounted || !ok) return;
    if (context.canPop()) context.pop();
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
            ),
          ),
        )
        .then((result) {
          if (!mounted) return;
          // The order was sent from the details screen — leave the table entirely.
          if (result == 'sent') {
            if (context.canPop()) context.pop();
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
                                cart: _cart,
                                byCode: _byCode,
                                money: _money,
                                remarksFor: _remarksFor,
                              ),
                            ),
                            const SizedBox(width: 10),
                            _ActionColumn(
                              sending: _sending,
                              onClear: hasItems && !_sending
                                  ? _confirmClear
                                  : null,
                              onDetails: hasItems && !_sending
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
    );
  }
}

/// The running order as a card of compact lines (name, quantity, line total,
/// remove ✕). Each line is expandable — tapping the name / non-button area
/// reveals its napomene editor. Auto-scrolls to the newest line when added.
class _CartCard extends StatefulWidget {
  const _CartCard({
    required this.cart,
    required this.byCode,
    required this.money,
    required this.remarksFor,
  });

  final MqttCart cart;
  final Map<int, MqttArticle> byCode;
  final NumberFormat money;
  final List<MqttRemark> Function(int code) remarksFor;

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
                return _CartLineTile(
                  key: ValueKey('cartline_${line.code}_$i'),
                  index: i,
                  line: line,
                  cart: widget.cart,
                  name: article?.name ?? 'Artikl ${line.code}',
                  unit: article?.unit ?? '',
                  lineTotal: widget.money.format(
                    (article?.price ?? 0) * line.qty,
                  ),
                  available: widget.remarksFor(line.code),
                );
              },
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
    required this.onClear,
    required this.onDetails,
    required this.onSend,
  });

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
            child: busy
                ? Center(
                    child: SizedBox(
                      width: iconSize * 0.85,
                      height: iconSize * 0.85,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: fg,
                      ),
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
        onTap: onTap,
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
