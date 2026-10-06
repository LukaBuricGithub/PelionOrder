import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pelion_order/features/mqtt/models/mqtt_menu.dart';

/// The worked example from the spec (Pelion-Orderman-raspored-artikala.md,
/// 5. 10. 2026): a 3 × 4 grid where place 3 is empty and Čokolada sits at
/// place 13 — the first square of the second screen.
String _payload({
  Object? prikaz = const {'stupci': 3, 'redovi': 4, 'scroll': true},
  List<int> places = const [1, 2, 4, 5, 6, 13],
}) {
  return jsonEncode({
    'ts': 1759658400000,
    'uredaj': 'DEMO-POS-1',
    'prikaz': ?prikaz,
    'napomene': [
      {'cnap': '1', 'naziv': 'bez šećera', 'sve': true},
    ],
    'grupe': [
      {
        'id': 1,
        'naziv': 'Kava',
        'rbr': 1,
        'artikli': [
          for (final place in places)
            {
              'cartikl': 100 + place,
              'naziv': 'Artikl $place',
              'cijena': 1.6,
              'jm': 'kom',
              'porez': '25',
              'rbr': place,
              'napomene': <String>[],
            },
        ],
      },
    ],
  });
}

List<MqttArticle> _articles(String raw) =>
    MqttMenu.fromArtikliPayload(raw).groups.single.articles;

/// Names only, with an empty string for an empty square — compact enough to
/// assert a whole screen at a glance.
List<String> _names(List<MqttArticle?> screen) => [
  for (final a in screen) a?.name ?? '',
];

void main() {
  group('prikaz', () {
    test('is read when present and absent otherwise', () {
      final withLayout = MqttMenu.fromArtikliPayload(_payload()).layout!;
      expect(withLayout.columns, 3);
      expect(withLayout.rows, 4);
      expect(withLayout.scroll, isTrue);
      expect(withLayout.slotsPerScreen, 12);

      // No layout saved on the kasa: the message is as it always was.
      expect(
        MqttMenu.fromArtikliPayload(_payload(prikaz: null)).layout,
        isNull,
      );
    });

    test('a grid the kasa cannot produce is ignored', () {
      final menu = MqttMenu.fromArtikliPayload(
        _payload(prikaz: const {'stupci': 99, 'redovi': 4, 'scroll': true}),
      );
      expect(menu.layout, isNull, reason: 'better no layout than a wrong one');
    });
  });

  group('placeInGrid', () {
    test('puts every article in its own square, holes included', () {
      final screens = MqttDisplayLayout.placeInGrid(
        _articles(_payload()),
        columns: 3,
        rows: 4,
        scroll: true,
      );

      expect(screens, hasLength(2), reason: 'place 13 opens a second screen');
      expect(_names(screens.first), [
        'Artikl 1', 'Artikl 2', '', // place 3 is empty
        'Artikl 4', 'Artikl 5', 'Artikl 6',
        '', '', '',
        '', '', '',
      ]);
      // Place 13 is the first square of the second screen, to the right.
      expect(_names(screens[1]).first, 'Artikl 13');
    });

    test('without scrolling there is exactly one screen', () {
      final screens = MqttDisplayLayout.placeInGrid(
        _articles(_payload(places: const [1, 2, 4])),
        columns: 3,
        rows: 4,
        scroll: false,
      );
      expect(screens, hasLength(1));
      expect(_names(screens.single).take(4), [
        'Artikl 1',
        'Artikl 2',
        '',
        'Artikl 4',
      ]);
    });

    test('an article past the only screen is pulled into a free square', () {
      // The kasa does not send this, but a wrong message must not hide an
      // article a waiter has to be able to sell.
      final screens = MqttDisplayLayout.placeInGrid(
        _articles(_payload(places: const [1, 13])),
        columns: 3,
        rows: 4,
        scroll: false,
      );
      expect(screens, hasLength(1));
      expect(_names(screens.single).take(2), ['Artikl 1', 'Artikl 13']);
    });

    test('the same places reflow into the waiter\'s own grid', () {
      // "Moja veličina": the designer's order and holes survive, the geometry
      // is the waiter's — here 4 × 4, so place 13 is still on screen one.
      final screens = MqttDisplayLayout.placeInGrid(
        _articles(_payload()),
        columns: 4,
        rows: 4,
        scroll: true,
      );
      expect(screens, hasLength(1));
      expect(_names(screens.single), [
        'Artikl 1',
        'Artikl 2',
        '',
        'Artikl 4',
        'Artikl 5',
        'Artikl 6',
        '',
        '',
        '',
        '',
        '',
        '',
        'Artikl 13',
        '',
        '',
        '',
      ]);
    });

    test('an article with no place is appended, never dropped', () {
      final screens = MqttDisplayLayout.placeInGrid(
        _articles(_payload(places: const [1, 2, 0])),
        columns: 3,
        rows: 3,
        scroll: true,
      );
      final flat = screens.expand(_names).where((n) => n.isNotEmpty);
      expect(flat, containsAll(['Artikl 1', 'Artikl 2', 'Artikl 0']));
    });

    test('no articles means no screens', () {
      expect(
        MqttDisplayLayout.placeInGrid(
          const [],
          columns: 3,
          rows: 3,
          scroll: true,
        ),
        isEmpty,
      );
    });
  });
}
