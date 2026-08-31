import 'dart:convert';

import 'package:http/http.dart' as http;

/// An exception carrying text already written for the end user.
///
/// UI error widgets show [userMessage] verbatim instead of a screen's generic
/// copy, so anything a service says in plain Croatian reaches the person who
/// can act on it.
abstract class UserFacingException implements Exception {
  String get userMessage;
}

/// Raised when there is no active network transport (WiFi / Ethernet /
/// Cellular) before a venue call is even attempted — the Flutter analog of the
/// reference client's `NoConnectionException` thrown by its
/// `ConnectivityInterceptor`. Repositories catch this to fall back to cached
/// data or to queue an order for later resend.
class NoConnectionException implements UserFacingException {
  const NoConnectionException([this.message = 'Nema internetske veze.']);

  final String message;

  @override
  String get userMessage => message;

  @override
  String toString() => 'NoConnectionException($message)';
}

/// Typed exception surfaced when a venue call returns a non-2xx response.
///
/// The venue server rarely returns a structured error body, so [errorCode] and
/// [message] are usually null and [rawBody] is kept for debugging.
class ApiException implements UserFacingException {
  const ApiException({
    required this.statusCode,
    required this.rawBody,
    this.errorCode,
    this.message,
  });

  final int statusCode;
  final String? errorCode;
  final String? message;
  final String rawBody;

  @override
  String get userMessage =>
      (message != null && message!.isNotEmpty)
          ? message!
          : 'Greška poslužitelja ($statusCode).';

  /// Builds an [ApiException] from a non-2xx HTTP response. Silently tolerates
  /// non-JSON bodies — the caller still gets a usable exception with the
  /// status code and raw body.
  factory ApiException.fromResponse(http.Response resp) {
    String? code;
    String? msg;
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) {
        final rawCode = decoded['error'];
        final rawMsg = decoded['message'];
        code = rawCode is String ? rawCode : null;
        msg = rawMsg is String ? rawMsg : null;
      }
    } catch (_) {
      // Body wasn't JSON — fine, the caller falls back to the generic copy.
    }
    return ApiException(
      statusCode: resp.statusCode,
      errorCode: code,
      message: msg,
      rawBody: resp.body,
    );
  }

  @override
  String toString() {
    final m = (message != null && message!.isNotEmpty) ? ' — $message' : '';
    return 'ApiException($statusCode$m)';
  }
}

/// Throws [ApiException] when [resp] is non-2xx. No-op otherwise. Use as the
/// single non-2xx guard inside every API client so the error surface stays
/// uniform.
void throwIfError(http.Response resp) {
  if (resp.statusCode >= 200 && resp.statusCode < 300) return;
  throw ApiException.fromResponse(resp);
}
