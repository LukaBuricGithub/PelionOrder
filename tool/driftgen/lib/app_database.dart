import 'package:drift/drift.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// Codegen-only mirror of the real app_database.dart. The @DriftDatabase
/// annotation, table list and DAO method signatures are IDENTICAL to the real
/// one, so the generated app_database.g.dart is byte-identical and portable
/// back to the app. The runtime connection (_openConnection / path_provider)
/// is intentionally omitted here — drift does not generate from it.
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
  AppDatabase(super.executor);

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

  Future<DbOrder?> findOpenOrder(int tableCode, String userCode) {
    return (select(orders)
          ..where((o) =>
              o.tableCode.equals(tableCode) &
              o.userCode.equals(userCode) &
              o.pending.equals(false)))
        .getSingleOrNull();
  }

  Future<List<DbOrder>> getNotPendingOrders() =>
      (select(orders)..where((o) => o.pending.equals(false))).get();

  Future<List<DbOrder>> getPendingOrders() => (select(orders)
        ..where((o) => o.pending.equals(true) & o.sent.equals(false)))
      .get();

  Future<List<DbOrder>> getSentOrders() =>
      (select(orders)..where((o) => o.sent.equals(true))).get();

  Future<int> upsertOrder(OrdersCompanion order) =>
      into(orders).insertOnConflictUpdate(order);

  Future<void> updateOrder(OrdersCompanion order) =>
      update(orders).replace(order);

  Future<void> deleteOrderById(int id) =>
      (delete(orders)..where((o) => o.id.equals(id))).go();

  Future<void> deleteAllOrders() => delete(orders).go();

  Future<void> deletePendingOrders() =>
      (delete(orders)..where((o) => o.pending.equals(true))).go();

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
