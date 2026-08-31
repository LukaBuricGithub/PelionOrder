import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_config.dart';
import '../../settings/state/settings_provider.dart';
import 'master_data_providers.dart';

/// Continuously checks whether the venue server is reachable and exposes the
/// result as a simple `bool` (true = Online). Mirrors the reference client's
/// `PingViewModel` heartbeat loop (10s release / 30s debug).
///
/// Screens that need the indicator call [start] in `initState` and [stop] in
/// `dispose`; the loop runs as long as at least one screen is subscribed.
class HeartbeatController extends StateNotifier<bool> {
  HeartbeatController(this._ref) : super(false);

  final Ref _ref;
  Timer? _timer;
  int _subscribers = 0;

  Duration get _interval =>
      kDebugMode ? AppConfig.heartbeatIntervalDebug : AppConfig.heartbeatInterval;

  void start() {
    _subscribers++;
    if (_timer != null) return;
    _tick();
    _timer = Timer.periodic(_interval, (_) => _tick());
  }

  void stop() {
    if (_subscribers > 0) _subscribers--;
    if (_subscribers == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Forces an immediate heartbeat (e.g. after the user edits the profile).
  Future<void> pingNow() => _tick();

  Future<void> _tick() async {
    final api = _ref.read(masterDataApiProvider);
    if (api == null) {
      if (mounted) state = false;
      return;
    }
    try {
      final result = await api.pingStatusAndName();
      if (!mounted) return;
      state = result.online;
      final name = result.name;
      if (result.online && name != null && name.isNotEmpty) {
        _ref.read(settingsProvider.notifier).setBusinessName(name);
      }
    } catch (_) {
      if (mounted) state = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// App-wide online/offline status. `true` when the last heartbeat reached the
/// venue server.
final heartbeatProvider =
    StateNotifierProvider<HeartbeatController, bool>((ref) {
  return HeartbeatController(ref);
});
