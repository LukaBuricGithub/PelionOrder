import 'dart:convert';

import '../../shared/data/venue_api_client.dart';
import '../models/article.dart';
import '../models/article_group.dart';
import '../models/branch.dart';
import '../models/ping_response.dart';
import '../models/remark.dart';
import '../models/table_detail.dart';
import '../models/terrace.dart';
import '../models/user.dart';
import '../models/venue_table.dart';

/// Talks to the venue server's master-data / sync endpoints. Mirrors the
/// reference client's `UserApi`, `TerraceApi`, `TableApi`, `GroupApi`,
/// `ItemApi`, `RemarkApi`, `BranchApi`, `PingApi`.
///
/// Endpoints (relative to `/api/v1/`):
///   GET  ping             — health check / venue name (`pingAndUpdateData`)
///   GET  userList         — staff/users
///   GET  teraceList       — terraces/zones (note server misspelling)
///   GET  tableList        — tables
///   GET  tableDetail      — one table's current bill (?TableCode=)
///   GET  touchGroupList   — article groups
///   GET  touchItemList    — articles
///   GET  remarkList       — predefined remarks
///   GET  branchList       — branches (traffic filter)
class MasterDataApi {
  const MasterDataApi(this._client);

  final VenueApiClient _client;

  static List<Map<String, dynamic>> _asMaps(List<dynamic> list) => list
      .whereType<Map>()
      .map((m) => Map<String, dynamic>.from(m))
      .toList(growable: false);

  /// Plain online check — true when the server answers 2xx.
  Future<bool> ping() async {
    final resp = await _client.getRaw('ping');
    return resp.statusCode >= 200 && resp.statusCode < 300;
  }

  /// Ping variant that also reads the venue/business name from the response.
  Future<PingResponse?> pingAndReadName() async {
    final list = await _client.getList('ping');
    final maps = _asMaps(list);
    if (maps.isEmpty) return null;
    return PingResponse.fromRemoteJson(maps.first);
  }

  /// Single heartbeat call: whether the server is reachable (2xx) plus the
  /// venue name when the body carries it. Used by the online-status heartbeat
  /// so one request answers both questions.
  Future<({bool online, String? name})> pingStatusAndName() async {
    final resp = await _client.getRaw('ping');
    final online = resp.statusCode >= 200 && resp.statusCode < 300;
    String? name;
    if (online && resp.body.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
          name = PingResponse.fromRemoteJson(
                  Map<String, dynamic>.from(decoded.first as Map))
              .businessName;
        }
      } catch (_) {
        // Body wasn't the list shape — still online, just no name.
      }
    }
    return (online: online, name: name);
  }

  Future<List<User>> fetchUsers() async {
    final list = await _client.getList('userList');
    return _asMaps(list).map(User.fromRemoteJson).toList(growable: false);
  }

  Future<List<Terrace>> fetchTerraces() async {
    final list = await _client.getList('teraceList');
    return _asMaps(list).map(Terrace.fromRemoteJson).toList(growable: false);
  }

  Future<List<VenueTable>> fetchTables() async {
    final list = await _client.getList('tableList');
    return _asMaps(list)
        .map(VenueTable.fromRemoteJson)
        .toList(growable: false);
  }

  Future<List<TableDetail>> fetchTableDetail(int tableCode) async {
    final list = await _client.getList('tableDetail', {'TableCode': tableCode});
    return _asMaps(list)
        .map(TableDetail.fromRemoteJson)
        .toList(growable: false);
  }

  Future<List<ArticleGroup>> fetchGroups() async {
    final list = await _client.getList('touchGroupList');
    return _asMaps(list)
        .map(ArticleGroup.fromRemoteJson)
        .toList(growable: false);
  }

  Future<List<Article>> fetchArticles() async {
    final list = await _client.getList('touchItemList');
    return _asMaps(list).map(Article.fromRemoteJson).toList(growable: false);
  }

  Future<List<Remark>> fetchRemarks() async {
    final list = await _client.getList('remarkList');
    return _asMaps(list).map(Remark.fromRemoteJson).toList(growable: false);
  }

  Future<List<Branch>> fetchBranches() async {
    final list = await _client.getList('branchList');
    return _asMaps(list).map(Branch.fromRemoteJson).toList(growable: false);
  }
}
