import 'package:flutter/foundation.dart';

/// A predefined note/modifier attached to an ordered item (e.g. "no ice",
/// "well done"). Bound to an article by [itemId]. Ported from the reference
/// client's `Remark`.
///
/// Remote JSON: `REMARKNAME`, `ITEMID`. The local [id] is assigned by the
/// database (autoincrement) and is not part of the wire format.
@immutable
class Remark {
  const Remark({
    required this.id,
    required this.name,
    required this.itemId,
  });

  final int id;
  final String name;
  final int itemId;

  factory Remark.fromRemoteJson(Map<String, dynamic> json) {
    return Remark(
      id: 0,
      name: (json['REMARKNAME'] ?? '').toString().trim(),
      itemId: (json['ITEMID'] as num?)?.toInt() ??
          int.tryParse((json['ITEMID'] ?? '').toString()) ??
          0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Remark &&
      other.id == id &&
      other.name == name &&
      other.itemId == itemId;

  @override
  int get hashCode => Object.hash(id, name, itemId);
}
