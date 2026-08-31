import 'package:flutter/foundation.dart';

/// A physical table, identified by a [code] number (and optional [name]). A
/// table can be free or "owned" by the waiter who opened it ([userCode]).
///
/// Named `VenueTable` rather than `Table` to avoid colliding with Flutter's
/// `Table` layout widget. Ported from the reference client's `Table`.
///
/// Remote JSON: `TABLECODE`, `TABLENAME`, `USERCODE`, `NOOFITEMS`.
@immutable
class VenueTable {
  const VenueTable({
    required this.code,
    required this.name,
    required this.userCode,
    required this.itemCount,
  });

  final int code;
  final String name;

  /// Code of the waiter currently owning (reserving) the table, or empty when
  /// the table is free.
  final String userCode;

  /// Number of items currently on the table.
  final int itemCount;

  bool get isFree => userCode.isEmpty;

  /// `"code"` when unnamed, `"code-name"` otherwise.
  String get displayName => name.isEmpty ? '$code' : '$code-$name';

  VenueTable copyWith({
    int? code,
    String? name,
    String? userCode,
    int? itemCount,
  }) {
    return VenueTable(
      code: code ?? this.code,
      name: name ?? this.name,
      userCode: userCode ?? this.userCode,
      itemCount: itemCount ?? this.itemCount,
    );
  }

  factory VenueTable.fromRemoteJson(Map<String, dynamic> json) {
    return VenueTable(
      code: (json['TABLECODE'] as num?)?.toInt() ??
          int.tryParse((json['TABLECODE'] ?? '').toString()) ??
          0,
      name: (json['TABLENAME'] ?? '').toString().trim(),
      userCode: (json['USERCODE'] ?? '').toString().trim(),
      itemCount: (json['NOOFITEMS'] as num?)?.toInt() ??
          int.tryParse((json['NOOFITEMS'] ?? '').toString()) ??
          0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VenueTable &&
      other.code == code &&
      other.name == name &&
      other.userCode == userCode &&
      other.itemCount == itemCount;

  @override
  int get hashCode => Object.hash(code, name, userCode, itemCount);
}
