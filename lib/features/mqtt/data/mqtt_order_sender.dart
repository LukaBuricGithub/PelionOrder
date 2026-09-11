import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/mqtt_order_reply.dart';
import '../state/mqtt_cart.dart';
import 'mqtt_service.dart';

/// A fresh `msg_id` (UUID v4). Generated once when the waiter confirms an
/// order and reused for every retry of that same order.
String newMsgId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // variant 1
  String hex(int from, int to) =>
      b.sublist(from, to).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

/// Merges lines for the same article carrying the same napomene into one line
/// with the summed quantity — the "Grupiraj artikle pri slanju" setting.
///
/// The kasa never does this itself ("Kasa ne zbraja iste artikle — dva retka
/// ostaju dva retka", doc 3.2), so what we send is exactly what the kitchen
/// ticket shows. Lines only merge when the article, the remark codes and the
/// free text all match — differing napomene must stay separate lines, or the
/// kitchen loses the instruction. First-seen order is preserved.
List<MqttCartLine> groupCartLines(List<MqttCartLine> lines) {
  final order = <String>[];
  final grouped = <String, MqttCartLine>{};
  for (final l in lines) {
    // Sorted, so the same set of remarks keys the same regardless of the order
    // the waiter ticked them in.
    final codes = [...l.remarkCodes]..sort();
    final key = '${l.code}|${codes.join(',')}|${l.napomenaTekst}';
    final existing = grouped[key];
    if (existing == null) {
      // A copy: summing below must never touch the waiter's live cart.
      order.add(key);
      grouped[key] = l.copy();
    } else {
      existing.qty += l.qty;
    }
  }
  return [for (final k in order) grouped[k]!];
}

/// Builds the order JSON (protocol doc, 3.2). Lines keep the waiter's order;
/// `napomene` carries remark CODES and `napomena_tekst` the free text. `istek`
/// defaults to ts + 10 min, as recommended.
String buildOrderJson({
  required String msgId,
  required String od,
  required int stol,
  required String cuser,
  required List<MqttCartLine> lines,
  Duration validity = const Duration(minutes: 10),
}) {
  final ts = DateTime.now().millisecondsSinceEpoch;
  return jsonEncode({
    'msg_id': msgId,
    'od': od,
    'ts': ts,
    'istek': ts + validity.inMilliseconds,
    'stol': stol,
    'cuser': cuser,
    'stavke': [
      for (final l in lines)
        {
          'cartikl': l.code,
          // Whole quantities as ints, otherwise a decimal (dot-separated).
          'kol': l.qty == l.qty.roundToDouble() ? l.qty.toInt() : l.qty,
          if (l.remarkCodes.isNotEmpty) 'napomene': l.remarkCodes,
          if (l.napomenaTekst.isNotEmpty) 'napomena_tekst': l.napomenaTekst,
        },
    ],
  });
}

enum MqttSendOutcome {
  ok, // booked (or already booked — repeated msg_id)
  odbijeno, // rejected by the kasa; `message` says why
  istekla, // expired — must be re-sent as a NEW order
  kasaNedostupna, // no answer (or no connection) — nothing is known yet
  neispravno, // failed our own pre-send validation
}

class MqttSendResult {
  const MqttSendResult({
    required this.outcome,
    required this.msgId,
    required this.message,
    this.reply,
    this.repeated = false,
  });

  final MqttSendOutcome outcome;
  final String msgId;

  /// Text to show the waiter (the kasa's `poruka` when it is meaningful).
  final String message;
  final MqttOrderReply? reply;

  /// The kasa had already seen this msg_id and replayed its SAVED answer. The
  /// text of such a reply is always "Nalog je već zaprimljen" whatever the
  /// status, so for anything but ok [message] is our own wording — the real
  /// reason is the one that came with the first answer.
  final bool repeated;

  bool get isOk => outcome == MqttSendOutcome.ok;

  /// The kasa gave a FINAL answer that booked nothing: this msg_id can never
  /// be booked any more, so the items may only go out again as a new order.
  bool get isFinalRefusal =>
      outcome == MqttSendOutcome.odbijeno || outcome == MqttSendOutcome.istekla;
}

