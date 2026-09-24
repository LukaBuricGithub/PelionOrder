import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/state/shared_preferences_provider.dart';
import '../data/mqtt_service.dart';
import '../models/mqtt_user.dart';

const _kMqttKorisniciKey = 'mqtt_korisnici_raw_v1';
const _kMqttKorisniciVerKey = 'mqtt_korisnici_ver_v1';

/// What this provider saves — removed when the phone moves to another venue
/// (see `forgetVenueData`).
const mqttUsersStorageKeys = [_kMqttKorisniciKey, _kMqttKorisniciVerKey];

/// Holds the MQTT-delivered staff list (`podaci/korisnici`) used for PIN login.
/// Loads the last-saved list from local storage on startup, then updates live
/// whenever the broker sends a new payload — persisting each one so login works
/// on a cold start before the next connection re-delivers the retained message.
class MqttUsersNotifier extends StateNotifier<List<MqttUser>> {
  MqttUsersNotifier(this._prefs) : super(const []) {
    final saved = _prefs.getString(_kMqttKorisniciKey);
    if (saved != null && saved.isNotEmpty) state = _parse(saved) ?? state;
    _reevaluate();
    MqttService.instance.korisniciRawJson.addListener(_reevaluate);
    MqttService.instance.verzijaRawJson.addListener(_reevaluate);
  }

  final SharedPreferences _prefs;

  /// Applies the korisnici payload only when its version hash differs from the
  /// saved one — skips re-parsing/re-storing an unchanged staff list.
  void _reevaluate() {
    final raw = MqttService.instance.korisniciRawJson.value;
    if (raw == null || raw.isEmpty) return;
    final hash = MqttService.instance.versionFor('korisnici');
    if (hash == null) return; // wait until the version is known
    if (hash == _prefs.getString(_kMqttKorisniciVerKey)) return; // unchanged
    final parsed = _parse(raw);
    if (parsed == null) return;
    _prefs.setString(_kMqttKorisniciKey, raw);
    _prefs.setString(_kMqttKorisniciVerKey, hash);
    state = parsed;
  }

  List<MqttUser>? _parse(String raw) {
    try {
      return MqttUser.listFromKorisniciPayload(raw);
    } catch (e) {
      debugPrint('MQTT korisnici parse failed: $e');
      return null;
    }
  }

  @override
  void dispose() {
    MqttService.instance.korisniciRawJson.removeListener(_reevaluate);
    MqttService.instance.verzijaRawJson.removeListener(_reevaluate);
    super.dispose();
  }
}

final mqttUsersProvider =
    StateNotifierProvider<MqttUsersNotifier, List<MqttUser>>((ref) {
  return MqttUsersNotifier(ref.watch(sharedPreferencesProvider));
});
