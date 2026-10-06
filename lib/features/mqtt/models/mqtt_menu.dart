import 'dart:convert';

/// One article as delivered over MQTT on `kasa/{licenca}/podaci/artikli`
/// (nested inside each group's `artikli`).
class MqttArticle {
  const MqttArticle({
    required this.code,
    required this.name,
    required this.fullName,
    required this.price,
    required this.color,
    required this.order,
    required this.unit,
    required this.tax,
    required this.icon,
    this.napomene = const [],
  });

  final int code; // cartikl
  final String name; // naziv
  final String fullName; // naziv_puni
  final double price; // cijena
  final String color; // boja
  final int order; // rbr
  final String unit; // jm
  final String tax; // porez
  final String icon; // ikona

  /// Ids (`cnap`) of the predefined remarks allowed for this article. A remark
  /// with `sve: true` applies to every article regardless of this list.
  final List<String> napomene;

  factory MqttArticle.fromJson(Map<String, dynamic> j) => MqttArticle(
    code: (j['cartikl'] as num?)?.toInt() ?? 0,
    name: j['naziv']?.toString() ?? '',
    fullName: j['naziv_puni']?.toString() ?? '',
    price: (j['cijena'] as num?)?.toDouble() ?? 0,
    color: j['boja']?.toString() ?? '',
    order: (j['rbr'] as num?)?.toInt() ?? 0,
    unit: j['jm']?.toString() ?? '',
    tax: j['porez']?.toString() ?? '',
    icon: j['ikona']?.toString() ?? '',
    napomene:
        (j['napomene'] as List?)
            ?.map((e) => e.toString())
            .where((s) => s.isNotEmpty)
            .toList() ??
        const [],
  );
}

/// One article group ("grupa") from `podaci/artikli`, holding its articles.
class MqttArticleGroup {
  const MqttArticleGroup({
    required this.id,
    required this.order,
    required this.name,
    required this.icon,
    required this.color,
    required this.articles,
  });

  final int id;
  final int order; // rbr
  final String name; // naziv
  final String icon; // ikona
  final String color; // boja
  final List<MqttArticle> articles;

