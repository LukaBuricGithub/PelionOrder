import 'dart:convert';

/// Another device's last status on our licence, from
/// `kasa/{licenca}/status/{client_id}` (spec v4.0, §3 and §11.2) — just what
/// the phone needs to decide whether it may send: what kind of device it is,
/// whether it is online, and whether it takes orders right now.
class MqttDeviceStatus {
  const MqttDeviceStatus({
    required this.tip,
    required this.naziv,
    required this.status,
    required this.prima,
  });

  /// `KASA`, `MREZA`, `WEBMASTER` or `PELIONORDER` — compared exactly, as the
  /// spec requires (`KASA` and `Kasa` are different values).
  final String tip;
  final String naziv;

  /// `online` or `offline`.
  final String status;

  /// The device takes and prints orders right now. Only a kasa holding the
  /// database, in production, in its sales screen, ever reports true.
  final bool prima;

  bool get isOnline => status == 'online';
  bool get isKasa => tip == 'KASA';

  /// Parses a status payload, or null when it isn't a JSON object.
  ///
  /// A status without `prima` comes from an I-Kasa older than v4.0. It is kept
  /// — with `prima` false: such a kasa doesn't check repeated or stale orders,
  /// so the phone never sends to it until it is updated.
  static MqttDeviceStatus? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return MqttDeviceStatus(
        tip: (decoded['tip'] ?? '').toString(),
        naziv: (decoded['naziv'] ?? '').toString(),
        status: (decoded['status'] ?? '').toString(),
        prima: decoded['prima'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() =>
      'MqttDeviceStatus(tip: $tip, status: $status, prima: $prima, naziv: $naziv)';
}
