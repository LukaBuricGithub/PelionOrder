import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_database.dart';

/// Single app-wide [AppDatabase] instance. Closed when the provider is
/// disposed (i.e. app teardown).
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
