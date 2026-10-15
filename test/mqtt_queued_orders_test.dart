import 'package:flutter_test/flutter_test.dart';
import 'package:pelion_order/features/mqtt/state/mqtt_cart.dart';
import 'package:pelion_order/features/mqtt/state/mqtt_outbox_provider.dart';
import 'package:pelion_order/features/mqtt/state/mqtt_send_gate_provider.dart';

/// "Čeka slanje": the waiter may press Pošalji while sending is locked. The
/// order is frozen, never published, and goes out by itself when it can.
MqttOutboxOrder _order(MqttOutboxStatus status, {DateTime? createdAt}) =>
    MqttOutboxOrder(
      msgId: 'm1',
      stol: 31,
      cuser: '01',
      payload: '{}',
      lines: [MqttCartLine(101)],
      sentLineCount: 1,
      createdAt: createdAt ?? DateTime(2026, 10, 15, 20, 15),
      status: status,
    );

void main() {
  group('which locked states may still take an order', () {
    test('the three passing reasons queue', () {
      expect(MqttSendGate.ordermanNijeSpojen.canQueue, isTrue);
      expect(MqttSendGate.kasaNijeSpojena.canQueue, isTrue);
      expect(MqttSendGate.kasaNijeUProdaji.canQueue, isTrue);
    });

    test('a phone with no QR code still refuses', () {
      // Nothing to address the order to: no uredaj, no licence, no broker.
      expect(MqttSendGate.skenirajKod.canQueue, isFalse);
    });

    test('an open gate sends rather than queues', () {
      expect(MqttSendGate.otkljucano.canQueue, isFalse);
      expect(MqttSendGate.otkljucano.isOpen, isTrue);
    });
  });

  group('a queued order', () {
    final queued = _order(MqttOutboxStatus.queued);

    test('asks nothing of the waiter, so it is not red', () {
      expect(queued.isQueued, isTrue);
      expect(queued.needsAttention, isFalse, reason: 'its table stays amber');
      expect(queued.isProblem, isFalse);
    });

    test('offers no resend — it goes by itself — but can be deleted', () {
      expect(queued.canResend, isFalse);
      expect(queued.canDelete, isTrue);
    });

    test('was never published, so deleting it warns about nothing', () {
      expect(queued.mayBePrinted, isFalse);
    });
  });

  test('a queued order survives a restart as itself', () {
    final restored = MqttOutboxOrder.tryFromJson(
      _order(MqttOutboxStatus.queued).toJson(),
    );
    expect(restored?.status, MqttOutboxStatus.queued);
  });

  group('poslano when a queued order finally goes out', () {
    // The rule flushQueued() applies, kept here because it is the one thing
    // that decides whether the kasa accepts or refuses the order.
    test('a never-published order is restamped — it has nothing to repeat', () {
      expect(_order(MqttOutboxStatus.queued).published, isFalse);
    });

    test('a published one keeps its own, per §11.6', () {
      // Pressing "Pošalji ponovno" on a red order while sending is locked
      // puts an ALREADY SENT order back in the queue; a resend must carry the
      // same msg_id and the same poslano as the send it repeats.
      final resent = _order(
        MqttOutboxStatus.unconfirmed,
      ).copyWith(published: true, status: MqttOutboxStatus.queued);
      expect(resent.isQueued, isTrue);
      expect(resent.published, isTrue);
    });
  });

  group('the queue clock', () {
    final placed = DateTime(2026, 10, 15, 20, 0);

    test('runs from when the order was placed, the first time', () {
      expect(
        _order(MqttOutboxStatus.queued, createdAt: placed).queuedSince,
        placed,
      );
    });

    test('restarts when the waiter puts an expired order back in', () {
      // Otherwise "Stavi u red" would be useless: the order is already older
      // than the cap and would expire again on the next sweep.
      final back = placed.add(const Duration(hours: 1));
      final requeued = _order(
        MqttOutboxStatus.notSent,
        createdAt: placed,
      ).copyWith(status: MqttOutboxStatus.queued, queuedAt: back);
      expect(requeued.queuedSince, back);
      expect(
        requeued.createdAt,
        placed,
        reason: 'the list still shows when the items were ordered',
      );
    });

    test('survives a restart', () {
      final back = placed.add(const Duration(minutes: 90));
      final saved = _order(
        MqttOutboxStatus.queued,
        createdAt: placed,
      ).copyWith(queuedAt: back).toJson();
      expect(MqttOutboxOrder.tryFromJson(saved)?.queuedSince, back);
    });
  });

  test('the wait before the waiter is asked to decide is half an hour', () {
    // Longer and a kasa switched on at 23:00 prints for a table that left at
    // 20:30 — the kasa cannot catch that, because `poslano` is stamped when
    // the order finally goes out.
    //
    // Lowering this to try the cycle quickly is fine; this test is the thing
    // that stops the testing value reaching a release.
    expect(MqttOutboxNotifier.queuedMaxWait, const Duration(minutes: 30));
  });
}
