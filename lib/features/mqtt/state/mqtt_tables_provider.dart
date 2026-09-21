import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/state/shared_preferences_provider.dart';
import '../data/mqtt_service.dart';
import '../models/mqtt_tables.dart';

const _kMqttStoloviKey = 'mqtt_stolovi_raw_v1';
const _kMqttStoloviVerKey = 'mqtt_stolovi_ver_v1';
const _kMqttStanjeKey = 'mqtt_stolovi_stanje_raw_v1';

/// Holds the MQTT-delivered tables grouped by zone (`podaci/stolovi`). Loads the
/// last-saved list on startup, then updates live + persists on each payload.
class MqttTablesNotifier extends StateNotifier<List<MqttTerrace>> {
  MqttTablesNotifier(this._prefs) : super(const []) {
    final saved = _prefs.getString(_kMqttStoloviKey);
    if (saved != null && saved.isNotEmpty) state = _parse(saved) ?? state;
    _reevaluate();
    MqttService.instance.stoloviRawJson.addListener(_reevaluate);
    MqttService.instance.verzijaRawJson.addListener(_reevaluate);
  }

  final SharedPreferences _prefs;

  /// Applies the stolovi payload only when its version hash differs from the
  /// saved one — skips re-parsing/re-storing an unchanged table layout.
  void _reevaluate() {
    final raw = MqttService.instance.stoloviRawJson.value;
    if (raw == null || raw.isEmpty) return;
    final hash = MqttService.instance.versionFor('stolovi');
    if (hash == null) return; // wait until the version is known
    if (hash == _prefs.getString(_kMqttStoloviVerKey)) return; // unchanged
    final parsed = _parse(raw);
    if (parsed == null) return;
    _prefs.setString(_kMqttStoloviKey, raw);
    _prefs.setString(_kMqttStoloviVerKey, hash);
    state = parsed;
  }

  List<MqttTerrace>? _parse(String raw) {
    try {
      return MqttTerrace.listFromStoloviPayload(raw);
    } catch (e) {
      debugPrint('MQTT stolovi parse failed: $e');
      return null;
    }
  }

  @override
  void dispose() {
    MqttService.instance.stoloviRawJson.removeListener(_reevaluate);
    MqttService.instance.verzijaRawJson.removeListener(_reevaluate);
    super.dispose();
  }
}

final mqttTablesProvider =
    StateNotifierProvider<MqttTablesNotifier, List<MqttTerrace>>((ref) {
  return MqttTablesNotifier(ref.watch(sharedPreferencesProvider));
});

/// Holds occupied ("zauzet") tables keyed by number (`podaci/stolovi_stanje`),
/// each with its server-side summary (cuser, waiter, amount, item count).
/// Updates live + persists so the last-known occupancy shows before reconnect.
class MqttOccupiedNotifier extends StateNotifier<Map<int, MqttTableState>> {
  MqttOccupiedNotifier(this._prefs) : super(const {}) {
    final saved = _prefs.getString(_kMqttStanjeKey);
    if (saved != null && saved.isNotEmpty) state = _parse(saved) ?? state;
    _applyIfPresent();
    MqttService.instance.stanjeRawJson.addListener(_onStanje);
  }

  final SharedPreferences _prefs;

  void _onStanje() => _applyIfPresent();

  void _applyIfPresent() {
    final raw = MqttService.instance.stanjeRawJson.value;
    if (raw == null || raw.isEmpty) return;
    final parsed = _parse(raw);
    if (parsed == null) return;
    _prefs.setString(_kMqttStanjeKey, raw);
    state = parsed;
  }

  Map<int, MqttTableState>? _parse(String raw) {
    try {
      return tableStatesFromStanje(raw);
    } catch (e) {
      debugPrint('MQTT stolovi_stanje parse failed: $e');
      return null;
    }
  }

  @override
  void dispose() {
    MqttService.instance.stanjeRawJson.removeListener(_onStanje);
    super.dispose();
  }
}

final mqttOccupiedProvider =
    StateNotifierProvider<MqttOccupiedNotifier, Map<int, MqttTableState>>((ref) {
  return MqttOccupiedNotifier(ref.watch(sharedPreferencesProvider));
});

/// Tables the kasa has LOCKED (`zakljucani` in `stolovi_stanje`): table number
/// → who holds it (`CORD3` = orderman 3, otherwise a kasa's tag).
///
/// Not persisted, unlike the occupancy above: a lock is only true while the
/// kasa says so, and showing yesterday's lock would block a free table.
class MqttLockedNotifier extends StateNotifier<Map<int, String>> {
  MqttLockedNotifier() : super(const {}) {
    _apply();
    MqttService.instance.stanjeRawJson.addListener(_apply);
  }

  void _apply() {
    final raw = MqttService.instance.stanjeRawJson.value;
    if (raw == null || raw.isEmpty) return;
    try {
      state = tableLocksFromStanje(raw);
    } catch (e) {
      debugPrint('MQTT zakljucani parse failed: $e');
    }
  }

  @override
  void dispose() {
    MqttService.instance.stanjeRawJson.removeListener(_apply);
    super.dispose();
  }
}

final mqttLockedProvider =
    StateNotifierProvider<MqttLockedNotifier, Map<int, String>>(
        (ref) => MqttLockedNotifier());
