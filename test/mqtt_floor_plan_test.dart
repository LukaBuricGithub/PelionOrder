import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pelion_order/features/mqtt/models/mqtt_floor_plan.dart';

/// A `podaci/tlocrt` message in the shape the kasa publishes it
/// (tlocrt-mobitel.md §3/§4), small enough to reason about by hand: 8 × 8,
/// a wall along the top row, a door, and two tables.
String _payload({
  bool enabled = true,
  int version = 1,
  int cols = 8,
  int rows = 8,
}) {
  return jsonEncode({
    'ts': 1790928000000,
    'uredaj': 'DEMO-POS-1',
    'ukljuceno': enabled,
    'terase': [
      {
        'id': 1,
        'spremljen': true,
        'tlocrt': {
          'verzija': version,
          'celija': 16,
          'sirina': cols,
          'visina': rows,
          'boja_pozadine': '#202020',
          'legenda': {
            '#': {'tip': 'zid'},
            '=': {'tip': 'vrata'},
            'B': {'tip': 'sank'},
          },
          'podloga': [
            '###=####',
            '........',
            '........',
            '........',
            '........',
            '........',
            'BBBB....',
            '........',
          ],
          'objekti': [
            {
              'tip': 'stol',
              'stol': 6,
              'x': 3,
              'y': 2,
              'w': 3,
              'h': 3,
              'oblik': 'K',
              'sjedala': 2,
            },
            {
              'tip': 'stol',
              'stol': 0,
              'x': 0,
              'y': 4,
              'w': 2,
              'h': 2,
              'oblik': 'O',
              'sjedala': 0,
            },
            {'tip': 'tekst', 'tekst': 'Šank', 'x': 0, 'y': 6, 'w': 4, 'h': 1},
          ],
        },
      },
    ],
  });
}

void main() {
  group('MqttFloorPlan', () {
    test('parses a terrace, its grid and its objects', () {
      final plan = MqttFloorPlan.tryParse(_payload())!;
      expect(plan.enabled, isTrue);
      expect(plan.terraces, hasLength(1));

      final doc = plan.forTerrace(1)!.plan;
      expect(doc.cols, 8);
      expect(doc.rows, 8);
      expect(doc.objects, hasLength(3));
      expect(plan.forTerrace(99), isNull);
    });

    test('reads cell types through the legend, floor by default', () {
      final doc = MqttFloorPlan.tryParse(_payload())!.forTerrace(1)!.plan;
      expect(doc.cellType(0, 0), 'zid');
      expect(doc.cellType(3, 0), 'vrata');
      expect(doc.cellType(0, 6), 'sank');
      expect(doc.cellType(4, 4), 'pod'); // '.' is not in the legend
      expect(doc.cellType(-1, 0), 'pod'); // outside the grid
      expect(doc.cellType(99, 99), 'pod');
    });

    test('keeps table 0 — a valid table number', () {
      final doc = MqttFloorPlan.tryParse(_payload())!.forTerrace(1)!.plan;
      expect(doc.tablesByNumber.keys, containsAll(<int>[0, 6]));
      expect(doc.tablesByNumber[0]!.shape, 'O');
      expect(doc.tablesByNumber[6]!.seats, 2);
    });

    test('a table is hit anywhere inside its frame, seating included', () {
      final table = MqttFloorPlan.tryParse(
        _payload(),
      )!.forTerrace(1)!.plan.tablesByNumber[6]!;
      expect(table.contains(3, 2), isTrue); // top-left cell
      expect(table.contains(5, 4), isTrue); // bottom-right cell
      expect(table.contains(6, 4), isFalse); // one past the frame
      expect(table.contains(2, 2), isFalse);
    });

    test('an unsupported format version is unusable, so the grid is used', () {
      final plan = MqttFloorPlan.tryParse(_payload(version: 2))!;
      expect(plan.terraces, isEmpty);
    });

    test('a grid outside the kasa\'s 8–256 limit is rejected', () {
      expect(MqttFloorPlan.tryParse(_payload(cols: 4))!.terraces, isEmpty);
      expect(MqttFloorPlan.tryParse(_payload(rows: 300))!.terraces, isEmpty);
    });

    test('TLOCRT_ON off parses as "no plan", not as an error', () {
      final plan = MqttFloorPlan.tryParse(
        jsonEncode({
          'ts': 1790928000000,
          'uredaj': 'DEMO-POS-1',
          'ukljuceno': false,
          'terase': [],
        }),
      )!;
      expect(plan.enabled, isFalse);
      expect(plan.terraces, isEmpty);
    });

    test('a short podloga row is padded instead of failing', () {
      final raw = jsonEncode({
        'ukljuceno': true,
        'terase': [
          {
            'id': 2,
            'tlocrt': {
              'verzija': 1,
              'sirina': 8,
              'visina': 8,
              'legenda': {
                '#': {'tip': 'zid'},
              },
              'podloga': ['##', '', '........'],
              'objekti': [],
            },
          },
        ],
      });
      final doc = MqttFloorPlan.tryParse(raw)!.forTerrace(2)!.plan;
      expect(doc.ground, hasLength(8));
      expect(doc.cellType(0, 0), 'zid');
      expect(doc.cellType(7, 0), 'pod'); // padded
      expect(doc.cellType(3, 7), 'pod'); // missing row
    });

    test('rubbish is rejected rather than half-parsed', () {
      expect(MqttFloorPlan.tryParse('not json'), isNull);
      expect(MqttFloorPlan.tryParse('[]'), isNull);
    });
  });
}
