// Basic smoke test for the Orderman app shell.
//
// Feature-level tests live alongside their features; this just verifies the
// splash screen builds without throwing. It deliberately asserts nothing
// about what is ON it: the screen is intentionally blank, because the OS
// native splash stays painted over it until the first real screen is ready
// (see SplashScreen).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pelion_order/features/auth/presentation/splash_screen.dart';
import 'package:pelion_order/features/shared/state/shared_preferences_provider.dart';

void main() {
  testWidgets('Splash screen builds without throwing', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: SplashScreen()),
      ),
    );

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
