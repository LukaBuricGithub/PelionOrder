import 'package:flutter/material.dart';
// `show` matters: intl also exports a `TextDirection` that would shadow
// Flutter's and break the text measurement below.
import 'package:intl/intl.dart' show NumberFormat;

import '../models/mqtt_menu.dart';
import '../state/mqtt_pending_transfers_provider.dart';
import '../state/mqtt_table_contents.dart';
import 'mqtt_qty_pad.dart' show formatQtyWithUnit;

/// Whether one of the table's existing lines has reached the kasa.
///
/// Deliberately only two states, answering the one question a waiter can act
/// on: "did my order get there?". The kasa also reports whether a line has gone
/// on to the kitchen/bar, but that is a second journey, it can't be acted on
/// from the phone (these lines are read-only), and showing it as a third tag
/// made the whole scheme confusing.
enum MqttExistingStatus {
  /// On its way from the phone to the kasa. Shown as "Šalje se".
  naPutu,

  /// The kasa has it. Shown as "Poslano" — but the value is deliberately NOT
  /// named `poslano`: on the kasa that word means "sent on to the kitchen/bar"
  /// (`MqttRacunStavka.poslano`), a different stage this tag does not show.
  zaprimljeno,
}

/// Colour, label and icon for [status] — exactly the floor plan's badges
/// (amber ↑ still going, green ✓ arrived), so the list and the floor plan speak
/// one language and a waiter who reads one can read the other.
///
/// The labels follow the waiter's own button — "Pošalji narudžbu" → "Šalje se"
/// → "Poslano" — so each tag describes the action they took.
(Color, String, IconData) mqttExistingStatusStyle(
  MqttExistingStatus status,
  bool dark,
) =>
    switch (status) {
      MqttExistingStatus.naPutu => (
          dark ? const Color(0xFFF4A83A) : const Color(0xFFE8890C),
          'Šalje se',
          Icons.arrow_upward,
        ),
      MqttExistingStatus.zaprimljeno => (
          dark ? const Color(0xFF4FC98A) : const Color(0xFF2E9E5B),
          'Poslano',
          Icons.check,
        ),
    };

/// The notice for lines another device is still sending — the kasa reports
/// those only as a count. Croatian plural: 1 stavka, 2–4 stavke, 5+ stavki
/// (11–14 take the 5+ form).
String mqttOthersPendingText(int n) {
  final last = n % 10;
  final lastTwo = n % 100;
  final phrase = (last == 1 && lastTwo != 11)
      ? 'stavka se šalje'
      : (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14))
          ? 'stavke se šalju'
          : 'stavki se šalje';
  return '$n $phrase s drugog uređaja';
}

/// One existing line, flattened for display — whether it came from the kasa's
/// bill or from this phone's travelling copy.
class MqttExistingRow {
  const MqttExistingRow({
    required this.id,
    required this.name,
    required this.qty,
    required this.unit,
    required this.napomene,
    required this.amount,
    required this.status,
  });

  /// Identity for keying the row, so an expanded row stays expanded across the
  /// refreshes that happen while a transfer is pending — and a row that moves
  /// collapses rather than handing its expansion to a different line.
  final String id;
  final String name;
  final double qty;
  final String unit;

  /// Each napomena separately, so they can be shown as individual chips.
  final List<String> napomene;
  final double amount;
  final MqttExistingStatus status;
}

/// Everything already ordered for a table, ready to render above the new cart.
///
/// Display-only by construction: these rows are never cart lines, so they can
/// never be sent, cleared, reordered or grouped. Sending them again would book
/// every item on the table a second time — the kasa appends, it doesn't
/// reconcile.
class MqttExistingItems {
  const MqttExistingItems({
    required this.rows,
    required this.othersPending,
    required this.total,
    required this.loading,
    required this.awaiting,
    required this.placeholders,
    required this.error,
  });

  static const none = MqttExistingItems(
    rows: [],
    othersPending: 0,
    total: 0,
    loading: false,
    awaiting: false,
    placeholders: 0,
    error: null,
  );

