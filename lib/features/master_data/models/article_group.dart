import 'package:flutter/foundation.dart';

/// A menu category shown as a large button (e.g. "Drinks", "Food",
/// "Desserts"). Ported from the reference client's `Group`.
///
/// Remote JSON: `TOUCHGROUPCODE`, `TOUCHGROUPORDER`, `TOUCHGROUPNAME`.
@immutable
class ArticleGroup {
  const ArticleGroup({
    required this.code,
    required this.order,
    required this.name,
  });

  final String code;
  final int order;
  final String name;

  factory ArticleGroup.fromRemoteJson(Map<String, dynamic> json) {
    return ArticleGroup(
      // Trim: server pads this code with trailing spaces (see Article.groupCode).
      code: (json['TOUCHGROUPCODE'] ?? '').toString().trim(),
      order: (json['TOUCHGROUPORDER'] as num?)?.toInt() ??
          int.tryParse((json['TOUCHGROUPORDER'] ?? '').toString()) ??
          0,
      name: (json['TOUCHGROUPNAME'] ?? '').toString().trim(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ArticleGroup &&
      other.code == code &&
      other.order == order &&
      other.name == name;

  @override
  int get hashCode => Object.hash(code, order, name);
}
