/// App-wide configuration constants.
///
/// Unlike the ikasa app (which talks to fixed Pelion cloud backends), the
/// Pelion Order waiter-ordering app talks to a **venue's own on-premise
/// server**.
/// The server's network address (and access key) come from the user-selected
/// server profile at runtime — see `features/profiles`. There is therefore no
/// single hard-coded base URL here; instead we keep the parts that ARE fixed:
/// the URL scheme, the API path prefix and connection timeouts.
class AppConfig {
  const AppConfig._();

  /// Scheme used to reach the venue server. The reference Android client uses
  /// plain HTTP (`usesCleartextTraffic=true`) because it talks to a device on
  /// the local network, so we mirror that here.
  static const venueScheme = String.fromEnvironment(
    'VENUE_SCHEME',
    defaultValue: 'http',
  );

  /// Path prefix every venue endpoint sits under, e.g.
  /// `http://<ip>/api/v1/ping`. Matches the reference client's Retrofit base
  /// URL (`http://api.empty/api/v1/`), whose host is swapped for the profile's
  /// IP at request time.
  static const venueApiPrefix = 'api/v1';

  /// Header name carrying the venue access key on every request.
  static const apiKeyHeader = 'X-API-KEY';

  /// Default per-request timeout for venue calls.
  static const requestTimeout = Duration(seconds: 15);

  /// How often the heartbeat pings the venue server to refresh the
  /// Online/Offline indicator. The reference client uses 10s in release and
  /// 30s in debug; we follow the same idea.
  static const heartbeatInterval = Duration(seconds: 10);
  static const heartbeatIntervalDebug = Duration(seconds: 30);
}
