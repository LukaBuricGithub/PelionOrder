import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/state/shared_preferences_provider.dart';
import '../data/printer_service.dart';

const _kPrinterKey = 'printer_bluetooth_v1';

/// The printer this phone prints to, kept across restarts.
///
/// The phone's own choice, not the venue's: two waiters in one venue can carry
/// different printers, so this is deliberately NOT wiped with the venue data
/// when a new QR code is scanned.
class PrinterNotifier extends StateNotifier<PrinterDevice?> {
  PrinterNotifier(this._prefs) : super(null) {
    final saved = _prefs.getString(_kPrinterKey);
    if (saved == null || saved.isEmpty) return;
    try {
      final map = jsonDecode(saved) as Map<String, dynamic>;
      state = PrinterDevice(
        name: (map['name'] ?? '').toString(),
        mac: (map['mac'] ?? '').toString(),
      );
    } catch (e) {
      debugPrint('Pisač ▸ stored printer unreadable: $e');
    }
  }

  final SharedPreferences _prefs;

  Future<void> select(PrinterDevice device) async {
    await _prefs.setString(
      _kPrinterKey,
      jsonEncode({'name': device.name, 'mac': device.mac}),
    );
    state = device;
  }

  Future<void> forget() async {
    await _prefs.remove(_kPrinterKey);
    state = null;
  }
}

final printerProvider = StateNotifierProvider<PrinterNotifier, PrinterDevice?>(
  (ref) => PrinterNotifier(ref.watch(sharedPreferencesProvider)),
);
