import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../master_data/models/table_detail.dart';
import '../../master_data/models/terrace.dart';
import '../../master_data/models/venue_table.dart';
import '../../master_data/state/master_data_providers.dart';
import '../../shared/data/api_exception.dart';

// NOTE: the offline order queue (order repository, ordering API and the
// pending-orders providers) lived here until ordering moved to MQTT. Orders are
// now published straight to the kasa — see features/mqtt — so nothing writes to
// the local queue any more and all of it was removed. What remains below serves
// the read-only "Pregled stolova" screens.

/// Cached terraces + tables for the read-only Tables Overview.
final tablesOverviewProvider = FutureProvider.autoDispose<
    (List<Terrace>, List<VenueTable>)>((ref) async {
  final master = ref.watch(masterDataRepositoryProvider);
  final terraces = await master.cachedTerraces();
  final tables = await master.cachedTables();
  return (terraces, tables);
});

/// A table's current server-side bill (aggregated per item). Requires a
/// connection — throws when offline / no profile.
final tableDetailProvider =
    FutureProvider.autoDispose.family<List<TableDetail>, int>(
        (ref, tableCode) async {
  final api = ref.watch(masterDataApiProvider);
  if (api == null) {
    throw const NoConnectionException('Nije odabran profil.');
  }
  return api.fetchTableDetail(tableCode);
});
