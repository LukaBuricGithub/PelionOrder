import 'package:drift/drift.dart' show Value;

import '../../database/app_database.dart';
import '../../shared/services/connectivity_service.dart';
import '../models/order.dart';
import 'order_request.dart';
import 'ordering_api.dart';

/// Coordinates orders between the local drift queue and the venue server.
///
/// Order lifecycle (two booleans):
///   * `pending == false`             → an open draft on a table (editable)
///   * `pending == true, sent == false` → queued for sending (offline queue)
///   * `pending == true, sent == true`  → delivered to the server
///
/// Sending sets `pending = true`, persists, then POSTs; on success `sent` is
/// set to true, otherwise the order stays queued and is auto-resent by the
/// heartbeat. Mirrors the reference client's `OrderRepositoryImpl` +
/// `ReservationRepositoryImpl`.
class OrderRepository {
  OrderRepository({
    required AppDatabase db,
    required ConnectivityService connectivity,
    required bool shouldGroupArticles,
    OrderingApi? api,
  })  : _db = db,
        _connectivity = connectivity,
        _shouldGroupArticles = shouldGroupArticles,
        _api = api;

  final AppDatabase _db;
  final ConnectivityService _connectivity;
  final bool _shouldGroupArticles;
  final OrderingApi? _api;

  // ── Reads ────────────────────────────────────────────────────────────────
  Future<List<Order>> allOrders() async =>
      (await _db.getAllOrders()).map(_fromDb).toList(growable: false);

  Future<Order?> getOrder(int id) async {
    final row = await _db.getOrderById(id);
    return row == null ? null : _fromDb(row);
  }

  Future<List<Order>> pendingOrders() async =>
      (await _db.getPendingOrders()).map(_fromDb).toList(growable: false);

  Future<int> pendingCount() async => (await _db.getPendingOrders()).length;

  /// Continues an existing open (non-pending) order for this table+user, or
  /// creates a fresh in-memory one. Mirrors `getExistingOrNewOrder`.
  Future<Order> getOrCreateOpenOrder({
    required int tableCode,
    required String userCode,
    required int nowMillis,
  }) async {
    final existing = await _db.findOpenOrder(tableCode, userCode);
    if (existing != null) return _fromDb(existing);
    return Order(
      orderTime: nowMillis,
      userCode: userCode,
      tableCode: tableCode,
      items: const [],
    );
  }

  // ── Writes ───────────────────────────────────────────────────────────────
  /// Persists an open draft (forces pending = false). Returns the row id.
  Future<int> saveDraft(Order order) async {
    final draft = order.copyWith(pending: false, sent: false);
    final id = await _db.upsertOrder(_toCompanion(draft));
    return id;
  }

  /// Persists [order] exactly as-is, preserving its `pending`/`sent` flags.
  /// Used when editing an order in the details screen, which may be either an
  /// open draft OR a queued (pending) order pulled from the offline queue —
  /// forcing it back to a draft would silently drop it from the send queue.
  Future<int> updateOrder(Order order) async {
    return _db.upsertOrder(_toCompanion(order));
  }

  Future<void> deleteOrder(int id) => _db.deleteOrderById(id);

  /// Finalizes and attempts to send [order]. Always persists it as pending
  /// first (so it survives as a queued order), then — when online — POSTs it.
  /// Returns true only when the server acknowledged; false means it stays in
  /// the offline queue for later auto-resend.
  Future<bool> sendOrder(Order order) async {
    var o = order.copyWith(pending: true, sent: false);
    final id = await _db.upsertOrder(_toCompanion(o));
    o = o.copyWith(id: id);

    final api = _api;
    if (api == null || !await _connectivity.hasConnection()) {
      return false; // queued
    }

    try {
      final body = OrderRequest.fromOrder(o)
          .toJsonString(shouldGroupArticles: _shouldGroupArticles);
      final ok = await api.postOrder(body);
      if (ok) {
        await _db.upsertOrder(_toCompanion(o.copyWith(sent: true)));
        return true;
      }
      return false;
    } catch (_) {
      return false; // stays queued
    }
  }

  /// Attempts to resend every queued order. Returns how many were acknowledged.
  /// Called by the heartbeat whenever the connection is up.
  Future<int> sendPendingOrders() async {
    if (_api == null || !await _connectivity.hasConnection()) return 0;
    final pending = await pendingOrders();
    var sent = 0;
    for (final o in pending) {
      if (await sendOrder(o)) sent++;
    }
    return sent;
  }

  // ── Reservations (optimistic offline) ────────────────────────────────────
  /// Reserves a table. Like the reference client, returns **true when offline**
  /// (optimistic — you can still open the table), and false only on an actual
  /// server rejection.
  Future<bool> reserveTable(String userCode, int tableCode) async {
    final api = _api;
    if (api == null || !await _connectivity.hasConnection()) return true;
    try {
      return await api.reserveTable(userCode, tableCode);
    } catch (_) {
      return true; // treat transport failure as "offline → optimistic"
    }
  }

  Future<bool> removeReservation(int tableCode) async {
    final api = _api;
    if (api == null || !await _connectivity.hasConnection()) return true;
    try {
      return await api.removeReservation(tableCode);
    } catch (_) {
      return true;
    }
  }

  // ── Mapping ──────────────────────────────────────────────────────────────
  OrdersCompanion _toCompanion(Order o) => OrdersCompanion(
        id: o.id == 0 ? const Value.absent() : Value(o.id),
        orderTime: Value(o.orderTime),
        userCode: Value(o.userCode),
        tableCode: Value(o.tableCode),
        items: Value(o.items),
        pending: Value(o.pending),
        sent: Value(o.sent),
      );

  Order _fromDb(DbOrder r) => Order(
        id: r.id,
        orderTime: r.orderTime,
        userCode: r.userCode,
        tableCode: r.tableCode,
        items: r.items,
        pending: r.pending,
        sent: r.sent,
      );
}
