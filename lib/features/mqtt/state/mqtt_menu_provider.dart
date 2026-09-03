import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/state/shared_preferences_provider.dart';
import '../data/mqtt_service.dart';
import '../models/mqtt_menu.dart';

const _kMqttArtikliKey = 'mqtt_artikli_raw_v1';

/// Holds the MQTT-delivered menu — article groups + predefined remark
/// definitions ([MqttMenu]). Loads the last-saved payload from local storage on
/// startup, then updates live whenever the broker sends a new `podaci/artikli`
/// payload — persisting each one so it survives restarts (and shows before the
/// next connection re-delivers the retained message).
class MqttMenuNotifier extends StateNotifier<MqttMenu> {
  MqttMenuNotifier(this._prefs) : super(MqttMenu.empty) {
    // 1) Restore the previously saved menu (if any).
    final saved = _prefs.getString(_kMqttArtikliKey);
    if (saved != null && saved.isNotEmpty) state = _parse(saved) ?? state;

    // 2) If a payload already arrived before this provider existed, use it.
    _applyIfPresent();

    // 3) Live updates from the broker.
    MqttService.instance.artikliRawJson.addListener(_onArtikli);
  }

  final SharedPreferences _prefs;

  void _onArtikli() => _applyIfPresent();

  void _applyIfPresent() {
    final raw = MqttService.instance.artikliRawJson.value;
    if (raw == null || raw.isEmpty) return;
    final parsed = _parse(raw);
    if (parsed == null) return;
    _prefs.setString(_kMqttArtikliKey, raw); // save locally
    state = parsed;
  }

  MqttMenu? _parse(String raw) {
    try {
      return MqttMenu.fromArtikliPayload(raw);
    } catch (e) {
      debugPrint('MQTT menu parse failed: $e');
      return null;
    }
  }

  @override
  void dispose() {
    MqttService.instance.artikliRawJson.removeListener(_onArtikli);
    super.dispose();
  }
}

final mqttMenuProvider =
    StateNotifierProvider<MqttMenuNotifier, MqttMenu>((ref) {
  return MqttMenuNotifier(ref.watch(sharedPreferencesProvider));
});
