import 'dart:convert';

/// One table from `podaci/stolovi` (nested inside a terrace's `stolovi`).
class MqttTable {
  const MqttTable({required this.broj, required this.naziv});

  final int broj; // table number
  final String naziv; // optional label (e.g. "ŠANK", "WC"); may be empty

  factory MqttTable.fromJson(Map<String, dynamic> j) => MqttTable(
        broj: (j['broj'] as num?)?.toInt() ?? 0,
        naziv: (j['naziv'] ?? '').toString(),
      );
}

/// One zone ("terasa") from `podaci/stolovi`, holding its tables.
class MqttTerrace {
  const MqttTerrace({
    required this.id,
    required this.naziv,
    required this.od,
    required this.to,
    required this.tables,
  });

  final int id;
  final String naziv; // may be empty
  final int od; // first table number
  final int to; // last table number ("do" in the payload)
  final List<MqttTable> tables;

  /// Display label for the zone chip: the naziv, or a numbered fallback.
  String get label => naziv.trim().isNotEmpty ? naziv.trim() : 'Terasa $id';

  factory MqttTerrace.fromJson(Map<String, dynamic> j) {
    final tables = (j['stolovi'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(MqttTable.fromJson)
            .toList() ??
        <MqttTable>[];
    return MqttTerrace(
      id: (j['id'] as num?)?.toInt() ?? 0,
      naziv: (j['naziv'] ?? '').toString(),
      od: (j['od'] as num?)?.toInt() ?? 0,
      to: (j['do'] as num?)?.toInt() ?? 0,
      tables: tables,
    );
  }

  /// Parses the full `podaci/stolovi` payload (`{"terase":[...],"ts":...}`).
  static List<MqttTerrace> listFromStoloviPayload(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const [];
    final terase = decoded['terase'];
    if (terase is! List) return const [];
    return terase
        .whereType<Map<String, dynamic>>()
        .map(MqttTerrace.fromJson)
        .toList();
  }
}

/// The set of occupied ("zauzet") table numbers from `podaci/stolovi_stanje`.
/// (We only need occupancy for colouring; per-waiter details are ignored.)
Set<int> occupiedStoloviFromStanje(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) return const {};
  final zauzeti = decoded['zauzeti'];
  if (zauzeti is! List) return const {};
  final result = <int>{};
  for (final e in zauzeti) {
    if (e is Map) {
      final n = (e['stol'] as num?)?.toInt();
      if (n != null) result.add(n);
    }
  }
  return result;
}
