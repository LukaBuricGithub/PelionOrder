import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/state/shared_preferences_provider.dart';
import '../data/mqtt_service.dart';
import '../models/mqtt_tables.dart';

const _kMqttStoloviKey = 'mqtt_stolovi_raw_v1';
const _kMqttStanjeKey = 'mqtt_stolovi_stanje_raw_v1';

/// Holds the MQTT-delivered tables grouped by zone (`podaci/stolovi`). Loads the
/// last-saved list on startup, then updates live + persists on each payload.
class MqttTablesNotifier extends StateNotifier<List<MqttTerrace>> {
  MqttTablesNotifier(this._prefs) : super(const []) {
    final saved = _prefs.getString(_kMqttStoloviKey);
    if (saved != null && saved.isNotEmpty) state = _parse(saved) ?? state;
    _applyIfPresent();
    MqttService.instance.stoloviRawJson.addListener(_onStolovi);
  }

  final SharedPreferences _prefs;

  void _onStolovi() => _applyIfPresent();

  void _applyIfPresent() {
    final raw = MqttService.instance.stoloviRawJson.value;
    if (raw == null || raw.isEmpty) return;
    final parsed = _parse(raw);
    if (parsed == null) return;
    _prefs.setString(_kMqttStoloviKey, raw);
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
    MqttService.instance.stoloviRawJson.removeListener(_onStolovi);
    super.dispose();
  }
}

final mqttTablesProvider =
    StateNotifierProvider<MqttTablesNotifier, List<MqttTerrace>>((ref) {
  return MqttTablesNotifier(ref.watch(sharedPreferencesProvider));
});

/// Holds the set of occupied ("zauzet") table numbers (`podaci/stolovi_stanje`).
/// Updates live + persists so the last-known occupancy shows before reconnect.
class MqttOccupiedNotifier extends StateNotifier<Set<int>> {
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

  Set<int>? _parse(String raw) {
    try {
      return occupiedStoloviFromStanje(raw);
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
    StateNotifierProvider<MqttOccupiedNotifier, Set<int>>((ref) {
  return MqttOccupiedNotifier(ref.watch(sharedPreferencesProvider));
});