/// Sends orders to the kasa and waits for the matching reply.
///
/// Idempotency (protocol doc, 3.5): the same order is retried with the SAME
/// `msg_id` — the kasa remembers every id and simply replays its answer, so a
/// retry can never double-book. A new id is only ever used for genuinely new
/// content, or after a final refusal (odbijeno / istekla), which booked nothing.
///
/// Orders are frozen and persisted by the outbox (`mqttOutboxProvider`) before
/// they are sent; this class only validates, publishes and waits.
class MqttOrderSender {
  MqttOrderSender._();
  static final MqttOrderSender instance = MqttOrderSender._();

  /// How long to wait for a reply before resending the same payload.
  static const replyTimeout = Duration(seconds: 10);

  /// Default attempts before reporting "no answer".
  static const maxAttempts = 5;

  /// The kasa's text for a repeated msg_id (any status).
  static const _repeatText = 'Nalog je već zaprimljen';

  /// Checks that need nothing from the kasa. Returns the problem, or null when
  /// an order with these values may be built and sent.
  ///
  /// A bad `od` makes the kasa drop the order silently (no reply at all), so it
  /// is never even tried — see the protocol doc, 4.3.
  MqttSendResult? precheck({
    required String cuser,
    required List<MqttCartLine> lines,
  }) {
    final svc = MqttService.instance;
    if (svc.clientId == null || !svc.isReplyIdValid) {
      return _invalid(
          'Neispravan identifikator uređaja — skenirajte QR kod ponovno.');
    }
    if (cuser.trim().isEmpty) return _invalid('Nedostaje šifra konobara.');
    if (lines.isEmpty) return _invalid('Nalog nema stavaka.');
    return null;
  }

  /// Publishes an already-built order [payload] and waits for the kasa's
  /// answer. Every attempt sends this identical payload — same msg_id, same
  /// ts/istek — so the kasa can always recognise a repeat, and its expiry keeps
  /// counting from when the order was first built.
  Future<MqttSendResult> sendPayload({
    required String msgId,
    required String payload,
    int attempts = maxAttempts,
  }) async {
    final svc = MqttService.instance;
    if (!svc.isConnected) {
      return MqttSendResult(
        outcome: MqttSendOutcome.kasaNedostupna,
        msgId: msgId,
        message: 'Nema veze s kasom.',
      );
    }

    // Listen BEFORE publishing so a fast reply can't be missed.
    final completer = Completer<MqttOrderReply>();
    final sub = svc.orderReplies.listen((r) {
      if (r.msgId == msgId && !completer.isCompleted) completer.complete(r);
    });

    try {
      for (var attempt = 1; attempt <= attempts; attempt++) {
        debugPrint('MQTT ▸ order attempt $attempt/$attempts (msg_id=$msgId)');
        svc.publishOrder(payload);
        try {
          final reply = await completer.future.timeout(replyTimeout);
          debugPrint('MQTT ◂ order reply: $reply');
          return _fromReply(reply, msgId);
        } on TimeoutException {
          // No answer — resend the SAME payload with the SAME msg_id.
        }
      }
      return MqttSendResult(
        outcome: MqttSendOutcome.kasaNedostupna,
        msgId: msgId,
        message: 'Kasa ne odgovara.',
      );
    } finally {
      await sub.cancel();
    }
  }

  MqttSendResult _invalid(String message) => MqttSendResult(
        outcome: MqttSendOutcome.neispravno,
        msgId: '',
        message: message,
      );

  MqttSendResult _fromReply(MqttOrderReply r, String msgId) {
    final outcome = switch (r.status) {
      MqttOrderStatus.ok => MqttSendOutcome.ok,
      MqttOrderStatus.istekla => MqttSendOutcome.istekla,
      // An unrecognised status is treated as a rejection rather than success.
      MqttOrderStatus.odbijeno || MqttOrderStatus.unknown =>
        MqttSendOutcome.odbijeno,
    };
    final repeated = r.poruka.trim().startsWith(_repeatText);
    // A replayed refusal still reads "Nalog je već zaprimljen" — never show
    // that for an order that was NOT booked.
    final useKasaText =
        r.poruka.isNotEmpty && !(repeated && outcome != MqttSendOutcome.ok);
    return MqttSendResult(
      outcome: outcome,
      msgId: msgId,
      message: useKasaText ? r.poruka : _defaultMessage(outcome),
      reply: r,
      repeated: repeated,
    );
  }

  String _defaultMessage(MqttSendOutcome o) => switch (o) {
        MqttSendOutcome.ok => 'Nalog zaprimljen',
        MqttSendOutcome.istekla => 'Nalog je istekao.',
        _ => 'Kasa je odbila nalog.',
      };
}
