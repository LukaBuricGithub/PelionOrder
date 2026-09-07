import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../models/mqtt_connection_config.dart';
import '../models/mqtt_order_reply.dart';
import '../models/mqtt_table_query.dart';

/// A long-lived MQTT connection speaking the real Pelion "semafor" protocol,
/// driven by a [MqttConnectionConfig] built from the scanned QR code. Connects
/// and KEEPS the socket open (auto-reconnect), subscribes to
/// `kasa/{licenca}/poruka`, publishes a retained "online" status and a "dojava"
/// (visible in PelionAdmin), and acks any inbound message. Everything is logged
/// to the console.
///
/// Topics all live under `kasa/{licenca}/` because the broker ACL is
/// `readwrite kasa/%u/#` (`%u` = licenca / username).
///
/// Lifecycle: the app wires [onAppPaused] / [onAppResumed] to the widget
/// lifecycle. On background we publish `offline` and drop the socket (the OS
/// would suspend us and the broker would time us out anyway); on resume we
/// reconnect.
///
/// Once the device is provisioned (QR scanned — the code is persisted by
/// `mqttConfigProvider`), the app connects on its own: `main.dart` calls
/// [ensureConnected] at launch, so every cold start and every return from
/// background comes back online without anyone touching the settings screen.
class MqttService {
  MqttService._();
  static final MqttService instance = MqttService._();

  MqttServerClient? _client;
  MqttConnectionConfig? _config;

  /// Intent flag: true once a connection has been asked for (auto-connect at
  /// launch with the stored QR provisioning, or the button in "Postavke
  /// uređaja"), false after a manual [disconnect]. Only while this is true do
  /// the lifecycle hooks drop/restore the connection.
  bool _shouldBeConnected = false;

  /// Guards [ensureConnected] so the launch and resume paths can't run two
  /// retry loops against each other.
  bool _connectLoopRunning = false;

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

  // ── Protocol topics (mirror MqttKasaService), computed from the config ──────
  String get _tStatus =>
      'kasa/${_cfg.licenca}/status/${_cfg.uredaj}'; // device → server (retained)
  String get _tPoruka => 'kasa/${_cfg.licenca}/poruka'; // server → device
  String get _tAck => 'kasa/${_cfg.licenca}/ack'; // device → server
  String get _tDojava => 'kasa/${_cfg.licenca}/dojava'; // visible in admin
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

  /// Our MQTT client-id — this is the `od` field of an order, and the last
  /// segment of the reply topic.
  String? get clientId => _config?.uredaj;

  /// Publishes an order payload to `kasa/{LICENCA}/narudzbe`.
  ///
  /// QoS 1 and **retain: false** — a retained order would be re-executed by
  /// every kasa that later subscribes (protocol doc, 3.1). Returns false when
  /// we're not connected.
  bool publishOrder(String payload) {
    if (_client == null || !isConnected || _config == null) return false;
    _publish(_tNarudzbe, payload);
    return true;
  }

  /// Where questions for the kasa go ("what is on this table").
  String get _tUpiti => 'kasa/${_cfg.licenca}/upiti';

  /// Publishes a query payload to `kasa/{LICENCA}/upiti`. QoS 1, retain false —
  /// a question must never outlive the moment it was asked.
  bool publishQuery(String payload) {
    if (_client == null || !isConnected || _config == null) return false;
    _publish(_tUpiti, payload);
    return true;
  }

  /// Our PRIVATE reply topic: the kasa answers an order on
  /// `kasa/{LICENCA}/mob/{od}`, where `od` is our MQTT client-id
  /// (`_cfg.uredaj`). We stay subscribed for the whole session, so a reply is
  /// never missed — including one sent while we were away.
  String get _tMob => 'kasa/${_cfg.licenca}/mob/${_cfg.uredaj}';

  /// The reply topic we're subscribed to (null until connected once).
  String? get replyTopic => _config == null ? null : _tMob;

  /// Whether our `od` (client-id) is usable in an order. The kasa SILENTLY
  /// drops an order whose `od` is empty, longer than 64 chars, or contains
  /// `/ + #` — no reply at all — so this must hold before sending.
  bool get isReplyIdValid {
    final id = _config?.uredaj ?? '';
    return id.isNotEmpty && id.length <= 64 && !RegExp(r'[/+#]').hasMatch(id);
  }

  /// Connects using [config] (built from the scanned QR code). The MQTT
  /// client-id is the device id `config.uredaj` — the real provisioned id
  /// `<licenca>-ORDERMAN-<n>`.
  Future<String> connectAndSend(MqttConnectionConfig config) async {
    if (isConnected) {
      _publishDojava('Ponovni test iz mobilne aplikacije');
      return 'MQTT: već spojeno — nova dojava poslana (prati CMD / PelionAdmin).';
    }

    _config = config;
    _shouldBeConnected = true; // remember we want to stay connected
    return _openConnection();
  }

