import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// One-shot "is this build older than what the store has" check, run once at
/// launch. What to do about it is the UI's decision (see
/// `UpdateRequiredGate`). Ported from the ikasa app, which has run this for a
/// while.
class VersionCheckService {
  const VersionCheckService();

  /// Croatian storefront — the app is published for Croatia. The lookup falls
  /// back to the country-less (US) endpoint if this ever needs to change, so
  /// it keeps working until the constant is updated.
  static const _iosCountry = 'hr';

  /// The app's Play listing (Android gives us no version name to show, see
  /// [_checkAndroid]).
  static const _playUrl =
      'https://play.google.com/store/apps/details?id=hr.pelion.order';

  /// VERSION_DIAG — only used by [debugForceUpdate] on iOS, where a real
  /// check supplies `trackViewUrl` instead.
  static const _appStoreUrl = 'https://apps.apple.com/hr/app/pelion-order/';

  /// The last answer, and when it was taken. Not persisted.
  ///
  /// A real answer is trusted for [_trustAnswer]; a failed one is retried much
  /// sooner. The old code cached failures for the life of the process, so a
  /// check that ran on the first frame — before wifi had associated — silenced
  /// the feature until the app was killed and reopened.
  static VersionCheckResult? _cached;
  static DateTime? _cachedAt;
  static bool _cachedFailed = false;

  static const _trustAnswer = Duration(minutes: 30);
  static const _retryAfterFailure = Duration(minutes: 2);

  /// VERSION_DIAG — what the last check actually did, in words, for the
  /// "Provjera verzije" card in Postavke uređaja. Without it a failed check
  /// and "you are up to date" look exactly the same: nothing happens.
  static final ValueNotifier<String> lastOutcome = ValueNotifier<String>(
    'još nije provjereno',
  );

  /// VERSION_DIAG — bumped to ask [UpdateRequiredGate] to check again right
  /// now (the diagnostics card uses it after flipping [debugForceUpdate]).
  static final ValueNotifier<int> checkRequested = ValueNotifier<int>(0);

  /// VERSION_DIAG — pretends the store has a newer build, so the overlay can
  /// be seen and tried without publishing anything. Never true in a shipped
  /// build: only the diagnostics card sets it.
  static bool debugForceUpdate = false;

  Future<VersionCheckResult> check({bool force = false}) async {
    final cached = _cached;
    final at = _cachedAt;
    if (!force && cached != null && at != null) {
      final good = _cachedFailed ? _retryAfterFailure : _trustAnswer;
      if (DateTime.now().difference(at) < good) return cached;
    }

    try {
      final info = await PackageInfo.fromPlatform();
      final installed = info.version.trim();

      // VERSION_DIAG
      if (debugForceUpdate) {
        lastOutcome.value = '$installed · prisilno uključeno (test)';
        return _remember(
          VersionCheckResult(
            installedVersion: installed,
            latestVersion: null,
            updateAvailable: true,
            storeUrl: Platform.isIOS ? _appStoreUrl : _playUrl,
          ),
          failed: false,
        );
      }

      if (Platform.isAndroid) {
        return _remember(await _checkAndroid(installed), failed: false);
      }
      if (Platform.isIOS) {
        return _remember(
          await _checkIos(installed, info.packageName),
          failed: false,
        );
      }
      lastOutcome.value = '$installed · ova platforma se ne provjerava';
      return _remember(
        VersionCheckResult.notApplicable(installed),
        failed: false,
      );
    } catch (e) {
      // A failed check must never stand between a waiter and a working app:
      // no network, a store outage, or a build installed outside the store
      // (Play's API throws then) all end up here and mean "no update". It is
      // remembered as a FAILURE, so the next resume tries again.
      debugPrint('Verzija ▸ provjera nije uspjela: $e');
      lastOutcome.value = 'provjera nije uspjela · $e';
      return _remember(
        const VersionCheckResult(
          installedVersion: '',
          latestVersion: null,
          updateAvailable: false,
          storeUrl: null,
        ),
        failed: true,
      );
    }
  }

  VersionCheckResult _remember(VersionCheckResult r, {required bool failed}) {
    _cached = r;
    _cachedAt = DateTime.now();
    _cachedFailed = failed;
    return r;
  }

