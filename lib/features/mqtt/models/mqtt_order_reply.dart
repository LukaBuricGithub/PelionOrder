import 'dart:convert';

/// The kasa's answer to an order, delivered on `kasa/{LICENCA}/mob/{od}`.
enum MqttOrderStatus {
  ok, // booked (or already booked — a repeated msg_id)
  odbijeno, // rejected; `poruka` says why
  istekla, // expired before the kasa processed it
  unknown, // unrecognised status string
}

/// One reply message. Matched to the sent order by [msgId].
class MqttOrderReply {
  const MqttOrderReply({
    required this.msgId,
    required this.status,
    required this.poruka,
    required this.stol,
    required this.ts,
  });

  /// Same `msg_id` as the order — this is how a reply is paired to its order.
  final String msgId;
  final MqttOrderStatus status;

  /// Croatian text to show the waiter.
  final String poruka;

  /// Table from the order, as text (empty when the order had none).
  final String stol;

  /// Kasa's clock (ms). Difference vs the order's `ts` = our clock skew.
  final int ts;

  bool get isOk => status == MqttOrderStatus.ok;
  bool get isRejected => status == MqttOrderStatus.odbijeno;
  bool get isExpired => status == MqttOrderStatus.istekla;

  static MqttOrderStatus _statusFrom(String s) =>
      switch (s.trim().toLowerCase()) {
        'ok' => MqttOrderStatus.ok,
        'odbijeno' => MqttOrderStatus.odbijeno,
        'istekla' => MqttOrderStatus.istekla,
        _ => MqttOrderStatus.unknown,
      };

  factory MqttOrderReply.fromJson(Map<String, dynamic> j) => MqttOrderReply(
        msgId: (j['msg_id'] ?? '').toString(),
        status: _statusFrom((j['status'] ?? '').toString()),
        poruka: (j['poruka'] ?? '').toString(),
        stol: (j['stol'] ?? '').toString(),
        ts: (j['ts'] as num?)?.toInt() ?? 0,
      );

  /// Parses a reply payload; null when it isn't usable (not a JSON object, or
  /// no `msg_id` — without it the reply can't be paired to an order).
  static MqttOrderReply? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final reply = MqttOrderReply.fromJson(decoded);
      return reply.msgId.isEmpty ? null : reply;
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() =>
      'MqttOrderReply(msgId: $msgId, status: ${status.name}, '
      'poruka: "$poruka", stol: $stol)';
}
