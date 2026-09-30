import 'dart:async';
import 'dart:io' show HttpException, Platform, SocketException;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../../../firebase_options.dart';

/// Crash reporting through Firebase Crashlytics (project `pelion-order`).
///
/// Called once from `main()`, inside the guarded zone, before anything that
/// can fail — so an error during startup is reported too.
///
/// Two rules shape everything here:
///
///  * **A broken reporter must never break the app.** If Firebase can't
///    start (no config on a platform, a Google outage, a sideloaded build),
///    the app runs on exactly as before, just without reports. Nothing in
///    this class is allowed to throw into the startup path.
///  * **A dropped connection is not a crash.** On a restaurant floor the
///    Wi-Fi cuts out, the broker goes away and sockets time out constantly.
///    Those are recorded as *non-fatal* so they stay visible in the Issues
///    list without destroying the crash-free-users figure — otherwise the
///    dashboard would report a broken app every busy evening.
class CrashReporting {
  const CrashReporting._();

  static bool _ready = false;

  /// Whether reports actually reach Crashlytics. False until [init] has
  /// succeeded, and after a failed Firebase start.
  static bool get isReady => _ready;

  /// Brings Firebase up and installs the two global error handlers.
  static Future<void> init() async {
    try {
      // iOS needs the credentials handed over in Dart, see
      // DefaultFirebaseOptions; Android reads google-services.json, which
      // Gradle has baked into the app's resources.
      if (Platform.isIOS) {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.ios);
      } else {
        await Firebase.initializeApp();
      }
      _ready = true;
    } catch (e) {
      debugPrint('Crashlytics ▸ Firebase se nije pokrenuo: $e');
      return;
    }

    try {
      // Nothing is sent from debug builds: an exception hit while developing
      // is not a crash in the field, and it would pollute both the issue
      // list and the crash-free rate. The setting is stored natively, so a
      // release build installed over a debug one turns reporting back on.
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        !kDebugMode,
      );

      // Errors from the Flutter framework itself (a failed build, a layout
      // assertion …).
      FlutterError.onError = (details) {
        // Keep Flutter's own behaviour: the red error box in debug and the
        // console dump everywhere. Overriding onError without this would
        // silently swallow errors during development.
        FlutterError.presentError(details);
        if (isNetworkError(details.exception)) {
          FirebaseCrashlytics.instance.recordFlutterError(details);
          return;
        }
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      };

      // Async errors that never pass through the framework — e.g. an
      // unawaited Future that throws. Returning true marks them handled so
      // the app keeps running.
      PlatformDispatcher.instance.onError = (error, stack) {
        record(error, stack);
        return true;
      };
    } catch (e) {
      debugPrint('Crashlytics ▸ postavljanje nije uspjelo: $e');
    }
  }

  /// Attaches the venue this device is provisioned for to every later report,
  /// so a crash arrives as "phone 3 at this venue" instead of anonymously.
  /// They show up on the "Keys" tab of a report in the Firebase console.
  ///
  /// Business identifiers only. The signed-in waiter's name and code are
  /// deliberately never attached — they are the one genuinely personal field
  /// in the app, and the privacy policy promises crash reports carry neither.
  static void setVenueContext({
    required String licenca,
    required String uredaj,
    required String naziv,
  }) {
    _setKey('licenca', licenca);
    _setKey('uredaj', uredaj);
    _setKey('naziv', naziv);
  }

  /// Before the first scan, and after the venue data is wiped. Crashlytics
  /// has no "delete key" call, so the keys are overwritten rather than
  /// removed — otherwise a report from a wiped device would still carry the
  /// previous venue's name.
  static void clearVenueContext() =>
      setVenueContext(licenca: '—', uredaj: '—', naziv: 'nije skenirano');

  /// Whether the broker connection was up when the report was made. Most of
  /// what can go wrong in this app is connection-shaped, so this is usually
  /// the first thing worth knowing about a crash.
  static void setConnected(bool connected) =>
      _setKey('mqtt', connected ? 'spojen' : 'nije spojen');

  static void _setKey(String key, String value) {
    if (!_ready) return;
    unawaited(FirebaseCrashlytics.instance.setCustomKey(key, value));
  }

  /// Records one error, fatal unless it looks like a network problem.
  /// Safe to call at any time: with Crashlytics unavailable it just prints.
  static void record(Object error, StackTrace stack, {String? reason}) {
    if (!_ready) {
      debugPrint('Greška (Crashlytics nedostupan): $error\n$stack');
      return;
    }
    unawaited(
      FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        reason: reason,
        fatal: !isNetworkError(error),
      ),
    );
  }

  /// True when [error] is a transient connectivity problem rather than a
  /// bug. Matched by type where possible, and otherwise by text — several
  /// packages (`http`, the platform channels) wrap the real cause in a way
  /// that hides its type.
  static bool isNetworkError(Object error) {
    if (error is SocketException) return true;
    if (error is HttpException) return true;
    if (error is TimeoutException) return true;
    final msg = error.toString().toLowerCase();
    return msg.contains('socketexception') ||
        msg.contains('httpexception') ||
        msg.contains('timeoutexception') ||
        msg.contains('handshakeexception') ||
        // package:http wraps every transport failure as ClientException.
        msg.contains('clientexception') ||
        // mqtt_client: NoConnectionException / ConnectionException — the
        // broker being unreachable is the normal state half the shift.
        msg.contains('connectionexception') ||
        msg.contains('connection timed out') ||
        msg.contains('connection refused') ||
        msg.contains('connection closed') ||
        msg.contains('connection reset') ||
        msg.contains('failed host lookup') ||
        msg.contains('network is unreachable') ||
        msg.contains('software caused connection abort') ||
        // iOS (CFNetwork/NSURLError) phrasings the substrings above miss.
        msg.contains('request timed out') ||
        msg.contains('network connection was lost') ||
        msg.contains('connection appears to be offline') ||
        msg.contains('could not connect to the server') ||
        msg.contains('cannot connect to host');
  }
}
