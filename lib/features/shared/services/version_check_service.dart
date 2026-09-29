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

  /// Cached for the life of the process, so a resume or a hot reload doesn't
  /// query the store again. Not persisted.
  static VersionCheckResult? _cached;

  Future<VersionCheckResult> check() async {
    if (_cached != null) return _cached!;

    try {
      final info = await PackageInfo.fromPlatform();
      final installed = info.version.trim();

      if (Platform.isAndroid) return _cached = await _checkAndroid(installed);
      if (Platform.isIOS) {
        return _cached = await _checkIos(installed, info.packageName);
      }
      return _cached = VersionCheckResult.notApplicable(installed);
    } catch (e) {
      // A failed check must never stand between a waiter and a working app:
      // no network, a store outage, or a build installed outside the store
      // (Play's API throws then) all end up here and mean "no update".
      debugPrint('Verzija ▸ provjera nije uspjela: $e');
      return _cached = const VersionCheckResult(
        installedVersion: '',
        latestVersion: null,
        updateAvailable: false,
        storeUrl: null,
      );
    }
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
    return VersionCheckResult(
      installedVersion: installed,
      latestVersion: null,
      updateAvailable: available,
      storeUrl: available ? _playUrl : null,
    );
  }

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
      return VersionCheckResult.notApplicable(installed);
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final results = (body['results'] as List?) ?? const [];
    if (results.isEmpty) return VersionCheckResult.notApplicable(installed);

    final entry = results.first as Map<String, dynamic>;
    final latest = (entry['version'] as String?)?.trim() ?? '';
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