  factory MqttArticleGroup.fromJson(Map<String, dynamic> j) {
    final articles =
        (j['artikli'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(MqttArticle.fromJson)
            .toList() ??
        <MqttArticle>[];
    articles.sort((a, b) => a.order.compareTo(b.order));
    return MqttArticleGroup(
      id: (j['id'] as num?)?.toInt() ?? 0,
      order: (j['rbr'] as num?)?.toInt() ?? 0,
      name: j['naziv']?.toString() ?? '',
      icon: j['ikona']?.toString() ?? '',
      color: j['boja']?.toString() ?? '',
      articles: articles,
    );
  }
}

/// A predefined remark ("napomena") definition from the top-level `napomene`
/// list of `podaci/artikli`.
class MqttRemark {
  const MqttRemark({
    required this.cnap,
    required this.naziv,
    required this.sve,
  });

  final String cnap; // id, referenced by article.napomene
  final String naziv; // display text
  final bool sve; // true → available for every article

  factory MqttRemark.fromJson(Map<String, dynamic> j) => MqttRemark(
    cnap: (j['cnap'] ?? '').toString(),
    naziv: (j['naziv'] ?? '').toString(),
    sve: j['sve'] == true,
  );
}

/// The `prikaz` object: the layout a venue arranged for the phone on the kasa
/// ("Raspored na mobitelu"). Present only once such a layout has been saved —
/// without it the message is what it always was, and the app lays the articles
/// out itself.
///
/// What it changes is what `rbr` MEANS. Normally it is a sort order; with a
/// layout it is a **place in this grid**, and the places may have holes: an
/// article at `rbr` 4 stands in the fourth square even when the third is
/// empty. That is deliberate — an article deactivated on the kasa leaves its
/// square empty instead of pulling every later article one place back, so
/// nothing moves under the waiter's fingers.
class MqttDisplayLayout {
  const MqttDisplayLayout({
    required this.columns,
    required this.rows,
    required this.scroll,
  });

  /// Squares across (3 or 4) and down (3 or 4) on one screen — the kasa only
  /// offers 3 × 3, 3 × 4 and 4 × 4.
  final int columns;
  final int rows;

  /// False: one screen only, and `rbr` never exceeds [slotsPerScreen]. True:
  /// several screens, swiped left and right as the app has always done.
  final bool scroll;

  int get slotsPerScreen => columns * rows;

  /// Lays [articles] out as screens of squares, each square either an article
  /// or null (an empty place). A screen is read left to right, top to bottom;
  /// the next screen is to the right.
  ///
  /// [columns] × [rows] is the grid to lay them into, which is NOT always this
  /// layout's own: a waiter may choose their own tile size, and then the
  /// venue's reading order and its holes are kept but reflowed into their
  /// grid. Pass this layout's own numbers to reproduce the designer's screen
  /// exactly.
  ///
  /// Articles whose `rbr` is missing or out of range are appended after the
  /// last placed one rather than dropped — a square in the wrong place beats
  /// an article a waiter cannot sell.
  static List<List<MqttArticle?>> placeInGrid(
    List<MqttArticle> articles, {
    required int columns,
    required int rows,
    required bool scroll,
  }) {
    if (articles.isEmpty) return const [];
    final perScreen = columns * rows;

    final placed = <int, MqttArticle>{};
    final leftovers = <MqttArticle>[];
    for (final a in articles) {
      final slot = a.order - 1; // `rbr` counts from 1
      if (slot < 0 || placed.containsKey(slot)) {
        leftovers.add(a);
      } else {
        placed[slot] = a;
      }
    }

    var highest = placed.keys.isEmpty
        ? -1
        : placed.keys.reduce((a, b) => a > b ? a : b);
    for (final a in leftovers) {
      placed[++highest] = a;
    }

    // Without scrolling the kasa guarantees one screen; anything beyond it
    // would be unreachable, so it is pulled back into the last free square.
    if (!scroll && highest >= perScreen) {
      final overflow = [
        for (final slot in placed.keys.toList()..sort())
          if (slot >= perScreen) slot,
      ];
      for (final slot in overflow) {
        final article = placed.remove(slot)!;
        var free = 0;
        while (free < perScreen && placed.containsKey(free)) {
          free++;
        }
        if (free < perScreen) placed[free] = article;
      }
      highest = perScreen - 1;
    }

    final screens = scroll ? (highest ~/ perScreen) + 1 : 1;
    return [
      for (var screen = 0; screen < screens; screen++)
        [for (var i = 0; i < perScreen; i++) placed[screen * perScreen + i]],
    ];
  }

  static MqttDisplayLayout? tryParse(Object? value) {
    if (value is! Map) return null;
    final columns = (value['stupci'] as num?)?.toInt() ?? 0;
    final rows = (value['redovi'] as num?)?.toInt() ?? 0;
    // Anything outside what the kasa can produce is treated as "no layout"
    // rather than guessed at: a wrong grid would put every article in the
    // wrong square, which is worse than laying them out ourselves.
    if (columns < 2 || columns > 6 || rows < 2 || rows > 6) return null;
    return MqttDisplayLayout(
      columns: columns,
      rows: rows,
      scroll: value['scroll'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MqttDisplayLayout &&
      other.columns == columns &&
      other.rows == rows &&
      other.scroll == scroll;

  @override
  int get hashCode => Object.hash(columns, rows, scroll);
}

/// The parsed `podaci/artikli` payload: article groups + the predefined remark
/// definitions.
class MqttMenu {
  const MqttMenu({required this.groups, required this.remarks, this.layout});

  final List<MqttArticleGroup> groups;
  final List<MqttRemark> remarks;

  /// The venue's own arrangement, or null when the kasa sends none (then the
  /// app arranges the articles itself, in `rbr` order, as it always has).
  final MqttDisplayLayout? layout;

  static const empty = MqttMenu(groups: [], remarks: []);

  /// Predefined remarks available for [article]: every "sve" (global) remark
  /// plus the ones the article lists by id, in the broker's order. Returns the
  /// full remark (code + name) — orders are sent with the code (`cnap`).
  List<MqttRemark> remarksFor(MqttArticle article) => [
    for (final r in remarks)
      if (r.sve || article.napomene.contains(r.cnap)) r,
  ];

  /// Display name for a remark code (`cnap`), falling back to the code itself.
  String remarkName(String cnap) {
    for (final r in remarks) {
      if (r.cnap == cnap) return r.naziv;
    }
    return cnap;
  }

  /// Parses the full `podaci/artikli` payload into groups (sorted by `rbr`) plus
  /// the predefined remark definitions. Returns [empty] on a shape mismatch.
  static MqttMenu fromArtikliPayload(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return empty;

    final grupe = decoded['grupe'];
    final groups = grupe is List
        ? (grupe
              .whereType<Map<String, dynamic>>()
              .map(MqttArticleGroup.fromJson)
              .toList()
            ..sort((a, b) => a.order.compareTo(b.order)))
        : <MqttArticleGroup>[];

    final nap = decoded['napomene'];
    final remarks = nap is List
        ? nap
              .whereType<Map<String, dynamic>>()
              .map(MqttRemark.fromJson)
              .toList()
        : <MqttRemark>[];

    return MqttMenu(
      groups: groups,
      remarks: remarks,
      layout: MqttDisplayLayout.tryParse(decoded['prikaz']),
    );
  }
}
