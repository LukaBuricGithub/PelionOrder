import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mqtt_cart.dart';

/// Session store of the local (unsent) MQTT orders, keyed by table number
/// (`broj`). Kept in memory for the app session so an order survives leaving the
/// order/details screens; the MQTT table-select screen colours tables that have
/// one. Nothing is sent to the broker (the MQTT flow's Send is a no-op).
class MqttOrdersNotifier extends StateNotifier<Map<int, List<MqttCartLine>>> {
  MqttOrdersNotifier() : super(const {});

  /// The saved order lines for [broj] (empty when none).
  List<MqttCartLine> linesFor(int broj) => state[broj] ?? const [];

  /// Stores [lines] for [broj] (as detached copies), or clears the table's order
  /// when [lines] is empty.
  void save(int broj, List<MqttCartLine> lines) {
    final next = Map<int, List<MqttCartLine>>.from(state);
    if (lines.isEmpty) {
      next.remove(broj);
    } else {
      next[broj] = [for (final l in lines) l.copy()];
    }
    state = next;
  }
}

final mqttOrdersProvider =
    StateNotifierProvider<MqttOrdersNotifier, Map<int, List<MqttCartLine>>>(
        (ref) => MqttOrdersNotifier());
