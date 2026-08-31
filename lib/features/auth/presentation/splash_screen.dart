import 'package:flutter/material.dart';

/// Shown while the app restores its persisted session at startup. The router
/// keeps this on screen until `isBootstrappingProvider` flips to false.
///
/// Intentionally blank: the OS native splash (flutter_native_splash) stays
/// painted over this until the first real screen is ready, so this only exists
/// as a plain background that matches the native splash color — no icon or
/// spinner ever shows.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: SizedBox.shrink());
  }
}
