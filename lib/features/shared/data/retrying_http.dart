import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// HTTP helpers that survive stale keep-alive connections without paying the
/// TCP handshake cost on every request. Ported from the ikasa app.
///
///  * A single process-wide [_sharedClient] handles the first attempt for
///    every request, reusing the underlying connection pool.
///  * If the first GET attempt fails with a connection-level error
///    (`TimeoutException`, `SocketException`, `HttpException`) — the signature
///    of a broken keep-alive — it is retried ONCE on a fresh client.
///  * 4xx/5xx HTTP status codes are NOT retried; those are real responses.
///  * POST/PUT get the shared client and the same timeout but no retry (not
///    safe to replay — a lost 200 could duplicate a resource / order).

const _defaultTimeout = Duration(seconds: 15);

/// Reused across every call so the underlying HttpClient's connection pool
/// actually gets to do its job. Never closed — it lives for the process
/// lifetime, matching the app's own lifecycle.
final http.Client _sharedClient = http.Client();

/// GET with fresh-connection auto-retry on transport failures.
Future<http.Response> retryingGet(
  Uri uri, {
  Map<String, String>? headers,
  Duration timeout = _defaultTimeout,
}) async {
  // Attempt 1 — shared client, fast path.
  try {
    return await _sharedClient.get(uri, headers: headers).timeout(timeout);
  } on TimeoutException {
    // fall through to retry
  } on SocketException {
    // fall through to retry
  } on HttpException {
    // fall through to retry
  }

  // Attempt 2 — fresh client, guaranteed no zombie socket carry-over.
  final freshClient = http.Client();
  try {
    return await freshClient.get(uri, headers: headers).timeout(timeout);
  } finally {
    freshClient.close();
  }
}

/// POST wrapped in a bounded timeout. Does NOT retry (POST is not generally
/// safe to replay).
Future<http.Response> postWithTimeout(
  Uri uri, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
  Duration timeout = _defaultTimeout,
}) async {
  return _sharedClient
      .post(uri, headers: headers, body: body, encoding: encoding)
      .timeout(timeout);
}

/// PUT wrapped in a bounded timeout. Does NOT retry.
Future<http.Response> putWithTimeout(
  Uri uri, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
  Duration timeout = _defaultTimeout,
}) async {
  return _sharedClient
      .put(uri, headers: headers, body: body, encoding: encoding)
      .timeout(timeout);
}