  /// Past a screenful, more placeholder rows add nothing.
  static const maxPlaceholders = 6;

  /// Oldest first: what is on the table, then what is still travelling.
  final List<MqttExistingRow> rows;

  /// Lines still travelling from ANOTHER device. The kasa reports those only as
  /// a count, so they can't be listed as lines.
  final int othersPending;

  /// Value of the existing order: the kasa's own total for what is on the
  /// table, plus this phone's travelling lines.
  final double total;

  /// Show the loading row: the first answer is taking a while.
  final bool loading;

  /// Still waiting for the kasa's first answer — true from the moment the
  /// screen opens, before [loading] starts showing — so the order list can stay
  /// blank instead of briefly claiming "Nema stavki u narudžbi".
  final bool awaiting;

  /// Placeholder rows to show while [awaiting], so the list has its shape from
  /// the first frame — see [compute] for how many. 0 once the answer is in, and
  /// when the device has nothing to size them from.
  final int placeholders;

  /// The kasa couldn't be asked and there is no earlier answer to show.
  final String? error;

  bool get hasContent =>
      rows.isNotEmpty ||
      othersPending > 0 ||
      loading ||
      error != null ||
      placeholders > 0;

  factory MqttExistingItems.compute({
    required MqttTableContents? contents,
    required List<MqttInTransitOrder> inTransit,
    required Map<int, MqttArticle> byCode,
    required String Function(String cnap) remarkName,
    required String? od,
    // The kasa's own total for the table from stolovi_stanje, used until the
    // first query answer arrives.
    double? seedTotal,
    // The table's line count from stolovi_stanje (`stavki`), used to size the
    // placeholder rows until the first query answer arrives.
    int? seedLineCount,
  }) {
    if (contents == null && inTransit.isEmpty) return none;
    final reply = contents?.reply;

    // If the latest answer already shows our lines on the table, the travelling
    // copies are stale — drop them here rather than wait for the watcher to
    // catch up, or the same items would show twice for a moment.
    final landed = reply != null &&
        MqttPendingTransfersNotifier.transferLanded(reply, od);
    final travelling = landed ? const <MqttInTransitOrder>[] : inTransit;

    // Still waiting for the kasa's first answer.
    final awaiting =
        contents != null && reply == null && contents.error == null;

    // Placeholders for that wait, as many as the device already expects: the
    // lines the kasa lists on the table plus our own travelling lines — so the
    // real rows replace them in roughly the same space. Never 0 for a table the
    // kasa lists as occupied; nothing to size them from otherwise.
    var placeholders = 0;
    if (awaiting && seedLineCount != null) {
      final travellingLines =
          travelling.fold<int>(0, (n, o) => n + o.lines.length);
      placeholders =
          (seedLineCount + travellingLines).clamp(1, maxPlaceholders);
    }

    final rows = <MqttExistingRow>[];
    var total = 0.0;

    // What is already on the table, exactly as the kasa booked it...
    if (reply != null) {
      final stavke = reply.sveStavke;
      for (var i = 0; i < stavke.length; i++) {
        final st = stavke[i];
        rows.add(MqttExistingRow(
          // The kasa appends new lines, so an earlier line keeps its position.
          id: 't${st.cartikl}_$i',
          name: st.naziv.isNotEmpty
              ? st.naziv
              : (byCode[st.cartikl]?.name ?? 'Artikl ${st.cartikl}'),
          qty: st.kol,
          unit: byCode[st.cartikl]?.unit ?? '',
          // The kasa joins napomene with ';'. Our own custom notes can never
          // contain one — they are sanitised before sending — so splitting on
          // it recovers the individual napomene.
          napomene: st.napomena
              .split(';')
              .map((p) => p.trim())
              .where((p) => p.isNotEmpty)
              .toList(),
          amount: st.iznos,
          // On the table means the kasa has it. Whether the kitchen/bar has
          // picked it up (`poslano`) is deliberately not shown — see
          // [MqttExistingStatus].
          status: MqttExistingStatus.zaprimljeno,
        ));
      }
      total += reply.ukupno;
    } else if (seedTotal != null) {
      // No answer yet: use the total the device already holds, so Ukupno is
      // right from the first frame instead of jumping when the answer lands.
      total += seedTotal;
    }

    // ...then what this phone sent that has not landed yet.
    var ourPending = 0;
    for (final order in travelling) {
      ourPending += order.sentLineCount;
      for (var j = 0; j < order.lines.length; j++) {
        final l = order.lines[j];
        final a = byCode[l.code];
        final amount = (a?.price ?? 0) * l.qty;
        rows.add(MqttExistingRow(
          id: 'p${order.msgId}_$j',
          name: a?.name ?? 'Artikl ${l.code}',
          qty: l.qty,
          unit: a?.unit ?? '',
          napomene: [...l.remarkCodes.map(remarkName), ...l.customNotes],
          amount: amount,
          status: MqttExistingStatus.naPutu,
        ));
        total += amount;
      }
    }

    final others = reply == null ? 0 : reply.naCekanju - ourPending;

    return MqttExistingItems(
      rows: rows,
      othersPending: others > 0 ? others : 0,
      total: total,
      loading: reply == null && (contents?.showLoading ?? false),
      awaiting: awaiting,
      placeholders: placeholders,
      error: reply == null ? contents?.error : null,
    );
  }
}

