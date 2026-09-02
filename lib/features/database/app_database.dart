import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../cashregister/models/order_item.dart';
import 'converters.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// The local SQLite database (drift), replacing the reference client's Room
/// `IKasaDatabase`. Holds the cached master data (users, articles, groups,
/// tables, terraces, remarks) and the offline order queue.
///
/// Reference-data sync is **delete-all-then-insert** (see the `replace*`
/// methods); the order queue is driven by the `pending`/`sent` flags.
@DriftDatabase(
  tables: [
    Users,
    Articles,
    ArticleGroups,
    VenueTables,
    Terraces,
    Remarks,
    Orders,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Testing / DI hook so an in-memory database can be injected.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  // ── Users ────────────────────────────────────────────────────────────────
  Future<List<DbUser>> getAllUsers() => select(users).get();

  Future<DbUser?> getUserByCode(String code) =>
      (select(users)..where((u) => u.code.equals(code))).getSingleOrNull();

  Future<void> replaceUsers(List<UsersCompanion> rows) async {
    await transaction(() async {
      await delete(users).go();
      await batch((b) => b.insertAll(users, rows));
    });
  }

  // ── Articles ─────────────────────────────────────────────────────────────
  Future<List<DbArticle>> getAllArticles() => select(articles).get();

  Future<void> replaceArticles(List<ArticlesCompanion> rows) async {
    await transaction(() async {
      await delete(articles).go();
      await batch((b) => b.insertAll(articles, rows));
    });
  }

  // ── Article groups ───────────────────────────────────────────────────────
  Future<List<DbArticleGroup>> getAllGroups() => select(articleGroups).get();

  Future<void> replaceGroups(List<ArticleGroupsCompanion> rows) async {
    await transaction(() async {
      await delete(articleGroups).go();
      await batch((b) => b.insertAll(articleGroups, rows));
    });
  }

  // ── Tables ───────────────────────────────────────────────────────────────
  Future<List<DbVenueTable>> getAllTables() => select(venueTables).get();

  Future<void> replaceTables(List<VenueTablesCompanion> rows) async {
    await transaction(() async {
      await delete(venueTables).go();
      await batch((b) => b.insertAll(venueTables, rows));
    });
  }

  // ── Terraces ─────────────────────────────────────────────────────────────
  Future<List<DbTerrace>> getAllTerraces() => select(terraces).get();

  Future<void> replaceTerraces(List<TerracesCompanion> rows) async {
    await transaction(() async {
      await delete(terraces).go();
      await batch((b) => b.insertAll(terraces, rows));
    });
  }

  // ── Remarks ──────────────────────────────────────────────────────────────
  Future<List<DbRemark>> getAllRemarks() => select(remarks).get();

  Future<List<DbRemark>> getRemarksForItem(int itemId) =>
      (select(remarks)..where((r) => r.itemId.equals(itemId))).get();

  Future<void> replaceRemarks(List<RemarksCompanion> rows) async {
    await transaction(() async {
      await delete(remarks).go();
      await batch((b) => b.insertAll(remarks, rows));
    });
  }

  // ── Orders (offline queue) ───────────────────────────────────────────────
  Future<List<DbOrder>> getAllOrders() => (select(orders)
        ..orderBy([(o) => OrderingTerm.desc(o.orderTime)]))
      .get();

  Future<DbOrder?> getOrderById(int id) =>
      (select(orders)..where((o) => o.id.equals(id))).getSingleOrNull();

  /// A non-pending draft for this table+user, if one exists (used to continue
  /// an open order rather than starting a new one).
  ///
  /// Returns the most recent match. We deliberately do NOT use
  /// `getSingleOrNull()` here: if more than one open draft ever exists for the
  /// same table+user (which the save/back flow can produce), that call throws
  /// and wedges the New Order screen on an infinite spinner. Ordering by
  /// `orderTime` desc + `limit(1)` continues the latest draft and can't throw.
  Future<DbOrder?> findOpenOrder(int tableCode, String userCode) {
    return (select(orders)
          ..where((o) =>
              o.tableCode.equals(tableCode) &
              o.userCode.equals(userCode) &
              o.pending.equals(false))
          ..orderBy([(o) => OrderingTerm.desc(o.orderTime)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<List<DbOrder>> getNotPendingOrders() =>
      (select(orders)..where((o) => o.pending.equals(false))).get();

  /// The resend queue: finalized but not yet delivered.
  Future<List<DbOrder>> getPendingOrders() => (select(orders)
        ..where((o) => o.pending.equals(true) & o.sent.equals(false)))
      .get();

  Future<List<DbOrder>> getSentOrders() =>
      (select(orders)..where((o) => o.sent.equals(true))).get();

  /// Inserts (or replaces by id) an order, returning its row id.
  ///
  /// NOTE: for an update we return the order's own id rather than the value
  /// from `insertOnConflictUpdate`. SQLite does not update `last_insert_rowid()`
  /// on an `ON CONFLICT DO UPDATE`, so that call returns a stale/wrong id on the
  /// update path — which previously made Order Details load the wrong (missing)
  /// order.
  Future<int> upsertOrder(OrdersCompanion order) async {
    if (order.id.present) {
      await into(orders).insertOnConflictUpdate(order);
      return order.id.value;
    }
    return into(orders).insert(order);
  }

  Future<void> updateOrder(OrdersCompanion order) =>
      update(orders).replace(order);

  Future<void> deleteOrderById(int id) =>
      (delete(orders)..where((o) => o.id.equals(id))).go();

  Future<void> deleteAllOrders() => delete(orders).go();

  Future<void> deletePendingOrders() =>
      (delete(orders)..where((o) => o.pending.equals(true))).go();

  /// Wipes every cached master-data table (used when switching venue profile).
  /// Orders are cleared separately by the caller as appropriate.
  Future<void> clearAllMasterData() async {
    await transaction(() async {
      await delete(users).go();
      await delete(articles).go();
      await delete(articleGroups).go();
      await delete(venueTables).go();
      await delete(terraces).go();
      await delete(remarks).go();
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'orderman.db'));
    return NativeDatabase.createInBackground(file);
  });
}
