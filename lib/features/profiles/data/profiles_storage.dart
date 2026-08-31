import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/api_entry.dart';

/// Persists the venue server profiles and the currently-selected one in
/// [SharedPreferences], mirroring the reference client's `app_prefs`
/// (`API_ENTRIES_KEYS` + `CURRENT_API_ENTRY_KEY`).
///
/// Server profiles deliberately live in SharedPreferences rather than the drift
/// database: they are device configuration, they must survive the
/// "delete-all-then-resync" wipe the master-data tables go through when
/// switching venues, and they are needed before the database is even usable.
class ProfilesStorage {
  ProfilesStorage(this._prefs);

  final SharedPreferences _prefs;

  static const _entriesKey = 'api_entries_v1';
  static const _currentIdKey = 'current_api_entry_id_v1';

  /// Flag set when the selected profile (or its address/key) changes, forcing
  /// a full master-data re-sync on the next opportunity. Mirrors the reference
  /// client's `NETWORK_PARAMETERS_UPDATED_KEY`.
  static const _networkParamsChangedKey = 'network_params_changed_v1';

  List<ApiEntry> loadEntries() {
    final raw = _prefs.getString(_entriesKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => ApiEntry.fromJson(Map<String, dynamic>.from(m)))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveEntries(List<ApiEntry> entries) async {
    final raw = jsonEncode(entries.map((e) => e.toJson()).toList());
    await _prefs.setString(_entriesKey, raw);
  }

  int? loadCurrentId() {
    final v = _prefs.getInt(_currentIdKey);
    return v == 0 ? null : v;
  }

  Future<void> saveCurrentId(int? id) async {
    if (id == null) {
      await _prefs.remove(_currentIdKey);
    } else {
      await _prefs.setInt(_currentIdKey, id);
    }
  }

  bool get networkParamsChanged =>
      _prefs.getBool(_networkParamsChangedKey) ?? false;

  Future<void> setNetworkParamsChanged(bool value) async {
    await _prefs.setBool(_networkParamsChangedKey, value);
  }
}
