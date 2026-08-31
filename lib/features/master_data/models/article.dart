import 'package:flutter/foundation.dart';

/// A single sellable product, with a [name], [price] and [unit] of measure.
/// Each article belongs to an article group ([groupCode]). Ported from the
/// reference client's `Item`.
///
/// Remote JSON: `ITEMCODE`, `ITEMNAME`, `ITEMPRICE`, `ITEMUOM`,
/// `TOUCHGROUPCODE`, `ITEMORDERNO`.
@immutable
class Article {
  const Article({
    required this.code,
    required this.name,
    required this.price,
    required this.unit,
    required this.groupCode,
    required this.order,
  });

  final int code;
  final String name;
  final double price;
  final String unit;
  final String groupCode;
  final int order;

  factory Article.fromRemoteJson(Map<String, dynamic> json) {
    return Article(
      code: (json['ITEMCODE'] as num?)?.toInt() ??
          int.tryParse((json['ITEMCODE'] ?? '').toString()) ??
          0,
      name: (json['ITEMNAME'] ?? '').toString().trim(),
      price: (json['ITEMPRICE'] as num?)?.toDouble() ??
          double.tryParse((json['ITEMPRICE'] ?? '').toString()) ??
          0.0,
      unit: (json['ITEMUOM'] ?? '').toString().trim(),
      // Server pads CHAR columns with trailing spaces (and to different widths
      // across endpoints), so trim before it is compared against a group code.
      groupCode: (json['TOUCHGROUPCODE'] ?? '').toString().trim(),
      order: (json['ITEMORDERNO'] as num?)?.toInt() ??
          int.tryParse((json['ITEMORDERNO'] ?? '').toString()) ??
          0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Article &&
      other.code == code &&
      other.name == name &&
      other.price == price &&
      other.unit == unit &&
      other.groupCode == groupCode &&
      other.order == order;

  @override
  int get hashCode =>
      Object.hash(code, name, price, unit, groupCode, order);
}
