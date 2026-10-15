import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The app's own bundle info (version name + build number), read once.
///
/// A FutureProvider because it is a platform-channel call; the result is kept,
/// so every later read is free. Same shape as the ikasa app's provider.
final appInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);
