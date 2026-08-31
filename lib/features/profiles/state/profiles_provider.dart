import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/state/shared_preferences_provider.dart';
import '../data/profiles_storage.dart';
import '../models/api_entry.dart';

final profilesStorageProvider = Provider<ProfilesStorage>((ref) {
  return ProfilesStorage(ref.watch(sharedPreferencesProvider));
});

/// Immutable snapshot of the server-profiles state: all saved profiles plus the
/// id of the currently-selected one.
@immutable
class ProfilesState {
  const ProfilesState({
    this.entries = const [],
    this.currentId,
  });

  final List<ApiEntry> entries;
  final int? currentId;

  /// The selected profile, or the first one, or null when none exist.
  ApiEntry? get current {
    if (entries.isEmpty) return null;
    for (final e in entries) {
      if (e.id == currentId) return e;
    }
    return entries.first;
  }

  ProfilesState copyWith({
    List<ApiEntry>? entries,
    int? currentId,
    bool clearCurrent = false,
  }) {
    return ProfilesState(
      entries: entries ?? this.entries,
      currentId: clearCurrent ? null : (currentId ?? this.currentId),
    );
  }
}

/// Manages the venue server profiles (add / edit / select / delete) and
/// persists them. Mirrors the reference client's Settings profile CRUD.
class ProfilesController extends StateNotifier<ProfilesState> {
  ProfilesController(this._storage) : super(const ProfilesState()) {
    _load();
  }

  final ProfilesStorage _storage;

  void _load() {
    final entries = _storage.loadEntries();
    final currentId = _storage.loadCurrentId();
    state = ProfilesState(entries: entries, currentId: currentId);
  }

  /// Adds a new profile (when [entry.id] is 0) or updates an existing one.
  /// Returns the persisted entry (with its assigned id).
  ///
  /// Single-profile invariant: the app allows only ONE server profile, so a
  /// "new" entry created while one already exists edits the existing profile
  /// instead of adding a second.
  Future<ApiEntry> save(ApiEntry entry) async {
    final isNew = entry.id == 0;
    final ApiEntry resolved;
    if (isNew && state.entries.isNotEmpty) {
      resolved = entry.copyWith(id: state.entries.first.id);
    } else if (isNew) {
      resolved = entry.copyWith(id: DateTime.now().millisecondsSinceEpoch);
    } else {
      resolved = entry;
    }

    final next = [...state.entries];
    final idx = next.indexWhere((e) => e.id == resolved.id);
    if (idx >= 0) {
      // If the address or key of the *selected* profile changed, the cached
      // master data may be stale — force a re-sync next time.
      final prev = next[idx];
      if (resolved.id == state.currentId &&
          (prev.ip != resolved.ip || prev.apiKey != resolved.apiKey)) {
        await _storage.setNetworkParamsChanged(true);
      }
      next[idx] = resolved;
    } else {
      next.add(resolved);
    }

    await _storage.saveEntries(next);

    // First profile added becomes the selected one automatically.
    final newCurrentId = state.currentId ?? resolved.id;
    await _storage.saveCurrentId(newCurrentId);

    state = state.copyWith(entries: next, currentId: newCurrentId);
    return resolved;
  }

  Future<void> delete(int id) async {
    final next = state.entries.where((e) => e.id != id).toList();
    await _storage.saveEntries(next);

    var currentId = state.currentId;
    if (currentId == id) {
      currentId = next.isEmpty ? null : next.first.id;
      await _storage.saveCurrentId(currentId);
      await _storage.setNetworkParamsChanged(true);
    }
    state = ProfilesState(entries: next, currentId: currentId);
  }

  /// Selects a different profile. Switching venues invalidates the cached
  /// master data, so the network-params-changed flag is set to trigger a
  /// re-sync (and a data wipe) on the next opportunity.
  Future<void> select(int id) async {
    if (id == state.currentId) return;
    await _storage.saveCurrentId(id);
    await _storage.setNetworkParamsChanged(true);
    state = state.copyWith(currentId: id);
  }
}

final profilesProvider =
    StateNotifierProvider<ProfilesController, ProfilesState>((ref) {
  return ProfilesController(ref.watch(profilesStorageProvider));
});

/// Convenience selector for the currently-active venue profile. Every venue
/// API call reads this to know which server to talk to and which key to send.
final currentApiEntryProvider = Provider<ApiEntry?>((ref) {
  return ref.watch(profilesProvider).current;
});
