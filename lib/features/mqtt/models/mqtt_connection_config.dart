import 'dart:convert';

/// The parameters used to open the MQTT connection to the Pelion broker.
///
/// For now this is only **displayed** on the settings screen (built from a
/// scanned QR code) so we can see the exact connection payload. Later the MQTT
/// service will use it to actually connect. The non-licenca defaults mirror the
/// Pelion test-broker values currently hard-coded in `mqtt_test.dart`; the
/// `licenca` is the part scanned from the QR code.
class MqttConnectionConfig {
  const MqttConnectionConfig({
    required this.licenca,
    this.broker = 'mqtt.pelionpro.com',
    this.port = 8883,
    this.lozinka = '0000',
    this.zvuk = true,
    this.uredaj = 'MOBILE-002-POS',
    this.naziv = 'MOBILE TEST kasa',
    this.keepalive = 10,
    this.tls = true,
  });

  final String licenca;
  final String broker;
  final int port;
  final String lozinka;
  final bool zvuk;
  final String uredaj;
  final String naziv;
  final int keepalive;
  final bool tls;

  /// Builds a config from a scanned QR string of the form
  /// `<licenca>-ORDERMAN-<n>` (e.g. `ffdfedfafgsdghsg-ORDERMAN-01`):
  ///   * `licenca` = the text before the first `-` (the MQTT username), and
  ///   * `uredaj`  = the whole scanned string — the device id used in the MQTT
  ///     topics/payloads and as the MQTT client identifier.
  factory MqttConnectionConfig.fromScannedCode(String code) {
    final trimmed = code.trim();
    final licenca = trimmed.split('-').first.trim();
    return MqttConnectionConfig(licenca: licenca, uredaj: trimmed);
  }

  Map<String, dynamic> toJson() => {
        'broker': broker,
        'port': port,
        'licenca': licenca,
        'lozinka': lozinka,
        'zvuk': zvuk,
        'uredaj': uredaj,
        'naziv': naziv,
        'keepalive': keepalive,
        'tls': tls,
      };

  /// Pretty-printed JSON, for showing the connection payload on screen.
  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}
