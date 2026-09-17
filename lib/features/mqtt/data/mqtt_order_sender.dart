import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/mqtt_order_reply.dart';
import '../state/mqtt_cart.dart';
import 'mqtt_service.dart';

/// A fresh order `msg_id`: 12 random hexadecimal characters (spec v4.0, §10).
/// Made once, just before the order is first sent, and reused for every resend
/// of that same order. Random, never a counter: several phones send to one
/// kasa, and it recognises repeats by this id alone.
String newMsgId() {
  final r = Random.secure();
  return List.generate(12, (_) => r.nextInt(16).toRadixString(16)).join();
}

/// A fresh `msg_id` for a table query (UUID v4) — the table query protocol
/// (`upiti`, `tip: "stol"`) is separate from orders and unchanged.
String newQueryId() {
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
/// The kasa never does this itself, so what we send is exactly what the
/// kitchen ticket shows. Lines only merge when the article, the remark codes
/// and the free text all match — differing napomene must stay separate lines,
/// or the kitchen loses the instruction. First-seen order is preserved.
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

/// Builds the order JSON (spec v4.0, §10): `msg_id`, `uredaj` (our client_id),
/// `poslano` (the time of the first send, phone clock, whole ms) + the order
/// content. The kasa ignores an order missing any of the three.
///
/// Lines keep the waiter's order; `napomene` carries remark CODES and
/// `napomena_tekst` the free text.
String buildOrderJson({
  required String msgId,
  required String uredaj,
  required int poslano,
  required int stol,
  required String cuser,
  required List<MqttCartLine> lines,
}) {
  return jsonEncode({
    'msg_id': msgId,
    'uredaj': uredaj,
    'poslano': poslano,
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

/// What one send of an order came to (spec v4.0, §11.6).
enum MqttSendOutcome {
  ok, // printed (or already printed — a repeated msg_id)
  odbijeno, // not printed: not in sale, printer error, or an unknown reason
  zastarjela, // not printed: `poslano` too far from the kasa's clock
  nijeAktiviran, // the kasa doesn't accept this orderman (§9)
  nijePoslana, // couldn't be published at all — it never left the phone
  nijeIsporucena, // went out, but the broker never confirmed taking it
  nijePotvrdena, // published, but no confirmation within 10 s — unknown
  neispravno, // failed our own pre-send validation
}

class MqttSendResult {
  const MqttSendResult({
    required this.outcome,
    required this.msgId,
    required this.message,
    this.reply,
  });

  final MqttSendOutcome outcome;
  final String msgId;

  /// Text to show the waiter (§11.6).
  final String message;
  final MqttOrderReply? reply;

  bool get isOk => outcome == MqttSendOutcome.ok;
}

/// Sends orders to the kasa and waits for the matching confirmation.
///
/// Orders are frozen and persisted by the outbox (`mqttOutboxProvider`) before
/// they are sent; this class only validates, publishes and waits. Every
/// publish of an order carries the identical payload — same msg_id, same
/// `poslano` — so the kasa can always recognise a repeat and never prints an
/// order twice.
class MqttOrderSender {
  MqttOrderSender._();
  static final MqttOrderSender instance = MqttOrderSender._();

  /// How long to wait for the kasa's confirmation (§11.6): a correct one comes
  /// in under a second, and even a slow print fits in 10 s. A confirmation
  /// arriving later still updates the order (see the outbox).
  static const replyTimeout = Duration(seconds: 10);

  /// Checks that need nothing from the kasa. Returns the problem, or null when
  /// an order with these values may be built and sent.
  ///
  /// A bad `uredaj` makes the kasa drop the order silently (no confirmation at
  /// all), so it is never even tried.
  MqttSendResult? precheck({
    required String cuser,
    required List<MqttCartLine> lines,
  }) {
    final svc = MqttService.instance;
    if (svc.clientId == null || !svc.isReplyIdValid) {
      return _invalid(
        'Neispravan identifikator uređaja, skenirajte QR kod ponovno.',
      );
    }
    if (cuser.trim().isEmpty) return _invalid('Nedostaje šifra konobara.');
    if (lines.isEmpty) return _invalid('Nalog nema stavaka.');
    return null;
  }

  /// Publishes an already-built order [payload] once (§11.6) and waits for the
  /// kasa's confirmation.
  ///
  /// [onPublished] is called as soon as the broker has confirmed taking the
  /// order. The screen lets the waiter carry on from there; the wait for the
  /// kasa's confirmation continues in the background.
  ///
  /// Without the broker's confirmation the order counts as not sent: a
  /// connection can be dead for several seconds before the phone notices, and
  /// what was published on it is lost — the MQTT library never sends it
  /// again. Sending it again is safe: same msg_id, so if the broker did get
  /// it after all, the kasa recognises the repeat and doesn't print it twice.
  Future<MqttSendResult> sendPayload({
    required String msgId,
    required String payload,
    void Function()? onPublished,
  }) async {
    final svc = MqttService.instance;

    // Listen BEFORE publishing so a fast confirmation can't be missed.
    final completer = Completer<MqttOrderReply>();
    final sub = svc.orderReplies.listen((r) {
      if (r.msgId == msgId && !completer.isCompleted) completer.complete(r);
    });

    try {
      debugPrint('MQTT ▸ order send (msg_id=$msgId)');
      final delivered = await svc.publishOrderDelivered(payload);
      if (delivered == null) {
        // Couldn't even be published (no connection): nothing went out,
        // there is nothing to wait for.
        return MqttSendResult(
          outcome: MqttSendOutcome.nijePoslana,
          msgId: msgId,
          message: 'Nije poslana.',
        );
      }
      if (!delivered) {
        return MqttSendResult(
          outcome: MqttSendOutcome.nijeIsporucena,
          msgId: msgId,
          message: 'Nije poslana, poslužitelj nije potvrdio primitak.',
        );
      }
      onPublished?.call();
      try {
        final reply = await completer.future.timeout(replyTimeout);
        debugPrint('MQTT ◂ order confirmation: $reply');
        return resultFromReply(reply);
      } on TimeoutException {
        return MqttSendResult(
          outcome: MqttSendOutcome.nijePotvrdena,
          msgId: msgId,
          message: 'Nije potvrđena, provjeri u glavnom programu.',
        );
      }
    } finally {
      await sub.cancel();
    }
  }

  MqttSendResult _invalid(String message) => MqttSendResult(
        outcome: MqttSendOutcome.neispravno,
        msgId: '',
        message: message,
      );

  /// What a confirmation means for the order, in the words of §11.6.
  MqttSendResult resultFromReply(MqttOrderReply r) {
    final (outcome, message) = switch (r.odbijeno) {
      null => (MqttSendOutcome.ok, 'Primljena'),
      MqttOrderReply.nijeUProdaji => (
          MqttSendOutcome.odbijeno,
          'Nije primljena, glavni program nije u blagajni.',
        ),
      MqttOrderReply.greskaPisaca => (
          MqttSendOutcome.odbijeno,
          'Nije ispisana, provjeri pisač glavnog programa.',
        ),
      MqttOrderReply.zastarjela => (
          MqttSendOutcome.zastarjela,
          'Nije primljena, zastarjela. Pošalji ponovno; ako se ponovi odmah, '
              'provjeri sat na uređaju.',
        ),
      MqttOrderReply.nijeAktiviran => (
          MqttSendOutcome.nijeAktiviran,
          'Pelion Order nije aktiviran, skeniraj kod u glavnom programu.',
        ),
      _ => (MqttSendOutcome.odbijeno, 'Nije primljena.'),
    };
    return MqttSendResult(
      outcome: outcome,
      msgId: r.msgId,
      message: message,
      reply: r,
    );
  }
}
