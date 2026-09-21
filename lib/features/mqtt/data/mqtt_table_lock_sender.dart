import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/mqtt_table_lock.dart';
import 'mqtt_order_sender.dart' show newQueryId;
import 'mqtt_service.dart';

/// Builds an `ulaz` / `izlaz` message for a table's lock. `stol` goes out as a
/// NUMBER; the kasa echoes it back as a string.
String buildTableLockJson({
  required String msgId,
  required String uredaj,
  required String tip,
  required int stol,
}) {
  return jsonEncode({
    'msg_id': msgId,
    'uredaj': uredaj,
    'tip': tip,
    'stol': stol,
    'ts': DateTime.now().millisecondsSinceEpoch,
  });
}

/// What an `ulaz` / `izlaz` came to.
enum MqttLockOutcome {
  /// The lock is ours (or, for `izlaz`, released).
  ok,

  /// Someone else holds the table — the kasa, or another orderman.
  zauzeto,

  /// No answer: the kasa is off, has no connection, or isn't the one holding
  /// the database. Nothing is known about the lock.
  bezOdgovora,

  /// Failed our own check — no code scanned, or no connection.
  neispravno,
}

class MqttLockResult {
  const MqttLockResult({
    required this.outcome,
    required this.message,
    this.otvorenNa = '',
  });

  final MqttLockOutcome outcome;

  /// What the waiter is told when the table can't be taken.
  final String message;

  /// Who holds the table (`CORD3`, a kasa's tag), when the kasa said so.
  final String otvorenNa;

  bool get isOk => outcome == MqttLockOutcome.ok;
}

/// Takes and releases a table's lock ("brave stolova").
///
/// * `ulaz` before the waiter may work on a table, repeated while the table
///   screen is open — the kasa drops a lock 10 minutes after the last `ulaz`.
/// * `izlaz` when the waiter leaves the table.
///
/// One publish per call with a fresh `msg_id`: nothing is booked here, so
/// there is nothing to be idempotent about, and the repeats are driven by the
/// screen rather than by this class.
class MqttTableLockSender {
  MqttTableLockSender._();
  static final MqttTableLockSender instance = MqttTableLockSender._();

  /// How long to wait for the kasa's answer.
  static const replyTimeout = Duration(seconds: 6);

  /// Announces that this phone is working on [stol].
  Future<MqttLockResult> enter(int stol) => _send('ulaz', stol);

  /// Releases the table. The kasa always answers `ok`, even when there was no
  /// lock, so the result only says whether the message got out.
  Future<MqttLockResult> leave(int stol) => _send('izlaz', stol);

  Future<MqttLockResult> _send(String tip, int stol) async {
    final svc = MqttService.instance;
    final uredaj = svc.clientId;
    if (uredaj == null || !svc.isReplyIdValid) {
      return const MqttLockResult(
        outcome: MqttLockOutcome.neispravno,
        message: 'Neispravan identifikator uređaja, skenirajte QR kod ponovno.',
      );
    }
    if (!svc.isConnected) {
      return const MqttLockResult(
        outcome: MqttLockOutcome.neispravno,
        message: 'Nema veze s glavnim programom.',
      );
    }

    final msgId = newQueryId();
    final payload = buildTableLockJson(
      msgId: msgId,
      uredaj: uredaj,
      tip: tip,
      stol: stol,
    );

    // Listen BEFORE publishing so a fast answer can't be missed.
    final completer = Completer<MqttTableLockReply>();
    final sub = svc.lockReplies.listen((r) {
      if (r.msgId == msgId && !completer.isCompleted) completer.complete(r);
    });

    try {
      debugPrint('MQTT ▸ $tip (stol=$stol, msg_id=$msgId)');
      if (!svc.publishQuery(payload)) {
        return const MqttLockResult(
          outcome: MqttLockOutcome.neispravno,
          message: 'Nema veze s glavnim programom.',
        );
      }
      final reply = await completer.future.timeout(replyTimeout);
      debugPrint('MQTT ◂ $reply');
      if (reply.isOk) {
        return MqttLockResult(
          outcome: MqttLockOutcome.ok,
          message: '',
          otvorenNa: reply.otvorenNa,
        );
      }
      return MqttLockResult(
        outcome: MqttLockOutcome.zauzeto,
        message: reply.poruka.isNotEmpty
            ? reply.poruka
            : 'Stol je otvoren na drugom uređaju.',
        otvorenNa: reply.otvorenNa,
      );
    } on TimeoutException {
      return const MqttLockResult(
        outcome: MqttLockOutcome.bezOdgovora,
        message: 'Glavni program ne odgovara.',
      );
    } finally {
      await sub.cancel();
    }
  }
}
