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
        napomene: (j['napomene'] as List?)
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
    final articles = (j['artikli'] as List?)
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
  const MqttRemark({required this.cnap, required this.naziv, required this.sve});

  final String cnap; // id, referenced by article.napomene
  final String naziv; // display text
  final bool sve; // true → available for every article

  factory MqttRemark.fromJson(Map<String, dynamic> j) => MqttRemark(
        cnap: (j['cnap'] ?? '').toString(),
        naziv: (j['naziv'] ?? '').toString(),
        sve: j['sve'] == true,
      );
}

/// The parsed `podaci/artikli` payload: article groups + the predefined remark
/// definitions.
class MqttMenu {
  const MqttMenu({required this.groups, required this.remarks});

  final List<MqttArticleGroup> groups;
  final List<MqttRemark> remarks;

  static const empty = MqttMenu(groups: [], remarks: []);

  /// Predefined remark names available for [article]: every "sve" (global)
  /// remark plus the ones the article lists by id, in the broker's order.
  List<String> predefinedFor(MqttArticle article) => [
        for (final r in remarks)
          if (r.sve || article.napomene.contains(r.cnap)) r.naziv,
      ];

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

    return MqttMenu(groups: groups, remarks: remarks);
  }
}
