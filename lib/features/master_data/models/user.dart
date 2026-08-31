import 'package:flutter/foundation.dart';

import '../../shared/util/croatian_bool.dart';

/// A staff member / waiter. Login is by personal [pin]; the boolean rights
/// tailor what each person may do (see the reference client's `User`).
///
/// Server (remote) JSON uses UPPERCASE keys and `"D"/"N"` booleans:
/// `USERCODE`, `USERNAME`, `USERPIN`, `CHANGEQUANTITYRIGHT`,
/// `ALLTABLESOPENRIGHT`, `DELETERIGHT`, `SUPERUSER`.
@immutable
class User {
  const User({
    required this.code,
    required this.username,
    required this.pin,
    required this.changeQuantityRight,
    required this.allTablesOpenRight,
    required this.deleteRight,
    required this.superuser,
  });

  final String code;
  final String username;
  final int pin;

  /// Allowed to edit item quantities on an order.
  final bool changeQuantityRight;

  /// Allowed to open/work tables owned by other waiters (otherwise limited to
  /// free tables and their own).
  final bool allTablesOpenRight;

  /// Allowed to remove items/orders.
  final bool deleteRight;

  /// Full access, including the entire Traffic (reporting) section.
  final bool superuser;

  factory User.fromRemoteJson(Map<String, dynamic> json) {
    return User(
      code: (json['USERCODE'] ?? '').toString().trim(),
      username: (json['USERNAME'] ?? '').toString().trim(),
      pin: (json['USERPIN'] as num?)?.toInt() ??
          int.tryParse((json['USERPIN'] ?? '').toString()) ??
          0,
      changeQuantityRight: croatianStringToBool(json['CHANGEQUANTITYRIGHT']),
      allTablesOpenRight: croatianStringToBool(json['ALLTABLESOPENRIGHT']),
      deleteRight: croatianStringToBool(json['DELETERIGHT']),
      superuser: croatianStringToBool(json['SUPERUSER']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is User &&
      other.code == code &&
      other.username == username &&
      other.pin == pin &&
      other.changeQuantityRight == changeQuantityRight &&
      other.allTablesOpenRight == allTablesOpenRight &&
      other.deleteRight == deleteRight &&
      other.superuser == superuser;

  @override
  int get hashCode => Object.hash(code, username, pin, changeQuantityRight,
      allTablesOpenRight, deleteRight, superuser);
}
