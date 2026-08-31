import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../master_data/models/user.dart';
import '../../master_data/state/master_data_providers.dart';
import '../../settings/state/settings_provider.dart';
import 'session_provider.dart';

/// Orchestrates sign-in / sign-out and startup session restore. Modelled on
/// ikasa's `AuthController`: a plain class holding [Ref] that mutates the
/// session providers.
///
/// Login is by personal PIN, validated against the cached users — so it works
/// fully offline once master data has been downloaded at least once.
class AuthController {
  AuthController(this._ref);

  final Ref _ref;

  /// Restores the persisted session at startup: looks up the saved user code in
  /// the cached users and sets [currentUserProvider]. Always clears the
  /// bootstrapping flag when done so the router can leave the splash screen.
  Future<void> bootstrap() async {
    try {
      final code = _ref.read(settingsStorageProvider).loadCurrentUserCode();
      if (code != null && code.isNotEmpty) {
        final user =
            await _ref.read(masterDataRepositoryProvider).userByCode(code);
        _ref.read(currentUserProvider.notifier).state = user;
      }
    } catch (_) {
      // A corrupt cache shouldn't wedge startup — fall through to logged-out.
    } finally {
      _ref.read(isBootstrappingProvider.notifier).state = false;
    }
  }

  /// Validates [pin] against the cached users. On a match, persists the user
  /// code and sets the session; returns the matched [User] (or null on miss).
  Future<User?> loginWithPin(int pin) async {
    final user =
        await _ref.read(masterDataRepositoryProvider).findUserByPin(pin);
    if (user != null) {
      await _ref.read(settingsStorageProvider).saveCurrentUserCode(user.code);
      _ref.read(currentUserProvider.notifier).state = user;
    }
    return user;
  }

  /// Signs the current waiter out (does not touch cached master data).
  Future<void> logout() async {
    await _ref.read(settingsStorageProvider).saveCurrentUserCode(null);
    _ref.read(currentUserProvider.notifier).state = null;
  }
}

final authControllerProvider = Provider<AuthController>((ref) {
  return AuthController(ref);
});
