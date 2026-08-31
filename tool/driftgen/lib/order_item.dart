import 'package:flutter/foundation.dart';

/// One entry in an order: an article [code], its [quantity], and any [remarks]
/// (predefined or custom notes) attached to it. Ported from the reference
/// client's `OrderItem`.
///
/// Persisted inside a [Order] as a JSON list (see the drift `OrderItem`
/// converter), so it carries its own `fromJson`/`toJson`.
@immutable
class OrderItem {
  const OrderItem({
    required this.code,
    this.remarks = const [],
    required this.quantity,
  });

  final int code;
  final List<String> remarks;
  final double quantity;

  OrderItem copyWith({
    int? code,
    List<String>? remarks,
    double? quantity,
  }) {
    return OrderItem(
      code: code ?? this.code,
      remarks: remarks ?? this.remarks,
      quantity: quantity ?? this.quantity,
    );
  }

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      code: (json['code'] as num?)?.toInt() ?? 0,
      remarks: (json['remarks'] as List?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const [],
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'remarks': remarks,
        'quantity': quantity,
      };

  @override
  bool operator ==(Object other) =>
      other is OrderItem &&
      other.code == code &&
      listEquals(other.remarks, remarks) &&
      other.quantity == quantity;

  @override
  int get hashCode => Object.hash(code, Object.hashAll(remarks), quantity);
}
