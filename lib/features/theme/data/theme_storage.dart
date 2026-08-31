import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's light/dark theme choice. Ported from the ikasa app.
class ThemeStorage {
  ThemeStorage(this._prefs);

  final SharedPreferences _prefs;

  static const _themeModeKey = 'theme_mode_v1';

  /// The saved preference, or `null` if none was ever saved (first launch) —
  /// callers default that to light.
  ThemeMode? loadThemeMode() {
    switch (_prefs.getString(_themeModeKey)) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return null;
    }
  }

  Future<void> saveThemeMode(ThemeMode mode) {
    return _prefs.setString(
      _themeModeKey,
      mode == ThemeMode.dark ? 'dark' : 'light',
    );
  }
}
