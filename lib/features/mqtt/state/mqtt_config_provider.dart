import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/state/shared_preferences_provider.dart';
import '../models/mqtt_connection_config.dart';

const _kMqttQrCodeKey = 'mqtt_qr_code_v1';

/// The device's MQTT provisioning, derived from the scanned QR code and
/// **persisted**, so every launch can reconnect without scanning again.
///
/// Only the raw QR string is stored; the config is rebuilt from it, so changing
/// the broker defaults doesn't strand devices on stale values.
class MqttConfigNotifier extends StateNotifier<MqttConnectionConfig?> {
  MqttConfigNotifier(this._prefs) : super(null) {
    // No scan yet → no config: the app stays unprovisioned and never connects
    // on its own.
    final code = _prefs.getString(_kMqttQrCodeKey);
    if (code != null && code.isNotEmpty) {
      state = MqttConnectionConfig.fromScannedCode(code);
    }
  }

  final SharedPreferences _prefs;

  /// The raw provisioning string (the whole scanned QR value). It's also the
  /// device id (`uredaj`) we connect and send orders with.
  String? get scannedCode => state?.uredaj;

  /// Saves a freshly scanned QR code and adopts it as the active config.
  Future<void> saveScanned(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;
    await _prefs.setString(_kMqttQrCodeKey, trimmed);
    state = MqttConnectionConfig.fromScannedCode(trimmed);
  }

  /// Forgets the provisioning (device must be re-scanned).
  Future<void> clear() async {
    await _prefs.remove(_kMqttQrCodeKey);
    state = null;
  }
}

final mqttConfigProvider =
    StateNotifierProvider<MqttConfigNotifier, MqttConnectionConfig?>((ref) {
  return MqttConfigNotifier(ref.watch(sharedPreferencesProvider));
});
