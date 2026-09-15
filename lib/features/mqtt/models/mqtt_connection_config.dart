import 'dart:convert';

/// The parameters used to open the MQTT connection to the Pelion broker.
///
/// Everything identifying THIS device — `licenca`, `uredaj`, `naziv`, `grupa` —
/// comes from the QR code issued by the kasa and nothing else; there are no
/// fallbacks, so an unprovisioned device cannot connect anywhere. The remaining
/// fields are the fixed Pelion broker endpoint (see the constructor defaults).
///
/// Passed to `MqttService` (`mqtt_service.dart`) to connect.
class MqttConnectionConfig {
  const MqttConnectionConfig({
    required this.licenca,
    required this.uredaj,
    required this.naziv,
    required this.grupa,
    this.broker = 'mqtt.pelionpro.com',
    this.port = 8883,
    this.lozinka = '0000',
    this.zvuk = true,
    this.keepalive = 10,
    this.tls = true,
  });

  /// The licence — MQTT username, and the `kasa/{licenca}/…` topic root.
  final String licenca;
  final String broker;
  final int port;
  final String lozinka;
  final bool zvuk;

  /// This device's client_id, `{licenca}-PELIONORDER-{broj}` — the number is
  /// assigned by the kasa. Also the last segment of our status and reply topics.
  final String uredaj;

  /// The venue name, exactly as the kasa issued it.
  final String naziv;

  /// The kasa's group (`PRODUKCIJA`, `TEST`, `NELICENCIRANO`), reported as-is
  /// in our status.
  final String grupa;
  final int keepalive;
  final bool tls;

  /// Parses a QR code issued by the kasa:
  ///
  /// ```json
  /// {"lic":"53B5…", "id":"53B5…-PELIONORDER-3", "naziv":"…", "grupa":"PRODUKCIJA"}
  /// ```
  ///
  /// Returns null for anything else — including the old plain
  /// `<licenca>-ORDERMAN-<n>` strings, which the kasa no longer activates.
  ///
  /// The broker endpoint itself (host, port, TLS, password, keepalive) is NOT
  /// in the code — it's the same for every Pelion install.
  static MqttConnectionConfig? tryParseQr(String code) {
    try {
      final decoded = jsonDecode(code.trim());
      if (decoded is! Map) return null;
      String field(String key) => (decoded[key] ?? '').toString().trim();
      final lic = field('lic');
      final id = field('id');
      if (lic.isEmpty || id.isEmpty) return null;
      // The id belongs to its licence ({lic}-PELIONORDER-{broj}); one for any
      // other licence could never connect (the broker ACL is per licence).
      if (!id.startsWith('$lic-')) return null;
      // It is the last segment of our topics, so it must be usable there.
      if (id.length > 64 || RegExp(r'[/+#\s]').hasMatch(id)) return null;
      return MqttConnectionConfig(
        licenca: lic,
        uredaj: id,
        naziv: field('naziv'),
        grupa: field('grupa'),
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'broker': broker,
        'port': port,
        'licenca': licenca,
        'lozinka': lozinka,
        'zvuk': zvuk,
        'uredaj': uredaj,
        'naziv': naziv,
        'grupa': grupa,
        'keepalive': keepalive,
        'tls': tls,
      };

  /// Pretty-printed JSON, for showing the connection payload on screen.
  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}
