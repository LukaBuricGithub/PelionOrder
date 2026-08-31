import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/state/shared_preferences_provider.dart';
import '../data/theme_storage.dart';

final themeStorageProvider = Provider<ThemeStorage>((ref) {
  return ThemeStorage(ref.watch(sharedPreferencesProvider));
});

/// Holds the active [ThemeMode] and persists changes. Defaults to light (the
/// app's standard theme) until the user toggles. Modelled on ikasa's
/// `ThemeModeController`.
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._storage)
      : super(_storage.loadThemeMode() ?? ThemeMode.light);

  final ThemeStorage _storage;

  Future<void> setThemeMode(ThemeMode mode) async {
    if (state == mode) return;
    state = mode;
    await _storage.saveThemeMode(mode);
  }

  /// Flips between light and dark and persists the choice.
  Future<void> toggleThemeMode() {
    return setThemeMode(
      state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
    );
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>((ref) {
  return ThemeModeController(ref.watch(themeStorageProvider));
});
