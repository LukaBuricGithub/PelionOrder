import 'package:flutter_test/flutter_test.dart';
import 'package:pelion_order/features/mqtt/state/mqtt_cart.dart';
import 'package:pelion_order/features/mqtt/state/mqtt_housekeeping.dart';
import 'package:pelion_order/features/mqtt/state/mqtt_orders_provider.dart';

/// "Neposlane narudžbe" clears itself after a day, so a shift never starts on
/// yesterday's list — the blue items here, the red orders in the outbox.
void main() {
  final now = DateTime(2026, 10, 12, 20, 0);

  group('mqttIsExpired', () {
    test('keeps an entry right up to the 24th hour', () {
      final almost = now.subtract(const Duration(hours: 23, minutes: 59));
      expect(mqttIsExpired(almost, now: now), isFalse);
    });

    test('clears it at 24 hours and beyond', () {
      expect(
        mqttIsExpired(now.subtract(const Duration(hours: 24)), now: now),
        isTrue,
      );
      expect(
        mqttIsExpired(now.subtract(const Duration(days: 3)), now: now),
        isTrue,
      );
    });

    test('a clock that jumped backwards deletes nothing', () {
      expect(
        mqttIsExpired(now.add(const Duration(hours: 5)), now: now),
        isFalse,
      );
    });
  });

  group('MqttOrdersNotifier', () {
    test('sweeps tables nobody has touched for a day', () {
      final orders = MqttOrdersNotifier();
      addTearDown(orders.dispose);
      orders.save(11, [MqttCartLine(101)], null, cuser: '01');
      orders.save(12, [MqttCartLine(102)], null, cuser: '01');

      orders.pruneExpired(now: DateTime.now());
      expect(orders.state.length, 2, reason: 'fresh items stay');

      orders.pruneExpired(now: DateTime.now().add(const Duration(hours: 25)));
      expect(orders.state, isEmpty);
    });

    test('every edit restamps the table, so an open one is never swept', () {
      final orders = MqttOrdersNotifier();
      addTearDown(orders.dispose);
      orders.save(7, [MqttCartLine(101)], null);
      final stamped = orders.state[7]!.touchedAt;
      expect(DateTime.now().difference(stamped).inSeconds, lessThan(2));
    });
  });
}
