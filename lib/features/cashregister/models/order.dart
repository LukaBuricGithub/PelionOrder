import 'package:flutter/foundation.dart';

import 'order_item.dart';

/// Everything a waiter has entered for one table: a list of [items] and their
/// quantities/remarks, plus the offline-queue state. Ported from the reference
/// client's `Order`.
///
/// The order lifecycle is encoded by two booleans:
///   * `pending == false`             → a draft/open order held on a table
///                                       (editable, not yet queued).
///   * `pending == true, sent == false` → queued for sending (the offline
///                                        resend queue).
///   * `pending == true, sent == true`  → successfully delivered to the server.
@immutable
class Order {
  const Order({
    this.id = 0,
    required this.orderTime,
    required this.userCode,
    required this.tableCode,
    this.items = const [],
    this.pending = false,
    this.sent = false,
  });

  /// Local database id (autoincrement). 0 means "not yet persisted".
  final int id;

  /// Creation time in epoch milliseconds.
  final int orderTime;

  final String userCode;
  final int tableCode;
  final List<OrderItem> items;
  final bool pending;
  final bool sent;

  /// Groups items by article code, summing quantities — used for the live
  /// per-item quantity display on the ordering screen. Mirrors the reference
  /// client's `Order.getItemsMap()`.
  Map<int, double> get itemsMap {
    final map = <int, double>{};
    for (final item in items) {
      map.update(item.code, (q) => q + item.quantity,
          ifAbsent: () => item.quantity);
    }
    return map;
  }

  Order copyWith({
    int? id,
    int? orderTime,
    String? userCode,
    int? tableCode,
    List<OrderItem>? items,
    bool? pending,
    bool? sent,
  }) {
    return Order(
      id: id ?? this.id,
      orderTime: orderTime ?? this.orderTime,
      userCode: userCode ?? this.userCode,
      tableCode: tableCode ?? this.tableCode,
      items: items ?? this.items,
      pending: pending ?? this.pending,
      sent: sent ?? this.sent,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Order &&
      other.id == id &&
      other.orderTime == orderTime &&
      other.userCode == userCode &&
      other.tableCode == tableCode &&
      listEquals(other.items, items) &&
      other.pending == pending &&
      other.sent == sent;

  @override
  int get hashCode => Object.hash(id, orderTime, userCode, tableCode,
      Object.hashAll(items), pending, sent);
}
