import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../master_data/models/user.dart';

/// The currently signed-in waiter, or null when logged out. Set after a
/// successful PIN login and restored at startup from the saved user code.
final currentUserProvider = StateProvider<User?>((ref) => null);

/// True while the app is restoring the persisted session at startup. The router
/// keeps the splash screen up until this flips to false. Mirrors ikasa's
/// `isRestoringSessionProvider`.
final isBootstrappingProvider = StateProvider<bool>((ref) => true);