/// A read-only existing line: name and status tag, then quantity, napomene and
/// amount — all visible, none editable. There is no ✕ and no button behind the
/// quantity or the napomene.
///
/// Napomene never disappear silently. In [compact] mode (Stol X's narrow cart)
/// they sit on one line and a "+N" names however many didn't fit; tapping the
/// row expands it in place to show them all. Otherwise (the details screen)
/// every napomena is shown, wrapped.
class MqttExistingItemTile extends StatefulWidget {
  const MqttExistingItemTile({
    super.key,
    required this.row,
    required this.money,
    required this.scale,
    this.compact = true,
  });

  final MqttExistingRow row;
  final NumberFormat money;
  final double scale;
  final bool compact;

  @override
  State<MqttExistingItemTile> createState() => _MqttExistingItemTileState();
}

class _MqttExistingItemTileState extends State<MqttExistingItemTile> {
  bool _expanded = false;

  /// Rendered width of [text] — measured with the same text scaler the row's
  /// Text widgets use, or the measurement and the real layout would disagree.
  double _textWidth(BuildContext context, String text, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = tp.width;
    tp.dispose();
    return width;
  }

  /// How many napomene fit on one line in [avail], leaving room for the "+N"
  /// that names the rest. At least one is always shown, ellipsized if it must.
  int _fitCount(
    BuildContext context,
    List<String> notes,
    double avail,
    TextStyle noteStyle,
    TextStyle moreStyle,
  ) {
    final n = notes.length;
    for (var k = n; k > 1; k--) {
      final more = k < n ? _textWidth(context, '  +${n - k}', moreStyle) : 0.0;
      final shown = _textWidth(context, notes.take(k).join(', '), noteStyle);
      if (shown + more <= avail) return k;
    }
    return n == 0 ? 0 : 1;
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (color, label, icon) = mqttExistingStatusStyle(row.status, dark);
    final tagFg = dark ? const Color(0xFF10151C) : Colors.white;
    final s = widget.scale;
    final notes = row.napomene;

    final qtyStyle = TextStyle(fontSize: 13 * s, fontWeight: FontWeight.w600);
    final noteStyle = TextStyle(
      fontSize: 12 * s,
      fontStyle: FontStyle.italic,
      color: scheme.onSurfaceVariant,
    );
    final moreStyle = TextStyle(
      fontSize: 12 * s,
      fontWeight: FontWeight.w700,
      color: scheme.onSurface,
    );
    final qtyText = formatQtyWithUnit(row.qty, row.unit);
    final amountText = widget.money.format(row.amount);

    return LayoutBuilder(
      builder: (context, c) {
        // Width left for napomene between the quantity and the amount.
        final avail = c.maxWidth -
            (12 + 10) * s - // tile padding
            _textWidth(context, qtyText, qtyStyle) -
            (10 + 8) * s - // gaps either side of the napomene
            _textWidth(context, amountText, qtyStyle);

        // Every napomena as chips: always on the details screen, and in the
        // cart once the row has been expanded.
        final showAll = !widget.compact || _expanded;
        final shown = showAll
            ? notes.length
            : _fitCount(context, notes, avail, noteStyle, moreStyle);
        final hidden = notes.length - shown;
        final canToggle = widget.compact && (hidden > 0 || _expanded);

        Widget tile = Container(
          // A light wash of the status colour: readable at a glance without
          // turning the list into a traffic light.
          color: color.withValues(alpha: dark ? 0.16 : 0.09),
          padding: EdgeInsets.fromLTRB(12 * s, 7 * s, 10 * s, 8 * s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      row.name,
                      style: TextStyle(
                        fontSize: 14 * s,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SizedBox(width: 8 * s),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 7 * s,
                      vertical: 2 * s,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(6 * s),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 12 * s, color: tagFg),
                        SizedBox(width: 3 * s),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 10.5 * s,
                            fontWeight: FontWeight.w700,
                            color: tagFg,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4 * s),
              Row(
                children: [
                  Text(qtyText, style: qtyStyle),
                  SizedBox(width: 10 * s),
                  Expanded(
                    child: showAll || notes.isEmpty
                        // Expanded in the cart: a small cue that a tap folds
                        // the row back up. Nothing at all on the details screen.
                        ? (canToggle
                            ? Align(
                                alignment: Alignment.centerLeft,
                                child: Icon(
                                  Icons.expand_less,
                                  size: 16 * s,
                                  color: scheme.onSurfaceVariant,
                                ),
                              )
                            : const SizedBox.shrink())
                        : Row(
                            children: [
                              Flexible(
                                child: Text(
                                  notes.take(shown).join(', '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: noteStyle,
                                ),
                              ),
                              // Kept outside the ellipsized text, so the count of
                              // what's hidden can never itself be cut off.
                              if (hidden > 0) Text('  +$hidden', style: moreStyle),
                            ],
                          ),
                  ),
                  SizedBox(width: 8 * s),
                  Text(amountText, style: qtyStyle),
                ],
              ),
              if (showAll && notes.isNotEmpty) ...[
                SizedBox(height: 6 * s),
                Wrap(
                  spacing: 6 * s,
                  runSpacing: 5 * s,
                  children: [
                    for (final note in notes) _NoteChip(text: note, scale: s),
                  ],
                ),
              ],
            ],
          ),
        );

        if (canToggle) {
          tile = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: tile,
          );
        }
        return tile;
      },
    );
  }
}

