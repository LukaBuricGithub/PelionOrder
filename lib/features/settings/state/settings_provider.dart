import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/state/shared_preferences_provider.dart';
import '../data/settings_storage.dart';
import '../models/table_view_size.dart';

final settingsStorageProvider = Provider<SettingsStorage>((ref) {
  return SettingsStorage(ref.watch(sharedPreferencesProvider));
});

@immutable
class SettingsState {
  const SettingsState({
    this.tableViewSize = TableViewSize.medium,
    this.shouldGroupArticles = false,
    this.businessName,
  });

  final TableViewSize tableViewSize;
  final bool shouldGroupArticles;
  final String? businessName;

  SettingsState copyWith({
    TableViewSize? tableViewSize,
    bool? shouldGroupArticles,
    String? businessName,
  }) {
    return SettingsState(
      tableViewSize: tableViewSize ?? this.tableViewSize,
      shouldGroupArticles: shouldGroupArticles ?? this.shouldGroupArticles,
      businessName: businessName ?? this.businessName,
    );
  }
}

/// Holds the device display / sending preferences and persists changes.
class SettingsController extends StateNotifier<SettingsState> {
  SettingsController(this._storage)
      : super(SettingsState(
          tableViewSize: _storage.loadTableViewSize(),
          shouldGroupArticles: _storage.loadShouldGroupArticles(),
          businessName: _storage.loadBusinessName(),
        ));

  final SettingsStorage _storage;

  Future<void> setTableViewSize(TableViewSize size) async {
    await _storage.saveTableViewSize(size);
    state = state.copyWith(tableViewSize: size);
  }

  Future<void> setShouldGroupArticles(bool value) async {
    await _storage.saveShouldGroupArticles(value);
    state = state.copyWith(shouldGroupArticles: value);
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
