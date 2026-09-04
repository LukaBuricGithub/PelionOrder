import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mqtt_cart.dart';

/// A table's locally-held order: its lines plus the `msg_id` of the order
/// awaiting a reply (if one has been sent). The id is stored so a retry after
/// leaving the screen still reuses it — a new id would book a duplicate.
class MqttStoredOrder {
  const MqttStoredOrder({required this.lines, this.msgId});

  final List<MqttCartLine> lines;
  final String? msgId;
}

/// Session store of the local (unsent) MQTT orders, keyed by table number
/// (`broj`). Kept in memory for the app session so an order survives leaving the
/// order/details screens; the MQTT table-select screen colours tables that have
/// one.
class MqttOrdersNotifier extends StateNotifier<Map<int, MqttStoredOrder>> {
  MqttOrdersNotifier() : super(const {});

  /// The saved order lines for [broj] (empty when none).
  List<MqttCartLine> linesFor(int broj) => state[broj]?.lines ?? const [];

  /// The pending `msg_id` for [broj], if the order has been sent already.
  String? msgIdFor(int broj) => state[broj]?.msgId;

  /// Stores [lines] (as detached copies) and [msgId] for [broj], or clears the
  /// table's order when [lines] is empty.
  void save(int broj, List<MqttCartLine> lines, String? msgId) {
    final next = Map<int, MqttStoredOrder>.from(state);
    if (lines.isEmpty) {
      next.remove(broj);
    } else {
      next[broj] = MqttStoredOrder(
        lines: [for (final l in lines) l.copy()],
        msgId: msgId,
      );
    }
    state = next;
  }

  /// Drops the table's order entirely (used once the kasa accepted it).
  void clear(int broj) {
    final next = Map<int, MqttStoredOrder>.from(state)..remove(broj);
    state = next;
  }
}

final mqttOrdersProvider =
    StateNotifierProvider<MqttOrdersNotifier, Map<int, MqttStoredOrder>>(
        (ref) => MqttOrdersNotifier());
