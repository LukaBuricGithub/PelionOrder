import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/state/database_provider.dart';
import '../../master_data/models/table_detail.dart';
import '../../master_data/models/terrace.dart';
import '../../master_data/models/venue_table.dart';
import '../../master_data/state/master_data_providers.dart';
import '../../settings/state/settings_provider.dart';
import '../../shared/data/api_exception.dart';
import '../../shared/services/connectivity_service.dart';
import '../../shared/state/venue_api_client_provider.dart';
import '../data/order_repository.dart';
import '../data/ordering_api.dart';
import '../models/order.dart';

/// Ordering/reservation API bound to the current server profile, or null when
/// no profile is configured (the app then queues orders offline).
final orderingApiProvider = Provider<OrderingApi?>((ref) {
  final client = ref.watch(venueApiClientProvider);
  return client == null ? null : OrderingApi(client);
});

/// The order repository (offline queue + send/auto-resend + reservations).
/// Rebuilds when the profile or the group-articles setting changes.
final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  return OrderRepository(
    db: ref.watch(appDatabaseProvider),
    connectivity: ref.watch(connectivityServiceProvider),
    shouldGroupArticles: ref.watch(settingsProvider).shouldGroupArticles,
    api: ref.watch(orderingApiProvider),
  );
});

/// Number of pending (finalized-but-not-yet-sent) orders in the offline queue.
/// Invalidate after sending/auto-resending to refresh the badge.
final pendingOrdersCountProvider =
    FutureProvider.autoDispose<int>((ref) async {
  return ref.watch(orderRepositoryProvider).pendingCount();
});

/// The pending (unsent) orders queue, for the Orders list screen.
final pendingOrdersListProvider =
    FutureProvider.autoDispose<List<Order>>((ref) async {
  return ref.watch(orderRepositoryProvider).pendingOrders();
});

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
