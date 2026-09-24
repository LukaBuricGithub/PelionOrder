import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// The channel MainActivity answers on (Android only).
const _channel = MethodChannel('hr.pelion.order/app_settings');

/// Opens this app's own page in the phone's settings, where camera access can
/// be granted after it was refused — iOS asks only once, and Android stops
/// asking after "Ne pitaj ponovno", so this is the only way back.
///
/// Two ways, because no single package does both without breaking a build:
/// iOS opens the `app-settings:` URL (url_launcher), Android goes through a
/// method channel to MainActivity, which opens the app's details screen.
///
/// Returns false if the settings couldn't be opened; the caller leaves its
/// message on screen then.
Future<bool> openAppSettings() async {
  try {
    if (Platform.isIOS) {
      return await launchUrl(Uri.parse('app-settings:'));
    }
    final opened = await _channel.invokeMethod<bool>('openAppSettings');
    return opened ?? false;
  } catch (e) {
    debugPrint('▸ opening the app settings failed: $e');
    return false;
  }
}