  /// The app went to background (or is closing): publish `offline` and drop the
  /// socket. Keeps [_shouldBeConnected] so [onAppResumed] can restore it.
  Future<void> onAppPaused() async {
    if (!_shouldBeConnected) return;
    debugPrint('MQTT ▸ app paused → going offline');
    if (isConnected) _publishStatus('offline');
    _client?.disconnect();
    _client = null;
  }

  /// The app returned to foreground: reconnect if we were connected before and
  /// aren't already. No-op when the device was never provisioned.
  Future<void> onAppResumed() async {
    final config = _config;
    if (!_shouldBeConnected || isConnected || config == null) return;
    debugPrint('MQTT ▸ app resumed → reconnecting');
    await ensureConnected(config);
  }

  /// Connects with the device's stored provisioning, retrying a few times with a
  /// growing delay.
  ///
  /// Used at launch and on resume. A single attempt isn't enough there: a cold
  /// start regularly beats the phone's WiFi/mobile data to it, and
  /// [autoReconnect] only covers drops AFTER a connection was established — so
  /// one failed attempt would strand the app offline until someone opened
  /// "Postavke uređaja" and reconnected by hand.
  Future<void> ensureConnected(
    MqttConnectionConfig config, {
    int attempts = 4,
  }) async {
    if (isConnected || _connectLoopRunning) return;
    _connectLoopRunning = true;
    _config = config;
    _shouldBeConnected = true;
    try {
      for (var i = 1; i <= attempts; i++) {
        await _openConnection();
        if (isConnected) return;
        if (i < attempts) {
          final wait = Duration(seconds: 2 * i); // 2s, 4s, 6s
          debugPrint('MQTT ▸ connect failed (attempt $i/$attempts) — '
              'retry in ${wait.inSeconds}s');
          await Future<void>.delayed(wait);
          // The waiter may have connected manually in the meantime.
          if (isConnected) return;
        }
      }
      debugPrint('MQTT ✗ could not connect after $attempts attempts');
    } finally {
      _connectLoopRunning = false;
    }
  }

  /// Opens the socket using the stored [_config].
  Future<String> _openConnection() async {
    final config = _cfg;

    // Client-id = the device id from the QR (`<licenca>-ORDERMAN-<n>`).
    final clientId = config.uredaj;

    final client =
        MqttServerClient.withPort(config.broker, clientId, config.port)
          ..secure = config.tls
          ..keepAlivePeriod = config.keepalive
          ..connectTimeoutPeriod = 8000
          ..autoReconnect = true
          ..resubscribeOnAutoReconnect = true
          ..logging(on: true)
          ..setProtocolV311()
          // TEST ONLY: the broker cert is signed by a private CA ("Pelion
          // Orderman CA"). Accept it here instead of bundling the truststore.
          ..onBadCertificate = ((Object? cert) => true)
          ..onConnected = (() {
            debugPrint('MQTT ▸ connected as $clientId');
          })
          ..onDisconnected = (() {
            debugPrint('MQTT ▸ disconnected');
          })
          ..onSubscribed = ((String t) {
            debugPrint('MQTT ▸ subscribed: $t');
          })
          ..onSubscribeFail = ((String t) {
            debugPrint('MQTT ✗ subscribe DENIED (ACL): $t');
          })
          ..pongCallback = (() {
            debugPrint('MQTT ▸ pong (keepalive)');
          });

    // Last-Will: broker publishes "offline" (retained) if we drop unexpectedly.
    //
    // Deliberately NO .startClean(): we want a PERSISTENT session
    // (cleanSession = false) so the broker queues the kasa's reply to an order
    // while we're offline and delivers it when we reconnect — even if the app
    // was closed in the meantime (protocol doc, 4.2). This depends on the
    // client-id staying stable across runs, which it is: it's the provisioned
    // `uredaj` from the QR code.
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .withWillTopic(_tStatus)
        .withWillMessage(_statusJson('offline'))
        .withWillQos(MqttQos.atLeastOnce)
        .withWillRetain();
    _client = client;

    try {
      debugPrint('MQTT ▸ connecting to ssl://${config.broker}:${config.port} '
          'as $clientId (user=${config.licenca})…');
      await client.connect(config.licenca, config.lozinka);

      if (!isConnected) {
        final rc = client.connectionStatus?.returnCode;
        debugPrint('MQTT ✗ not connected: $rc');
        _client = null;
        return 'MQTT: nije spojeno (${rc ?? 'nepoznato'}).';
      }

      // Attach listeners AFTER connect: `client.updates` is null until the
      // client has connected, so listening earlier silently no-ops and every
      // inbound message (including the retained menu) is dropped.
      // (poruka → log + ack; podaci/artikli → the menu payload.)
      client.updates?.listen((events) {
        for (final e in events) {
          final m = e.payload as MqttPublishMessage;
          final payload =
              MqttPublishPayload.bytesToStringAsString(m.payload.message);
          debugPrint('MQTT ◂ ${e.topic}: $payload');
          if (e.topic == _tPoruka) _ack(payload);
          if (e.topic == _tArtikli) artikliRawJson.value = payload;
          if (e.topic == _tKorisnici) korisniciRawJson.value = payload;
          if (e.topic == _tStolovi) stoloviRawJson.value = payload;
          if (e.topic == _tStanje) stanjeRawJson.value = payload;
          // Our private reply topic carries BOTH order replies (`tip: "nalog"`)
          // and table-query answers (`tip: "stol"`); each is paired downstream
          // by the msg_id we generated.
          //
          // Only "stol" is matched positively — everything else keeps going to
          // the order path. `tip` on order replies is a recent addition on the
          // kasa side, so a kasa that predates it sends none at all, and a
          // strict positive match would silently break order sending.
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
          // Set the version LAST so, if it arrives in the same batch as the
          // data, the providers see the fresh data when they re-evaluate.
          if (e.topic == _tVerzija) verzijaRawJson.value = payload;
        }
      });
      client.published?.listen((m) {
        debugPrint(
            'MQTT ▸ published ACK id=${m.variableHeader?.messageIdentifier}'
            ' topic=${m.variableHeader?.topicName}');
      });

      // Now subscribe — the retained menu + users flow to the listener above.
      client.subscribe(_tPoruka, MqttQos.atLeastOnce);
      client.subscribe(_tArtikli, MqttQos.atLeastOnce);
      client.subscribe(_tKorisnici, MqttQos.atLeastOnce);
      client.subscribe(_tStolovi, MqttQos.atLeastOnce);
      client.subscribe(_tStanje, MqttQos.atLeastOnce);
      client.subscribe(_tVerzija, MqttQos.atLeastOnce);
      // Our private reply topic — MUST be subscribed before any order is sent,
      // and kept for the whole session (see the protocol doc, 4.1).
      client.subscribe(_tMob, MqttQos.atLeastOnce);
      debugPrint('MQTT ▸ replies on: $_tMob');
      if (!isReplyIdValid) {
        debugPrint('MQTT ✗ WARNING: "od" (${config.uredaj}) is invalid — the '
            'kasa will silently drop orders (no reply). It must be 1-64 chars '
            'and must not contain / + #');
      }
      _publishStatus('online');
      _publishDojava('Test veze iz mobilne aplikacije');

      return 'MQTT: spojeno kao ${config.uredaj}; status "online" + dojava '
          'poslani (prati CMD / PelionAdmin).';
    } catch (e) {
      debugPrint('MQTT ✗ error: $e');
      _client?.disconnect();
      _client = null;
      return 'MQTT greška: $e';
    }
  }

