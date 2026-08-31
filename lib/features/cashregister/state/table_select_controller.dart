import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/session_provider.dart';
import '../../master_data/models/terrace.dart';
import '../../master_data/models/user.dart';
import '../../master_data/models/venue_table.dart';
import '../../master_data/state/master_data_providers.dart';
import 'orders_providers.dart';

/// Visual status of a table tile, colour-coded so the floor is readable at a
/// glance.
enum TableStatus {
  free,
  mine,
  other,
  pendingMine,
}

@immutable
class TableSelectState {
  const TableSelectState({
    this.loading = true,
    this.terraces = const [],
    this.tables = const [],
    this.selectedTerrace = 0,
    this.myOrderTables = const {},
    this.pendingTables = const {},
  });

  final bool loading;
  final List<Terrace> terraces;
  final List<VenueTable> tables;
  final int selectedTerrace;

  /// Table codes where the current user has a local order (draft or pending) —
  /// these show as "yours" even before the server knows.
  final Set<int> myOrderTables;

  /// Table codes with a local unsent (pending) order — shown with a busy badge.
  final Set<int> pendingTables;

  Terrace? get currentTerrace =>
      (selectedTerrace >= 0 && selectedTerrace < terraces.length)
          ? terraces[selectedTerrace]
          : null;

  /// Tables belonging to the selected terrace (by inclusive code range).
  List<VenueTable> get tablesForCurrentTerrace {
    final t = currentTerrace;
    if (t == null) return const [];
    return tables.where((tbl) => t.containsTable(tbl.code)).toList()
      ..sort((a, b) => a.code.compareTo(b.code));
  }

  TableSelectState copyWith({
    bool? loading,
    List<Terrace>? terraces,
    List<VenueTable>? tables,
    int? selectedTerrace,
    Set<int>? myOrderTables,
    Set<int>? pendingTables,
  }) {
    return TableSelectState(
      loading: loading ?? this.loading,
      terraces: terraces ?? this.terraces,
      tables: tables ?? this.tables,
      selectedTerrace: selectedTerrace ?? this.selectedTerrace,
      myOrderTables: myOrderTables ?? this.myOrderTables,
      pendingTables: pendingTables ?? this.pendingTables,
    );
  }
}

/// Loads terraces + tables from the cache, merges in the user's local orders,
/// and periodically (30s) refreshes table ownership from the server. Mirrors
/// the reference client's `TableSelectViewModel`.
class TableSelectController extends StateNotifier<TableSelectState> {
  TableSelectController(this._ref) : super(const TableSelectState()) {
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  final Ref _ref;
  Timer? _timer;

  User? get _user => _ref.read(currentUserProvider);

  Future<void> _load() async {
    final master = _ref.read(masterDataRepositoryProvider);
    final terraces = await master.cachedTerraces();
    final tables = await master.cachedTables();
    final ordersInfo = await _localOrderTables();
    if (!mounted) return;
    state = state.copyWith(
      loading: false,
      terraces: terraces,
      tables: tables,
      myOrderTables: ordersInfo.$1,
      pendingTables: ordersInfo.$2,
      selectedTerrace: state.selectedTerrace.clamp(
        0,
        terraces.isEmpty ? 0 : terraces.length - 1,
      ),
    );
  }

  Future<void> _refresh() async {
    await _ref.read(masterDataRepositoryProvider).refreshTables();
    await _load();
  }

  /// Public refresh (pull-to-refresh / returning from an order).
  Future<void> reload() => _load();

  void selectTerrace(int index) {
    state = state.copyWith(selectedTerrace: index);
  }

  /// (myOrderTables, pendingTables) for the current user.
  Future<(Set<int>, Set<int>)> _localOrderTables() async {
    final user = _user;
    if (user == null) return (<int>{}, <int>{});
    final orders = await _ref.read(orderRepositoryProvider).allOrders();
    final mine = <int>{};
    final pending = <int>{};
    for (final o in orders) {
      if (o.userCode != user.code) continue;
      mine.add(o.tableCode);
      if (o.pending && !o.sent) pending.add(o.tableCode);
    }
    return (mine, pending);
  }

  TableStatus statusFor(VenueTable table) {
    final user = _user;
    if (state.pendingTables.contains(table.code)) return TableStatus.pendingMine;
    final mineByOrder = state.myOrderTables.contains(table.code);
    final mineByOwner = user != null && table.userCode == user.code;
    if (mineByOrder || mineByOwner) return TableStatus.mine;
    if (table.userCode.isNotEmpty) return TableStatus.other;
    return TableStatus.free;
  }

  /// Whether the current user may open [table] (permission + ownership rules).
  bool canOpen(VenueTable table) {
    final user = _user;
    if (user == null) return false;
    if (table.isFree) return true;
    if (table.userCode == user.code) return true;
    if (user.allTablesOpenRight) return true;
    return state.myOrderTables.contains(table.code);
  }

  /// Reserves the table for the current user. Returns true when the table can
  /// be opened (optimistic when offline). No-op false when logged out.
  Future<bool> reserve(VenueTable table) async {
    final user = _user;
    if (user == null) return false;
    return _ref
        .read(orderRepositoryProvider)
        .reserveTable(user.code, table.code);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final tableSelectControllerProvider = StateNotifierProvider.autoDispose<
    TableSelectController, TableSelectState>((ref) {
  return TableSelectController(ref);
});
