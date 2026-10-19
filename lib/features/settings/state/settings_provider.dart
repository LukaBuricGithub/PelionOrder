import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/state/shared_preferences_provider.dart';
import '../data/settings_storage.dart';
import '../models/menu_view_size.dart';
import '../models/order_entry_layout.dart';
import '../models/table_view_size.dart';

final settingsStorageProvider = Provider<SettingsStorage>((ref) {
  return SettingsStorage(ref.watch(sharedPreferencesProvider));
});

@immutable
class SettingsState {
  const SettingsState({
    this.tableViewSize = TableViewSize.medium,
    this.menuViewSize = MenuViewSize.small,
    this.orderEntryLayout = OrderEntryLayout.grid,
    this.shouldGroupArticles = false,
    this.groupListUnits = false,
    this.shouldAutoResend = false,
    this.useFloorPlan = false,
    this.followKasaMenu = true,
    this.businessName,
  });

  final TableViewSize tableViewSize;
  final MenuViewSize menuViewSize;

  /// How the order-entry screen is laid out on this phone.
  final OrderEntryLayout orderEntryLayout;
  final bool shouldGroupArticles;

  /// "Grupiraj artikle narudžbe", the "Popis" layout's own setting: keep an
  /// article's units on one line instead of sending them as separate entries.
  /// Only ever acted on where [orderEntryLayout] is `list`.
  final bool groupListUnits;
  final bool shouldAutoResend;

  /// Draw the venue's own floor plan instead of the generic grid. Only ever
  /// acted on where the venue actually sends one.
  final bool useFloorPlan;

  /// Lay the price list out as the venue arranged it on the kasa. Only ever
  /// acted on where the venue actually sends a layout (`prikaz`).
  final bool followKasaMenu;
  final String? businessName;

  /// Whether an article's units go out as separate entries — "Popis" with
  /// "Grupiraj artikle narudžbe" off. The one place this rule is written down:
  /// the grid is never split (each tap is already its own entry), and the
  /// setting is meaningless outside "Popis".
  bool get splitsOrderUnits =>
      orderEntryLayout == OrderEntryLayout.list && !groupListUnits;

  SettingsState copyWith({
    TableViewSize? tableViewSize,
    MenuViewSize? menuViewSize,
    OrderEntryLayout? orderEntryLayout,
    bool? shouldGroupArticles,
    bool? groupListUnits,
    bool? shouldAutoResend,
    bool? useFloorPlan,
    bool? followKasaMenu,
    String? businessName,
  }) {
    return SettingsState(
      tableViewSize: tableViewSize ?? this.tableViewSize,
      menuViewSize: menuViewSize ?? this.menuViewSize,
      orderEntryLayout: orderEntryLayout ?? this.orderEntryLayout,
      shouldGroupArticles: shouldGroupArticles ?? this.shouldGroupArticles,
      groupListUnits: groupListUnits ?? this.groupListUnits,
      shouldAutoResend: shouldAutoResend ?? this.shouldAutoResend,
      useFloorPlan: useFloorPlan ?? this.useFloorPlan,
      followKasaMenu: followKasaMenu ?? this.followKasaMenu,
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
          orderEntryLayout: _storage.loadOrderEntryLayout(),
          shouldGroupArticles: _storage.loadShouldGroupArticles(),
          groupListUnits: _storage.loadGroupListUnits(),
          shouldAutoResend: _storage.loadShouldAutoResend(),
          useFloorPlan: _storage.loadUseFloorPlan(),
          followKasaMenu: _storage.loadFollowKasaMenu(),
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

  Future<void> setGroupListUnits(bool value) async {
    await _storage.saveGroupListUnits(value);
    state = state.copyWith(groupListUnits: value);
  }

  Future<void> setOrderEntryLayout(OrderEntryLayout layout) async {
    await _storage.saveOrderEntryLayout(layout);
    state = state.copyWith(orderEntryLayout: layout);
  }

  Future<void> setShouldAutoResend(bool value) async {
    await _storage.saveShouldAutoResend(value);
    state = state.copyWith(shouldAutoResend: value);
  }

  Future<void> setUseFloorPlan(bool value) async {
    await _storage.saveUseFloorPlan(value);
    state = state.copyWith(useFloorPlan: value);
  }

  Future<void> setFollowKasaMenu(bool value) async {
    await _storage.saveFollowKasaMenu(value);
    state = state.copyWith(followKasaMenu: value);
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
