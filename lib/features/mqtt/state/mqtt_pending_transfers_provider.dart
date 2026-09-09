import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mqtt_service.dart';
import '../data/mqtt_table_query_sender.dart';

/// Tables whose orders the kasa has ACCEPTED but not yet moved onto the table
/// (`na_cekanju > 0`), so the floor plan can mark them.
///
/// This can't come from the floor plan's own data: `podaci/stolovi_stanje` is
/// retained and carries only stol/cuser/konobar/iznos/stavki — nothing about a
/// transfer in flight. That count exists only in a table QUERY reply.
///
/// Querying every table to paint a floor plan would be absurd, but we never
/// need to: a transfer is only pending because THIS device just sent an order,
/// so the watch list is whatever we sent recently — normally one table, never
/// more than a few.
class MqttPendingTransfersNotifier extends StateNotifier<Set<int>> {
  MqttPendingTransfersNotifier() : super(const {});

  Timer? _timer;
  bool _polling = false;

  /// When to give up on each table, so a kasa that never drains cannot leave us
  /// polling for the rest of the shift.
  final _deadlines = <int, DateTime>{};

  static const _interval = Duration(seconds: 3);
  static const _maxWatch = Duration(minutes: 5);

  /// Starts watching [stol] — call it right after the kasa accepts an order.
  void watchTable(int stol) {
    _deadlines[stol] = DateTime.now().add(_maxWatch);
    state = {...state, stol};
    _timer ??= Timer.periodic(_interval, (_) => _poll());
  }

  void _drop(int stol) {
    _deadlines.remove(stol);
    final next = {...state}..remove(stol);
    state = next;
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
      for (final stol in state.toList()) {
        if (!mounted) return;
        final deadline = _deadlines[stol];
        if (deadline != null && DateTime.now().isAfter(deadline)) {
          debugPrint('MQTT ▸ giving up watching table $stol — still pending '
              'after ${_maxWatch.inMinutes} min');
          _drop(stol);
          continue;
        }
        final result = await MqttTableQuerySender.instance.ask(stol);
        if (!mounted) return;
        final reply = result.reply;
        // Only a definite "nothing pending" clears the mark. A timeout or a
        // rejection leaves it up: we cannot show "everything arrived" on the
        // strength of an answer we never got.
        if (result.isOk && reply != null && reply.naCekanju == 0) {
          _drop(stol);
        }
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

final mqttPendingTransfersProvider =
    StateNotifierProvider<MqttPendingTransfersNotifier, Set<int>>(
        (ref) => MqttPendingTransfersNotifier());
