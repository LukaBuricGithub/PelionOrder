import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/mqtt_table_lock_sender.dart';

/// Holds one table's lock while its screen is open ("brave stolova").
///
/// The kasa drops a phone's lock 10 minutes after the last `ulaz`, so the
/// announcement is repeated every [refreshEvery] while the waiter is on the
/// table. A table opened without an answer (kasa offline) keeps announcing
/// itself too: the first `ulaz` that gets through claims the table, so a
/// cashier coming back later sees it as taken.
///
/// [onLost] fires when the kasa says somebody else holds the table — the
/// screen must then close and show the message.
class MqttTableLockKeeper {
  MqttTableLockKeeper({
    required this.stol,
    required this.onLost,
    bool alreadyGranted = false,
  }) {
    // Never two keepers at once: an older screen that somehow outlived its
    // table would keep announcing `ulaz` and take the table back. Replacing
    // the keeper of the SAME table sends NO `izlaz` — the table was just
    // claimed for this screen, and an `izlaz` would give it away again.
    final previous = _active;
    if (previous != null && previous != this) {
      previous.release(announce: previous.stol != stol);
    }
    _active = this;
    debugPrint('MQTT ▸ lock: holding stol $stol');
    // The floor plan takes the lock before opening the screen; then the first
    // refresh is due only after [refreshEvery].
    if (!alreadyGranted) unawaited(_announce());
    _timer = Timer.periodic(refreshEvery, (_) => unawaited(_announce()));
  }

  /// The keeper of the table currently open, if any.
  static MqttTableLockKeeper? _active;

  /// The app is going to the background: release the table now. A clean
  /// disconnect means the broker never publishes our last will, so without
  /// this the kasa would hold the lock until it expires (10 min).
  static void releaseForBackground() {
    final keeper = _active;
    if (keeper == null || keeper._released) return;
    debugPrint('MQTT ▸ lock: app paused, izlaz for stol ${keeper.stol}');
    keeper._held = false;
    unawaited(MqttTableLockSender.instance.leave(keeper.stol));
  }

  /// The app is back: claim the open table again.
  static void refreshAfterResume() => _active?.refreshNow();

  /// The phone moved to another venue: table numbers granted a moment ago
  /// meant tables THERE, and a keeper still running would announce to the
  /// wrong kasa. Stops it without an `izlaz` — the old connection is gone.
  static void forgetVenue() {
    _active?.release(announce: false);
    _granted.clear();
  }

  final int stol;

  /// Called with the kasa's message once the table is held by someone else.
  final void Function(String message) onLost;

  /// Well inside the kasa's 10-minute expiry, and cheap: one small message.
  static const refreshEvery = Duration(minutes: 2);

  /// Tables whose lock was granted a moment ago, and when — so opening the
  /// screen right after the floor plan's `ulaz` doesn't announce twice.
  static final _granted = <int, DateTime>{};
  static const _grantedFresh = Duration(seconds: 60);

  /// Remembers that [stol]'s lock has just been granted (called by the floor
  /// plan after its own `ulaz`).
  static void noteGranted(int stol) => _granted[stol] = DateTime.now();

  /// Whether [stol] was granted to us within the last minute.
  static bool grantedRecently(int stol) {
    final at = _granted[stol];
    return at != null && DateTime.now().difference(at) < _grantedFresh;
  }

  Timer? _timer;
  bool _busy = false;
  bool _released = false;

  /// True once the kasa has confirmed the lock is ours.
  bool get held => _held;
  bool _held = false;

  /// Announces again right now — used when the connection or the kasa comes
  /// back, instead of waiting for the next refresh.
  void refreshNow() => unawaited(_announce());

  Future<void> _announce() async {
    if (_released || _busy) return;
    _busy = true;
    try {
      final result = await MqttTableLockSender.instance.enter(stol);
      if (_released) return;
      switch (result.outcome) {
        case MqttLockOutcome.ok:
          _held = true;
          noteGranted(stol);
        case MqttLockOutcome.zauzeto:
          _held = false;
          debugPrint('MQTT ▸ lock lost on stol $stol: ${result.message}');
          onLost(result.message);
        case MqttLockOutcome.bezOdgovora:
        case MqttLockOutcome.neispravno:
          // Nothing is known about the lock; keep announcing.
          _held = false;
      }
    } finally {
      _busy = false;
    }
  }

  /// Leaves the table: stops the refresh and, with [announce], tells the kasa
  /// (`izlaz`). Safe to call more than once.
  void release({bool announce = true}) {
    if (_released) return;
    _released = true;
    _timer?.cancel();
    _timer = null;
    if (identical(_active, this)) _active = null;
    if (!announce) {
      debugPrint('MQTT ▸ lock: dropping stale keeper for stol $stol');
      return;
    }
    _granted.remove(stol);
    debugPrint('MQTT ▸ lock: releasing stol $stol (izlaz)');
    unawaited(MqttTableLockSender.instance.leave(stol));
  }
}
