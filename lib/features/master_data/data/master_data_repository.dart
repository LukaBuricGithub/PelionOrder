import 'package:drift/drift.dart' show Value;

import '../../database/app_database.dart';
import '../../shared/data/api_exception.dart';
import '../../shared/services/connectivity_service.dart';
import '../models/article.dart';
import '../models/article_group.dart';
import '../models/remark.dart';
import '../models/terrace.dart';
import '../models/user.dart';
import '../models/venue_table.dart';
import 'master_data_api.dart';

/// Outcome of a master-data sync attempt.
enum SyncStatus { ok, offline, error }

class SyncResult {
  const SyncResult(this.status, [this.message]);
  final SyncStatus status;
  final String? message;

  bool get isOk => status == SyncStatus.ok;
}

/// Coordinates the venue master data between the server and the local drift
/// cache. Sync is **delete-all-then-insert**; reads fall back to the cache when
/// offline (offline-first), mirroring the reference client's reference-data
/// repositories + `LoginViewModel.fetchData()`.
class MasterDataRepository {
  MasterDataRepository({
    required AppDatabase db,
    required ConnectivityService connectivity,
    MasterDataApi? api,
  })  : _db = db,
        _connectivity = connectivity,
        _api = api;

  final AppDatabase _db;
  final ConnectivityService _connectivity;

  /// Null when no server profile is selected — the app then runs cache-only.
  final MasterDataApi? _api;

  // In-memory cache of the (static) menu data, so navigating between screens
  // doesn't re-query SQLite and re-map the whole list every time (which caused
  // navigation lag into New Order / Order Details). Reset on sync / clear — and
  // naturally on a profile change, which recreates this repository.
  List<Article>? _articlesCache;
  List<ArticleGroup>? _groupsCache;
  List<Remark>? _remarksCache;

  bool get hasApi => _api != null;

  // ── Reads (cache) ──────────────────────────────────────────────────────────
  Future<bool> hasCachedUsers() async => (await _db.getAllUsers()).isNotEmpty;

  Future<List<User>> cachedUsers() async =>
      (await _db.getAllUsers()).map(_userFromDb).toList(growable: false);

  Future<List<Terrace>> cachedTerraces() async =>
      (await _db.getAllTerraces()).map(_terraceFromDb).toList(growable: false);

  Future<List<VenueTable>> cachedTables() async =>
      (await _db.getAllTables()).map(_tableFromDb).toList(growable: false);

  Future<List<ArticleGroup>> cachedGroups() async => _groupsCache ??=
      (await _db.getAllGroups()).map(_groupFromDb).toList(growable: false);

  Future<List<Article>> cachedArticles() async => _articlesCache ??=
      (await _db.getAllArticles()).map(_articleFromDb).toList(growable: false);

  Future<List<Remark>> cachedRemarksForItem(int itemId) async =>
      (await _db.getRemarksForItem(itemId))
          .map(_remarkFromDb)
          .toList(growable: false);

  Future<List<Remark>> cachedRemarks() async => _remarksCache ??=
      (await _db.getAllRemarks()).map(_remarkFromDb).toList(growable: false);

  /// Finds a staff member by PIN from the cached users (login is PIN-based and
  /// works fully offline).
  Future<User?> findUserByPin(int pin) async {
    final users = await cachedUsers();
    for (final u in users) {
      if (u.pin == pin) return u;
    }
    return null;
  }

  Future<User?> userByCode(String code) async {
    // Match on the trimmed code (cached rows may carry server padding) so a
    // saved session restores regardless of padding.
    final target = code.trim();
    for (final u in await cachedUsers()) {
      if (u.code == target) return u;
    }
    return null;
  }

  // ── Sync ────────────────────────────────────────────────────────────────────
  /// Downloads all master data and replaces the local cache. Sequenced the same
  /// way as the reference client: users → terraces → tables → groups → items →
  /// remarks. Returns [SyncStatus.offline] (no-op) when there is no connection
  /// or no profile, so callers keep working from the cache.
  Future<SyncResult> syncAll() async {
    final api = _api;
    if (api == null) {
      return const SyncResult(SyncStatus.offline, 'Nije odabran profil.');
    }
    if (!await _connectivity.hasConnection()) {
      return const SyncResult(SyncStatus.offline);
    }

    try {
      final users = await api.fetchUsers();
      final terraces = await api.fetchTerraces();
      final tables = await api.fetchTables();
      final groups = await api.fetchGroups();
      final articles = await api.fetchArticles();
      final remarks = await api.fetchRemarks();

      await _db.replaceUsers(users.map(_userToCompanion).toList());
      await _db.replaceTerraces(terraces.map(_terraceToCompanion).toList());
      await _db.replaceTables(tables.map(_tableToCompanion).toList());
      await _db.replaceGroups(groups.map(_groupToCompanion).toList());
      await _db.replaceArticles(articles.map(_articleToCompanion).toList());
      await _db.replaceRemarks(remarks.map(_remarkToCompanion).toList());

      _invalidateMenuCache();
      return const SyncResult(SyncStatus.ok);
    } on NoConnectionException {
      return const SyncResult(SyncStatus.offline);
    } catch (e) {
      return SyncResult(SyncStatus.error, e.toString());
    }
  }