  void _publishStatus(String status) =>
      _publish(_tStatus, _statusJson(status), retain: true);

  void _publishDojava(String tekst) => _publish(_tDojava, _dojavaJson(tekst));

  void _ack(String porukaPayload) {
    String msgId = '';
    try {
      final data = jsonDecode(porukaPayload);
      if (data is Map && data['msg_id'] != null) {
        msgId = data['msg_id'].toString();
      }
    } catch (_) {}
    _publish(_tAck, _ackJson(msgId));
  }

  void _publish(String topic, String payload, {bool retain = false}) {
    final c = _client;
    if (c == null) return;
    final builder = MqttClientPayloadBuilder()..addString(payload);
    final id = c.publishMessage(
      topic,
      MqttQos.atLeastOnce,
      builder.payload!,
      retain: retain,
    );
    debugPrint('MQTT ▸ publish → "$topic" (id=$id) $payload');
  }

  /// Manual, user-initiated disconnect: clears the intent flag so the lifecycle
  /// hooks won't silently reconnect afterwards.
  void disconnect() {
    debugPrint('MQTT ▸ manual disconnect');
    _shouldBeConnected = false;
    if (_config != null && isConnected) _publishStatus('offline');
    _client?.disconnect();
    _client = null;
  }

  // ── JSON payloads (mirror the Java service), built from the active config ───
  //
  // `uloga` is "orderman": this device is a waiter's mobile, not a kasa. (It
  // said "kasa" while the service was first mirrored from the Java one.)
  String _statusJson(String status) =>
      '{"status":"$status","naziv":"${_cfg.naziv}","tip":"PELION-ORDER",'
      '"uloga":"orderman","verzija":"1.0.0","uredaj":"${_cfg.uredaj}",'
      '"ts":${_now()}}';

  String _dojavaJson(String tekst) =>
      '{"tekst":"$tekst","naziv":"${_cfg.naziv}","uredaj":"${_cfg.uredaj}",'
      '"ts":${_now()}}';

  String _ackJson(String msgId) =>
      '{"msg_id":"$msgId","uredaj":"${_cfg.uredaj}","ts":${_now()}}';

  static int _now() => DateTime.now().millisecondsSinceEpoch;
}
