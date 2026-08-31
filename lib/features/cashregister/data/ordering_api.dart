import 'dart:convert';

import '../../shared/data/venue_api_client.dart';

/// Ordering + table-reservation endpoints on the venue server. Mirrors the
/// reference client's `OrderApi` and `ReservationApi`.
///
/// Endpoints (relative to `/api/v1/`):
///   POST postOrder                 — send an order (custom body, see below)
///   POST postTableReservation      — reserve a table  {userCode, tableCode}
///   POST postRemoveTableReservation— release a table  {tableCode}
class OrderingApi {
  const OrderingApi(this._client);

  final VenueApiClient _client;

  /// Sends [body], the hand-built non-standard JSON produced by
  /// `OrderRequest.toJsonString`. Returns true on a 2xx acknowledgement.
  Future<bool> postOrder(String body) async {
    final resp = await _client.postRaw('postOrder', body);
    return resp.statusCode >= 200 && resp.statusCode < 300;
  }

  /// Reserves [tableCode] for [userCode]. Reservation bodies use lowercase keys
  /// (default kotlinx serialization in the reference client).
  Future<bool> reserveTable(String userCode, int tableCode) async {
    final body = jsonEncode({'userCode': userCode, 'tableCode': tableCode});
    final resp = await _client.postRaw('postTableReservation', body);
    return resp.statusCode >= 200 && resp.statusCode < 300;
  }

  /// Releases the reservation on [tableCode].
  Future<bool> removeReservation(int tableCode) async {
    final body = jsonEncode({'tableCode': tableCode});
    final resp = await _client.postRaw('postRemoveTableReservation', body);
    return resp.statusCode >= 200 && resp.statusCode < 300;
  }
}