/// One napomena, read-only.
class _NoteChip extends StatelessWidget {
  const _NoteChip({required this.text, required this.scale});

  final String text;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = scale;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 3 * s),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8 * s),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12 * s, color: scheme.onSurface),
      ),
    );
  }
}

/// A one-line status row in the existing section: loading, kasa unreachable, or
/// lines travelling from another device.
class MqttExistingNoticeTile extends StatelessWidget {
  const MqttExistingNoticeTile({
    super.key,
    required this.text,
    required this.scale,
    this.icon,
    this.color,
    this.busy = false,
    this.onTap,
  });

  final String text;
  final double scale;
  final IconData? icon;
  final Color? color;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = scale;
    final tint = color;

    Widget body = Container(
      color: tint?.withValues(alpha: 0.10),
      padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 10 * s),
      child: Row(
        children: [
          if (busy)
            SizedBox(
              width: 14 * s,
              height: 14 * s,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.onSurfaceVariant,
              ),
            )
          else if (icon != null)
            Icon(icon, size: 16 * s, color: tint ?? scheme.onSurfaceVariant),
          if (busy || icon != null) SizedBox(width: 8 * s),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5 * s,
                fontWeight: FontWeight.w500,
                color:
                    tint == null ? scheme.onSurfaceVariant : scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap != null) body = InkWell(onTap: onTap, child: body);
    return body;
  }
}

