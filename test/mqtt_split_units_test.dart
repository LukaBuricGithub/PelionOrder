import 'package:flutter_test/flutter_test.dart';
import 'package:pelion_order/features/mqtt/data/mqtt_order_sender.dart';
import 'package:pelion_order/features/mqtt/state/mqtt_cart.dart';
import 'package:pelion_order/features/settings/models/order_entry_layout.dart';
import 'package:pelion_order/features/settings/state/settings_provider.dart';

/// "Grupiraj artikle narudžbe", the "Popis" layout's own setting. Off (the
/// default): each press of + is a portion of its own, so the kitchen reads
/// three coffees on three lines and each can be told apart. On: the press
/// raises the count and the article stays one entry.
///
/// A quantity TYPED into the number pad is a quantity either way — one line of
/// three is one entry of three. Only + makes entries.
void main() {
  group('ungrouped: + makes a portion of its own', () {
    test('three presses are three entries of one', () {
      final cart = MqttCart()
        ..addUnit(101)
        ..addUnit(101)
        ..addUnit(101);
      expect(cart.lines.length, 3);
      expect(cart.lines.every((l) => l.qty == 1), isTrue);
      // The price-list row still reads the article as a whole.
      expect(cart.quantityOf(101), 3);
    });

    test("an article's portions stay together", () {
      // Ordered A, B, A — the ticket must not interleave them.
      final cart = MqttCart()
        ..addUnit(101)
        ..addUnit(202)
        ..addUnit(101);
      expect(cart.lines.map((l) => l.code).toList(), [101, 101, 202]);
    });

    test('a new portion never inherits the last one napomena', () {
      final cart = MqttCart()..addUnit(101);
      cart
        ..addCustomNote(0, 'bez šećera')
        ..addUnit(101);
      expect(cart.lines.length, 2);
      expect(cart.lines[0].customNotes, ['bez šećera']);
      expect(cart.lines[1].customNotes, isEmpty);
      expect(cart.lines[1].remarkCodes, isEmpty);
    });

    test('each portion carries its own napomena to the kitchen', () {
      final cart = MqttCart()
        ..addUnit(101)
        ..addUnit(101)
        ..addUnit(101);
      cart.addCustomNote(1, 'bez šećera');
      final noted = cart.lines.where((l) => l.customNotes.isNotEmpty);
      expect(noted.length, 1, reason: 'one of three, not all three');
    });

    test('a typed quantity stays one entry — only + makes entries', () {
      final cart = MqttCart()..addUnit(101);
      cart.setTotalOf(101, 3);
      expect(cart.lines.length, 1, reason: '3 × KAVA, one line');
      expect(cart.lines.first.qty, 3);
    });

    group('the pad sets the TOTAL the row shows', () {
      // The row speaks for the article and shows the sum of its portions, so
      // the number typed in has to come back out of it. Writing to the last
      // portion alone gave 1 + 1 + 5 = 7 on a row that read 3.
      test('typing 5 over three portions leaves five, not seven', () {
        final cart = MqttCart()
          ..addUnit(101)
          ..addUnit(101)
          ..addUnit(101);
        cart.setTotalOf(101, 5);
        expect(cart.quantityOf(101), 5);
      });

      test('typing less drops whole portions off the back', () {
        final cart = MqttCart()
          ..addUnit(101)
          ..addUnit(101)
          ..addUnit(101);
        cart.setTotalOf(101, 2);
        expect(cart.quantityOf(101), 2);
        expect(cart.lines.length, 2);
      });

      test('down to one portion', () {
        final cart = MqttCart()
          ..addUnit(101)
          ..addUnit(101)
          ..addUnit(101);
        cart.setTotalOf(101, 1);
        expect(cart.quantityOf(101), 1);
        expect(cart.lines.length, 1);
      });

      test('the napomena on an earlier portion survives', () {
        final cart = MqttCart()..addUnit(101);
        cart
          ..addCustomNote(0, 'bez šećera')
          ..addUnit(101)
          ..setTotalOf(101, 6);
        expect(cart.quantityOf(101), 6);
        expect(cart.lines.first.customNotes, ['bez šećera']);
      });

      test('shrinking past it keeps it, reduced', () {
        final cart = MqttCart()..addUnit(101);
        cart
          ..addCustomNote(0, 'bez šećera')
          ..addUnit(101)
          ..addUnit(101)
          ..setTotalOf(101, 1);
        expect(cart.quantityOf(101), 1);
        expect(cart.lines.single.customNotes, ['bez šećera']);
      });

      test('a measure lands exactly, with no rounding drift', () {
        final cart = MqttCart()..addUnit(101);
        cart.setTotalOf(101, 0.3);
        expect(cart.quantityOf(101), 0.3);
      });

      test('other articles are untouched', () {
        final cart = MqttCart()
          ..addUnit(101)
          ..addUnit(202)
          ..addUnit(101);
        cart.setTotalOf(101, 4);
        expect(cart.quantityOf(101), 4);
        expect(cart.quantityOf(202), 1);
      });

      test('zero clears every portion of the article', () {
        final cart = MqttCart()
          ..addUnit(101)
          ..addUnit(101)
          ..addUnit(202);
        cart.setTotalOf(101, 0);
        expect(cart.quantityOf(101), 0);
        expect(cart.lines.map((l) => l.code).toList(), [202]);
      });
    });

    test('− takes a portion away, and the last one empties the order', () {
      final cart = MqttCart()
        ..addUnit(101)
        ..addUnit(101);
      cart.removeQuantity(101);
      expect(cart.lines.length, 1);
      cart.removeQuantity(101);
      expect(cart.isEmpty, isTrue);
    });

    test('nothing is merged on the way out', () {
      final cart = MqttCart()
        ..addUnit(101)
        ..addUnit(101);
      // groupArticles is off in this mode, so the payload is the lines as they
      // stand: two entries.
      expect(cart.lines.length, 2);
    });
  });

  group('grouped: + raises the count', () {
    test('three presses are one entry of three', () {
      final cart = MqttCart()
        ..addPlainQuantity(101)
        ..addPlainQuantity(101)
        ..addPlainQuantity(101);
      expect(cart.lines.length, 1);
      expect(cart.quantityOf(101), 3);
    });

    test('but a noted portion is never raised — the next starts clean', () {
      final cart = MqttCart()..addPlainQuantity(101);
      cart
        ..addCustomNote(0, 'bez šećera')
        ..addPlainQuantity(101);
      expect(cart.lines.length, 2);
      expect(cart.lines[1].customNotes, isEmpty);
      expect(cart.quantityOf(101), 2, reason: 'the row still reads two');
    });

    test('a remark code is enough to keep the next portion separate', () {
      final cart = MqttCart()..addPlainQuantity(101);
      cart
        ..toggleRemarkCode(0, '4')
        ..addPlainQuantity(101);
      expect(cart.lines.length, 2);
      expect(cart.lines[1].remarkCodes, isEmpty);
    });

    test('and grouping keeps those two apart, as differing lines must', () {
      final cart = MqttCart()..addPlainQuantity(101);
      cart
        ..addCustomNote(0, 'bez luka')
        ..addPlainQuantity(101);
      expect(groupCartLines(cart.lines).length, 2);
    });

    test('a further press raises the clean portion', () {
      final cart = MqttCart()..addPlainQuantity(101);
      cart
        ..addCustomNote(0, 'bez luka')
        ..addPlainQuantity(101)
        ..addPlainQuantity(101);
      expect(cart.lines.length, 2, reason: 'no third line');
      expect(cart.lines[1].qty, 2);
      expect(cart.quantityOf(101), 3);
    });

    test('the clean portion stays beside the article, not at the end', () {
      final cart = MqttCart()..addPlainQuantity(101);
      cart
        ..addCustomNote(0, 'bez luka')
        ..addPlainQuantity(202)
        ..addPlainQuantity(101);
      expect(cart.lines.map((l) => l.code).toList(), [101, 101, 202]);
    });
  });

  group('which mode applies', () {
    test('ungrouped is the default, and only under Popis', () {
      const list = SettingsState(orderEntryLayout: OrderEntryLayout.list);
      expect(list.splitsOrderUnits, isTrue);
      expect(list.copyWith(groupListUnits: true).splitsOrderUnits, isFalse);
    });

    test('never in the grid, whatever the setting says', () {
      const grid = SettingsState();
      expect(grid.orderEntryLayout, OrderEntryLayout.grid);
      expect(grid.splitsOrderUnits, isFalse);
      expect(grid.copyWith(groupListUnits: true).splitsOrderUnits, isFalse);
      expect(grid.copyWith(groupListUnits: false).splitsOrderUnits, isFalse);
    });

    test('it is a setting of its own — the grid merge flag is untouched', () {
      const s = SettingsState(orderEntryLayout: OrderEntryLayout.list);
      expect(s.copyWith(groupListUnits: true).shouldGroupArticles, isFalse);
    });
  });
}
