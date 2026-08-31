import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reports whether the device currently has an active network transport
/// (WiFi / Ethernet / Cellular / VPN). This is the Flutter analog of the
/// reference client's `ConnectivityInterceptor`: it answers "is there any
/// network at all" — NOT "is the venue server reachable" (that is the job of
/// the heartbeat ping).
///
/// Repositories consult [hasConnection] before a venue call and throw
/// [NoConnectionException] up front when the device is fully offline, so they
/// can fall back to cached data / queue an order without waiting for a socket
/// timeout.
class ConnectivityService {
  ConnectivityService([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  static bool _isConnected(List<ConnectivityResult> results) {
    return results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.ethernet ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.vpn);
  }

  /// One-shot check used before making a request.
  Future<bool> hasConnection() async {
    final results = await _connectivity.checkConnectivity();
    return _isConnected(results);
  }

  /// Stream of transport-availability changes.
  Stream<bool> get onConnectionChanged =>
      _connectivity.onConnectivityChanged.map(_isConnected);
}

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return ConnectivityService();
});
