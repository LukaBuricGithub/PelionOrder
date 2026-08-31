import 'package:flutter/foundation.dart';

/// Payload returned by the venue's `/ping` heartbeat when asked to also report
/// venue metadata. Ported from the reference client's `PingResponse`.
///
/// Remote JSON: `MSG`, `NAME` (the business/venue name shown in the UI).
@immutable
class PingResponse {
  const PingResponse({
    required this.message,
    required this.businessName,
  });

  final String message;
  final String businessName;

  factory PingResponse.fromRemoteJson(Map<String, dynamic> json) {
    return PingResponse(
      message: (json['MSG'] ?? '').toString().trim(),
      businessName: (json['NAME'] ?? '').toString().trim(),
    );
  }
}
