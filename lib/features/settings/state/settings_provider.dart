import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/state/shared_preferences_provider.dart';
import '../data/settings_storage.dart';
import '../models/menu_view_size.dart';
import '../models/table_view_size.dart';

final settingsStorageProvider = Provider<SettingsStorage>((ref) {
  return SettingsStorage(ref.watch(sharedPreferencesProvider));
});

@immutable
class SettingsState {
  const SettingsState({
    this.tableViewSize = TableViewSize.medium,
    this.menuViewSize = MenuViewSize.small,
    this.shouldGroupArticles = false,
    this.shouldAutoResend = false,
    this.preferTableGrid = false,
    this.businessName,
  });

  final TableViewSize tableViewSize;
  final MenuViewSize menuViewSize;
  final bool shouldGroupArticles;
  final bool shouldAutoResend;

  /// Stick to the generic grid although the venue has a floor plan.
  final bool preferTableGrid;
  final String? businessName;

  SettingsState copyWith({
    TableViewSize? tableViewSize,
    MenuViewSize? menuViewSize,
    bool? shouldGroupArticles,
    bool? shouldAutoResend,
    bool? preferTableGrid,
    String? businessName,
  }) {
    return SettingsState(
      tableViewSize: tableViewSize ?? this.tableViewSize,
      menuViewSize: menuViewSize ?? this.menuViewSize,
      shouldGroupArticles: shouldGroupArticles ?? this.shouldGroupArticles,
      shouldAutoResend: shouldAutoResend ?? this.shouldAutoResend,
      preferTableGrid: preferTableGrid ?? this.preferTableGrid,
      businessName: businessName ?? this.businessName,
    );
  }
}

/// Holds the device display / sending preferences and persists changes.
class SettingsController extends StateNotifier<SettingsState> {
  SettingsController(this._storage)
    : super(
        SettingsState(
          tableViewSize: _storage.loadTableViewSize(),
          menuViewSize: _storage.loadMenuViewSize(),
          shouldGroupArticles: _storage.loadShouldGroupArticles(),
          shouldAutoResend: _storage.loadShouldAutoResend(),
          preferTableGrid: _storage.loadPreferTableGrid(),
          businessName: _storage.loadBusinessName(),
        ),
      );

  final SettingsStorage _storage;

  Future<void> setTableViewSize(TableViewSize size) async {
    await _storage.saveTableViewSize(size);
    state = state.copyWith(tableViewSize: size);
  }

  Future<void> setMenuViewSize(MenuViewSize size) async {
    await _storage.saveMenuViewSize(size);
    state = state.copyWith(menuViewSize: size);
  }

  Future<void> setShouldGroupArticles(bool value) async {
    await _storage.saveShouldGroupArticles(value);
    state = state.copyWith(shouldGroupArticles: value);
  }

  Future<void> setShouldAutoResend(bool value) async {
    await _storage.saveShouldAutoResend(value);
    state = state.copyWith(shouldAutoResend: value);
  }

  Future<void> setPreferTableGrid(bool value) async {
    await _storage.savePreferTableGrid(value);
    state = state.copyWith(preferTableGrid: value);
  }

  Future<void> setBusinessName(String? name) async {
    await _storage.saveBusinessName(name);
    state = state.copyWith(businessName: name ?? '');
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsController, SettingsState>((ref) {
      return SettingsController(ref.watch(settingsStorageProvider));
    });
