import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Asks the OS to let the app keep running for a short while after it has
/// been put away.
///
/// Only iOS needs this, and only for seconds: a backgrounded app there is
/// suspended after about five, which is less than the kasa takes to answer an
/// order (one to five seconds, measured). `beginBackgroundTask` buys roughly
/// thirty — long enough to take the confirmation and close the connection
/// cleanly instead of leaving the answer stranded on the broker.
///
/// Android keeps a backgrounded app running on its own for long enough, so
/// everything here is a no-op there. See `ios/Runner/AppDelegate.swift`.
class BackgroundTime {
  const BackgroundTime._();

  static const _channel = MethodChannel('hr.pelion.order/background_time');

  /// Takes the assertion. Safe to call repeatedly — the native side keeps one.
  static Future<void> begin() => _call('begin');

  /// Releases it. ALWAYS call this when the work is done: an assertion left
  /// open is what makes iOS kill an app outright.
  static Future<void> end() => _call('end');

  static Future<void> _call(String method) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>(method);
    } catch (e) {
      // Nothing here is worth failing over: without the extra seconds the
      // connection simply closes earlier, which is today's behaviour.
      debugPrint('Background time ▸ $method nije uspio: $e');
    }
  }
}