/// A stand-in for an existing line while the kasa's first answer is on its way:
/// the same padding and the same two rows as [MqttExistingItemTile], drawn as
/// soft bars that gently pulse. The list has its shape from the first frame, and
/// the real rows take the space the placeholders already held.
class MqttExistingSkeletonTile extends StatefulWidget {
  const MqttExistingSkeletonTile({
    super.key,
    required this.index,
    required this.scale,
  });

  /// Position among the placeholders — varies the name bar's width, so the
  /// rows don't look stamped out.
  final int index;
  final double scale;

  @override
  State<MqttExistingSkeletonTile> createState() =>
      _MqttExistingSkeletonTileState();
}

class _MqttExistingSkeletonTileState extends State<MqttExistingSkeletonTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat(reverse: true);

  late final Animation<double> _opacity = Tween<double>(begin: 0.45, end: 1)
      .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

  static const _nameWidths = [0.62, 0.46, 0.7, 0.54, 0.66, 0.5];

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s = widget.scale;
    final fill = scheme.onSurface.withValues(alpha: dark ? 0.13 : 0.08);

    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(4 * s),
          ),
        );

    return FadeTransition(
      opacity: _opacity,
      child: Padding(
        // Same padding as a real row, so swapping one for the other keeps the
        // list where it is.
        padding: EdgeInsets.fromLTRB(12 * s, 7 * s, 10 * s, 8 * s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Name + status tag.
            SizedBox(
              height: 18 * s,
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor:
                            _nameWidths[widget.index % _nameWidths.length],
                        child: bar(double.infinity, 12 * s),
                      ),
                    ),
                  ),
                  SizedBox(width: 8 * s),
                  bar(58 * s, 16 * s),
                ],
              ),
            ),
            SizedBox(height: 4 * s),
            // Quantity … amount.
            SizedBox(
              height: 16 * s,
              child: Row(
                children: [
                  bar(40 * s, 11 * s),
                  const Spacer(),
                  bar(52 * s, 11 * s),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fades a row in — rising a few pixels into place — the first time it is
/// built, after an optional [delay] (how a list cascades in, row by row).
///
/// With [enabled] false the row simply appears. The widget structure is the
/// same either way, and only the first build decides, so neither flag ever
/// resets the row's own state (an expanded napomene list, for one).
class MqttFadeIn extends StatefulWidget {
  const MqttFadeIn({
    super.key,
    required this.child,
    this.enabled = true,
    this.delay = Duration.zero,
  });

  final Widget child;
  final bool enabled;
  final Duration delay;

  static const duration = Duration(milliseconds: 260);

  @override
  State<MqttFadeIn> createState() => _MqttFadeInState();
}

class _MqttFadeInState extends State<MqttFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    // One controller covering delay + animation: the delay is the silent start
    // of an Interval, so there is no timer to cancel.
    final total = widget.delay + MqttFadeIn.duration;
    _controller = AnimationController(
      vsync: this,
      duration: total,
      value: widget.enabled ? 0 : 1,
    );
    _t = CurvedAnimation(
      parent: _controller,
      curve: Interval(
        widget.delay.inMicroseconds / total.inMicroseconds,
        1,
        curve: Curves.easeOutCubic,
      ),
    );
    if (widget.enabled) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) {
        final v = _t.value;
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, (1 - v) * 10),
            child: child,
          ),
        );
      },
    );
  }
}

/// The existing-order block of a list, animated so nothing in it just pops:
///
/// * while [showPlaceholders], it shows [placeholders];
/// * when the kasa answers, the placeholders clear and [items] cascade in, one
///   row after another;
/// * an item that turns up later — a colleague's line landing, ours moving from
///   "Šalje se" to "Poslano" — fades in on its own;
/// * every change of height is animated, so whatever sits below it (the new
///   lines) slides down instead of jumping.
class MqttExistingSection extends StatefulWidget {
  const MqttExistingSection({
    super.key,
    required this.showPlaceholders,
    required this.placeholders,
    required this.items,
    this.separator,
  });

