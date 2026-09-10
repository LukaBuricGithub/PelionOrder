import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/mqtt_table_query_sender.dart';
import '../models/mqtt_table_query.dart';

/// What is on one table right now, asked from the kasa — the existing order the
/// order screen and its details screen show above the new lines.
///
/// A ChangeNotifier owned by the order screen and handed to the details screen,
/// so both render the same snapshot and one refresh serves both.
///
/// Refresh is deliberately not a blind poll: the order screen re-asks when
/// `podaci/stolovi_stanje` announces a change on this table, and this class only
/// polls on its own while `na_cekanju > 0` — the one state nothing else will
/// announce.
class MqttTableContents extends ChangeNotifier {
  MqttTableContents(this.stol);

  final int stol;

  /// The latest answer, kept while a newer one is being fetched so the list
  /// never blanks during a refresh.
  MqttTableQueryReply? reply;

  /// Waiting for the FIRST answer.
  bool loading = false;

  /// [loading], and slow enough to be worth saying so in words. Placeholder
  /// rows cover the wait from the first frame, so the "Učitavanje…" line is
  /// only for a kasa that is genuinely slow — a normal answer never shows it.
  bool get showLoading => loading && _slow;
  bool _slow = false;
  Timer? _slowTimer;
  static const _loadingGrace = Duration(seconds: 3);

  /// Why the kasa couldn't be asked — only set while there is no [reply] yet.
  String? error;

  Timer? _timer;
  bool _inFlight = false;
  bool _rerun = false;
  bool _disposed = false;

  /// Budget for the "still transferring" re-ask. Refilled on every deliberate
  /// refresh and whenever the pending count actually drops, so a slow but
  /// progressing transfer is watched to the end.
  int _pendingAsks = 0;
  static const _maxPendingAsks = 20; // 20 × 3 s ≈ a minute without progress

  Future<void> refresh({bool refill = false}) async {
    if (_disposed) return;
    if (refill) _pendingAsks = 0;
    // One query at a time; a refresh requested meanwhile runs once afterwards.
    if (_inFlight) {
      _rerun = true;
      return;
    }
    _inFlight = true;
    if (reply == null) {
      loading = true;
      // Deliberately not shown yet: the loading row appears only if the answer
      // is slow (see [showLoading]).
      _slowTimer ??= Timer(_loadingGrace, () {
        if (_disposed || !loading) return;
        _slow = true;
        notifyListeners();
      });
    }
    try {
      final result = await MqttTableQuerySender.instance.ask(stol);
      if (_disposed) return;
      final next = result.reply;
      if (result.isOk && next != null) {
        final prev = reply?.naCekanju;
        if (prev != null && next.naCekanju < prev) _pendingAsks = 0;
        reply = next;
        error = null;
      } else if (reply == null) {
        error =
            result.message.isNotEmpty ? result.message : 'Kasa ne odgovara.';
      }
      loading = false;
      _slow = false;
      _slowTimer?.cancel();
      _slowTimer = null;
      notifyListeners();

      _timer?.cancel();
      final r = reply;
      if (r != null && r.naCekanju > 0 && _pendingAsks < _maxPendingAsks) {
        _pendingAsks++;
        _timer = Timer(const Duration(seconds: 3), refresh);
      }
    } finally {
      _inFlight = false;
      if (_rerun && !_disposed) {
        _rerun = false;
        refresh();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _slowTimer?.cancel();
    super.dispose();
  }
}
