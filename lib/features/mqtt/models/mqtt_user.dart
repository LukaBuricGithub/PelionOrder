import 'dart:convert';

/// One staff member as delivered over MQTT on `kasa/{licenca}/podaci/korisnici`.
/// Login is by [pin]; the matched user's [displayName] is shown after sign-in.
class MqttUser {
  const MqttUser({
    required this.code,
    required this.fullName,
    required this.name,
    required this.role,
    required this.pin,
    required this.pj,
  });

  final String code; // cuser
  final String fullName; // ime_prezime
  final String name; // naziv
  final String role; // uloga (e.g. "Blagajna", "Administracija")
  final String pin; // pin (string; may be empty → cannot log in)
  final String pj; // pj

  /// Best name to display: the full name if present, else the short naziv.
  String get displayName =>
      fullName.trim().isNotEmpty ? fullName.trim() : name.trim();

  /// "Administracija" is treated as full access (superuser).
  bool get isAdmin => role.trim().toLowerCase() == 'administracija';

  /// The numeric PIN, or null when the user has no PIN (can't log in).
  int? get pinValue => pin.trim().isEmpty ? null : int.tryParse(pin.trim());

  factory MqttUser.fromJson(Map<String, dynamic> j) => MqttUser(
        code: (j['cuser'] ?? '').toString().trim(),
        fullName: (j['ime_prezime'] ?? '').toString(),
        name: (j['naziv'] ?? '').toString(),
        role: (j['uloga'] ?? '').toString(),
        pin: (j['pin'] ?? '').toString(),
        pj: (j['pj'] ?? '').toString(),
      );

  /// Parses the full `podaci/korisnici` payload (`{"korisnici":[...],"ts":...}`)
  /// into a list of users. Returns an empty list on a shape mismatch.
  static List<MqttUser> listFromKorisniciPayload(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const [];
    final list = decoded['korisnici'];
    if (list is! List) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(MqttUser.fromJson)
        .toList();
  }
}
