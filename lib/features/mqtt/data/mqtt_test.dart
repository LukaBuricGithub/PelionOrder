import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

// ── Config (from the JSON) ──────────────────────────────────────────────────
const _broker = 'mqtt.pelionpro.com';
const _port = 8883;
const _licenca = '7D5BE17A85AD3016DE3C914A'; // username
const _lozinka = '0000'; // password
const _uredaj = 'MOBILE-002-POS'; // device id
const _naziv = 'MOBILE TEST kasa';
const _keepAlive = 10;
const _tls = true;

// ── Protocol topics (mirrors MqttKasaService) — everything under kasa/{licenca}
//    because the broker ACL is "readwrite kasa/%u/#" (%u = licenca). ────────────
const _tStatus = 'kasa/$_licenca/status/$_uredaj'; // device → server (retained)
const _tPoruka = 'kasa/$_licenca/poruka'; // server → device (subscribe)
const _tAck = 'kasa/$_licenca/ack'; // device → server
const _tDojava = 'kasa/$_licenca/dojava'; // device → server (visible in admin)

/// A long-lived MQTT test connection speaking the real Pelion "semafor"
/// protocol. First tap connects and KEEPS the socket open (auto-reconnect),
/// subscribes to `kasa/{licenca}/poruka`, publishes a retained "online" status
/// and a "dojava" (visible in PelionAdmin), and acks any inbound message.
/// Everything is logged to the console.
class MqttTestService {
  MqttTestService._();
  static final MqttTestService instance = MqttTestService._();

  MqttServerClient? _client;

  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<String> connectAndSend() async {
    if (isConnected) {
      _publishDojava('Ponovni test iz mobilne aplikacije');
      return 'MQTT: već spojeno — nova dojava poslana (prati CMD / PelionAdmin).';
    }

    // Unique test client id so we don't kick the real device off the broker.
    final suffix =
        DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
    final clientId = '$_uredaj-TEST-$suffix';

    final client = MqttServerClient.withPort(_broker, clientId, _port)
      ..secure = _tls
      ..keepAlivePeriod = _keepAlive
      ..connectTimeoutPeriod = 8000
      ..autoReconnect = true
      ..resubscribeOnAutoReconnect = true
      ..logging(on: true)
      ..setProtocolV311()
      // TEST ONLY: the broker cert is signed by a private CA ("Pelion Orderman
      // CA"). Accept it here instead of bundling the truststore.
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

    // Inbound messages (kasa/{licenca}/poruka) → log + ack.
    client.updates?.listen((events) {
      for (final e in events) {
        final m = e.payload as MqttPublishMessage;
        final payload =
            MqttPublishPayload.bytesToStringAsString(m.payload.message);
        debugPrint('MQTT ◂ ${e.topic}: $payload');
        if (e.topic == _tPoruka) _ack(payload);
      }
    });
    client.published?.listen((m) {
      debugPrint('MQTT ▸ published ACK id=${m.variableHeader?.messageIdentifier}'
          ' topic=${m.variableHeader?.topicName}');
    });

    try {
      debugPrint('MQTT ▸ connecting to ssl://$_broker:$_port as $clientId '
          '(user=$_licenca)…');
      await client.connect(_licenca, _lozinka);

      if (!isConnected) {
        final rc = client.connectionStatus?.returnCode;
        debugPrint('MQTT ✗ not connected: $rc');
        _client = null;
        return 'MQTT: nije spojeno (${rc ?? 'nepoznato'}).';
      }

      // Receive centrala messages, announce online, and send a visible dojava.
      client.subscribe(_tPoruka, MqttQos.atLeastOnce);
      _publishStatus('online');
      _publishDojava('Test veze iz mobilne aplikacije');

      return 'MQTT: spojeno; status "online" + dojava poslani '
          '(prati CMD / PelionAdmin).';
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

  void disconnect() {
    debugPrint('MQTT ▸ manual disconnect');
    _publishStatus('offline');
    _client?.disconnect();
    _client = null;
  }

  // ── JSON payloads (mirrors the Java service) ──────────────────────────────
  static String _statusJson(String status) =>
      '{"status":"$status","naziv":"$_naziv","tip":"MOBILE","uloga":"kasa",'
      '"verzija":"1.0.0","uredaj":"$_uredaj","ts":${_now()}}';

  static String _dojavaJson(String tekst) =>
      '{"tekst":"$tekst","naziv":"$_naziv","uredaj":"$_uredaj","ts":${_now()}}';

  static String _ackJson(String msgId) =>
      '{"msg_id":"$msgId","uredaj":"$_uredaj","ts":${_now()}}';

  static int _now() => DateTime.now().millisecondsSinceEpoch;
}
