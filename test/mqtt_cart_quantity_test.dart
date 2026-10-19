import 'package:flutter_test/flutter_test.dart';
import 'package:pelion_order/features/mqtt/state/mqtt_cart.dart';

/// The "Popis" layout orders by ARTICLE: pressing the same one again raises
/// its quantity instead of starting a second line, and at zero it leaves the
/// order. The grid layout's one-line-per-tap behaviour is untouched.
void main() {
  test('pressing the same article again raises its quantity', () {
    final cart = MqttCart();
    cart
      ..addQuantity(101)
      ..addQuantity(101)
      ..addQuantity(101);
    expect(cart.lines.length, 1, reason: 'one line, not three');
    expect(cart.quantityOf(101), 3);
  });

  test('different articles keep their own rows', () {
    final cart = MqttCart()
      ..addQuantity(101)
      ..addQuantity(202)
      ..addQuantity(101);
    expect(cart.lines.length, 2);
    expect(cart.quantityOf(101), 2);
    expect(cart.quantityOf(202), 1);
  });

  test('going below one removes the article from the order', () {
    final cart = MqttCart()
      ..addQuantity(101)
      ..addQuantity(101);
    cart.removeQuantity(101);
    expect(cart.quantityOf(101), 1);
    cart.removeQuantity(101);
    expect(cart.quantityOf(101), 0);
    expect(cart.isEmpty, isTrue, reason: 'the line is gone, not left at zero');
  });

  test('removing something that was never ordered does nothing', () {
    final cart = MqttCart()..removeQuantity(999);
    expect(cart.isEmpty, isTrue);
  });

  group('setting a quantity outright (the number pad)', () {
    test('enters a measure in one go, for things sold by weight', () {
      // 300 g of steak is typed once, not pressed three hundred times.
      final cart = MqttCart()..setQuantityOf(101, 300);
      expect(cart.lines.length, 1);
      expect(cart.quantityOf(101), 300);
    });

    test('replaces the quantity of an article already ordered', () {
      final cart = MqttCart()
        ..addQuantity(101)
        ..setQuantityOf(101, 250);
      expect(cart.quantityOf(101), 250);
      expect(cart.lines.length, 1);
    });

    test('zero takes the article out of the order', () {
      final cart = MqttCart()
        ..addQuantity(101)
        ..setQuantityOf(101, 0);
      expect(cart.isEmpty, isTrue);
    });

    test('zero on an article that was never ordered adds nothing', () {
      final cart = MqttCart()..setQuantityOf(101, 0);
      expect(cart.isEmpty, isTrue);
    });
  });

  test('the napomene editor can find the line for an article', () {
    final cart = MqttCart()..addQuantity(101);
    expect(cart.lineIndexOf(101), 0);
    expect(cart.lineIndexOf(999), -1, reason: 'not ordered');
  });

  test('a cart built tap-by-tap still reads back correctly', () {
    // Switching layouts mid-order must not confuse the stepper: the grid adds
    // a line per tap, and the count has to be the sum of them.
    final cart = MqttCart()
      ..addLine(101)
      ..addLine(101);
    expect(cart.lines.length, 2);
    expect(cart.quantityOf(101), 2);
    cart.addQuantity(101);
    expect(cart.lines.length, 2, reason: 'merged into the last line');
    expect(cart.quantityOf(101), 3);
  });
}