  final bool showPlaceholders;

  /// Keyed widgets, so a loading line appearing above them doesn't rebuild the
  /// placeholders and restart their pulse.
  final List<Widget> placeholders;

  /// Each item with a stable id — that id is what decides whether it is new.
  final List<(String, Widget)> items;

  /// Drawn between entries (the cart's dividers). None on the details screen,
  /// whose cards space themselves.
  final Widget? separator;

  /// Gap between one row starting its fade-in and the next, for a cascade of
  /// [count] rows. Every row gets its turn — no cap — so a list that scrolls
  /// along with the cascade always has a row arriving at the bottom. A short
  /// order lists at an easy pace; a long one speeds up so the whole listing
  /// stays around a second.
  static Duration cascadeStepFor(int count) => Duration(
        microseconds: (_cascadeBudget.inMicroseconds / (count < 1 ? 1 : count))
            .clamp(22000, 55000)
            .round(),
      );

  static const _cascadeBudget = Duration(milliseconds: 900);

  @override
  State<MqttExistingSection> createState() => _MqttExistingSectionState();
}

class _MqttExistingSectionState extends State<MqttExistingSection> {
  static const _duration = Duration(milliseconds: 240);

  static const _itemsKey = ValueKey('items');

  /// Placeholders have been on screen — so the rows that replace them cascade
  /// in, rather than having simply been there from the start.
  bool _hadPlaceholders = false;

  /// Ids present when the items were first shown, with their position. Those
  /// cascade in if they replaced placeholders and otherwise just appear; an id
  /// outside this map is a later arrival and fades in on its own.
  Map<String, int>? _initial;

  List<Widget> _join(List<Widget> children) {
    final separator = widget.separator;
    if (separator == null) return children;
    return [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) separator,
        children[i],
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (widget.showPlaceholders) {
      _hadPlaceholders = true;
      body = Column(
        key: const ValueKey('placeholders'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: _join(widget.placeholders),
      );
    } else {
      final items = widget.items;
      final initial = _initial ??= {
        for (var i = 0; i < items.length; i++) items[i].$1: i,
      };
      final separator = widget.separator;
      body = Column(
        key: _itemsKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++)
            MqttFadeIn(
              key: ValueKey(items[i].$1),
              enabled: _hadPlaceholders || !initial.containsKey(items[i].$1),
              delay: _hadPlaceholders && initial.containsKey(items[i].$1)
                  ? MqttExistingSection.cascadeStepFor(initial.length) *
                      initial[items[i].$1]!
                  : Duration.zero,
              // The divider travels with the row below it, so a line never
              // shows up ahead of the row it belongs to.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (i > 0 && separator != null) separator,
                  items[i].$2,
                ],
              ),
            ),
        ],
      );
    }

    return AnimatedSize(
      duration: _duration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: _duration,
        // The placeholders clear quickly, so the rows cascading in over them
        // are never muddled with the bars underneath.
        reverseDuration: const Duration(milliseconds: 160),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        // The rows bring their own cascade; fading their column in as well would
        // wash the first rows out. Only what leaves (the placeholders) fades.
        transitionBuilder: (child, animation) => child.key == _itemsKey
            ? child
            : FadeTransition(opacity: animation, child: child),
        // Top-aligned (the default centres), so the placeholders and the rows
        // overlap from the first line down.
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [
            ...previous,
            ?current,
          ],
        ),
        child: body,
      ),
    );
  }
}

/// A small caption separating the existing order from the lines being added.
class MqttOrderSectionLabel extends StatelessWidget {
  const MqttOrderSectionLabel({
    super.key,
    required this.text,
    required this.scale,
    this.horizontalPadding = 12,
  });

  final String text;
  final double scale;

  /// Unscaled; the details screen's list already pads its content.
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding * scale,
        8 * scale,
        horizontalPadding * scale,
        4 * scale,
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11 * scale,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
