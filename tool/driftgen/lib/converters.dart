import 'dart:convert';

import 'package:drift/drift.dart';

import 'order_item.dart';

/// Stores an order's [OrderItem] list as a JSON string in a single text column,
/// mirroring the reference client's `OrderItemListTypeConverter` (kotlinx).
class OrderItemListConverter extends TypeConverter<List<OrderItem>, String> {
  const OrderItemListConverter();

  @override
  List<OrderItem> fromSql(String fromDb) {
    if (fromDb.isEmpty) return const [];
    final decoded = jsonDecode(fromDb);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((m) => OrderItem.fromJson(Map<String, dynamic>.from(m)))
        .toList(growable: false);
  }

  @override
  String toSql(List<OrderItem> value) {
    return jsonEncode(value.map((e) => e.toJson()).toList());
  }
}
