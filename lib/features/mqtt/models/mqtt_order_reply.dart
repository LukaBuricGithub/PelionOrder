import 'dart:convert';

/// The kasa's confirmation of an order (spec v4.0, §10), delivered on
/// `kasa/{LICENCA}/mob/{uredaj}`:
///
/// * `{msg_id, uredaj}` — the order was printed;
/// * `{msg_id, uredaj, odbijeno}` — it was not, for the reason in `odbijeno`
///   ([nijeAktiviran], [zastarjela], [nijeUProdaji], [greskaPisaca],
///   [stolZauzet]).
///
/// If the field is absent, the order was printed. The only proof an order was
/// received is this confirmation — a successful publish proves nothing.
class MqttOrderReply {
  const MqttOrderReply({
    required this.msgId,
    required this.uredaj,
    this.odbijeno,
  });

  /// Same `msg_id` as the order — this is how a confirmation is paired to it.
  final String msgId;

  /// The client_id of the kasa that answered.
  final String uredaj;

  /// Why the order was not printed, or null when it was.
  final String? odbijeno;

  /// Refusal reasons (§10).
  static const nijeAktiviran = 'nije aktiviran';
  static const zastarjela = 'zastarjela';
  static const nijeUProdaji = 'nije u prodaji';
  static const greskaPisaca = 'greska pisaca';

  /// The table is held by the kasa or another orderman ("brave stolova"). Only
  /// happens when the order went out without our `ulaz` getting through — a
  /// lock of our own lets the order past even if a cashier stepped in after.
  static const stolZauzet = 'stol zauzet';

  bool get isPrinted => odbijeno == null;

  /// Parses a confirmation; null when it isn't usable (not a JSON object, or no
  /// `msg_id` — without it the confirmation can't be paired to an order).
  static MqttOrderReply? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final msgId = (decoded['msg_id'] ?? '').toString();
      if (msgId.isEmpty) return null;
      return MqttOrderReply(
        msgId: msgId,
        uredaj: (decoded['uredaj'] ?? '').toString(),
        odbijeno: decoded['odbijeno']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'MqttOrderReply(msgId: $msgId, uredaj: $uredaj, '
      '${isPrinted ? 'printed' : 'odbijeno: $odbijeno'})';
}
