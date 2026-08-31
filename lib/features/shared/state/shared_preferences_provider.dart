import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide [SharedPreferences] instance.
///
/// Overridden in `main()` with the already-resolved instance so the rest of the
/// app can read it synchronously:
///
/// ```dart
/// final prefs = await SharedPreferences.getInstance();
/// runApp(ProviderScope(
///   overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
///   child: const OrdermanApp(),
/// ));
/// ```
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main().',
  );
});
