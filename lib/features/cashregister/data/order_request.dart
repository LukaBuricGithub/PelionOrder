import '../models/order.dart';
import '../models/order_item.dart';

/// Builds the request body for the venue's `postOrder` endpoint.
///
/// ⚠️ CRITICAL: this is NOT standard JSON. The reference client hand-builds the
/// body in `OrderRequest.toJsonString(shouldGroupArticles)` and the venue
/// server parses that exact custom shape. It must be reproduced byte-for-byte:
///
/// ```
/// {"userCode":<code>,"tableCode":<code>,{"itemCode":<c>,"quantity":<q>[,"remark":"r1,r2"]},{...}}
/// ```
///
/// Notes:
///   * `userCode` is written **unquoted** (raw) — the server treats it
///     numerically.
///   * item objects are appended after the two header fields, comma-separated
///     but **NOT wrapped in a JSON array**.
///   * the `remark` key is added **only** when the item has remarks; multiple
///     remarks are joined with `,` into a single string.
///   * when [shouldGroupArticles] is true (Settings toggle, default true),
///     items are grouped by `(code, remarks)` and their quantities summed —
///     one object per group. When false, one object per raw [OrderItem].
class OrderRequest {
  const OrderRequest({
    required this.userCode,
    required this.tableCode,
    required this.items,
  });

  final String userCode;
  final int tableCode;
  final List<OrderItem> items;

  factory OrderRequest.fromOrder(Order order) {
    return OrderRequest(
      userCode: order.userCode,
      tableCode: order.tableCode,
      items: order.items,
    );
  }

  String toJsonString({required bool shouldGroupArticles}) {
    final effectiveItems =
        shouldGroupArticles ? _groupItems(items) : items;

    final buffer = StringBuffer();
    // Header fields — userCode intentionally UNQUOTED.
    buffer.write('{"userCode":$userCode,"tableCode":$tableCode');
    for (final item in effectiveItems) {
      buffer.write(',');
      buffer.write(_itemToJson(item));
    }
    buffer.write('}');
    return buffer.toString();
  }

  static String _itemToJson(OrderItem item) {
    final b = StringBuffer();
    b.write('{"itemCode":${item.code},"quantity":${item.quantity}');
    if (item.remarks.isNotEmpty) {
      b.write(',"remark":"${item.remarks.join(',')}"');
    }
    b.write('}');
    return b.toString();
  }

  /// Groups by `(code, remarks)` summing quantities, preserving first-seen
  /// order. Matches the reference client's grouping behaviour.
  static List<OrderItem> _groupItems(List<OrderItem> items) {
    final order = <String>[];
    final grouped = <String, OrderItem>{};
    for (final item in items) {
      final key = '${item.code}|${item.remarks.join(',')}';
      final existing = grouped[key];
      if (existing == null) {
        order.add(key);
        grouped[key] = item;
      } else {
        grouped[key] =
            existing.copyWith(quantity: existing.quantity + item.quantity);
      }
    }
    return [for (final key in order) grouped[key]!];
  }
}
