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

/// The server-side state of one occupied ("zauzet") table from
/// `podaci/stolovi_stanje`. Only a summary is delivered (no item breakdown).
class MqttTableState {
  const MqttTableState({
    required this.stol,
    required this.cuser,
    required this.konobar,
    required this.iznos,
    required this.stavki,
    required this.kupac,
  });

  final int stol; // table number
  final String cuser; // code of the waiter who opened it
  final String konobar; // waiter display name
  final double iznos; // total amount
  final int stavki; // item count
  final String kupac; // customer (may be empty)

  factory MqttTableState.fromJson(Map<String, dynamic> j) => MqttTableState(
        stol: (j['stol'] as num?)?.toInt() ?? 0,
        cuser: (j['cuser'] ?? '').toString(),
        konobar: (j['konobar'] ?? '').toString(),
        iznos: (j['iznos'] as num?)?.toDouble() ?? 0,
        stavki: (j['stavki'] as num?)?.toInt() ?? 0,
        kupac: (j['kupac'] ?? '').toString(),
      );
}

/// Occupied tables from `podaci/stolovi_stanje`, keyed by table number.
Map<int, MqttTableState> tableStatesFromStanje(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) return const {};
  final zauzeti = decoded['zauzeti'];
  if (zauzeti is! List) return const {};
  final result = <int, MqttTableState>{};
  for (final e in zauzeti) {
    if (e is Map<String, dynamic>) {
      final st = MqttTableState.fromJson(e);
      result[st.stol] = st;
    }
  }
  return result;
}
