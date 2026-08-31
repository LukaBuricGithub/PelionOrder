import 'package:flutter/foundation.dart';

/// A venue branch, used as a filter in the Traffic (reporting) section. Ported
/// from the reference client's `Branch`.
///
/// Remote JSON: `BRANCHNAME`.
@immutable
class Branch {
  const Branch({required this.branchName});

  final String branchName;

  factory Branch.fromRemoteJson(Map<String, dynamic> json) {
    return Branch(branchName: (json['BRANCHNAME'] ?? '').toString().trim());
  }

  @override
  bool operator ==(Object other) =>
      other is Branch && other.branchName == branchName;

  @override
  int get hashCode => branchName.hashCode;
}
