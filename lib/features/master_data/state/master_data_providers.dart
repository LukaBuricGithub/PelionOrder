import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/state/database_provider.dart';
import '../../shared/services/connectivity_service.dart';
import '../../shared/state/venue_api_client_provider.dart';
import '../data/master_data_api.dart';
import '../data/master_data_repository.dart';

/// The master-data API bound to the current server profile, or null when no
/// profile is selected.
final masterDataApiProvider = Provider<MasterDataApi?>((ref) {
  final client = ref.watch(venueApiClientProvider);
  if (client == null) return null;
  return MasterDataApi(client);
});

/// The master-data repository (drift cache + optional server sync). Rebuilds
/// when the selected profile changes.
final masterDataRepositoryProvider = Provider<MasterDataRepository>((ref) {
  return MasterDataRepository(
    db: ref.watch(appDatabaseProvider),
    connectivity: ref.watch(connectivityServiceProvider),
    api: ref.watch(masterDataApiProvider),
  );
});
