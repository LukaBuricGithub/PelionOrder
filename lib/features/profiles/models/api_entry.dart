import 'package:flutter/foundation.dart';

/// A venue **server profile**: the network address of a venue's on-premise
/// server plus its access key. A device can hold several profiles and switch
/// between them (staff working across locations, or testing).
///
/// Ported from the reference client's `ApiEntry`. The [ip] is used verbatim as
/// the URL host at request time (see `VenueApiClient`), and [apiKey] is sent in
/// the `X-API-KEY` header.
@immutable
class ApiEntry {
  const ApiEntry({
    required this.id,
    required this.name,
    required this.ip,
    required this.apiKey,
  });

  /// Stable identifier. In the reference client this is
  /// `System.currentTimeMillis()` at creation; we keep the same "epoch millis"
  /// convention but generate it in the notifier (so this class stays pure).
  final int id;

  /// Human-readable label shown in the profile dropdown.
  final String name;

  /// The venue server's network address (host, optionally `host:port`). Used
  /// as the URL host — e.g. `192.168.1.50` → `http://192.168.1.50/api/v1/...`.
  final String ip;

  /// The venue access key, sent as the `X-API-KEY` header on every request.
  final String apiKey;

  ApiEntry copyWith({
    int? id,
    String? name,
    String? ip,
    String? apiKey,
  }) {
    return ApiEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      apiKey: apiKey ?? this.apiKey,
    );
  }

  factory ApiEntry.fromJson(Map<String, dynamic> json) {
    return ApiEntry(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] ?? '').toString(),
      ip: (json['ip'] ?? '').toString(),
      apiKey: (json['apiKey'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ip': ip,
        'apiKey': apiKey,
      };

  @override
  bool operator ==(Object other) =>
      other is ApiEntry &&
      other.id == id &&
      other.name == name &&
      other.ip == ip &&
      other.apiKey == apiKey;

  @override
  int get hashCode => Object.hash(id, name, ip, apiKey);

  @override
  String toString() => 'ApiEntry(id: $id, name: $name, ip: $ip)';
}
