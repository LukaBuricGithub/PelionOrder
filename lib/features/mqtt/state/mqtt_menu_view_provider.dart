import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/state/session_provider.dart';
import '../../shared/state/shared_preferences_provider.dart';
import '../data/mqtt_service.dart';
import '../models/mqtt_menu.dart';
import 'mqtt_menu_provider.dart';

/// Prefix of the per-waiter price-list cache. One pair of keys per `cuser`, so
/// two waiters sharing a phone each keep their own.
const _kUserMenuPrefix = 'mqtt_artikli_user_';

String _userRawKey(String cuser) => '$_kUserMenuPrefix${cuser}_raw_v1';
String _userVerKey(String cuser) => '$_kUserMenuPrefix${cuser}_ver_v1';

/// Removes every cached per-waiter price list — used when the phone moves to
/// another venue, where none of them mean anything any more. The keys carry a
/// waiter's code, so they can't be listed up front like the other caches.
Future<void> clearUserMenuStorage(SharedPreferences prefs) async {
  for (final key in prefs.getKeys().toList()) {
    if (key.startsWith(_kUserMenuPrefix)) await prefs.remove(key);
  }
}

/// The price list actually in force, and whether it is still being fetched.
@immutable
class MqttMenuView {
  const MqttMenuView({
    required this.menu,
    required this.loading,
    required this.personal,
  });

  static const empty = MqttMenuView(
    menu: MqttMenu.empty,
    loading: false,
    personal: false,
  );

  final MqttMenu menu;

  /// The signed-in waiter has their own price list and it hasn't arrived yet.
  /// The order screen holds a loader rather than showing the shared one, which
  /// would otherwise be replaced under the waiter's fingers a moment later.
  final bool loading;

  /// True when [menu] is this waiter's own rather than the venue's shared one.
  final bool personal;

  MqttMenuView copyWith({MqttMenu? menu, bool? loading, bool? personal}) =>
      MqttMenuView(
        menu: menu ?? this.menu,
        loading: loading ?? this.loading,
        personal: personal ?? this.personal,
      );
}

/// Chooses between the venue's shared price list and the one arranged for the
/// signed-in waiter (`podaci/artikli/{cuser}`), and keeps the choice current.
///
/// The decision is always made from `artikli_korisnika` in `podaci/verzija`,
/// never from the presence of a retained message: a deleted layout can leave
/// one behind on the broker, and a waiter must not be shown a price list the
/// venue has withdrawn.
class MqttMenuViewNotifier extends StateNotifier<MqttMenuView> {
  MqttMenuViewNotifier(this._prefs) : super(MqttMenuView.empty) {
    MqttService.instance.userArtikliRawJson.addListener(_onUserPayload);
    MqttService.instance.verzijaRawJson.addListener(_reevaluate);
  }

  /// How long a waiter waits for their own price list before the shared one is
  /// shown instead. The retained message normally arrives in well under a
  /// second; this is only for the case where it never comes at all — a kasa
  /// that lists the waiter but whose message is missing. Standing in front of
  /// a guest with an empty price list is the one outcome worth avoiding.
  static const fallbackAfter = Duration(seconds: 6);

  final SharedPreferences _prefs;

  MqttMenu _shared = MqttMenu.empty;
  MqttMenu? _personal;
  String? _cuser;
  Timer? _timeout;

  /// The venue's shared price list, from [mqttMenuProvider].
  void setSharedMenu(MqttMenu menu) {
    _shared = menu;
    _reevaluate();
  }

  /// The signed-in waiter's code, or null when nobody is signed in.
  void setUser(String? cuser) {
    final next = (cuser != null && cuser.trim().isNotEmpty)
        ? cuser.trim()
        : null;
    if (next == _cuser) return;
    _cuser = next;
    // Another waiter's layout is never carried over, not even for a frame.
    _personal = null;
    _timeout?.cancel();
    _reevaluate();
  }

  void _reevaluate() {
    final cuser = _cuser;
    final hash = cuser == null
        ? null
        : MqttService.instance.userMenuHashFor(cuser);

    // No waiter, or this one has no layout of their own: the shared list, and
    // their topic is dropped so nothing of it can arrive later.
    if (cuser == null || hash == null) {
      MqttService.instance.setUserMenuSource(null);
      _personal = null;
      _timeout?.cancel();
      state = MqttMenuView(menu: _shared, loading: false, personal: false);
      return;
    }

    MqttService.instance.setUserMenuSource(cuser);

    // Already held from this session, or saved from an earlier one with the
    // same hash: no wait at all.
    if (_personal == null && _prefs.getString(_userVerKey(cuser)) == hash) {
      final saved = _prefs.getString(_userRawKey(cuser));
      if (saved != null && saved.isNotEmpty) _personal = _parse(saved);
    }

    final personal = _personal;
    if (personal != null) {
      _timeout?.cancel();
      state = MqttMenuView(menu: personal, loading: false, personal: true);
      return;
    }

    // Nothing to show yet: hold, but never indefinitely.
    if (state.loading) return; // a wait is already running
    _timeout?.cancel();
    _timeout = Timer(fallbackAfter, () {
      if (!mounted || !state.loading) return;
      debugPrint(
        'MQTT ▸ cjenik konobara $_cuser nije stigao — zajednički cjenik',
      );
      state = MqttMenuView(menu: _shared, loading: false, personal: false);
    });
    state = MqttMenuView(menu: _shared, loading: true, personal: false);
  }

  void _onUserPayload() {
    final cuser = _cuser;
    if (cuser == null) return;
    final raw = MqttService.instance.userArtikliRawJson.value;
    if (raw == null) return;

    // An empty retained message is how the kasa deletes a waiter's layout.
    // The waiter should be out of `artikli_korisnika` too, but the message may
    // arrive first — treat it as "back to the shared list" either way.
    if (raw.trim().isEmpty) {
      _prefs.remove(_userRawKey(cuser));
      _prefs.remove(_userVerKey(cuser));
      _personal = null;
      _timeout?.cancel();
      state = MqttMenuView(menu: _shared, loading: false, personal: false);
      return;
    }

    final parsed = _parse(raw);
    if (parsed == null) return; // keep whatever is on screen
    _personal = parsed;
    _prefs.setString(_userRawKey(cuser), raw);
    final hash = MqttService.instance.userMenuHashFor(cuser);
    if (hash != null) _prefs.setString(_userVerKey(cuser), hash);
    _timeout?.cancel();
    state = MqttMenuView(menu: parsed, loading: false, personal: true);
  }

  MqttMenu? _parse(String raw) {
    try {
      return MqttMenu.fromArtikliPayload(raw);
    } catch (e) {
      debugPrint('MQTT user menu parse failed: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _timeout?.cancel();
    MqttService.instance.userArtikliRawJson.removeListener(_onUserPayload);
    MqttService.instance.verzijaRawJson.removeListener(_reevaluate);
    super.dispose();
  }
}

/// The price list every screen should read: the waiter's own where the venue
/// arranged one, the shared one otherwise.
final mqttMenuViewProvider =
    StateNotifierProvider<MqttMenuViewNotifier, MqttMenuView>((ref) {
      final notifier = MqttMenuViewNotifier(
        ref.watch(sharedPreferencesProvider),
      );
      ref.listen<MqttMenu>(mqttMenuProvider, (_, next) {
        notifier.setSharedMenu(next);
      }, fireImmediately: true);
      ref.listen(currentUserProvider, (_, next) {
        notifier.setUser(next?.code);
      }, fireImmediately: true);
      return notifier;
    });
