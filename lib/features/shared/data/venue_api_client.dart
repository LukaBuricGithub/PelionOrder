import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../app/app_config.dart';
import 'api_exception.dart';
import 'retrying_http.dart';

/// Low-level HTTP access to a venue's on-premise server.
///
/// Replaces the reference client's Retrofit setup (dummy base URL +
/// `HostInterceptor` swapping the host + `HeaderInterceptor` adding
/// `X-API-KEY`). Here the [host] (the profile's stored "IP", used verbatim as
/// the URL host, optionally `host:port`) and [apiKey] are supplied directly,
/// and every request is built as `http://<host>/api/v1/<path>` with the key in
/// the `X-API-KEY` header.
class VenueApiClient {
  const VenueApiClient({required this.host, required this.apiKey});

  final String host;
  final String apiKey;

  /// Normalizes [host] into a bare authority (strips any accidental scheme or
  /// trailing slash the user may have typed into the profile).
  String get _authority {
    var h = host.trim();
    h = h.replaceFirst(RegExp(r'^[a-zA-Z]+://'), '');
    h = h.replaceAll(RegExp(r'/+$'), '');
    return h;
  }

  Uri buildUri(String path, [Map<String, dynamic>? query]) {
    final cleanPath = path.replaceAll(RegExp(r'^/+'), '');
    final base =
        '${AppConfig.venueScheme}://$_authority/${AppConfig.venueApiPrefix}/$cleanPath';
    final uri = Uri.parse(base);
    if (query == null || query.isEmpty) return uri;
    final merged = <String, dynamic>{...uri.queryParameters};
    query.forEach((k, v) {
      if (v != null) merged[k] = v.toString();
    });
    return uri.replace(queryParameters: merged.isEmpty ? null : merged);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        AppConfig.apiKeyHeader: apiKey,
      };

  /// GET returning a decoded JSON list (the shape of every master-data and
  /// report endpoint). Returns an empty list for an empty/`204` body.
  Future<List<dynamic>> getList(String path,
      [Map<String, dynamic>? query]) async {
    final resp = await retryingGet(buildUri(path, query), headers: _headers);
    throwIfError(resp);
    if (resp.body.trim().isEmpty) return const [];
    final decoded = jsonDecode(resp.body);
    return decoded is List ? decoded : const [];
  }

  /// GET where only the HTTP status matters (e.g. the plain `/ping` health
  /// check). Returns the raw response for the caller to inspect.
  Future<http.Response> getRaw(String path,
      [Map<String, dynamic>? query]) async {
    return retryingGet(buildUri(path, query), headers: _headers);
  }

  /// POST a raw (already-encoded) body. Used both for JSON reservations and for
  /// the hand-built `postOrder` body. Returns the raw response.
  Future<http.Response> postRaw(String path, String body) async {
    return postWithTimeout(buildUri(path), headers: _headers, body: body);
  }
}
