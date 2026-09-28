import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'escpos.dart';

/// MainActivity answers here (the same channel that opens the app settings).
const _channel = MethodChannel('hr.pelion.order/app_settings');

enum _Permission { granted, denied, blocked }

/// Asks for BLUETOOTH_CONNECT and waits for the waiter's answer.
Future<_Permission> _requestBluetoothPermission() async {
  try {
    final answer = await _channel.invokeMethod<String>('requestBluetooth');
    return switch (answer) {
      'granted' => _Permission.granted,
      'permanentlyDenied' => _Permission.blocked,
      _ => _Permission.denied,
    };
  } catch (e) {
    debugPrint('Pisač ▸ Bluetooth permission request failed: $e');
    return _Permission.denied;
  }
}

/// Why a print didn't happen — each one has its own message in the UI.
enum PrinterFault {
  /// Bluetooth printing isn't available on this platform (see [Printers.kind]).
  unsupported,

  /// The waiter refused the Bluetooth permission this time.
  noPermission,

  /// Refused for good ("Ne pitaj ponovno"): only the app's page in the phone's
  /// settings can grant it now.
  permissionBlocked,

  /// Bluetooth is switched off on the phone.
  bluetoothOff,

  /// The printer didn't answer: out of range, switched off, or paired with
  /// another phone.
  notReachable,

  /// Connected, but the bytes didn't go through.
  writeFailed,
}

/// How this phone can talk to a printer.
enum PrinterKind {
  /// Bluetooth Classic (SPP) — what the venues' NaviaTEC 58 mm printers use.
  classic,

  /// No printing: iOS can't open a Classic connection (Apple allows it only
  /// for MFi-certified accessories through the vendor's own SDK), and the
  /// current printers are Classic-only. A BLE printer would work here, and
  /// that is where BLE support goes when it is needed.
  none,
}

/// One printer the phone knows about.
class PrinterDevice {
  const PrinterDevice({required this.name, required this.mac});

  final String name;
  final String mac;
}

/// The phone's side of Bluetooth printing.
///
/// Everything platform-specific is behind [kind], so the settings screen shows
/// what this phone can actually do instead of deciding it itself.
class Printers {
  const Printers._();

  static PrinterKind get kind =>
      Platform.isAndroid ? PrinterKind.classic : PrinterKind.none;

  static bool get isSupported => kind != PrinterKind.none;

  /// Bluetooth permission (Android 12+ asks for it) and the radio itself.
  /// Returns null when everything is ready, or what is missing.
  ///
  /// The permission is asked for through MainActivity, not through the printer
  /// plugin: the plugin only reports the current state, so the first attempt
  /// always came back "not granted" while Android's dialog was still open.
  static Future<PrinterFault?> ensureReady() async {
    if (!isSupported) return PrinterFault.unsupported;
    final granted = await _requestBluetoothPermission();
    if (granted != _Permission.granted) {
      return granted == _Permission.blocked
          ? PrinterFault.permissionBlocked
          : PrinterFault.noPermission;
    }
    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      return PrinterFault.bluetoothOff;
    }
    return null;
  }

  /// The printers paired with this phone in the Android Bluetooth settings.
  /// Pairing happens there, not here: it needs the PIN and is a one-time job.
  static Future<List<PrinterDevice>> paired() async {
    if (!isSupported) return const [];
    final found = await PrintBluetoothThermal.pairedBluetooths;
    return [
      for (final b in found) PrinterDevice(name: b.name, mac: b.macAdress),
    ];
  }

  /// Opens the connection, with one retry.
  ///
  /// A Classic socket often fails on the first try: the printer may still be
  /// holding a socket from an earlier attempt, or be asleep and need the first
  /// connect to wake it. Dropping whatever is there and asking again is what
  /// usually gets through.
  static Future<bool> _connectWithRetry(String mac) async {
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final ok = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
        debugPrint('Pisač ▸ connect to $mac (attempt $attempt): $ok');
        if (ok) return true;
      } catch (e) {
        debugPrint('Pisač ▸ connect to $mac (attempt $attempt) threw: $e');
      }
      try {
        await PrintBluetoothThermal.disconnect;
      } catch (_) {
        // Nothing open — fine.
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    return false;
  }

  /// Sends the test print to [mac].
  ///
  /// Connects, prints, and disconnects again: holding a Classic connection
  /// open would keep the printer bound to this phone, and a waiter's phone is
  /// not the only device in the venue that prints.
  static Future<PrinterFault?> printTest({
    required String mac,
    required String venue,
    required String device,
  }) async {
    final notReady = await ensureReady();
    if (notReady != null) return notReady;

    try {
      var connected = await PrintBluetoothThermal.connectionStatus;
      debugPrint('Pisač ▸ already connected: $connected');
      if (!connected) connected = await _connectWithRetry(mac);
      if (!connected) return PrinterFault.notReachable;
      final sent = await PrintBluetoothThermal.writeBytes(
        testPrint(venue: venue, device: device, now: DateTime.now()),
      );
      return sent ? null : PrinterFault.writeFailed;
    } catch (e) {
      debugPrint('Pisač ▸ test print failed: $e');
      return PrinterFault.notReachable;
    } finally {
      try {
        await PrintBluetoothThermal.disconnect;
      } catch (_) {
        // Already gone — nothing to release.
      }
    }
  }
}
