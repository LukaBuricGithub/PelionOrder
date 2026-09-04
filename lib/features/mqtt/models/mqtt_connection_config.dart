import 'dart:convert';

/// The parameters used to open the MQTT connection to the Pelion broker.
///
/// Everything identifying THIS device — `licenca`, `uredaj`, `naziv` — comes
/// from the scanned QR code and nothing else; there are no fallbacks, so an
/// unprovisioned device cannot connect anywhere. The remaining fields are the
/// fixed Pelion broker endpoint (see [fromScannedCode]).
///
/// Shown on the settings screen and passed to `MqttService`
/// (`mqtt_service.dart`) to connect.
class MqttConnectionConfig {
  const MqttConnectionConfig({
    required this.licenca,
    required this.uredaj,
    required this.naziv,
    this.broker = 'mqtt.pelionpro.com',
    this.port = 8883,
    this.lozinka = '0000',
    this.zvuk = true,
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
  ///   * `licenca` = the text before the first `-` (the MQTT username),
  ///   * `uredaj`  = the whole scanned string — the device id used in the MQTT
  ///     topics/payloads and as the MQTT client identifier, and
  ///   * `naziv`   = the part after the licenca (e.g. `ORDERMAN-1`), the
  ///     readable device name we publish in `status`/`dojava`.
  ///
  /// The broker endpoint itself (host, port, TLS, password, keepalive) is NOT
  /// in the QR — it's the same for every Pelion install, so it stays as the
  /// constructor defaults above.
  factory MqttConnectionConfig.fromScannedCode(String code) {
    final trimmed = code.trim();
    final parts = trimmed.split('-');
    final licenca = parts.first.trim();
    final naziv = parts.length > 1 ? parts.sublist(1).join('-') : trimmed;
    return MqttConnectionConfig(
      licenca: licenca,
      uredaj: trimmed,
      naziv: naziv,
    );
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
