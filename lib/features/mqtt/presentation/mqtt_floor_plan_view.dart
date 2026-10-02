import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/mqtt_floor_plan.dart';
import '../models/mqtt_tables.dart';
import 'table_status.dart';

/// Draws one terrace's own floor plan (`podaci/tlocrt`) instead of the generic
/// grid: the room as the venue drew it on the kasa, with the tables in their
/// real places.
///
/// The plan keeps the kasa's proportions (one square cell, never stretched to
/// the screen) and is explored by dragging and pinching — on a 64 × 39 plan a
/// 4 × 4 table is only about 26 dp wide when the whole room is on screen,
/// which is under the 48 dp a finger needs.
///
/// Colours follow the kasa's own palette, so a table means the same thing to
/// the waiter here as it does on the till.
class MqttFloorPlanView extends StatefulWidget {
  const MqttFloorPlanView({
    super.key,
    required this.doc,
    required this.tables,
    required this.facts,
    required this.canOpenAll,
    required this.opening,
    required this.onTapTable,
  });

  final TlocrtDoc doc;

  /// The zone's tables by number, for their names. A table drawn on the plan
  /// but missing here is still drawn and still opens — it just shows no name.
  final Map<int, MqttTable> tables;

  final MqttTableFacts facts;

  /// Whether this waiter holds pravo 008 (may open colleagues' tables) — the
  /// lock / eye in a table's top corner.
  final bool canOpenAll;

  /// The table whose lock is being asked for right now: it gets a ring, and
  /// every other table stops reacting until the kasa answers.
  final int? opening;

  final void Function(MqttTable table, TableTileStatus status, String? occupant)
  onTapTable;

  @override
  State<MqttFloorPlanView> createState() => _MqttFloorPlanViewState();
}

class _MqttFloorPlanViewState extends State<MqttFloorPlanView> {
  final _controller = TransformationController();

