import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/state/shared_preferences_provider.dart';
import '../data/mqtt_service.dart';
import '../models/mqtt_connection_config.dart';

/// The raw QR code issued by the kasa (JSON: lic, id, naziv, grupa).
///
/// A new key on purpose: the old `mqtt_qr_code_v1` held a plain
/// `<licenca>-ORDERMAN-<n>` string, which the kasa no longer activates. It is
/// left untouched but ignored, so an updated device simply asks for its new
/// code.
const _kMqttQrCodeKey = 'mqtt_qr_code_v2';

/// The licence (venue) the data on this phone — menu, staff, tables, unsent
/// orders — was received under. Kept apart from the QR code on purpose: a
/// device the kasa no longer accepts forgets its code but keeps its data, so
/// a new code for the SAME venue can carry on with it.
const _kMqttDataLicencaKey = 'mqtt_data_licenca_v1';

/// The device's MQTT provisioning, derived from the scanned QR code and
/// **persisted**, so every launch can reconnect without scanning again.
///
/// Only the raw QR string is stored; the config is rebuilt from it, so changing
/// the broker defaults doesn't strand devices on stale values.
class MqttConfigNotifier extends StateNotifier<MqttConnectionConfig?> {
  MqttConfigNotifier(this._prefs) : super(null) {
    // No (valid) scan yet → no config: the app stays unprovisioned and never
    // connects on its own.
    final code = _prefs.getString(_kMqttQrCodeKey);
    if (code != null && code.isNotEmpty) {
      state = MqttConnectionConfig.tryParseQr(code);
    }
  }

  final SharedPreferences _prefs;

  /// The device id (client_id) from the scanned code, if provisioned.
  String? get scannedCode => state?.uredaj;

  /// Saves a freshly scanned QR code and adopts it as the active config.
  /// Returns false — and changes nothing — when the code isn't a valid code
  /// issued by the kasa, so a wrong scan can't replace a working provisioning.
  Future<bool> saveScanned(String code) async {
    final config = MqttConnectionConfig.tryParseQr(code);
    if (config == null) return false;
    await _prefs.setString(_kMqttQrCodeKey, code.trim());
    state = config;
    return true;
  }

  /// The venue (licence) whose data this phone holds; before this was
  /// recorded, the venue of the current code. Null when unknown.
  String? get dataLicenca =>
      _prefs.getString(_kMqttDataLicencaKey) ?? state?.licenca;

  /// Records that the data on this phone now belongs to [licenca].
  Future<void> setDataLicenca(String licenca) =>
      _prefs.setString(_kMqttDataLicencaKey, licenca);

  /// The kasa refused an order with "nije aktiviran" (§9, §11.6): this code is
  /// no longer accepted there — never activated, cancelled, or the device was
  /// deactivated. Disconnect and forget it, so the waiter is asked to scan a
  /// new one ("Skeniraj kod na kasi"). Unsent orders stay on the phone.
  Future<void> forgetDevice() async {
    if (state == null) return;
    debugPrint('MQTT ▸ the kasa says this orderman is not activated — '
        'forgetting the code');
    MqttService.instance.disconnect();
    await clear();
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