  /// Re-fetches just the tables and replaces the cache. Used by the Table
  /// Select screen's periodic (30s) refresh so table ownership stays current.
  /// No-op when offline or without a profile.
  Future<void> refreshTables() async {
    final api = _api;
    if (api == null) return;
    if (!await _connectivity.hasConnection()) return;
    try {
      final tables = await api.fetchTables();
      await _db.replaceTables(tables.map(_tableToCompanion).toList());
    } catch (_) {
      // Keep the existing cache on any failure.
    }
  }

  /// Wipes cached master data AND any queued orders — used when switching venue
  /// profile (`LoginViewModel.clearData()`).
  Future<void> clearAll() async {
    await _db.clearAllMasterData();
    await _db.deleteAllOrders();
    _invalidateMenuCache();
  }

  /// Drops the in-memory menu cache so the next read reloads from the DB.
  void _invalidateMenuCache() {
    _articlesCache = null;
    _groupsCache = null;
    _remarksCache = null;
  }

  // ── Mappers: domain → drift companion ───────────────────────────────────────
  static UsersCompanion _userToCompanion(User u) => UsersCompanion.insert(
        code: u.code,
        username: Value(u.username),
        pin: Value(u.pin),
        changeQuantityRight: Value(u.changeQuantityRight),
        allTablesOpenRight: Value(u.allTablesOpenRight),
        deleteRight: Value(u.deleteRight),
        superuser: Value(u.superuser),
      );

  static TerracesCompanion _terraceToCompanion(Terrace t) =>
      TerracesCompanion.insert(
        code: t.code,
        tableFrom: Value(t.tableFrom),
        tableTo: Value(t.tableTo),
      );

  static VenueTablesCompanion _tableToCompanion(VenueTable t) =>
      VenueTablesCompanion.insert(
        code: Value(t.code),
        name: Value(t.name),
        userCode: Value(t.userCode),
        itemCount: Value(t.itemCount),
      );

  static ArticleGroupsCompanion _groupToCompanion(ArticleGroup g) =>
      ArticleGroupsCompanion.insert(
        code: g.code,
        name: Value(g.name),
        orderNo: Value(g.order),
      );

  static ArticlesCompanion _articleToCompanion(Article a) =>
      ArticlesCompanion.insert(
        code: Value(a.code),
        name: Value(a.name),
        price: Value(a.price),
        unit: Value(a.unit),
        groupCode: Value(a.groupCode),
        orderNo: Value(a.order),
      );

  static RemarksCompanion _remarkToCompanion(Remark r) =>
      RemarksCompanion.insert(
        name: Value(r.name),
        itemId: Value(r.itemId),
      );

  // ── Mappers: drift row → domain ─────────────────────────────────────────────
  // NOTE: the venue server pads CHAR columns with trailing spaces, and to
  // *different* widths across endpoints (e.g. group `TOUCHGROUPCODE` is padded
  // wider than the item's), so codes must be trimmed before any equality check
  // (article→group matching, table ownership, etc.). We trim here so even data
  // cached before this fix works without a re-sync.
  static User _userFromDb(DbUser r) => User(
        code: r.code.trim(),
        username: r.username.trim(),
        pin: r.pin,
        changeQuantityRight: r.changeQuantityRight,
        allTablesOpenRight: r.allTablesOpenRight,
        deleteRight: r.deleteRight,
        superuser: r.superuser,
      );

  static Terrace _terraceFromDb(DbTerrace r) =>
      Terrace(code: r.code.trim(), tableFrom: r.tableFrom, tableTo: r.tableTo);

  static VenueTable _tableFromDb(DbVenueTable r) => VenueTable(
        code: r.code,
        name: r.name.trim(),
        userCode: r.userCode.trim(),
        itemCount: r.itemCount,
      );

  static ArticleGroup _groupFromDb(DbArticleGroup r) =>
      ArticleGroup(code: r.code.trim(), order: r.orderNo, name: r.name.trim());

  static Article _articleFromDb(DbArticle r) => Article(
        code: r.code,
        name: r.name.trim(),
        price: r.price,
        unit: r.unit.trim(),
        groupCode: r.groupCode.trim(),
        order: r.orderNo,
      );

  static Remark _remarkFromDb(DbRemark r) =>
      Remark(id: r.id, name: r.name.trim(), itemId: r.itemId);
}
