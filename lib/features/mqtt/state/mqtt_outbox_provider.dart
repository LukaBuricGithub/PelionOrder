import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/state/shared_preferences_provider.dart';
import '../data/mqtt_order_sender.dart';
import '../data/mqtt_service.dart';
import 'mqtt_cart.dart';
import 'mqtt_pending_transfers_provider.dart';

/// Where an order in "Neposlane narudžbe" stands.
enum MqttOutboxStatus {
  /// No answer from the kasa yet — not sent, or sent and not confirmed. It may
  /// already be booked (a stored copy on the broker, a lost reply), so it is
  /// only ever resent as itself, automatically.
  waiting,

  /// The kasa refused it. Final for its msg_id: nothing was booked, and only a
  /// resend as a NEW order — the waiter's decision — can book it.
  rejected,

  /// The kasa received it too late. Final, exactly like [rejected].
  expired,
}

/// One order frozen at the moment the waiter pressed "Pošalji".
///
/// Frozen means it can never be edited: an edit would have to go out under a
/// new msg_id, and if the original then still arrived — held by the broker,
/// or booked with its reply lost — the kasa would book the items twice. So the
/// order is kept exactly as sent until the kasa gives a definite answer.
class MqttOutboxOrder {
  const MqttOutboxOrder({
    required this.msgId,
    required this.stol,
    required this.cuser,
    required this.payload,
    required this.lines,
    required this.sentLineCount,
    required this.createdAt,
    required this.status,
    this.reason = '',
    this.published = false,
  });

  final String msgId;
  final int stol;

  /// The waiter who ordered — decides who may see and act on it.
  final String cuser;

  /// The exact message, built once. Every resend is byte-for-byte this, so the
  /// kasa's expiry keeps counting from when the waiter actually ordered.
  final String payload;

  /// The lines as the waiter built them, for display and for a resend as new.
  final List<MqttCartLine> lines;

  /// How many `stavke` the payload carries (after grouping).
  final int sentLineCount;
  final DateTime createdAt;
  final MqttOutboxStatus status;

  /// The kasa's reason for a refusal (from its FIRST answer).
  final String reason;

  /// Whether the order has been published at least once. Until then deleting
  /// it carries no risk of it still being booked.
  final bool published;

  /// Refused or expired: waits for the waiter to resend it as new or delete it.
  bool get needsWaiter => status != MqttOutboxStatus.waiting;

  MqttOutboxOrder copyWith({
    MqttOutboxStatus? status,
    String? reason,
    bool? published,
  }) => MqttOutboxOrder(
    msgId: msgId,
    stol: stol,
    cuser: cuser,
    payload: payload,
    lines: lines,
    sentLineCount: sentLineCount,
    createdAt: createdAt,
    status: status ?? this.status,
    reason: reason ?? this.reason,
    published: published ?? this.published,
  );

  Map<String, dynamic> toJson() => {
    'msg_id': msgId,
    'stol': stol,
    'cuser': cuser,
    'payload': payload,
    'lines': [
      for (final l in lines)
        {
          'code': l.code,
          'qty': l.qty,
          'remarks': l.remarkCodes,
          'notes': l.customNotes,
        },
    ],
    'sent_lines': sentLineCount,
    'created': createdAt.millisecondsSinceEpoch,
    'status': status.name,
    'reason': reason,
    'published': published,
  };

