import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/session_provider.dart';
import 'mqtt_cart.dart';
import 'mqtt_housekeeping.dart';
import 'mqtt_tables_provider.dart';

/// A table's locally-held order: its lines plus the `msg_id` of the order
/// awaiting a reply (if one has been sent). The id is stored so a retry after
/// leaving the screen still reuses it — a new id would book a duplicate.
class MqttStoredOrder {
  MqttStoredOrder({
    required this.lines,
    this.msgId,
    this.cuser,
    DateTime? touchedAt,
  }) : touchedAt = touchedAt ?? DateTime.now();

  final List<MqttCartLine> lines;
  final String? msgId;

  /// The waiter who started adding these items.
  final String? cuser;

  /// When the items were last changed — NOT when the table was first opened,
  /// so a table someone is still working on can never be swept away under
  /// them (see [MqttOrdersNotifier.pruneExpired]).
  final DateTime touchedAt;
}

/// Session store of the local (unsent) MQTT orders, keyed by table number
/// (`broj`). Kept in memory for the app session only — closing the app drops
/// them — so an order survives leaving the order/details screens; the MQTT
/// table-select screen colours tables that have one blue.
class MqttOrdersNotifier extends StateNotifier<Map<int, MqttStoredOrder>> {
  MqttOrdersNotifier() : super(const {}) {
    _housekeeping = Timer.periodic(
      mqttHousekeepingInterval,
      (_) => pruneExpired(),
    );
  }

  Timer? _housekeeping;

  /// The saved order lines for [broj] (empty when none).
  List<MqttCartLine> linesFor(int broj) => state[broj]?.lines ?? const [];

  /// The pending `msg_id` for [broj], if the order has been sent already.
  String? msgIdFor(int broj) => state[broj]?.msgId;

  /// Stores [lines] (as detached copies) and [msgId] for [broj], or clears the
  /// table's order when [lines] is empty. [cuser] is recorded when the table
  /// gets its first items; later edits keep the original waiter — unless
  /// [takeOver], when [cuser] replaces items they were never shown.
  void save(
    int broj,
    List<MqttCartLine> lines,
    String? msgId, {
    String? cuser,
    bool takeOver = false,
  }) {
    final next = Map<int, MqttStoredOrder>.from(state);
    if (lines.isEmpty) {
      next.remove(broj);
    } else {
      next[broj] = MqttStoredOrder(
        lines: [for (final l in lines) l.copy()],
        msgId: msgId,
        cuser: takeOver ? cuser : (state[broj]?.cuser ?? cuser),
      );
    }
    state = next;
  }

  /// Drops the table's order entirely — once it is sent, or deleted.
  void clear(int broj) {
    if (!state.containsKey(broj)) return;
    final next = Map<int, MqttStoredOrder>.from(state)..remove(broj);
    state = next;
  }

  /// Drops items nobody has touched for [mqttKeepUnsentFor], so a shift never
  /// starts with yesterday's blue tables on the floor plan. On most phones
  /// this never fires — these items live in memory and die with the app — but
  /// a device that is simply never closed would otherwise keep them forever.
  void pruneExpired({DateTime? now}) {
    final next = {
      for (final e in state.entries)
        if (!mqttIsExpired(e.value.touchedAt, now: now)) e.key: e.value,
    };
    if (next.length == state.length) return;
    debugPrint(
      'MQTT ▸ neposlane stavke: brišem ${state.length - next.length} '
      'stolova starijih od ${mqttKeepUnsentFor.inHours} h',
    );
    state = next;
  }

  @override
  void dispose() {
    _housekeeping?.cancel();
    super.dispose();
  }
}

final mqttOrdersProvider =
    StateNotifierProvider<MqttOrdersNotifier, Map<int, MqttStoredOrder>>(
      (ref) => MqttOrdersNotifier(),
    );

/// Whether the signed-in waiter may see the unsent items on [stol]: the
/// waiter who added them, the waiter the kasa lists on the table, or anyone
/// with pravo 008.
bool mqttDraftVisibleTo(
  MqttStoredOrder draft, {
  required String? cuser,
  required String? tableCuser,
  required bool allTables,
}) =>
    allTables ||
    (cuser != null && (draft.cuser == cuser || tableCuser == cuser));

/// The unsent items ("blue" tables) the signed-in waiter may see, by table.
final mqttVisibleDraftsProvider = Provider<Map<int, MqttStoredOrder>>((ref) {
  final me = ref.watch(currentUserProvider);
  final occupied = ref.watch(mqttOccupiedProvider);
  return {
    for (final e in ref.watch(mqttOrdersProvider).entries)
      if (mqttDraftVisibleTo(
        e.value,
        cuser: me?.code,
        tableCuser: occupied[e.key]?.cuser,
        allTables: me?.allTablesOpenRight ?? false,
      ))
        e.key: e.value,
  };
});
