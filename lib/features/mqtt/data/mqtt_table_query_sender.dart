import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/mqtt_table_query.dart';
import 'mqtt_order_sender.dart' show newMsgId;
import 'mqtt_service.dart';

/// Builds the "what is on this table" query. `stol` goes out as a NUMBER; the
/// kasa echoes it back as a string so it can be compared 1:1 with what we sent.
String buildTableQueryJson({
  required String msgId,
  required String od,
  required int stol,
}) {
  return jsonEncode({
    'msg_id': msgId,
    'od': od,
    'tip': 'stol',
    'stol': stol,
    'ts': DateTime.now().millisecondsSinceEpoch,
  });
}

enum MqttQueryOutcome {
  ok, // answered
  odbijeno, // the kasa refused (unknown tip, bad table, kasa error)
  kasaNedostupna, // no answer — kasa off, or not the one holding the DB
  neispravno, // failed our own pre-send validation
}

class MqttTableQueryResult {
  const MqttTableQueryResult({
    required this.outcome,
    required this.message,
    this.reply,
  });

  final MqttQueryOutcome outcome;

  /// Text to show the waiter (the kasa's `poruka` when it answered).
  final String message;
  final MqttTableQueryReply? reply;

  bool get isOk => outcome == MqttQueryOutcome.ok;
}

/// Asks the kasa what is currently on a table.
///
/// Unlike [MqttOrderSender] this generates a FRESH `msg_id` for every attempt:
/// a query is a read, not a booking, so there is nothing to be idempotent
/// about and each answer should be a new snapshot. The answer is never
/// retained — it is only as fresh as the moment it was asked.
class MqttTableQuerySender {
  MqttTableQuerySender._();
  static final MqttTableQuerySender instance = MqttTableQuerySender._();

  /// How long to wait for an answer before retrying.
  static const replyTimeout = Duration(seconds: 6);

  /// Attempts before reporting the kasa unreachable. Fewer than an order's
  /// five: nothing is lost by giving up on a read, and the waiter is waiting.
  static const maxAttempts = 2;

  Future<MqttTableQueryResult> ask(int stol) async {
    final svc = MqttService.instance;

    // A query without a valid `od` is dropped silently by the kasa — exactly
    // as with orders — so we never send one blind.
    final od = svc.clientId;
    if (od == null || !svc.isReplyIdValid) {
      return const MqttTableQueryResult(
        outcome: MqttQueryOutcome.neispravno,
        message: 'Neispravan identifikator uređaja — skenirajte QR kod ponovno.',
      );
    }
    if (!svc.isConnected) {
      return const MqttTableQueryResult(
        outcome: MqttQueryOutcome.kasaNedostupna,
        message: 'Nema veze s kasom.',
      );
    }

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final msgId = newMsgId();
      final payload = buildTableQueryJson(msgId: msgId, od: od, stol: stol);

      // Listen BEFORE publishing so a fast answer can't be missed.
      final completer = Completer<MqttTableQueryReply>();
      final sub = svc.tableReplies.listen((r) {
        if (r.msgId == msgId && !completer.isCompleted) completer.complete(r);
      });

      try {
        debugPrint('MQTT ▸ table query $attempt/$maxAttempts '
            '(stol=$stol, msg_id=$msgId)');
        debugPrint('MQTT ▸ query payload: $payload');
        svc.publishQuery(payload);
        final reply = await completer.future.timeout(replyTimeout);
        debugPrint('MQTT ◂ $reply');
        debugPrint('MQTT ◂ my od tag: "${odTag(od)}" — '
            'pending for me: ${reply.pendingForDevice(od)}');
        if (reply.isOk) {
          return MqttTableQueryResult(
            outcome: MqttQueryOutcome.ok,
            message: reply.poruka,
            reply: reply,
          );
        }
        return MqttTableQueryResult(
          outcome: MqttQueryOutcome.odbijeno,
          message:
              reply.poruka.isNotEmpty ? reply.poruka : 'Kasa je odbila upit.',
          reply: reply,
        );
      } on TimeoutException {
        // Ask again with a new id; the previous one is simply abandoned.
      } finally {
        await sub.cancel();
      }
    }

    return const MqttTableQueryResult(
      outcome: MqttQueryOutcome.kasaNedostupna,
      message: 'Kasa ne odgovara.',
    );
  }
}
