import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../models/mqtt_connection_config.dart';
import '../models/mqtt_order_reply.dart';
import '../models/mqtt_table_query.dart';

/// The phone's single, long-lived MQTT connection to the Pelion broker, driven
/// by a [MqttConnectionConfig] built from the QR code issued by the kasa, and
/// following the connection rules of the spec "I-Kasa MQTT javljanje" v4.0:
///
/// * **Connecting (§7)** — MQTT 3.1.1, clean session false, keepalive 10 s,
///   15 s connection timeout. The FIRST connection of a session is retried
///   forever by [_scheduleRetry]: 5 s, 10 s, 20 s, 40 s, then every 60 s, each
///   plus a random 0–5 s; when the broker refuses the login (return code 4/5)
///   the pace drops to 1 min, 2 min, 5 min, then every 10 min. Once connected,
///   drops are recovered by the client's own auto-reconnect.
/// * **After every connection** (the first one and every auto-reconnect):
///   subscribe with QoS 1, wait for the broker to confirm the subscriptions,
///   and only then publish our status "online" — so nothing announces us as
///   reachable before our reply topic really exists.
/// * **Status and last will (§3, §6)** — `kasa/{lic}/status/{id}`, retained,
///   QoS 1, always the whole message. The kasa activates this orderman when it
///   sees it.
/// * **Clean shutdown (§6)** — stop reconnecting, publish "offline", wait up to
///   3 s for the broker to confirm delivery, then disconnect. Used when the app
///   goes to the background and on a manual disconnect.
///
/// Nothing is ever queued for later: publishing while not connected fails at
/// once (the client has no offline buffer), and callers see that.
///
/// Topics all live under `kasa/{licenca}/` because the broker ACL is
/// `readwrite kasa/%u/#` (`%u` = licenca / username). The phone does NOT take
/// part in `poruka`/`ack` (PelionAdmin → kasa popups) and sends no `dojava`.
class MqttService {
  MqttService._();
  static final MqttService instance = MqttService._();

  MqttServerClient? _client;
  MqttConnectionConfig? _config;

  /// The service should hold a connection: set by [ensureConnected] /
  /// [connectAndSend], cleared by [disconnect] and while the app is in the
  /// background. Nothing (re)connects while this is false.
  bool _running = false;

  /// Stopped because the app went to the background — [onAppResumed] starts it
  /// again. (A manual [disconnect] stays stopped.)
  bool _pausedByLifecycle = false;

  /// One connection attempt at a time: a second connect while one is running
  /// would either fail or open two connections with the same client_id.
  bool _attemptInProgress = false;

  /// A clean shutdown that hasn't finished yet. The next attempt waits for it,
  /// so the old connection is gone — and its "offline" delivered — before a new
  /// one opens with the same client_id: two live connections with one id would
  /// knock each other off the broker, and the old "offline" could land after
  /// the new "online".
  Future<void>? _shutdownInProgress;

  /// The next scheduled attempt of the first connection (see [_scheduleRetry]).
  Timer? _retryTimer;
  int _failedAttempts = 0;
  int _refusedAttempts = 0;
  bool _lastAttemptRefused = false;
  final _random = Random();

