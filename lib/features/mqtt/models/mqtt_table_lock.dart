import 'dart:convert';

/// The kasa's answer to an `ulaz` / `izlaz` on a table ("brave stolova").
///
/// The kasa and a phone must never work on the same table at once. The kasa
/// keeps a lock per table; a phone takes it by announcing `ulaz` and releases
/// it with `izlaz`. Whoever is first holds the table.
///
/// Arrives on `kasa/{lic}/mob/{uredaj}`, the same private topic as order
/// confirmations and table-query answers — told apart by `tip`.
class MqttTableLockReply {
  const MqttTableLockReply({
    required this.msgId,
    required this.tip,
    required this.status,
    required this.poruka,
    required this.stol,
    required this.otvorenNa,
  });

  /// The id of the request this answers, echoed unchanged.
  final String msgId;

  /// `ulaz` or `izlaz`.
  final String tip;

  /// `ok` or `odbijeno`.
  final String status;

  /// Empty on `ok`; otherwise the text for the waiter, e.g. "Stol je otvoren
  /// na kasi KASA1".
  final String poruka;

  /// The table, as a string in the answer.
  final String stol;

  /// Who holds the table: `CORD3` (orderman 3), a kasa's tag, or empty when
  /// nobody does.
  final String otvorenNa;

  bool get isOk => status == 'ok';

  /// Whether this lock is ours — the kasa writes `CORD` + the orderman number.
  bool heldBy(String? clientId) =>
      clientId != null && otvorenNa == lockTagFor(clientId);

  /// Parses a lock answer, or null when the payload isn't one.
  static MqttTableLockReply? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final tip = (decoded['tip'] ?? '').toString();
      if (tip != 'ulaz' && tip != 'izlaz') return null;
      return MqttTableLockReply(
        msgId: (decoded['msg_id'] ?? '').toString(),
        tip: tip,
        status: (decoded['status'] ?? '').toString(),
        poruka: (decoded['poruka'] ?? '').toString(),
        stol: (decoded['stol'] ?? '').toString(),
        otvorenNa: (decoded['otvoren_na'] ?? '').toString(),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() =>
      'MqttTableLockReply(tip: $tip, stol: $stol, status: $status, '
      'otvoren_na: "$otvorenNa", poruka: "$poruka")';
}

/// The kasa's lock tag for a device: `CORD` + the orderman number taken from
/// the client_id (`…-PELIONORDER-3` → `CORD3`). Empty when the id carries no
/// number — the kasa then refuses with "Uređaj nije Orderman".
String lockTagFor(String clientId) {
  for (final separator in const ['-PELIONORDER-', '-ORDERMAN-']) {
    final i = clientId.lastIndexOf(separator);
    if (i >= 0) return 'CORD${clientId.substring(i + separator.length)}';
  }
  return '';
}

/// Who holds a table, for the waiter: `CORD3` → "Pelion Order 3", anything
/// else is a kasa's own tag.
String mqttLockHolderName(String tag) =>
    tag.startsWith('CORD') ? 'Pelion Order ${tag.substring(4)}' : tag;

/// The message for a table locked by [tag]: "Stol je otvoren na kasi KASA1" /
/// "Stol je otvoren na uređaju Pelion Order 3".
String mqttLockHolderText(String tag) => tag.startsWith('CORD')
    ? 'Stol je otvoren na uređaju ${mqttLockHolderName(tag)}.'
    : 'Stol je otvoren na kasi $tag.';
