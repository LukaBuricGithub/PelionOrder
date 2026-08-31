import 'package:flutter/foundation.dart';

/// One aggregated line of a table's current bill, as returned by the venue's
/// `tableDetail` endpoint. Ported from the reference client's `TableDetail`.
///
/// Remote JSON (uppercase): `ITEMCODE`, `ITEMNAME`, `QUANTITY`, `AMOUNT`.
@immutable
class TableDetail {
  const TableDetail({
    required this.itemCode,
    required this.itemName,
    required this.quantity,
    required this.amount,
  });

  final int itemCode;
  final String itemName;
  final double quantity;
  final double amount;

  factory TableDetail.fromRemoteJson(Map<String, dynamic> json) {
    return TableDetail(
      itemCode: (json['ITEMCODE'] as num?)?.toInt() ??
          int.tryParse((json['ITEMCODE'] ?? '').toString()) ??
          0,
      itemName: (json['ITEMNAME'] ?? '').toString().trim(),
      quantity: (json['QUANTITY'] as num?)?.toDouble() ??
          double.tryParse((json['QUANTITY'] ?? '').toString()) ??
          0.0,
      amount: (json['AMOUNT'] as num?)?.toDouble() ??
          double.tryParse((json['AMOUNT'] ?? '').toString()) ??
          0.0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TableDetail &&
      other.itemCode == itemCode &&
      other.itemName == itemName &&
      other.quantity == quantity &&
      other.amount == amount;

  @override
  int get hashCode => Object.hash(itemCode, itemName, quantity, amount);
}
