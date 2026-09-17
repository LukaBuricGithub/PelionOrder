import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mqtt_service.dart';
import '../models/mqtt_device_status.dart';
import 'mqtt_config_provider.dart';

/// Whether this orderman may send an order right now — and if not, what the
/// waiter is told (spec v4.0, §11.4).
enum MqttSendGate {
  skenirajKod('Skeniraj kod u glavnom programu'),
  ordermanNijeSpojen('Pelion Order nije spojen'),
  otkljucano(''),
  kasaNijeUProdaji('Glavni program nije u blagajni'),
  kasaNijeSpojena('Glavni program nije spojen');

  const MqttSendGate(this.message);

  /// What the waiter is told while sending is locked (empty when open).
  final String message;

  bool get isOpen => this == MqttSendGate.otkljucano;

  /// Whether a kasa is online and this phone connected, so a table can be
  /// asked for what is on it — also while the kasa is out of the sales screen.
  bool get canReachKasa =>
      this == MqttSendGate.otkljucano || this == MqttSendGate.kasaNijeUProdaji;
}

/// §11.4, checked top-down — the first condition that holds decides, so the
/// waiter always sees the root cause: without its own connection the phone
/// knows nothing about the kasa, so it must not claim anything about it.
///
/// The phone never picks a kasa: sending is open as soon as ANY device is
/// online and takes orders (only a production kasa in its sales screen does).
MqttSendGate computeSendGate({
  required bool hasCode,
  required bool connected,
  required bool statusesReady,
  required Iterable<MqttDeviceStatus> devices,
}) {
  if (!hasCode) return MqttSendGate.skenirajKod;
  // Until the broker has confirmed the status subscription on this connection,
  // the device table may still be missing statuses — nothing about it counts.
  if (!connected || !statusesReady) return MqttSendGate.ordermanNijeSpojen;
  if (devices.any((d) => d.isOnline && d.prima)) return MqttSendGate.otkljucano;
  if (devices.any((d) => d.isOnline && d.isKasa)) {
    return MqttSendGate.kasaNijeUProdaji;
  }
  return MqttSendGate.kasaNijeSpojena;
}

/// The current send state, recalculated whenever the connection, the status
/// subscription or any device's status changes, and when the device is
/// provisioned or loses its code.
final mqttSendGateProvider = Provider<MqttSendGate>((ref) {
  final svc = MqttService.instance;
  void changed() => ref.invalidateSelf();
  svc.connected.addListener(changed);
  svc.statusesReady.addListener(changed);
  svc.devices.addListener(changed);
  ref.onDispose(() {
    svc.connected.removeListener(changed);
    svc.statusesReady.removeListener(changed);
    svc.devices.removeListener(changed);
  });
  return computeSendGate(
    hasCode: ref.watch(mqttConfigProvider) != null,
    connected: svc.connected.value,
    statusesReady: svc.statusesReady.value,
    devices: svc.devices.value.values,
  );
});
