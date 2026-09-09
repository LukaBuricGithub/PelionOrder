import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../master_data/models/user.dart';
import '../../mqtt/models/mqtt_user.dart';
import '../../mqtt/state/mqtt_users_provider.dart';
import '../../settings/state/settings_provider.dart';
import 'session_provider.dart';

/// Orchestrates sign-in / sign-out and startup session restore. A plain class
/// holding [Ref] that mutates the session providers.
///
/// Login is by personal PIN, validated against the **MQTT** staff list
/// (`podaci/korisnici`, see [mqttUsersProvider]) — which is persisted locally,
/// so login works on a cold start once the list has been received at least
/// once. The matched [MqttUser] is mapped onto the app's [User] model so the
/// rest of the app (hub, table ownership, orders) is unchanged.
class AuthController {
  AuthController(this._ref);

  final Ref _ref;

  /// Maps an MQTT user onto the app's [User].
  ///
  /// `allTablesOpenRight` comes from the payload's `prava` (right `008`): with
  /// it a waiter may open tables held by colleagues, without it only their own.
  /// The remaining rights are still granted unconditionally — no code has been
  /// defined for them yet.
  User _toUser(MqttUser u) => User(
        code: u.code,
        username: u.displayName,
        pin: u.pinValue ?? 0,
        changeQuantityRight: true,
        allTablesOpenRight: u.canOpenAllTables,
        deleteRight: true,
        superuser: u.isAdmin,
      );

  /// Restores the persisted session at startup: looks up the saved user code in
  /// the MQTT staff list and sets [currentUserProvider]. Always clears the
  /// bootstrapping flag when done so the router can leave the splash screen.
  Future<void> bootstrap() async {
    try {
      final code = _ref.read(settingsStorageProvider).loadCurrentUserCode();
      if (code != null && code.isNotEmpty) {
        final target = code.trim();
        for (final u in _ref.read(mqttUsersProvider)) {
          if (u.code == target) {
            _ref.read(currentUserProvider.notifier).state = _toUser(u);
            break;
          }
        }
      }
    } catch (_) {
      // A corrupt cache shouldn't wedge startup — fall through to logged-out.
    } finally {
      _ref.read(isBootstrappingProvider.notifier).state = false;
    }
  }

  /// Validates [pin] against the MQTT staff list. On a match, persists the user
  /// code and sets the session; returns the matched [User] (or null on miss).
  Future<User?> loginWithPin(int pin) async {
    MqttUser? match;
    for (final u in _ref.read(mqttUsersProvider)) {
      if (u.pinValue != null && u.pinValue == pin) {
        match = u;
        break;
      }
    }
    if (match == null) return null;
    final user = _toUser(match);
    await _ref.read(settingsStorageProvider).saveCurrentUserCode(user.code);
    _ref.read(currentUserProvider.notifier).state = user;
    return user;
  }

  /// Signs the current waiter out.
  Future<void> logout() async {
    await _ref.read(settingsStorageProvider).saveCurrentUserCode(null);
    _ref.read(currentUserProvider.notifier).state = null;
  }
}

final authControllerProvider = Provider<AuthController>((ref) {
  return AuthController(ref);
});
