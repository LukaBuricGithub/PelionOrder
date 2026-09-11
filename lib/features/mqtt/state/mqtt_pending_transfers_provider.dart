import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mqtt_service.dart';
import '../data/mqtt_table_query_sender.dart';
import '../models/mqtt_table_query.dart';
import 'mqtt_cart.dart';

/// One order this device sent that the kasa ACCEPTED but has not yet moved onto
/// the table.
class MqttInTransitOrder {
  const MqttInTransitOrder({
    required this.msgId,
    required this.lines,
    required this.sentLineCount,
  });

  final String msgId;

  /// The lines as the waiter built them (detached copies). Kept because until
  /// the kasa transfers them, its query reply cannot show them: it lists only
  /// what is already ON the table, and reports travelling lines as a bare count.
  final List<MqttCartLine> lines;

  /// How many `stavke` actually went out, after grouping — the number the kasa
  /// counts in `na_cekanju`, which differs from [lines] when grouping is on.
  final int sentLineCount;
}

/// Orders this device sent that are accepted but not yet on their table, keyed
/// by table number — so the floor plan can mark those tables, and the order
/// screen can show the travelling lines as "na putu".
///
/// This can't come from the floor plan's own data: `podaci/stolovi_stanje` is
/// retained and carries only stol/cuser/konobar/iznos/stavki — nothing about a
/// transfer in flight. That count exists only in a table QUERY reply, and even
/// there only as a number, never as lines.
///
/// Querying every table to paint a floor plan would be absurd, but we never
/// need to: a transfer is only pending because THIS device just sent an order,
/// so the watch list is whatever we sent recently — normally one table, never
/// more than a few.
class MqttPendingTransfersNotifier
    extends StateNotifier<Map<int, List<MqttInTransitOrder>>> {
  MqttPendingTransfersNotifier() : super(const {});

  Timer? _timer;
  bool _polling = false;

  /// When to give up on each table, so a kasa that never drains cannot leave us
  /// polling for the rest of the shift.
  final _deadlines = <int, DateTime>{};

  static const _interval = Duration(seconds: 3);
  static const _maxWatch = Duration(minutes: 5);

  /// Tables whose last watch ended because the order LANDED — not because we
  /// gave up on it. The floor plan uses this to keep such a table drawn as ours
  /// until `stolovi_stanje` catches up, instead of flashing it free in between.
  final _landed = <int>{};

  /// Whether the watch on [stol] ended with its order on the table.
  bool justLanded(int stol) => _landed.contains(stol);

  /// Starts watching [stol] — call it right after the kasa accepts [order].
  void watchTable(int stol, MqttInTransitOrder order) {
    _landed.remove(stol);
    _deadlines[stol] = DateTime.now().add(_maxWatch);
    state = {
      ...state,
      stol: [...?state[stol], order],
    };
    _timer ??= Timer.periodic(_interval, (_) => _poll());
  }

  /// Whether this device's lines for a table have all landed, judged from a
  /// query [reply].
  ///
  /// When the kasa names the devices still pending, that is trusted — otherwise
  /// a colleague's transfer on the same table would keep OUR lines shown as
  /// travelling after they had landed, i.e. twice. Without that list, only a
  /// zero total count is conclusive.
  static bool transferLanded(MqttTableQueryReply reply, String? od) {
    if (reply.naCekanju == 0) return true;
    if (reply.naCekanjuUredaji.isNotEmpty) return !reply.pendingForDevice(od);
    return false;
  }

  /// Applies a query reply obtained elsewhere — the order screen asks too — so
  /// landed lines are cleared the moment ANY fresh answer shows it.
  void applyReply(int stol, MqttTableQueryReply reply) {
    if (!state.containsKey(stol)) return;
    if (transferLanded(reply, MqttService.instance.clientId)) {
      _landed.add(stol);
      _drop(stol);
    }
  }

  void _drop(int stol) {
    _deadlines.remove(stol);
    state = {...state}..remove(stol);
    if (state.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _poll() async {
    // A query can take longer than the interval (6 s timeout, two attempts), so
    // never let two rounds overlap.
    if (_polling) return;
    if (state.isEmpty) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    // Offline: keep the marks, stop asking. The watch resumes on reconnect.
    if (!MqttService.instance.isConnected) return;

    _polling = true;
    try {
      for (final stol in state.keys.toList()) {
        if (!mounted) return;
        final deadline = _deadlines[stol];
        if (deadline != null && DateTime.now().isAfter(deadline)) {
          debugPrint('MQTT ▸ giving up watching table $stol — still pending '
              'after ${_maxWatch.inMinutes} min');
          _landed.remove(stol);
          _drop(stol);
          continue;
        }
        final result = await MqttTableQuerySender.instance.ask(stol);
        if (!mounted) return;
        final reply = result.reply;
        // Only a definite answer can clear the mark. A timeout or a rejection
        // leaves it up: "everything arrived" can't rest on a reply never got.
        if (result.isOk && reply != null) applyReply(stol, reply);
      }
    } finally {
      _polling = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final mqttPendingTransfersProvider = StateNotifierProvider<
    MqttPendingTransfersNotifier, Map<int, List<MqttInTransitOrder>>>(
  (ref) => MqttPendingTransfersNotifier(),
);
