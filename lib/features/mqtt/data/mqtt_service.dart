import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../models/mqtt_connection_config.dart';

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
/// reconnect — but only if a connection was actually established first
/// ([_shouldBeConnected]), so the app never auto-connects on its own.
class MqttService {
  MqttService._();
  static final MqttService instance = MqttService._();

  MqttServerClient? _client;
  MqttConnectionConfig? _config;

  /// Intent flag: true once the user has connected (via the QR "Spoji se" in
  /// "Postavke uređaja"), false after a manual [disconnect]. Only while this is
  /// true do the lifecycle hooks drop/restore the connection.
  bool _shouldBeConnected = false;

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
  /// aren't already. No-op when the user never connected.
  Future<void> onAppResumed() async {
    if (!_shouldBeConnected || isConnected || _config == null) return;
    debugPrint('MQTT ▸ app resumed → reconnecting');
    await _openConnection();
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
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .withWillTopic(_tStatus)
        .withWillMessage(_statusJson('offline'))
        .withWillQos(MqttQos.atLeastOnce)
        .withWillRetain()
        .startClean();
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
  String _statusJson(String status) =>
      '{"status":"$status","naziv":"${_cfg.naziv}","tip":"PELION-ORDER",'
      '"uloga":"kasa","verzija":"1.0.0","uredaj":"${_cfg.uredaj}","ts":${_now()}}';

  String _dojavaJson(String tekst) =>
      '{"tekst":"$tekst","naziv":"${_cfg.naziv}","uredaj":"${_cfg.uredaj}",'
      '"ts":${_now()}}';

  String _ackJson(String msgId) =>
      '{"msg_id":"$msgId","uredaj":"${_cfg.uredaj}","ts":${_now()}}';

  static int _now() => DateTime.now().millisecondsSinceEpoch;
}
