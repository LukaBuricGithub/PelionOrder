import 'dart:convert';
import 'dart:ui' show Color;

/// The venue's own floor plan, from `kasa/{LICENCA}/podaci/tlocrt` (retained).
///
/// One message carries every enabled terrace, each with its own layout
/// document; the terrace `id` is the same one `podaci/stolovi` uses, which is
/// what ties a drawn table to its name and to the occupancy snapshot.
///
/// Everything here is "best effort on purpose": an unreadable or unsupported
/// document must never leave the waiter without a table screen, so every parse
/// failure ends as `null` / [enabled] false and the caller falls back to the
/// generic grid. (Spec: tlocrt-mobitel.md, 2. 10. 2026.)
class MqttFloorPlan {
  const MqttFloorPlan({required this.enabled, required this.terraces});

  /// `TLOCRT_ON` on the kasa. False means "draw the usual grid" — not an
  /// error, just a venue that hasn't drawn a plan.
  final bool enabled;

  final List<MqttFloorTerrace> terraces;

  static const empty = MqttFloorPlan(enabled: false, terraces: []);

  /// The layout for the terrace with this id, or null when it has none (then
  /// that zone falls back to the grid while others may still be drawn).
  MqttFloorTerrace? forTerrace(int id) {
    for (final t in terraces) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Parses a whole `podaci/tlocrt` payload. Returns null when the message
  /// isn't usable at all; a terrace whose own document is broken is dropped
  /// while the rest are kept.
  static MqttFloorPlan? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final enabled = decoded['ukljuceno'] == true;
      final list = decoded['terase'];
      final terraces = <MqttFloorTerrace>[];
      if (list is List) {
        for (final e in list) {
          if (e is! Map) continue;
          final t = MqttFloorTerrace._tryParse(e);
          if (t != null) terraces.add(t);
        }
      }
      return MqttFloorPlan(enabled: enabled, terraces: terraces);
    } catch (_) {
      return null;
    }
  }
}

/// One terrace's layout inside [MqttFloorPlan].
class MqttFloorTerrace {
  const MqttFloorTerrace({
    required this.id,
    required this.saved,
    required this.plan,
  });

  /// Matches `podaci/stolovi.terase[].id`.
  final int id;

  /// False when the kasa generated the layout itself because the venue hasn't
  /// drawn one (or it couldn't be loaded). Still a perfectly drawable plan —
  /// worth knowing only for diagnostics.
  final bool saved;

  final TlocrtDoc plan;

  static MqttFloorTerrace? _tryParse(Map<dynamic, dynamic> j) {
    final doc = j['tlocrt'];
    if (doc is! Map) return null;
    final plan = TlocrtDoc._tryParse(doc);
    if (plan == null) return null;
    return MqttFloorTerrace(
      id: (j['id'] as num?)?.toInt() ?? 0,
      saved: j['spremljen'] == true,
      plan: plan,
    );
  }
}

/// The layout document itself (`TLOCRT.SADRZAJ`): a grid of cells plus the
/// objects standing on it.
class TlocrtDoc {
  const TlocrtDoc({
    required this.cols,
    required this.rows,
    required this.background,
    required this.legend,
    required this.ground,
    required this.objects,
  });

  /// The only format version this app draws. Anything else falls back to the
  /// grid rather than guessing at a layout it doesn't understand.
  static const supportedVersion = 1;

  /// The kasa accepts 8–256 cells per axis; outside that the document is
  /// treated as unusable.
  static const _minSide = 8;
  static const _maxSide = 256;

  /// Grid size in cells — never assume the usual 64 × 39.
  final int cols;
  final int rows;

  final Color background;

  /// Character → cell type, e.g. `#` → `zid`. A character missing from here
  /// is floor (`pod`), as on the kasa.
  final Map<String, String> legend;

  /// [rows] strings of [cols] characters, top row first.
  final List<String> ground;

  /// Tables, decor and labels, in the order they are drawn.
  final List<TlocrtObject> objects;

  /// The cell type at (x, y) — `pod` outside the grid, so callers can ask
  /// about any coordinate without checking bounds first.
  String cellType(int x, int y) {
    if (x < 0 || y < 0 || y >= ground.length) return 'pod';
    final row = ground[y];
    if (x >= row.length) return 'pod';
    return legend[row[x]] ?? 'pod';
  }

