// Basic smoke test for the Orderman app shell.
//
// Feature-level tests live alongside their features; this just verifies the
// splash screen renders the app name without throwing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orderman/features/auth/presentation/splash_screen.dart';
import 'package:orderman/features/shared/state/shared_preferences_provider.dart';

void main() {
  testWidgets('Splash screen renders the app name', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: SplashScreen()),
      ),
    );

    expect(find.text('Pelion Order'), findsOneWidget);
  });
}
