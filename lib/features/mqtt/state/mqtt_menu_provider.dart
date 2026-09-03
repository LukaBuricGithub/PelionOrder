import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/state/shared_preferences_provider.dart';
import '../data/mqtt_service.dart';
import '../models/mqtt_menu.dart';

const _kMqttArtikliKey = 'mqtt_artikli_raw_v1';
const _kMqttArtikliVerKey = 'mqtt_artikli_ver_v1';

/// Holds the MQTT-delivered menu — article groups + predefined remark
/// definitions ([MqttMenu]). Loads the last-saved payload from local storage on
/// startup, then updates live whenever the broker sends a new `podaci/artikli`
/// payload — persisting each one so it survives restarts (and shows before the
/// next connection re-delivers the retained message).
class MqttMenuNotifier extends StateNotifier<MqttMenu> {
  MqttMenuNotifier(this._prefs) : super(MqttMenu.empty) {
    // Restore the previously saved menu (if any) so it shows before connect.
    final saved = _prefs.getString(_kMqttArtikliKey);
    if (saved != null && saved.isNotEmpty) state = _parse(saved) ?? state;

    // Re-evaluate on either the data or the version arriving (order-agnostic).
    _reevaluate();
    MqttService.instance.artikliRawJson.addListener(_reevaluate);
    MqttService.instance.verzijaRawJson.addListener(_reevaluate);
  }

  final SharedPreferences _prefs;

  /// Applies the artikli payload only when its version hash differs from the
  /// saved one — skips re-parsing/re-storing an unchanged menu.
  void _reevaluate() {
    final raw = MqttService.instance.artikliRawJson.value;
    if (raw == null || raw.isEmpty) return;
    final hash = MqttService.instance.versionFor('artikli');
    if (hash == null) return; // wait until the version is known
    if (hash == _prefs.getString(_kMqttArtikliVerKey)) return; // unchanged
    final parsed = _parse(raw);
    if (parsed == null) return;
    _prefs.setString(_kMqttArtikliKey, raw);
    _prefs.setString(_kMqttArtikliVerKey, hash);
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
    MqttService.instance.artikliRawJson.removeListener(_reevaluate);
    MqttService.instance.verzijaRawJson.removeListener(_reevaluate);
    super.dispose();
  }
}

final mqttMenuProvider =
    StateNotifierProvider<MqttMenuNotifier, MqttMenu>((ref) {
  return MqttMenuNotifier(ref.watch(sharedPreferencesProvider));
});