  /// Parses a saved order, or null when it is unusable.
  static MqttOutboxOrder? tryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    try {
      final lines = <MqttCartLine>[
        for (final l in (raw['lines'] as List? ?? const []))
          if (l is Map<String, dynamic>)
            MqttCartLine((l['code'] as num).toInt())
              ..qty = (l['qty'] as num).toDouble()
              ..remarkCodes.addAll([
                for (final c in (l['remarks'] as List? ?? const []))
                  c.toString(),
              ])
              ..customNotes.addAll([
                for (final n in (l['notes'] as List? ?? const [])) n.toString(),
              ]),
      ];
      final msgId = (raw['msg_id'] ?? '').toString();
      final payload = (raw['payload'] ?? '').toString();
      if (msgId.isEmpty || payload.isEmpty || lines.isEmpty) return null;
      return MqttOutboxOrder(
        msgId: msgId,
        stol: (raw['stol'] as num).toInt(),
        cuser: (raw['cuser'] ?? '').toString(),
        payload: payload,
        lines: lines,
        sentLineCount: (raw['sent_lines'] as num?)?.toInt() ?? lines.length,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (raw['created'] as num?)?.toInt() ?? 0,
        ),
        status: MqttOutboxStatus.values.firstWhere(
          (s) => s.name == raw['status'],
          orElse: () => MqttOutboxStatus.waiting,
        ),
        reason: (raw['reason'] ?? '').toString(),
        published: raw['published'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Whether a waiter may see and act on [order]: their own orders, or every
/// order when they hold pravo 008.
bool mqttOutboxVisibleTo(
  MqttOutboxOrder order, {
  required String? cuser,
  required bool allTables,
}) => allTables || order.cuser == cuser;

/// "Neposlane narudžbe": every order the kasa hasn't definitely answered, kept
/// on the device until it has.
///
/// * Pressing "Pošalji" FREEZES the order here (and saves it) before it is
///   published, so it survives leaving the screen and closing the app.
/// * A waiting order is resent automatically — on every round while the phone
///   is connected — always as the identical message. By the kasa's msg_id
///   check that can never book it twice.
/// * A definite answer settles it: ok hands it to the transfer watch (↑ on the
///   floor plan), a refusal or expiry leaves it here for the waiter.
///
/// The screen that submitted an order handles that first answer itself (it
/// shows ✓ or the refusal); it CLAIMS the order while it waits. If the screen
/// goes away first, the outbox finishes the job — see [release].
class MqttOutboxNotifier extends StateNotifier<List<MqttOutboxOrder>> {
  MqttOutboxNotifier(this._prefs, this._transfers) : super(const []) {
    state = _load();
    _timer = Timer.periodic(_roundInterval, (_) => _pump());
    // Orders left over from before a restart go out as soon as the connection
    // is up, not only on the first periodic round.
    _firstRound = Timer(const Duration(seconds: 5), _pump);
  }

  static const _key = 'mqtt_outbox_v1';

  /// Pause between automatic resend rounds.
  static const _roundInterval = Duration(seconds: 20);

  final SharedPreferences _prefs;
  final MqttPendingTransfersNotifier _transfers;
  Timer? _timer;
  Timer? _firstRound;
  bool _pumping = false;

  /// Orders with a send in progress right now.
  final _inFlight = <String>{};

  /// Orders whose first answer a screen is waiting to handle itself.
  final _claimed = <String>{};

  /// Answers that arrived for a claimed order, until the screen takes them.
  final _parked = <String, MqttSendResult>{};

  // ── Called by the order screen ────────────────────────────────────────────

  /// Freezes [lines] into a new order for [stol] and saves it, claimed by the
  /// caller. Nothing is published yet — see [sendNow]. Returns the problem
  /// instead when the order can't be built (then nothing is saved).
  ({MqttOutboxOrder? order, MqttSendResult? problem}) freeze({
    required int stol,
    required String cuser,
    required List<MqttCartLine> lines,
    required bool groupArticles,
  }) {
    final problem = MqttOrderSender.instance.precheck(
      cuser: cuser,
      lines: lines,
    );
    if (problem != null) return (order: null, problem: problem);
    final order = _build(
      stol: stol,
      cuser: cuser,
      lines: lines,
      groupArticles: groupArticles,
    );
    _claimed.add(order.msgId);
    state = [...state, order];
    _save();
    return (order: order, problem: null);
  }

  /// The caller's own attempt at [order] — a short one: if the kasa doesn't
  /// answer in time, the automatic rounds carry on with the same message.
  Future<MqttSendResult> sendNow(MqttOutboxOrder order, {int attempts = 2}) =>
      _attempt(order, attempts);

  /// The claiming screen handled the answer itself (✓, or a refusal it gave
  /// back to the waiter as an editable draft): drop the order.
  void finish(String msgId) {
    _claimed.remove(msgId);
    _parked.remove(msgId);
    _removeIds({msgId});
  }

  /// The claiming screen is done waiting — no answer yet, or it closed. From
  /// here the outbox owns the order: an answer that arrived meanwhile is
  /// applied now, and a waiting order joins the automatic rounds.
  void release(String msgId) {
    if (!_claimed.remove(msgId)) return;
    final parked = _parked.remove(msgId);
    if (parked != null) _apply(msgId, parked);
  }

  // ── Called by "Neposlane narudžbe" ────────────────────────────────────────

  /// Tries every waiting order now instead of at the next round.
  Future<void> retryNow() => _pump();

  /// Sends the refused / expired orders of [stol] that [allowed] permits again,
  /// each as a NEW order (new msg_id, fresh time). The old ids are final on the
  /// kasa and booked nothing, so this cannot duplicate.
  void resendAsNew(
    int stol, {
    required bool Function(MqttOutboxOrder order) allowed,
    required bool groupArticles,
  }) {
    var changed = false;
    final next = <MqttOutboxOrder>[];
    for (final o in state) {
      final eligible =
          o.stol == stol &&
          o.needsWaiter &&
          allowed(o) &&
          MqttOrderSender.instance.precheck(cuser: o.cuser, lines: o.lines) ==
              null;
      if (eligible) {
        changed = true;
        next.add(
          _build(
            stol: o.stol,
            cuser: o.cuser,
            lines: o.lines,
            groupArticles: groupArticles,
          ),
        );
      } else {
        next.add(o);
      }
    }
    if (!changed) return;
    state = next;
    _save();
    unawaited(_pump());
  }

  /// Deletes orders. For a waiting order that was already published this does
  /// NOT unsend it — the caller must have warned the waiter.
  void remove(Set<String> msgIds) {
    for (final id in msgIds) {
      _claimed.remove(id);
      _parked.remove(id);
    }
    _removeIds(msgIds);
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  MqttOutboxOrder _build({
    required int stol,
    required String cuser,
    required List<MqttCartLine> lines,
    required bool groupArticles,
  }) {
    final msgId = newMsgId();
    final copies = [for (final l in lines) l.copy()];
    final sent = groupArticles ? groupCartLines(copies) : copies;
    return MqttOutboxOrder(
      msgId: msgId,
      stol: stol,
      cuser: cuser,
      payload: buildOrderJson(
        msgId: msgId,
        // Guaranteed by precheck().
        od: MqttService.instance.clientId!,
        stol: stol,
        cuser: cuser,
        lines: sent,
      ),
      lines: copies,
      sentLineCount: sent.length,
      createdAt: DateTime.now(),
      status: MqttOutboxStatus.waiting,
    );
  }

  Future<MqttSendResult> _attempt(MqttOutboxOrder order, int attempts) async {
    _inFlight.add(order.msgId);
    try {
      if (MqttService.instance.isConnected) _markPublished(order.msgId);
      final result = await MqttOrderSender.instance.sendPayload(
        msgId: order.msgId,
        payload: order.payload,
        attempts: attempts,
      );
      if (mounted) _settle(order.msgId, result);
      return result;
    } finally {
      _inFlight.remove(order.msgId);
    }
  }

  /// One automatic round: every waiting order that nobody else is handling,
  /// oldest first, one attempt each.
  Future<void> _pump() async {
    if (_pumping || !mounted || !MqttService.instance.isConnected) return;
    _pumping = true;
    try {
      for (final order in [...state]) {
        if (!mounted || !MqttService.instance.isConnected) return;
        final current = _find(order.msgId);
        if (current == null || current.status != MqttOutboxStatus.waiting) {
          continue;
        }
        if (_claimed.contains(order.msgId) || _inFlight.contains(order.msgId)) {
          continue;
        }
        await _attempt(current, 1);
      }
    } finally {
      _pumping = false;
    }
  }

  void _settle(String msgId, MqttSendResult result) {
    // No definite answer: the order stays waiting for the next round.
    if (result.outcome == MqttSendOutcome.kasaNedostupna ||
        result.outcome == MqttSendOutcome.neispravno) {
      return;
    }
    if (_claimed.contains(msgId)) {
      _parked[msgId] = result;
      return;
    }
    _apply(msgId, result);
  }

  void _apply(String msgId, MqttSendResult result) {
    final order = _find(msgId);
    if (order == null) return;
    switch (result.outcome) {
      case MqttSendOutcome.ok:
        debugPrint(
          'MQTT ▸ outbox: ${order.msgId} accepted (stol ${order.stol})',
        );
        _removeIds({msgId});
        _transfers.watchTable(
          order.stol,
          MqttInTransitOrder(
            msgId: order.msgId,
            lines: order.lines,
            sentLineCount: order.sentLineCount,
          ),
        );
      case MqttSendOutcome.odbijeno:
      case MqttSendOutcome.istekla:
        _update(
          msgId,
          (o) => o.copyWith(
            status: result.outcome == MqttSendOutcome.istekla
                ? MqttOutboxStatus.expired
                : MqttOutboxStatus.rejected,
            // A replayed refusal carries no reason — keep the first one.
            reason: result.repeated && o.reason.isNotEmpty
                ? o.reason
                : result.message,
          ),
        );
      case MqttSendOutcome.kasaNedostupna:
      case MqttSendOutcome.neispravno:
        break;
    }
  }

  MqttOutboxOrder? _find(String msgId) {
    for (final o in state) {
      if (o.msgId == msgId) return o;
    }
    return null;
  }

  void _markPublished(String msgId) {
    final o = _find(msgId);
    if (o == null || o.published) return;
    _update(msgId, (o) => o.copyWith(published: true));
  }

  void _update(String msgId, MqttOutboxOrder Function(MqttOutboxOrder) change) {
    state = [for (final o in state) o.msgId == msgId ? change(o) : o];
    _save();
  }

  void _removeIds(Set<String> msgIds) {
    if (!state.any((o) => msgIds.contains(o.msgId))) return;
    state = [
      for (final o in state)
        if (!msgIds.contains(o.msgId)) o,
    ];
    _save();
  }

  List<MqttOutboxOrder> _load() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [for (final e in decoded) ?MqttOutboxOrder.tryFromJson(e)];
    } catch (e) {
      debugPrint('MQTT outbox load failed: $e');
      return const [];
    }
  }

  void _save() {
    _prefs.setString(_key, jsonEncode([for (final o in state) o.toJson()]));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _firstRound?.cancel();
    super.dispose();
  }
}

final mqttOutboxProvider =
    StateNotifierProvider<MqttOutboxNotifier, List<MqttOutboxOrder>>((ref) {
      return MqttOutboxNotifier(
        ref.watch(sharedPreferencesProvider),
        ref.read(mqttPendingTransfersProvider.notifier),
      );
    });