  /// Every table on this plan, by table number. The number ties the drawing to
  /// `podaci/stolovi` (names) and to the occupancy snapshot.
  Map<int, TlocrtObject> get tablesByNumber => {
    for (final o in objects)
      if (o.isTable && o.table != null) o.table!: o,
  };

  static TlocrtDoc? _tryParse(Map<dynamic, dynamic> j) {
    final version = (j['verzija'] as num?)?.toInt() ?? 0;
    if (version != supportedVersion) return null;

    final cols = (j['sirina'] as num?)?.toInt() ?? 0;
    final rows = (j['visina'] as num?)?.toInt() ?? 0;
    if (cols < _minSide || cols > _maxSide) return null;
    if (rows < _minSide || rows > _maxSide) return null;

    // The kasa sends exactly `visina` rows of `sirina` characters, but a short
    // row would otherwise throw while drawing: pad instead, so one malformed
    // line costs a few floor cells rather than the whole screen.
    final rawGround = (j['podloga'] as List?) ?? const [];
    final ground = <String>[];
    for (var y = 0; y < rows; y++) {
      final line = y < rawGround.length ? rawGround[y].toString() : '';
      ground.add(line.length >= cols ? line : line.padRight(cols, '.'));
    }

    final legend = <String, String>{};
    final rawLegend = j['legenda'];
    if (rawLegend is Map) {
      rawLegend.forEach((key, value) {
        final k = key.toString();
        if (k.isEmpty) return;
        final tip = value is Map ? (value['tip'] ?? '').toString() : '';
        if (tip.isNotEmpty) legend[k] = tip;
      });
    }

    final objects = <TlocrtObject>[];
    final rawObjects = j['objekti'];
    if (rawObjects is List) {
      for (final e in rawObjects) {
        if (e is! Map) continue;
        final o = TlocrtObject._tryParse(e);
        if (o != null) objects.add(o);
      }
    }

    return TlocrtDoc(
      cols: cols,
      rows: rows,
      background: _parseColor(j['boja_pozadine']) ?? const Color(0xFF202020),
      legend: legend,
      ground: ground,
      objects: objects,
    );
  }
}

/// A table, a piece of decor or a label on the plan. Coordinates are whole
/// cells, `(0, 0)` top left, and `w`/`h` cover the whole frame — seating
/// included, which is why a table's body is drawn inset.
class TlocrtObject {
  const TlocrtObject({
    required this.type,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.table,
    this.shape = 'K',
    this.seats = 0,
    this.icon = '',
    this.text = '',
  });

  final String type; // stol | dekor | tekst
  final int x;
  final int y;
  final int w;
  final int h;

  /// Table number — the key everything else is matched by. Table 0 is allowed,
  /// so null (absent) is the only "not a table" marker.
  final int? table;

  /// `K` square with rounded corners, `O` ellipse inside the frame.
  final String shape;
  final int seats;

  /// `biljka`, `stup`, `kasa`, or anything else (drawn as a label).
  final String icon;
  final String text;

  bool get isTable => type == 'stol';

  /// True when (cx, cy) falls inside this object's frame. The whole frame is
  /// active, including for a round table.
  bool contains(int cx, int cy) =>
      cx >= x && cx < x + w && cy >= y && cy < y + h;

  static TlocrtObject? _tryParse(Map<dynamic, dynamic> j) {
    final type = (j['tip'] ?? '').toString();
    if (type.isEmpty) return null;
    final w = (j['w'] as num?)?.toInt() ?? 0;
    final h = (j['h'] as num?)?.toInt() ?? 0;
    if (w <= 0 || h <= 0) return null;
    return TlocrtObject(
      type: type,
      x: (j['x'] as num?)?.toInt() ?? 0,
      y: (j['y'] as num?)?.toInt() ?? 0,
      w: w,
      h: h,
      table: (j['stol'] as num?)?.toInt(),
      shape: (j['oblik'] ?? 'K').toString(),
      seats: (j['sjedala'] as num?)?.toInt() ?? 0,
      icon: (j['ikona'] ?? '').toString(),
      text: (j['tekst'] ?? '').toString(),
    );
  }
}

/// `#RRGGBB` (or `#AARRGGBB`) as sent by the kasa. Null when unreadable, so
/// the caller can fall back to its own default.
Color? _parseColor(Object? value) {
  if (value == null) return null;
  var hex = value.toString().trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final n = int.tryParse(hex, radix: 16);
  return n == null ? null : Color(n);
}
