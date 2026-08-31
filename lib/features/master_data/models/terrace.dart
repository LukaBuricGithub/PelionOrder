import 'package:flutter/foundation.dart';

/// A seating area / zone of the venue (e.g. "Garden", "Upstairs"). Each terrace
/// covers an inclusive range of table codes [tableFrom]..[tableTo].
///
/// Remote JSON: `TERACECODE` (note the server's misspelling of "terrace"),
/// `TABLEFROM`, `TABLETO`.
@immutable
class Terrace {
  const Terrace({
    required this.code,
    required this.tableFrom,
    required this.tableTo,
  });

  final String code;
  final int tableFrom;
  final int tableTo;

  /// Whether [tableCode] falls within this terrace's inclusive range.
  bool containsTable(int tableCode) =>
      tableCode >= tableFrom && tableCode <= tableTo;

  factory Terrace.fromRemoteJson(Map<String, dynamic> json) {
    int asInt(Object? v) =>
        (v as num?)?.toInt() ?? int.tryParse((v ?? '').toString()) ?? 0;
    return Terrace(
      code: (json['TERACECODE'] ?? '').toString().trim(),
      tableFrom: asInt(json['TABLEFROM']),
      tableTo: asInt(json['TABLETO']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Terrace &&
      other.code == code &&
      other.tableFrom == tableFrom &&
      other.tableTo == tableTo;

  @override
  int get hashCode => Object.hash(code, tableFrom, tableTo);
}