  /// The current pinch zoom, 1 being the fitted view. Rounded before it is
  /// stored, so a pinch repaints the plan a handful of times rather than on
  /// every pixel.
  double _scale = 1;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransform);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransform);
    _controller.dispose();
    super.dispose();
  }

  void _onTransform() {
    final next =
        (_controller.value.getMaxScaleOnAxis() * 20).roundToDouble() / 20;
    if (next != _scale) setState(() => _scale = next);
  }

  void _handleTap(Offset local, double cell) {
    if (widget.opening != null) return; // one table at a time
    final cx = (local.dx / cell).floor();
    final cy = (local.dy / cell).floor();
    if (cx < 0 || cy < 0 || cx >= widget.doc.cols || cy >= widget.doc.rows) {
      return;
    }
    // Last drawn wins, so the table on top is the one that is hit. The whole
    // frame is active, round tables included.
    for (final o in widget.doc.objects.reversed) {
      if (!o.isTable || o.table == null) continue;
      if (!o.contains(cx, cy)) continue;
      final broj = o.table!;
      final table = widget.tables[broj] ?? MqttTable(broj: broj, naziv: '');
      widget.onTapTable(
        table,
        widget.facts.statusFor(broj),
        widget.facts.occupantFor(broj),
      );
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // The height decides everything: the whole depth of the room is on
        // screen at once and stays there, and the plan is only ever as wide as
        // that makes it. Square cells, so the room keeps the shape the venue
        // drew — the kasa sizes each axis separately and may stretch it.
        final cell = c.maxHeight / widget.doc.rows;
        final width = cell * widget.doc.cols;
        final height = c.maxHeight;
        // A room wider than the screen is walked along sideways; one that fits
        // doesn't move at all.
        final scrolls = width > c.maxWidth;
        // What a table can hold follows the size a cell actually has on the
        // glass, not the zoom factor: a shallow room is already drawn large at
        // the fitted view, and a deep one stays small until it is zoomed.
        final detail = _Detail.forCell(cell * _scale);
        // Zoomed out, the whole depth of the room is on screen, so up and down
        // have nowhere to go and are locked. Zoomed in they are needed again.
        final zoomed = _scale > 1.01;

        return ClipRect(
          child: InteractiveViewer(
            transformationController: _controller,
            // `false`: the plan keeps its own width instead of being squeezed
            // into the screen, and sits at the left edge — the room starts
            // where the screen starts.
            constrained: false,
            // Zoomed out is the fitted view, so the depth of the room can
            // never be scrolled away from.
            minScale: 1,
            maxScale: 4,
            // No slack: the plan cannot be dragged off its own edges, which is
            // what made it feel loose.
            boundaryMargin: EdgeInsets.zero,
            // Left and right only while the whole height is on screen. Zoomed
            // in there is more room than fits vertically too, so the lock is
            // lifted — otherwise the bottom of the room would be unreachable.
            panAxis: zoomed ? PanAxis.free : PanAxis.horizontal,
            panEnabled: scrolls || zoomed,
            child: SizedBox(
              width: width,
              height: height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Inside the viewer, so the position is already in plan
                // coordinates — no need to undo pan and zoom by hand.
                onTapUp: (d) => _handleTap(d.localPosition, cell),
                child: Stack(
                  children: [
                    // The room never changes while the waiter works; only
                    // the tables do. Kept apart so a new occupancy repaints
                    // the tables alone.
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _RoomPainter(doc: widget.doc, cell: cell),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _TablesPainter(
                          doc: widget.doc,
                          cell: cell,
                          tables: widget.tables,
                          facts: widget.facts,
                          canOpenAll: widget.canOpenAll,
                          opening: widget.opening,
                          detail: detail,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// What fits inside a table's body at the size a cell currently has on screen.
/// A 3 × 3 table's body is a little under two cells wide, so a cell of 14 dp
/// leaves roughly 25 dp for a name — enough for a short one — and 22 dp leaves
/// room for the amount under it.
enum _Detail {
  number,
  withName,
  withAmount;

  static _Detail forCell(double cell) {
    if (cell >= 22) return _Detail.withAmount;
    if (cell >= 14) return _Detail.withName;
    return _Detail.number;
  }
}

// ── The room: floor, walls, bar, decor, labels and seating ────────────────
// Colours are the kasa's (tlocrt-mobitel.md §4), so the plan is recognisably
// the same room the manager drew on the till.
const _kCellColors = <String, Color>{
  'zid': Color(0xFF969696),
  'vrata': Color(0xFFBE965A),
  'sank': Color(0xFF78502D),
  'iza_sanka': Color(0xFF46372D),
  'sanitarije': Color(0xFF3C556E),
  'vani': Color(0xFF2D4B2D),
};

class _RoomPainter extends CustomPainter {
  const _RoomPainter({required this.doc, required this.cell});

  final TlocrtDoc doc;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = doc.background);

    final paint = Paint()..style = PaintingStyle.fill;
    for (var y = 0; y < doc.rows; y++) {
      for (var x = 0; x < doc.cols; x++) {
        final color = _kCellColors[doc.cellType(x, y)];
        if (color == null) continue; // pod → the background already covers it
        paint.color = color;
        canvas.drawRect(
          Rect.fromLTWH(x * cell, y * cell, cell + 0.5, cell + 0.5),
          paint,
        );
      }
    }

    // A grid discreet enough to give the room a sense of scale without
    // turning a zoomed-out plan into a mesh.
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 0.5;
    for (var x = 1; x < doc.cols; x++) {
      canvas.drawLine(
        Offset(x * cell, 0),
        Offset(x * cell, doc.rows * cell),
        grid,
      );
    }
    for (var y = 1; y < doc.rows; y++) {
      canvas.drawLine(
        Offset(0, y * cell),
        Offset(doc.cols * cell, y * cell),
        grid,
      );
    }

    for (final o in doc.objects) {
      switch (o.type) {
        case 'dekor':
          _paintDecor(canvas, o);
        case 'tekst':
          _paintText(
            canvas,
            o.text,
            _frameOf(o),
            const Color(0xFFD0D0D0),
            maxHeight: 0.8,
          );
        case 'stol':
          _paintSeats(canvas, o);
      }
    }
  }

  Rect _frameOf(TlocrtObject o) =>
      Rect.fromLTWH(o.x * cell, o.y * cell, o.w * cell, o.h * cell);

  void _paintDecor(Canvas canvas, TlocrtObject o) {
    final frame = _frameOf(o).deflate(cell * 0.15);
    final body = Paint()..color = const Color(0xFF3A3A3A);
    switch (o.icon) {
      case 'biljka':
        body.color = const Color(0xFF2F4F2F);
        canvas.drawOval(frame, body);
      case 'stup':
        body.color = const Color(0xFF5A5A5A);
        canvas.drawRect(frame, body);
      case 'kasa':
        body.color = const Color(0xFF4A4A6A);
        canvas.drawRRect(
          RRect.fromRectAndRadius(frame, Radius.circular(cell * 0.2)),
          body,
        );
      default:
        canvas.drawRRect(
          RRect.fromRectAndRadius(frame, Radius.circular(cell * 0.2)),
          body,
        );
        _paintText(canvas, o.icon, frame, const Color(0xFFBBBBBB));
    }
  }

  /// Chairs, drawn only where the kasa draws them: a table with seats that is
  /// at least 3 × 3 cells. They sit in the frame's margin, which is why a
  /// seated table's body is inset further.
  void _paintSeats(Canvas canvas, TlocrtObject o) {
    if (o.seats <= 0 || o.w < 3 || o.h < 3) return;
    final frame = _frameOf(o);
    final paint = Paint()..color = const Color(0xFF6B6B6B);
    final seat = cell * 0.5;
    final radius = Radius.circular(seat * 0.3);
    // Spread around the frame: top, bottom, left, right in turn, so four
    // seats land one per side and two land opposite each other.
    for (var i = 0; i < o.seats; i++) {
      final side = i % 4;
      final index = i ~/ 4 + 1;
      final along = index / (o.seats ~/ 4 + 2);
      late Offset center;
      switch (side) {
        case 0:
          center = Offset(frame.left + frame.width * along, frame.top + seat);
        case 1:
          center = Offset(
            frame.left + frame.width * along,
            frame.bottom - seat,
          );
        case 2:
          center = Offset(frame.left + seat, frame.top + frame.height * along);
        default:
          center = Offset(frame.right - seat, frame.top + frame.height * along);
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: seat, height: seat),
          radius,
        ),
        paint,
      );
    }
  }

  void _paintText(
    Canvas canvas,
    String text,
    Rect frame,
    Color color, {
    double maxHeight = 1,
  }) {
    if (text.isEmpty) return;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: cell * 0.9,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: frame.width);
    // Shrink to fit rather than clip: a label the venue typed is worth
    // reading, even in a narrow frame.
    final scale = math.min(
      1.0,
      math.min(
        frame.width / math.max(painter.width, 1),
        frame.height * maxHeight / math.max(painter.height, 1),
      ),
    );
    canvas.save();
    canvas.translate(frame.center.dx, frame.center.dy);
    canvas.scale(scale);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RoomPainter old) => old.doc != doc || old.cell != cell;
}

// ── The tables: the only part that changes while the waiter works ─────────
// The SAME colours as the grid's tiles, deliberately not the kasa's palette:
// a waiter switching between the two views must not have to re-learn what red
// means. Red is "another waiter holds this", teal "yours", blue "typed here,
// not sent", neutral "free" — and the corner icon, not the colour, says
// whether a red table blocks you (lock) or merely warns you (eye).
const _kOtherColor = Color(0xFFD46A5A);
const _kMineColor = Color(0xFF3E8E7E);
const _kDraftColor = Color(0xFF4A78B4);
const _kFreeDark = Color(0xFF3A4756);
const _kFreeDarkFg = Color(0xFFC9D3DE);
const _kFreeLight = Color(0xFFD8DEE4);
const _kFreeLightFg = Color(0xFF37424E);

class _TablesPainter extends CustomPainter {
  const _TablesPainter({
    required this.doc,
    required this.cell,
    required this.tables,
    required this.facts,
    required this.canOpenAll,
    required this.opening,
    required this.detail,
  });

  final TlocrtDoc doc;
  final double cell;
  final Map<int, MqttTable> tables;
  final MqttTableFacts facts;

  /// Pravo 008 — decides whether a colleague's table shows a lock or an eye,
  /// exactly as on the grid.
  final bool canOpenAll;

  final int? opening;
  final _Detail detail;

  @override
  void paint(Canvas canvas, Size size) {
    for (final o in doc.objects) {
      if (!o.isTable || o.table == null) continue;
      _paintTable(canvas, o, o.table!);
    }
  }

  void _paintTable(Canvas canvas, TlocrtObject o, int broj) {
    final frame = Rect.fromLTWH(o.x * cell, o.y * cell, o.w * cell, o.h * cell);
    // Seats live in the frame's margin, so a seated table's body is inset
    // further than a bare one (§4).
    final inset = cell * (o.seats > 0 && o.w >= 3 && o.h >= 3 ? 0.6 : 0.15);
    final body = frame.deflate(inset);
    if (body.isEmpty) return;

    final status = facts.statusFor(broj);
    final locked = facts.isLocked(broj);
    // The floor is the venue's own colour, so which "free" tone reads on it
    // follows the floor rather than the app's theme.
    final darkFloor = doc.background.computeLuminance() < 0.5;
    final (Color color, Color fg, IconData? corner) = switch (status) {
      // Red always means "another waiter holds this" — the icon says whether
      // that BLOCKS you: a lock without pravo 008, an eye with it. A locked
      // table can't be entered from a phone by anyone, pravo 008 included.
      TableTileStatus.occupiedOther => (
        _kOtherColor,
        Colors.white,
        locked || !canOpenAll ? Icons.lock : Icons.visibility,
      ),
      TableTileStatus.occupiedMine => (
        _kMineColor,
        Colors.white,
        Icons.visibility,
      ),
      TableTileStatus.order => (_kDraftColor, Colors.white, null),
      TableTileStatus.free =>
        darkFloor
            ? (_kFreeDark, _kFreeDarkFg, null)
            : (_kFreeLight, _kFreeLightFg, null),
    };

    final fill = Paint()..color = color;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, cell * 0.08)
      ..color = Colors.black.withValues(alpha: 0.45);

    if (o.shape == 'O') {
      canvas.drawOval(body, fill);
      canvas.drawOval(body, edge);
    } else {
      final r = RRect.fromRectAndRadius(body, Radius.circular(cell * 0.35));
      canvas.drawRRect(r, fill);
      canvas.drawRRect(r, edge);
    }

    // The table the kasa is being asked about: a ring, so it is obvious which
    // one the wait belongs to.
    if (opening == broj) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          body.inflate(cell * 0.18),
          Radius.circular(cell * 0.5),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, cell * 0.12)
          ..color = Colors.white,
      );
    }

    _paintLabel(canvas, body, broj, fg);
    // Top right: may you go in (lock / eye) — the same question the grid's
    // corner icon answers. Bottom right: where the order is on its journey,
    // so the two never compete for the same pixels.
    final r = math.max(3.0, body.shortestSide * 0.18);
    if (corner != null) {
      _paintCorner(
        canvas,
        Offset(body.right - r * 0.8, body.top + r * 0.8),
        r,
        const Color(0xCC1B2430),
        Colors.white,
        corner,
      );
    }
    _paintMark(canvas, body, r, facts.markFor(broj));
  }

  /// The number always; the name and then the amount as the zoom makes room.
  /// [onColor] is the status's own foreground, the same pairing the grid uses.
  void _paintLabel(Canvas canvas, Rect body, int broj, Color onColor) {
    final lines = <String>['$broj'];
    if (detail != _Detail.number) {
      final naziv = tables[broj]?.naziv.trim() ?? '';
      if (naziv.isNotEmpty) lines.add(naziv);
    }
    if (detail == _Detail.withAmount) {
      final iznos = facts.occupied[broj]?.iznos;
      if (iznos != null && iznos > 0) lines.add(iznos.toStringAsFixed(2));
    }

    final painter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: lines.first,
            style: TextStyle(
              color: onColor,
              fontSize: cell * 1.1,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          for (final line in lines.skip(1))
            TextSpan(
              text: '\n$line',
              style: TextStyle(
                color: onColor,
                fontSize: cell * 0.75,
                fontWeight: FontWeight.w500,
                height: 1.15,
              ),
            ),
        ],
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: lines.length,
      ellipsis: '…',
    )..layout(maxWidth: body.width);

    final scale = math.min(
      1.0,
      math.min(
        body.width / math.max(painter.width, 1),
        body.height / math.max(painter.height, 1),
      ),
    );
    canvas.save();
    canvas.translate(body.center.dx, body.center.dy);
    canvas.scale(scale);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }

  /// The same answer the grid's corner badge gives — where is the order on its
  /// journey — in the same colours and with the same three glyphs (! / ↑ / ✓).
  ///
  /// The shape carries the meaning as well as the colour does, which matters
  /// both at a glance and for anyone who reads those hues as similar. Where a
  /// table is drawn too small for a glyph to be anything but a smudge, the
  /// badge stays a plain dot and the colour carries it alone.
  void _paintMark(Canvas canvas, Rect body, double r, TableSendMark mark) {
    // The plan is always drawn on the kasa's dark floor, so these are the
    // dark-theme variants of the grid's badge colours.
    final (Color fill, IconData? icon, Color glyph) = switch (mark) {
      TableSendMark.unsent => (
        const Color(0xFFFF7B72),
        Icons.priority_high,
        const Color(0xFF3A0B08),
      ),
      TableSendMark.pending => (
        const Color(0xFFF4A83A),
        Icons.arrow_upward,
        const Color(0xFF3A2600),
      ),
      TableSendMark.sent => (
        const Color(0xFF4FC98A),
        Icons.check,
        const Color(0xFF063020),
      ),
      TableSendMark.none => (Colors.transparent, null, Colors.transparent),
    };
    if (icon == null) return;
    // Bottom right, opposite the lock/eye.
    _paintCorner(
      canvas,
      Offset(body.right - r * 0.8, body.bottom - r * 0.8),
      r,
      fill,
      glyph,
      icon,
    );
  }

  /// One corner marker: a disc ringed in the floor's colour so it reads as
  /// separate from the table under it, whatever colour that table is.
  ///
  /// The size is tied to the TABLE rather than to the cell, so a marker stays
  /// in proportion on a big table and never swallows a small one. Below about
  /// 5.5 the glyph would be a smudge, so the disc is left to carry the meaning
  /// on its own — which is why colour and shape always say the same thing.
  void _paintCorner(
    Canvas canvas,
    Offset center,
    double r,
    Color fill,
    Color glyph,
    IconData icon,
  ) {
    canvas.drawCircle(
      center,
      r + math.max(0.75, r * 0.14),
      Paint()..color = const Color(0xFF1B2430),
    );
    canvas.drawCircle(center, r, Paint()..color = fill);

    if (r < 5.5) return;
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: r * 1.7,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: glyph,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_TablesPainter old) =>
      old.doc != doc ||
      old.cell != cell ||
      old.facts != facts ||
      old.canOpenAll != canOpenAll ||
      old.opening != opening ||
      old.detail != detail ||
      old.tables != tables;
}
