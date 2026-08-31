import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../master_data/data/master_data_repository.dart';
import '../../master_data/state/master_data_providers.dart';
import '../../profiles/state/profiles_provider.dart';

@immutable
class LoginUiState {
  const LoginUiState({
    this.syncing = false,
    this.hasUsers = false,
    this.error,
  });

  /// True while a master-data download is in progress.
  final bool syncing;

  /// Whether staff data is cached — the Login (PIN) button is only enabled when
  /// this is true, matching the reference client.
  final bool hasUsers;

  /// Last sync error, if any (shown as a banner).
  final String? error;

  LoginUiState copyWith({
    bool? syncing,
    bool? hasUsers,
    String? error,
    bool clearError = false,
  }) {
    return LoginUiState(
      syncing: syncing ?? this.syncing,
      hasUsers: hasUsers ?? this.hasUsers,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Drives the Login screen's data-sync: auto-downloads master data when it is
/// missing or the profile changed, and backs the manual "Ažuriraj podatke"
/// button. Mirrors `LoginViewModel.fetchData()` / `clearData()`.
class LoginController extends StateNotifier<LoginUiState> {
  LoginController(this._ref) : super(const LoginUiState()) {
    _init();
  }

  final Ref _ref;

  Future<void> _init() async {
    await _refreshHasUsers();
    await maybeAutoSync();
  }

  Future<void> _refreshHasUsers() async {
    final has = await _ref.read(masterDataRepositoryProvider).hasCachedUsers();
    if (mounted) state = state.copyWith(hasUsers: has);
  }

  /// Re-evaluate cached-users state and re-run auto-sync when the selected
  /// profile changes (added / edited / deleted). Keeps the "Prijava" gate
  /// honest — e.g. after deleting the profile (which wipes the cache) the
  /// button must disable even though this controller stayed alive.
  Future<void> onProfilesChanged() async {
    await _refreshHasUsers();
    await maybeAutoSync();
  }

  /// Auto-sync on entering the login screen when online and either no data is
  /// cached yet or the selected profile changed.
  Future<void> maybeAutoSync() async {
    final repo = _ref.read(masterDataRepositoryProvider);
    if (!repo.hasApi) return;
    final profilesStorage = _ref.read(profilesStorageProvider);
    final changed = profilesStorage.networkParamsChanged;
    final has = await repo.hasCachedUsers();
    if (!changed && has) return;
    await updateData();
  }

  /// Force a fresh master-data download (the "Ažuriraj podatke" button).
  Future<void> updateData() async {
    final repo = _ref.read(masterDataRepositoryProvider);
    final profilesStorage = _ref.read(profilesStorageProvider);

    if (mounted) state = state.copyWith(syncing: true, clearError: true);

    // Switching venue / changed connection params invalidates the old cache.
    if (profilesStorage.networkParamsChanged) {
      await repo.clearAll();
    }

    final result = await repo.syncAll();
    if (result.isOk) {
      await profilesStorage.setNetworkParamsChanged(false);
    }

    final has = await repo.hasCachedUsers();
    if (!mounted) return;
    state = LoginUiState(
      syncing: false,
      hasUsers: has,
      error: result.status == SyncStatus.error ? result.message : null,
    );
  }
}

final loginControllerProvider =
    StateNotifierProvider.autoDispose<LoginController, LoginUiState>((ref) {
  return LoginController(ref);
});