  /// Play knows whether a newer build exists, but exposes only its version
  /// CODE, not the version name — so there is no number to show and
  /// [VersionCheckResult.latestVersion] stays null on purpose. The dialog
  /// then leaves that line out instead of printing a phrase where a version
  /// belongs ("Nova verzija: novija verzija", which reads like a fault).
  Future<VersionCheckResult> _checkAndroid(String installed) async {
    final info = await InAppUpdate.checkForUpdate();
    final available =
        info.updateAvailability == UpdateAvailability.updateAvailable;
    // VERSION_DIAG — Play answering at all is the thing worth knowing: it
    // only answers for a build IT installed, on a track this account is in.
    lastOutcome.value =
        '$installed · Play: '
        '${available ? 'dostupna novija verzija' : _playSays(info)}';
    return VersionCheckResult(
      installedVersion: installed,
      latestVersion: null,
      updateAvailable: available,
      storeUrl: available ? _playUrl : null,
    );
  }

  /// VERSION_DIAG — Play's non-"update available" answers, said plainly.
  static String _playSays(AppUpdateInfo info) =>
      switch (info.updateAvailability) {
        UpdateAvailability.updateNotAvailable => 'nema novije verzije',
        UpdateAvailability.developerTriggeredUpdateInProgress =>
          'ažuriranje je već u tijeku',
        UpdateAvailability.unknown => 'nepoznato (Play nije odgovorio)',
        _ => 'nepoznat odgovor',
      };

  /// iOS has no equivalent API, so this asks Apple's public lookup endpoint
  /// what version is live and compares it with the installed one.
  Future<VersionCheckResult> _checkIos(
    String installed,
    String bundleId,
  ) async {
    final uri = Uri.parse(
      'https://itunes.apple.com/$_iosCountry/lookup?bundleId=$bundleId',
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) {
      // VERSION_DIAG
      lastOutcome.value = '$installed · App Store: HTTP ${response.statusCode}';
      return VersionCheckResult.notApplicable(installed);
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final results = (body['results'] as List?) ?? const [];
    if (results.isEmpty) {
      // VERSION_DIAG — the single most useful line on iOS: the lookup only
      // knows PUBLISHED App Store releases, so a TestFlight-only app can
      // never be found and the overlay can never appear.
      lastOutcome.value =
          '$installed · App Store: aplikacija nije pronađena '
          '(nije javno objavljena — TestFlight se ne vidi)';
      return VersionCheckResult.notApplicable(installed);
    }

    final entry = results.first as Map<String, dynamic>;
    final latest = (entry['version'] as String?)?.trim() ?? '';
    // VERSION_DIAG
    lastOutcome.value =
        '$installed · App Store: ${latest.isEmpty ? 'bez verzije' : latest}'
        '${latest.isNotEmpty && _isNewer(latest, installed) ? ' — dostupna novija' : ''}';
    return VersionCheckResult(
      installedVersion: installed,
      latestVersion: latest.isEmpty ? null : latest,
      updateAvailable: latest.isNotEmpty && _isNewer(latest, installed),
      storeUrl: entry['trackViewUrl'] as String?,
    );
  }

  /// True when [latest] is a higher version than [installed], comparing the
  /// dotted numbers. A segment that isn't a number is compared as text, so an
  /// unusual version string can't crash the check.
  static bool _isNewer(String latest, String installed) {
    final a = latest.split('.');
    final b = installed.split('.');
    final count = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < count; i++) {
      final ai = i < a.length ? int.tryParse(a[i]) : 0;
      final bi = i < b.length ? int.tryParse(b[i]) : 0;
      if (ai != null && bi != null) {
        if (ai > bi) return true;
        if (ai < bi) return false;
      } else {
        final as = i < a.length ? a[i] : '';
        final bs = i < b.length ? b[i] : '';
        final cmp = as.compareTo(bs);
        if (cmp > 0) return true;
        if (cmp < 0) return false;
      }
    }
    return false;
  }
}

@immutable
class VersionCheckResult {
  const VersionCheckResult({
    required this.installedVersion,
    required this.latestVersion,
    required this.updateAvailable,
    required this.storeUrl,
  });

  factory VersionCheckResult.notApplicable(String installed) =>
      VersionCheckResult(
        installedVersion: installed,
        latestVersion: null,
        updateAvailable: false,
        storeUrl: null,
      );

  final String installedVersion;
  final String? latestVersion;
  final bool updateAvailable;
  final String? storeUrl;
}
