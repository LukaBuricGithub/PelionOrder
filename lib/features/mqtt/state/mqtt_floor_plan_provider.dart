import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/state/shared_preferences_provider.dart';
import '../data/mqtt_service.dart';
import '../models/mqtt_floor_plan.dart';

const _kMqttTlocrtKey = 'mqtt_tlocrt_raw_v1';
const _kMqttTlocrtVerKey = 'mqtt_tlocrt_ver_v1';

/// Cleared when the phone moves to another venue (see `forgetVenueData`).
const mqttFloorPlanStorageKeys = [_kMqttTlocrtKey, _kMqttTlocrtVerKey];

/// The venue's floor plan (`podaci/tlocrt`), kept the same way the table list
/// is: the last payload is saved, so the plan is on screen before the broker
/// answers, and a new one is parsed only when the `tlocrt` version hash
/// changes.
///
/// A venue with no plan — an older kasa that never publishes the topic, or
/// `TLOCRT_ON` off — simply leaves this at [MqttFloorPlan.empty], which the
/// table screen reads as "draw the grid".
class MqttFloorPlanNotifier extends StateNotifier<MqttFloorPlan> {
  MqttFloorPlanNotifier(this._prefs) : super(MqttFloorPlan.empty) {
    final saved = _prefs.getString(_kMqttTlocrtKey);
    if (saved != null && saved.isNotEmpty) state = _parse(saved) ?? state;
    _reevaluate();
    MqttService.instance.tlocrtRawJson.addListener(_reevaluate);
    MqttService.instance.verzijaRawJson.addListener(_reevaluate);
  }

  final SharedPreferences _prefs;

  void _reevaluate() {
    final raw = MqttService.instance.tlocrtRawJson.value;
    if (raw == null) return; // nothing received on this connection yet
    // An EMPTY payload on a retained topic is how a publisher deletes the
    // retained message — the kasa saying "forget the plan I gave you". Without
    // this the saved plan would outlive the venue's decision to drop it and
    // keep being drawn, with no message ever coming to replace it.
    if (raw.trim().isEmpty) {
      _prefs.remove(_kMqttTlocrtKey);
      _prefs.remove(_kMqttTlocrtVerKey);
      if (state.terraces.isNotEmpty || state.enabled) {
        state = MqttFloorPlan.empty;
      }
      return;
    }
    final hash = MqttService.instance.versionFor('tlocrt');
    // A kasa old enough to publish no `tlocrt` hash still publishes the plan
    // itself on some installs; apply it on the payload alone rather than
    // waiting for a hash that will never come. A missing hash is explicitly
    // not the same as "no plan" (spec §3).
    if (hash != null) {
      if (hash == _prefs.getString(_kMqttTlocrtVerKey)) return; // unchanged
    } else if (raw == _prefs.getString(_kMqttTlocrtKey)) {
      return; // same bytes as last time
    }
    final parsed = _parse(raw);
    if (parsed == null) return;
    _prefs.setString(_kMqttTlocrtKey, raw);
    if (hash != null) _prefs.setString(_kMqttTlocrtVerKey, hash);
    state = parsed;
  }

  MqttFloorPlan? _parse(String raw) {
    final parsed = MqttFloorPlan.tryParse(raw);
    if (parsed == null) debugPrint('MQTT tlocrt parse failed');
    return parsed;
  }

  @override
  void dispose() {
    MqttService.instance.tlocrtRawJson.removeListener(_reevaluate);
    MqttService.instance.verzijaRawJson.removeListener(_reevaluate);
    super.dispose();
  }
}

final mqttFloorPlanProvider =
    StateNotifierProvider<MqttFloorPlanNotifier, MqttFloorPlan>((ref) {
      return MqttFloorPlanNotifier(ref.watch(sharedPreferencesProvider));
    });
