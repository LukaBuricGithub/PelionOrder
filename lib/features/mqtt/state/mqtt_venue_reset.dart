import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_controller.dart';
import '../../master_data/state/master_data_providers.dart';
import '../../shared/state/shared_preferences_provider.dart';
import '../data/mqtt_service.dart';
import 'mqtt_menu_provider.dart';
import 'mqtt_orders_provider.dart';
import 'mqtt_outbox_provider.dart';
import 'mqtt_pending_transfers_provider.dart';
import 'mqtt_table_lock_keeper.dart';
import 'mqtt_tables_provider.dart';
import 'mqtt_users_provider.dart';

/// Forgets everything this phone knows about the venue it was set up for —
/// for a QR code from ANOTHER venue (a different licence), so nothing of the
/// old one is shown, used to sign in or sent to the new kasa:
///
/// * the menu (groups, articles, napomene), the staff list, the tables and
///   their state — saved copies, their versions and the connection's own
///   last-received copies;
/// * unsent items on tables and "Neposlane narudžbe" (they can't go to a
///   different kasa);
/// * the signed-in waiter, who belongs to the old staff list;
/// * the old local database (master data from the former REST server).
///
/// Everything is rebuilt empty and fills in from the new venue as soon as the
/// phone connects to it.
Future<void> forgetVenueData(WidgetRef ref) async {
  debugPrint('MQTT ▸ code for another venue → forgetting the previous data');

  // In memory first, so nothing below can re-apply the old venue's payloads.
  MqttTableLockKeeper.forgetVenue();
  MqttService.instance.forgetVenueData();

  // Saved copies.
  final prefs = ref.read(sharedPreferencesProvider);
  for (final key in [
    ...mqttMenuStorageKeys,
    ...mqttUsersStorageKeys,
    ...mqttTablesStorageKeys,
    ...MqttOutboxNotifier.storageKeys,
  ]) {
    await prefs.remove(key);
  }

  // The signed-in waiter (and the saved code that would restore them).
  await ref.read(authControllerProvider).logout();

  // Rebuilt from the now-empty storage, so each starts empty. The outbox
  // holds the in-transit tracker it was created with, so both go together.
  ref
    ..invalidate(mqttMenuProvider)
    ..invalidate(mqttUsersProvider)
    ..invalidate(mqttTablesProvider)
    ..invalidate(mqttOccupiedProvider)
    ..invalidate(mqttLockedProvider)
    ..invalidate(mqttOrdersProvider)
    ..invalidate(mqttPendingTransfersProvider)
    ..invalidate(mqttOutboxProvider);
  // "Neposlane narudžbe" runs from launch (see main.dart) so it can apply
  // the kasa's confirmations at any time — start the fresh one now as well.
  ref.read(mqttOutboxProvider);

  // The former REST server's master data, kept in a local database.
  try {
    await ref.read(masterDataRepositoryProvider).clearAll();
  } catch (e) {
    debugPrint('MQTT ▸ clearing the local database failed: $e');
  }
}