  static const _connectTimeout = Duration(seconds: 15);
  static const _retryDelays = [
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 40),
    Duration(seconds: 60),
  ];
  static const _refusedDelays = [
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 10),
  ];

  /// Random extra per retry, so phones don't all come back in the same second
  /// after an outage.
  static const _maxJitterMs = 5000;

  /// How long to wait for the broker to confirm our subscriptions before
  /// announcing "online" anyway (a lost confirmation must not keep the phone
  /// invisible forever).
  static const _subscriptionConfirmWait = Duration(seconds: 10);

  /// How long a clean shutdown waits for "offline" to be delivered.
  static const _offlineDeliveryWait = Duration(seconds: 3);

  /// Subscriptions still waiting for the broker's confirmation (SUBACK) on the
  /// current connection, and the signal that they have all settled.
  final _pendingSubscriptions = <String>{};
  Completer<void>? _subscriptionsSettled;

  /// `spojen` in our status (ms since epoch): when the connection attempt that
  /// first succeeded in this run of the app started. The same value goes into
  /// the last will and into every "online", and it doesn't change on later
  /// reconnects — only a new run (or a new device identity) starts it again.
  int? _spojen;

  /// The raw `podaci/artikli` payload (the menu: groups + articles), updated
  /// whenever the broker delivers it (it's retained, so it arrives on connect).
  /// The menu provider listens to this, parses + persists it.
  final ValueNotifier<String?> artikliRawJson = ValueNotifier<String?>(null);

  /// The raw `podaci/korisnici` payload (staff/users used for PIN login),
  /// updated whenever the broker delivers it (retained → arrives on connect).
  final ValueNotifier<String?> korisniciRawJson = ValueNotifier<String?>(null);

  /// The raw `podaci/stolovi` payload (tables grouped by zone/terrace).
  final ValueNotifier<String?> stoloviRawJson = ValueNotifier<String?>(null);

  /// The raw `podaci/stolovi_stanje` payload (which tables are occupied).
  final ValueNotifier<String?> stanjeRawJson = ValueNotifier<String?>(null);

  /// The raw `podaci/verzija` payload — a version hash per data section
  /// (stolovi / artikli / korisnici). Providers compare these against their
  /// saved hash to skip re-parsing/re-storing unchanged sections.
  final ValueNotifier<String?> verzijaRawJson = ValueNotifier<String?>(null);

  /// The state of THE connection, announced as it changes — true while the
  /// phone is connected to the broker. Not a second connection: [isConnected]
  /// can only be asked, while this also tells whoever listens (e.g. the
  /// connection bubble in "Neposlane narudžbe") the moment it is lost or back.
  final ValueNotifier<bool> connected = ValueNotifier<bool>(false);

  /// Replies from the kasa to our orders (`kasa/{LICENCA}/mob/{od}`). Broadcast
  /// so the send logic can await the one matching its `msg_id`.
  final _orderReplies = StreamController<MqttOrderReply>.broadcast();
  Stream<MqttOrderReply> get orderReplies => _orderReplies.stream;

  /// The most recent reply (handy for diagnostics).
  MqttOrderReply? lastOrderReply;

  /// Replies to our table queries (`tip: "stol"`), on the same `mob/{od}` topic
  /// as the order replies above. Broadcast, paired downstream by `msg_id`.
  final _tableReplies = StreamController<MqttTableQueryReply>.broadcast();
  Stream<MqttTableQueryReply> get tableReplies => _tableReplies.stream;

  /// The `tip` of a reply payload, or null when it has none / isn't JSON.
  /// Used only to route between the order and table-query streams.
  String? _tipOf(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['tip'] != null) {
        return decoded['tip'].toString();
      }
    } catch (_) {}
    return null;
  }

  /// The current version hash for [section] (from the last `podaci/verzija`),
  /// or null if not received / not present.
  String? versionFor(String section) {
    final raw = verzijaRawJson.value;
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded[section] != null) {
        return decoded[section].toString();
      }
    } catch (_) {}
    return null;
  }

  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  /// The licenca of the active connection (null until connected once).
  String? get licenca => _config?.licenca;

  /// The exact topic we subscribe to for the menu (null until connected once).
  String? get subscribedArtikliTopic => _config == null ? null : _tArtikli;

  MqttConnectionConfig get _cfg => _config!;

  // ── Topics, computed from the config ───────────────────────────────────────
  static String _statusTopic(MqttConnectionConfig c) =>
      'kasa/${c.licenca}/status/${c.uredaj}'; // our status (retained)
  String get _tStatus => _statusTopic(_cfg);
  String get _tArtikli =>
      'kasa/${_cfg.licenca}/podaci/artikli'; // menu (retained)
  String get _tKorisnici =>
      'kasa/${_cfg.licenca}/podaci/korisnici'; // staff/users (retained)
  String get _tStolovi =>
      'kasa/${_cfg.licenca}/podaci/stolovi'; // tables + zones (retained)
  String get _tStanje =>
      'kasa/${_cfg.licenca}/podaci/stolovi_stanje'; // occupancy (retained)
  String get _tVerzija =>
      'kasa/${_cfg.licenca}/podaci/verzija'; // per-section version hashes

  /// Where orders are published. Shared by every mobile under the licenca;
  /// only the kasa holding the DB processes them.
  String get _tNarudzbe => 'kasa/${_cfg.licenca}/narudzbe';

  /// Where questions for the kasa go ("what is on this table").
  String get _tUpiti => 'kasa/${_cfg.licenca}/upiti';

  /// Our PRIVATE reply topic: the kasa answers orders and table queries on
  /// `kasa/{LICENCA}/mob/{id}`. Subscribed for the whole session, so a reply is
  /// never missed — including one sent while we were away (persistent session).
  String get _tMob => 'kasa/${_cfg.licenca}/mob/${_cfg.uredaj}';

  /// Everything the phone subscribes to, every time it connects.
  List<String> get _subscriptionTopics =>
      [_tArtikli, _tKorisnici, _tStolovi, _tStanje, _tVerzija, _tMob];

  /// Our MQTT client-id — this is the `od` field of an order, and the last
  /// segment of the reply topic.
  String? get clientId => _config?.uredaj;

  /// The reply topic we're subscribed to (null until connected once).
  String? get replyTopic => _config == null ? null : _tMob;

  /// Whether our `od` (client-id) is usable in an order. The kasa SILENTLY
  /// drops an order whose `od` is empty, longer than 64 chars, or contains
  /// `/ + #` — no reply at all — so this must hold before sending.
  bool get isReplyIdValid {
    final id = _config?.uredaj ?? '';
    return id.isNotEmpty && id.length <= 64 && !RegExp(r'[/+#]').hasMatch(id);
  }

  /// Publishes an order payload to `kasa/{LICENCA}/narudzbe`.
  ///
  /// QoS 1 and **retain: false** — a retained order would be re-executed by
  /// every kasa that later subscribes. Returns false when it could not be
  /// published right now (not connected); nothing is queued for later.
  bool publishOrder(String payload) {
    if (_config == null) return false;
    return _publish(_tNarudzbe, payload) != null;
  }

  /// Publishes a query payload to `kasa/{LICENCA}/upiti`. QoS 1, retain false —
  /// a question must never outlive the moment it was asked.
  bool publishQuery(String payload) {
    if (_config == null) return false;
    return _publish(_tUpiti, payload) != null;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Starts the connection with [config] (the "Postavke uređaja" scan/connect
  /// buttons) and returns a line describing the first attempt. If it fails,
  /// the retries carry on in the background.
  Future<String> connectAndSend(MqttConnectionConfig config) async {
    await _adopt(config);
    _running = true;
    _pausedByLifecycle = false;
    if (isConnected) return 'MQTT: spojeno kao ${config.uredaj}.';
    if (_attemptInProgress) return 'MQTT: spajanje je u tijeku…';
    return _attempt();
  }

  /// Connects with the device's stored provisioning — at launch. Never gives
  /// up: a failed attempt schedules the next one (see [_scheduleRetry]).
  Future<void> ensureConnected(MqttConnectionConfig config) async {
    await _adopt(config);
    _running = true;
    _pausedByLifecycle = false;
    if (isConnected || _attemptInProgress) return;
    await _attempt();
  }

  /// The app went to the background (or is closing): clean shutdown. The OS
  /// would cut the connection anyway; announcing "offline" ourselves means the
  /// broker doesn't keep showing us online until the keepalive runs out.
  Future<void> onAppPaused() async {
    if (!_running) return;
    debugPrint('MQTT ▸ app paused → clean shutdown');
    _running = false;
    _pausedByLifecycle = true;
    await _cleanShutdown();
  }

  /// The app returned to the foreground: start again, as a new connection
  /// (a new first-connection retry sequence).
  Future<void> onAppResumed() async {
    if (!_pausedByLifecycle || _config == null) return;
    debugPrint('MQTT ▸ app resumed → connecting');
    _pausedByLifecycle = false;
    _running = true;
    _resetRetries();
    if (isConnected || _attemptInProgress) return;
    await _attempt();
  }

  /// Manual, user-initiated disconnect: clean shutdown, and nothing reconnects
  /// on its own afterwards.
  void disconnect() {
    debugPrint('MQTT ▸ manual disconnect');
    _running = false;
    _pausedByLifecycle = false;
    unawaited(_cleanShutdown());
  }

  /// Takes [config] as the active provisioning. A different device identity (a
  /// newly scanned code) first shuts the old connection down cleanly and starts
  /// `spojen` and the retry sequence afresh.
  Future<void> _adopt(MqttConnectionConfig config) async {
    final previous = _config;
    if (previous != null && previous.uredaj != config.uredaj) {
      await _cleanShutdown();
      _spojen = null;
      _resetRetries();
    }
    _config = config;
  }

  // ── Connecting ─────────────────────────────────────────────────────────────

  /// One attempt at the first connection; schedules the next one if it fails.
  Future<String> _attempt() async {
    final config = _config;
    if (config == null) {
      return 'MQTT: uređaj nije postavljen — skenirajte QR kod.';
    }
    _retryTimer?.cancel();
    _retryTimer = null;
    _attemptInProgress = true;
    final String result;
    try {
      final shutdown = _shutdownInProgress;
      if (shutdown != null) await shutdown;
      result = await _openConnection(config);
    } finally {
      _attemptInProgress = false;
    }
    if (isConnected) {
      _resetRetries();
    } else {
      _scheduleRetry();
    }
    return result;
  }

  /// Plans the next attempt of the first connection, per §7: 5, 10, 20, 40 s,
  /// then every 60 s — or 1, 2, 5, then every 10 min when the broker refused
  /// the login — each plus a random 0–5 s, counted from the end of the failed
  /// attempt. Only while the service is running and not connected.
  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    if (!_running || _config == null || isConnected) return;
    final Duration base;
    if (_lastAttemptRefused) {
      base = _refusedDelays[min(_refusedAttempts, _refusedDelays.length - 1)];
      _refusedAttempts++;
    } else {
      base = _retryDelays[min(_failedAttempts, _retryDelays.length - 1)];
      _failedAttempts++;
    }
    final wait =
        base + Duration(milliseconds: _random.nextInt(_maxJitterMs + 1));
    debugPrint('MQTT ▸ next connection attempt in ${wait.inSeconds} s'
        '${_lastAttemptRefused ? ' (the broker refused the login)' : ''}');
    _retryTimer = Timer(wait, () {
      _retryTimer = null;
      if (_running && !isConnected && !_attemptInProgress) _attempt();
    });
  }

  void _resetRetries() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _failedAttempts = 0;
    _refusedAttempts = 0;
    _lastAttemptRefused = false;
  }

  /// Opens a connection with [config]: builds the options and the last will
  /// (with this attempt's `spojen`), connects, subscribes, waits for the
  /// subscriptions to be confirmed, and announces "online".
  Future<String> _openConnection(MqttConnectionConfig config) async {
    // Client-id = the id from the kasa's QR code (`{lic}-PELIONORDER-{broj}`).
    final clientId = config.uredaj;

    // `spojen` for this attempt, built into the last will BEFORE connecting:
    // the start of this attempt — or, once one has succeeded in this run, that
    // first value, so the will and the "online" status never disagree.
    final attemptSpojen = _spojen ?? DateTime.now().millisecondsSinceEpoch;

    // One try per attempt: the retry pacing is ours (§7), not the client's.
    final client = MqttServerClient.withPort(
      config.broker,
      clientId,
      config.port,
      maxConnectionAttempts: 1,
    );
    client
      ..secure = config.tls
      ..keepAlivePeriod = config.keepalive
      // An attempt that hangs must not hold up the next one.
      ..connectTimeoutPeriod = _connectTimeout.inMilliseconds
      // After the first success, drops are recovered by the client itself,
      // with the same options and the same last will.
      ..autoReconnect = true
      ..resubscribeOnAutoReconnect = true
      ..logging(on: true)
      ..setProtocolV311()
      // TEST ONLY: the broker cert is signed by a private CA ("Pelion
      // Orderman CA"). Accept it here instead of bundling the truststore.
      ..onBadCertificate = ((Object? cert) => true);

    // Every callback first checks that this client is still the current one:
    // a replaced or shut-down client must not change the service's state.
    bool current() => identical(_client, client);
    client
      ..onConnected = (() {
        if (!current()) return;
        debugPrint('MQTT ▸ connected as $clientId');
        connected.value = true;
      })
      ..onDisconnected = (() {
        if (!current()) return;
        debugPrint('MQTT ▸ disconnected');
        connected.value = false;
      })
      ..onAutoReconnect = (() {
        if (!current()) return;
        debugPrint('MQTT ▸ connection lost — reconnecting');
        connected.value = false;
        // The client resubscribes on its own once back; wait for those
        // confirmations before announcing "online" again.
        _expectSubscriptionConfirmations();
      })
      ..onAutoReconnected = (() {
        if (!current()) return;
        debugPrint('MQTT ▸ reconnected');
        connected.value = true;
        unawaited(_announceOnline(client));
      })
      ..onSubscribed = ((String topic) {
        if (!current()) return;
        debugPrint('MQTT ▸ subscribed: $topic');
        _subscriptionSettled(topic);
      })
      ..onSubscribeFail = ((String topic) {
        if (!current()) return;
        debugPrint('MQTT ✗ subscribe DENIED (ACL): $topic');
        _subscriptionSettled(topic);
      })
      // Supplying this makes a failed attempt return instead of throwing.
      ..onFailedConnectionAttempt = ((int attempt) {
        debugPrint('MQTT ✗ connection attempt failed');
      })
      ..pongCallback = (() {
        debugPrint('MQTT ▸ pong (keepalive)');
      });

    // Last-Will on kasa/{lic}/status/{id}: the full status with
    // "status":"offline", retained, QoS 1 — the broker publishes it if we drop
    // without a clean disconnect.
    //
    // Deliberately NO .startClean(): a PERSISTENT session (cleanSession =
    // false), so the broker keeps our subscriptions and queues the kasa's
    // replies during short drops. It depends on a stable client-id — the id
    // issued by the kasa.
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .withWillTopic(_statusTopic(config))
        .withWillMessage(_statusJson(config, 'offline', attemptSpojen))
        .withWillQos(MqttQos.atLeastOnce)
        .withWillRetain();
    _client = client;

    try {
      debugPrint('MQTT ▸ connecting to ssl://${config.broker}:${config.port} '
          'as $clientId (user=${config.licenca})…');
      await client.connect(config.licenca, config.lozinka);
    } catch (e) {
      debugPrint('MQTT ✗ connect error: $e');
    }

    if (!current()) {
      // Shut down (or replaced by a new code) while this attempt was running.
      _discard(client);
      return 'MQTT: spajanje prekinuto.';
    }
    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      final rc = client.connectionStatus?.returnCode;
      _lastAttemptRefused = rc == MqttConnectReturnCode.badUsernameOrPassword ||
          rc == MqttConnectReturnCode.notAuthorized;
      debugPrint('MQTT ✗ not connected: $rc');
      _client = null;
      connected.value = false;
      _discard(client);
      return _lastAttemptRefused
          ? 'MQTT: broker je odbio prijavu (${rc?.name}).'
          : 'MQTT: nije spojeno (${rc?.name ?? 'nepoznato'}).';
    }

    _lastAttemptRefused = false;
    _spojen = attemptSpojen;

    // Attach listeners AFTER connect: `client.updates` is null until the
    // client has connected, so listening earlier silently no-ops and every
    // inbound message (including the retained menu) is dropped.
    client.updates?.listen((events) {
      if (!current()) return;
      for (final e in events) {
        _onMessage(e);
      }
    });
    client.published?.listen((m) {
      debugPrint(
          'MQTT ▸ published ACK id=${m.variableHeader?.messageIdentifier}'
          ' topic=${m.variableHeader?.topicName}');
    });

    // Subscribe with QoS 1 — the retained data flows to the listener above —
    // and announce "online" only once the broker has confirmed them.
    _expectSubscriptionConfirmations();
    try {
      for (final topic in _subscriptionTopics) {
        client.subscribe(topic, MqttQos.atLeastOnce);
      }
    } catch (e) {
      debugPrint('MQTT ✗ subscribe failed: $e');
    }
    debugPrint('MQTT ▸ replies on: $_tMob');
    if (!isReplyIdValid) {
      debugPrint('MQTT ✗ WARNING: "od" (${config.uredaj}) is invalid — the '
          'kasa will silently drop orders (no reply). It must be 1-64 chars '
          'and must not contain / + #');
    }
    await _announceOnline(client);
    connected.value = isConnected;
    return 'MQTT: spojeno kao ${config.uredaj}.';
  }

  /// Routes one inbound message by topic.
  void _onMessage(MqttReceivedMessage<MqttMessage> e) {
    final m = e.payload as MqttPublishMessage;
    final payload = MqttPublishPayload.bytesToStringAsString(m.payload.message);
    debugPrint('MQTT ◂ ${e.topic}: $payload');
    if (e.topic == _tArtikli) artikliRawJson.value = payload;
    if (e.topic == _tKorisnici) korisniciRawJson.value = payload;
    if (e.topic == _tStolovi) stoloviRawJson.value = payload;
    if (e.topic == _tStanje) stanjeRawJson.value = payload;
    // Our private reply topic carries BOTH order replies (`tip: "nalog"`) and
    // table-query answers (`tip: "stol"`); each is paired downstream by the
    // msg_id we generated.
    //
    // Only "stol" is matched positively — everything else keeps going to the
    // order path, so a kasa that sends no `tip` on order replies still works.
    if (e.topic == _tMob) {
      final tip = _tipOf(payload);
      if (tip == 'stol') {
        final reply = MqttTableQueryReply.tryParse(payload);
        if (reply == null) {
          debugPrint('MQTT ✗ unusable table reply (no msg_id?): $payload');
        } else {
          _tableReplies.add(reply);
        }
      } else {
        if (tip != null && tip != 'nalog') {
          debugPrint('MQTT ▸ unknown reply tip "$tip" — routed to orders; '
              'add a case for it if this is a new query type');
        }
        final reply = MqttOrderReply.tryParse(payload);
        if (reply == null) {
          debugPrint('MQTT ✗ unusable order reply (no msg_id?): $payload');
        } else {
          lastOrderReply = reply;
          _orderReplies.add(reply);
        }
      }
    }
    // Set the version LAST so, if it arrives in the same batch as the data,
    // the providers see the fresh data when they re-evaluate.
    if (e.topic == _tVerzija) verzijaRawJson.value = payload;
  }

  void _expectSubscriptionConfirmations() {
    _pendingSubscriptions
      ..clear()
      ..addAll(_subscriptionTopics);
    _subscriptionsSettled = Completer<void>();
  }

  /// The broker answered a subscription (granted or denied) — denied ones
  /// settle too, so an ACL problem can't hold "online" back forever.
  void _subscriptionSettled(String topic) {
    if (!_pendingSubscriptions.remove(topic)) return;
    final settled = _subscriptionsSettled;
    if (_pendingSubscriptions.isEmpty &&
        settled != null &&
        !settled.isCompleted) {
      settled.complete();
    }
  }

  /// Publishes "online" once the subscriptions are confirmed (or the wait has
  /// run out) — and only if [client] is still the live connection.
  Future<void> _announceOnline(MqttServerClient client) async {
    final settled = _subscriptionsSettled;
    if (settled != null) {
      try {
        await settled.future.timeout(_subscriptionConfirmWait);
      } on TimeoutException {
        debugPrint('MQTT ▸ subscriptions not all confirmed within '
            '${_subscriptionConfirmWait.inSeconds} s ($_pendingSubscriptions) '
            '— announcing online anyway');
      }
    }
    if (!identical(_client, client) || !isConnected) return;
    // The "connected" message: our full status, retained, on
    // kasa/{lic}/status/{id}. The kasa marks this orderman activated the moment
    // it sees it — and because it is retained, even a kasa that is offline
    // right now gets it as soon as it connects.
    _publishStatus('online');
  }

  // ── Shutting down ──────────────────────────────────────────────────────────

  /// Clean shutdown (§6): no more retries, "offline" published and confirmed
  /// by the broker (at most [_offlineDeliveryWait]), then a proper disconnect —
  /// which also tells the broker not to publish our last will.
  Future<void> _cleanShutdown() {
    final shutdown = _performCleanShutdown();
    _shutdownInProgress = shutdown;
    return shutdown.whenComplete(() {
      if (identical(_shutdownInProgress, shutdown)) _shutdownInProgress = null;
    });
  }

  Future<void> _performCleanShutdown() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    final client = _client;
    final config = _config;
    // Detached first: from here nothing treats this client as the connection,
    // and none of its callbacks change the service's state.
    _client = null;
    connected.value = false;
    if (client == null) return;

    if (config != null &&
        client.connectionStatus?.state == MqttConnectionState.connected) {
      final delivered = Completer<void>();
      int? id;
      final sub = client.published?.listen((m) {
        if (id != null &&
            m.variableHeader?.messageIdentifier == id &&
            !delivered.isCompleted) {
          delivered.complete();
        }
      });
      try {
        final builder = MqttClientPayloadBuilder()
          ..addString(_statusJson(config, 'offline', _spojen ?? _now()));
        id = client.publishMessage(
          _statusTopic(config),
          MqttQos.atLeastOnce,
          builder.payload!,
          retain: true,
        );
        debugPrint('MQTT ▸ publish offline (id=$id) — waiting for delivery');
        await delivered.future.timeout(_offlineDeliveryWait);
        debugPrint('MQTT ▸ offline delivered');
      } catch (e) {
        debugPrint('MQTT ▸ offline not confirmed before disconnecting: $e');
      } finally {
        await sub?.cancel();
      }
    }
    _discard(client);
  }

  /// Disconnects a client that is no longer wanted, making sure it doesn't try
  /// to reconnect on its own afterwards.
  void _discard(MqttServerClient client) {
    client.autoReconnect = false;
    try {
      client.disconnect();
    } catch (_) {}
  }

  // ── Publishing ─────────────────────────────────────────────────────────────

  void _publishStatus(String status) => _publish(
        _tStatus,
        _statusJson(_cfg, status, _spojen ?? _now()),
        retain: true,
      );

  /// Publishes with QoS 1 right now, or returns null when that's not possible
  /// (not connected, or the client refused). Never queues.
  int? _publish(String topic, String payload, {bool retain = false}) {
    final c = _client;
    if (c == null || !isConnected) return null;
    try {
      final builder = MqttClientPayloadBuilder()..addString(payload);
      final id = c.publishMessage(
        topic,
        MqttQos.atLeastOnce,
        builder.payload!,
        retain: retain,
      );
      debugPrint('MQTT ▸ publish → "$topic" (id=$id) $payload');
      return id;
    } catch (e) {
      debugPrint('MQTT ✗ publish → "$topic" failed: $e');
      return null;
    }
  }

  // ── JSON payloads ──────────────────────────────────────────────────────────
  //
  // Always jsonEncode, never string interpolation: `naziv` is the venue name
  // and may contain quotes. Dart ints are written as whole numbers (never
  // 1.789E12), which the kasa requires for `sh` and `spojen`.

  /// Our status (spec v4.0, §3): the whole message on every publish, fields
  /// and values exactly as specified. `prima` is always false — an orderman
  /// sends orders, it never receives them. No `opp`/`onu` (kasa-only).
  static String _statusJson(
    MqttConnectionConfig config,
    String status,
    int spojen,
  ) =>
      jsonEncode({
        'sh': 1,
        'uredaj': config.uredaj,
        'tip': 'PELIONORDER',
        'grupa': config.grupa,
        'naziv': config.naziv,
        'status': status,
        'prima': false,
        'spojen': spojen,
      });

  static int _now() => DateTime.now().millisecondsSinceEpoch;
}
