import 'package:flutter_test/flutter_test.dart';
import 'package:pelion_order/features/mqtt/state/mqtt_cart.dart';
import 'package:pelion_order/features/mqtt/state/mqtt_kasa_silence_provider.dart';
import 'package:pelion_order/features/mqtt/state/mqtt_outbox_provider.dart';

/// The field case this covers (7. 10. 2026): a venue ended an evening with
/// seven orders stuck on "Nije potvrđena". All seven had been printed — the
/// kasa answered every one — but the phone was pocketed a moment after each
/// send, the confirmations expired on the broker, and the app offered neither
/// "Pošalji ponovno" nor "Obriši" for that state. Nobody could clear them from
/// any device.
MqttOutboxOrder _order(MqttOutboxStatus status, {bool published = true}) =>
    MqttOutboxOrder(
      msgId: 'm1',
      stol: 31,
      cuser: '01',
      payload: '{}',
      lines: [MqttCartLine(101)],
      sentLineCount: 1,
      createdAt: DateTime(2026, 10, 7, 20, 15),
      status: status,
      published: published,
    );

void main() {
  group('an unconfirmed order', () {
    test('can be sent again and deleted, whatever its age', () {
      final order = _order(MqttOutboxStatus.unconfirmed);
      expect(order.isUnconfirmed, isTrue);
      expect(order.canResend, isTrue);
      expect(order.canDelete, isTrue);
      // It still is not a "didn't get through" case: the kasa very probably
      // printed it, and the waiter is told so.
      expect(order.isProblem, isFalse);
      expect(order.mayBePrinted, isTrue);
    });

    test('needs the waiter, so its table is red like a failed one', () {
      expect(_order(MqttOutboxStatus.unconfirmed).needsAttention, isTrue);
      expect(_order(MqttOutboxStatus.notSent).needsAttention, isTrue);
      expect(_order(MqttOutboxStatus.refused).needsAttention, isTrue);
      expect(_order(MqttOutboxStatus.stale).needsAttention, isTrue);
    });
  });

  test('an order inside its 10-second wait gets no buttons', () {
    final order = _order(MqttOutboxStatus.sending);
    expect(order.canResend, isFalse);
    expect(order.canDelete, isFalse);
    expect(order.needsAttention, isFalse);
    // But deleting it would still be risky, if it ever could be deleted.
    expect(order.mayBePrinted, isTrue);
  });

  group('MqttKasaSilenceNotifier', () {
    test('warns only from the second unanswered order on', () {
      final silence = MqttKasaSilenceNotifier();
      expect(silence.state, 0);
      silence.unanswered();
      // One lost confirmation is normal: the phone went into a pocket.
      expect(silence.state < MqttKasaSilenceNotifier.threshold, isTrue);
      silence.unanswered();
      expect(silence.state >= MqttKasaSilenceNotifier.threshold, isTrue);
    });

    test('anything the kasa says clears it, refusals included', () {
      final silence = MqttKasaSilenceNotifier()
        ..unanswered()
        ..unanswered()
        ..answered();
      expect(silence.state, 0);
    });
  });

  group('mqttKasaSilenceText', () {
    test('counts in words up to four', () {
      expect(mqttKasaSilenceText(2), 'Zadnje dvije narudžbe nisu potvrđene');
      expect(mqttKasaSilenceText(4), 'Zadnje četiri narudžbe nisu potvrđene');
    });

    test('switches to the genitive from five on', () {
      expect(mqttKasaSilenceText(7), 'Zadnjih 7 narudžbi nije potvrđeno');
    });
  });
}
