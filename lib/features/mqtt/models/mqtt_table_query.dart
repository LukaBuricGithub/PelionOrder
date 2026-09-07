import 'dart:convert';

/// How many trailing characters of an `od` the kasa keeps in
/// `na_cekanju_uredaji` — that is all that fits in its CTERMINAL column.
const int kOdTagLength = 20;

/// The kasa's tag for a device: the last [kOdTagLength] characters of its `od`.
String odTag(String od) =>
    od.length <= kOdTagLength ? od : od.substring(od.length - kOdTagLength);

double _num(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0;
  return 0;
}

int _int(Object? v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

/// One line on an open bill, as the kasa recorded it.
///
/// Prices are shown, never recomputed: `iznos` is what the kasa wrote, and a
/// line discount is carried separately in [popust] / [cijenaBezPopusta]. Our
/// own phone orders always come back with `popust == 0`.
class MqttRacunStavka {
  const MqttRacunStavka({
    required this.cartikl,
    required this.naziv,
    required this.kol,
    required this.mc,
    required this.iznos,
    required this.napomena,
    required this.cuser,
    required this.poslano,
    required this.popust,
    required this.cijenaBezPopusta,
  });

  final int cartikl;
  final String naziv;
  final double kol;

  /// Unit price on the bill.
  final double mc;

  /// `kol × mc` as the kasa booked it.
  final double iznos;

  final String napomena;
  final String cuser;

  /// True once the line has gone to the kitchen/bar — the kasa will not let it
  /// be changed any more.
  final bool poslano;

  /// Line discount, whole percent (0 for anything ordered from a phone).
  final int popust;

  /// Unit price before [popust]; equals [mc] when there is no discount.
  final double cijenaBezPopusta;

  bool get hasPopust => popust != 0;

  factory MqttRacunStavka.fromJson(Map<String, dynamic> j) => MqttRacunStavka(
        cartikl: _int(j['cartikl']),
        naziv: j['naziv']?.toString() ?? '',
        kol: _num(j['kol']),
        mc: _num(j['mc']),
        iznos: _num(j['iznos']),
        napomena: j['napomena']?.toString() ?? '',
        cuser: j['cuser']?.toString() ?? '',
        poslano: j['poslano'] == true,
        popust: _int(j['popust']),
        cijenaBezPopusta:
            j['cijena_bez_popusta'] == null ? _num(j['mc']) : _num(j['cijena_bez_popusta']),
      );
}

/// One open bill on the table. A table can hold several after a split; `crac`
/// is its number WITHIN the table ('1', '2', …), so the identity is the pair
/// (stol, crac) — it is reused once a bill is settled.
class MqttRacun {
  const MqttRacun({
    required this.crac,
    required this.cuser,
    required this.konobar,
    required this.kupac,
    required this.ukupno,
    required this.stavke,
  });

  final String crac;
  final String cuser;
  final String konobar;
  final String kupac;
  final double ukupno;
  final List<MqttRacunStavka> stavke;

  factory MqttRacun.fromJson(Map<String, dynamic> j) => MqttRacun(
        crac: j['crac']?.toString() ?? '',
        cuser: j['cuser']?.toString() ?? '',
        konobar: j['konobar']?.toString() ?? '',
        kupac: j['kupac']?.toString() ?? '',
        ukupno: _num(j['ukupno']),
        stavke: (j['stavke'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(MqttRacunStavka.fromJson)
                .toList() ??
            const [],
      );
}

/// The kasa's answer to a "what is on this table" query (`tip: "stol"`),
/// delivered on our private `mob/{od}` topic.
///
/// It is a SNAPSHOT of the table right now — not an order history. The answer
/// is never retained, so it is only ever as fresh as the moment it was asked.
class MqttTableQueryReply {
  const MqttTableQueryReply({
    required this.msgId,
    required this.tip,
    required this.status,
    required this.poruka,
    required this.stol,
    required this.otvorenNa,
    required this.naCekanju,
    required this.naCekanjuUredaji,
    required this.ukupno,
    required this.ts,
    required this.racuni,
  });

  final String msgId;
  final String tip;

  /// `ok` or `odbijeno`.
  final String status;
  final String poruka;

  /// Echoed back exactly as we sent it (the kasa returns it as a string).
  final String stol;

  /// `TABLE_LOCK.ID_MULTI`: the kasa holding the table, or `"mob"` while any
  /// phone order for it is still waiting to be transferred. Empty = free.
  final String otvorenNa;

  /// Order lines the kasa has not yet moved onto the table. While this is > 0
  /// the list below is still going to change.
  final int naCekanju;

  /// Devices with orders still pending for this table, each the last 20
  /// characters of its `od` (see [odTag]).
  final List<String> naCekanjuUredaji;

  final double ukupno;
  final int ts;
  final List<MqttRacun> racuni;

  bool get isOk => status == 'ok';

  /// An empty table: no open bills. `racuni: []` with `ukupno: 0` is a valid
  /// answer, NOT an error.
  bool get isEmptyTable => racuni.isEmpty;

  /// Someone is working this table on a kasa. `"mob"` does not count — that
  /// only means a phone order is in transit.
  bool get heldByKasa => otvorenNa.isNotEmpty && otvorenNa != 'mob';

  /// Whether one of OUR orders is among those still waiting to be transferred.
  bool pendingForDevice(String? od) {
    if (od == null || od.isEmpty) return false;
    return naCekanjuUredaji.contains(odTag(od));
  }

  /// Every line across every open bill, in bill order.
  List<MqttRacunStavka> get sveStavke =>
      [for (final r in racuni) ...r.stavke];

  factory MqttTableQueryReply.fromJson(Map<String, dynamic> j) =>
      MqttTableQueryReply(
        msgId: j['msg_id']?.toString() ?? '',
        tip: j['tip']?.toString() ?? '',
        status: j['status']?.toString() ?? '',
        poruka: j['poruka']?.toString() ?? '',
        stol: j['stol']?.toString() ?? '',
        otvorenNa: j['otvoren_na']?.toString() ?? '',
        naCekanju: _int(j['na_cekanju']),
        naCekanjuUredaji: (j['na_cekanju_uredaji'] as List?)
                ?.map((e) => e.toString())
                .where((s) => s.isNotEmpty)
                .toList() ??
            const [],
        ukupno: _num(j['ukupno']),
        ts: _int(j['ts']),
        racuni: (j['racuni'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(MqttRacun.fromJson)
                .toList() ??
            const [],
      );

  /// Parses a payload, or null when it isn't a JSON object carrying a msg_id
  /// (without one we could never pair it with a query we sent).
  static MqttTableQueryReply? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final reply = MqttTableQueryReply.fromJson(decoded);
      return reply.msgId.isEmpty ? null : reply;
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'MqttTableQueryReply(stol: $stol, status: $status, '
      'racuni: ${racuni.length}, stavki: ${sveStavke.length}, '
      'naCekanju: $naCekanju, uredaji: $naCekanjuUredaji, '
      'otvorenNa: "$otvorenNa", ukupno: $ukupno)';
}
