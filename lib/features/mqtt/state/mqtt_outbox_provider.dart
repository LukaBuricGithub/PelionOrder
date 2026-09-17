import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../settings/state/settings_provider.dart';
import '../../shared/state/shared_preferences_provider.dart';
import '../data/mqtt_order_sender.dart';
import '../data/mqtt_service.dart';
import '../models/mqtt_order_reply.dart';
import 'mqtt_cart.dart';
import 'mqtt_config_provider.dart';
import 'mqtt_pending_transfers_provider.dart';
import 'mqtt_send_gate_provider.dart';

/// Where an order in "Neposlane narudžbe" stands (spec v4.0, §11.6).
enum MqttOutboxStatus {
  /// Published and waiting for the kasa's confirmation (at most 10 s). It can't
  /// be sent again until that wait is over (§11.5, rule 4).
  sending,

  /// Published, but no confirmation came within 10 s — "Nije potvrđena –
  /// provjeri na kasi". It may well have been printed; a resend keeps its
  /// msg_id, so the kasa never prints it twice.
  unconfirmed,

  /// It didn't reach the broker — "Nije poslana": it never left the phone,
  /// or the broker never confirmed taking it (see `published`).
  notSent,

  /// The kasa answered and did not print it (not in the sales screen, printer
  /// error, orderman not activated, or an unknown reason — see `reason`).
  refused,

  /// The kasa refused it as "zastarjela": `poslano` was more than 10 minutes
  /// from the kasa's clock. It goes out again as a NEW order (§11.6, rule 1).
  stale,
}

/// One order frozen at the moment the waiter pressed "Pošalji".
///
/// Frozen means it can never be edited: changed items would have to go out
/// under a new msg_id, and if the original had been printed after all, the
/// kasa would print the items twice (§11.7). So the order is kept exactly as
/// sent until the kasa confirms it, or the waiter deletes it.
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

  /// The exact message, built once and resent unchanged — same msg_id, same
  /// `poslano` — except that its `uredaj` follows a new code of the same
  /// licence.
  final String payload;

  /// The lines as the waiter built them, for display and for a new order after
  /// "zastarjela".
  final List<MqttCartLine> lines;

  /// How many `stavke` the payload carries (after grouping).
  final int sentLineCount;
  final DateTime createdAt;
  final MqttOutboxStatus status;

  /// What the waiter is told about the last attempt (§11.6 wording).
  final String reason;

  /// Whether the order has been published at least once.
  final bool published;

  /// Didn't get through — not sent, refused or too old ("red"): the waiter may
  /// send it again or delete it. An order with the broker ("amber": waiting
  /// for the kasa, or not confirmed) can be neither — the broker hands it to
  /// the kasa when the kasa comes back.
  bool get isProblem =>
      status == MqttOutboxStatus.notSent ||
      status == MqttOutboxStatus.refused ||
      status == MqttOutboxStatus.stale;

  /// "Pošalji ponovno" may send it — only a [isProblem] order.
  bool get canResend => isProblem;

  /// The kasa may have printed it without us knowing — deleting it doesn't
  /// undo that, so the waiter is warned first.
  bool get mayBePrinted =>
      status == MqttOutboxStatus.sending ||
      status == MqttOutboxStatus.unconfirmed ||
      (status == MqttOutboxStatus.notSent && published);

  /// The client_id this order was sent under (from its payload).
  String? get uredaj {
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map ? decoded['uredaj']?.toString() : null;
    } catch (_) {
      return null;
    }
  }

  MqttOutboxOrder copyWith({
    MqttOutboxStatus? status,
    String? reason,
    bool? published,
    String? payload,
  }) => MqttOutboxOrder(
    msgId: msgId,
    stol: stol,
    cuser: cuser,
    payload: payload ?? this.payload,
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

  /// A saved status name — including those of earlier app versions. A send the
  /// app was closed in the middle of is "not confirmed": nothing is known.
  static MqttOutboxStatus _statusFrom(Object? name, bool published) =>
      switch (name) {
        'notSent' => MqttOutboxStatus.notSent,
        'refused' || 'rejected' => MqttOutboxStatus.refused,
        'stale' || 'expired' => MqttOutboxStatus.stale,
        'waiting' when !published => MqttOutboxStatus.notSent,
        _ => MqttOutboxStatus.unconfirmed,
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
      final payload = _toV4Payload((raw['payload'] ?? '').toString());
      if (msgId.isEmpty || payload.isEmpty || lines.isEmpty) return null;
      final published = raw['published'] == true;
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
        status: _statusFrom(raw['status'], published),
        reason: (raw['reason'] ?? '').toString(),
        published: published,
      );
    } catch (_) {
      return null;
    }
  }
}

/// An order saved by an earlier version of the app carries `od`, `ts` and
/// `istek` instead of `uredaj` and `poslano` — and the kasa ignores an order
/// without those (spec v4.0, §10). Rewrites such a payload to the v4.0 fields,
/// keeping its msg_id and original send time. A v4.0 payload is returned
/// unchanged.
String _toV4Payload(String payload) {
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map<String, dynamic>) return payload;
    const legacyKeys = {'od', 'ts', 'istek'};
    if (!decoded.keys.any(legacyKeys.contains)) return payload;
    final uredaj = decoded['uredaj'] ?? decoded['od'];
    final poslano = decoded['poslano'] ?? decoded['ts'];
    if (uredaj == null || poslano == null) return payload;
    return jsonEncode({
      'msg_id': decoded['msg_id'],
      'uredaj': uredaj,
      'poslano': poslano,
      for (final e in decoded.entries)
        if (!legacyKeys.contains(e.key) &&
            e.key != 'msg_id' &&
            e.key != 'uredaj' &&
            e.key != 'poslano')
          e.key: e.value,
    });
  } catch (_) {
    return payload;
  }
}

/// [payload] with its `uredaj` replaced — everything else, msg_id and
/// `poslano` included, stays as it was.
String _withUredaj(String payload, String uredaj) {
  final decoded = jsonDecode(payload) as Map<String, dynamic>;
  return jsonEncode({...decoded, 'uredaj': uredaj});
}

/// Whether a waiter may see and act on [order]: their own orders, or every
/// order when they hold pravo 008.
bool mqttOutboxVisibleTo(
  MqttOutboxOrder order, {
  required String? cuser,
  required bool allTables,
}) => allTables || order.cuser == cuser;

/// "Neposlane narudžbe": every order this phone sent that the kasa hasn't
/// confirmed as printed, kept on the device — across restarts too (§11.5,
/// rule 5) — until it is confirmed or the waiter deletes it.
///
/// * Pressing "Pošalji" FREEZES the order here before it is published, so the
///   same items can never go out again under a new msg_id.
/// * Every send is ONE publish followed by up to 10 s of waiting (§11.6). The
///   screen that sent it only waits for the publish ([sendNow]); the wait for
///   the kasa's confirmation runs here, in the background.
/// * [resend] is "Pošalji ponovno". With "Automatsko ponovno slanje" on (a
///   device setting — the spec's §11.6 default is manual only) orders are
///   also sent again on their own, see [autoResendNow].
/// * A confirmation settles its order whenever it arrives — also after the
///   wait, also after a restart.
class MqttOutboxNotifier extends StateNotifier<List<MqttOutboxOrder>> {
  MqttOutboxNotifier(
    this._prefs,
    this._transfers,
    this._canSend,
    this._onNotActivated,
    this._autoResend,
  ) : super(const []) {
    state = _load();
    // Confirmations that arrive outside a send's own wait still settle their
    // order (§11.6) — see [_onReply].
    _replies = MqttService.instance.orderReplies.listen(_onReply);
    _autoTimer = Timer.periodic(autoResendInterval, (_) => autoResendNow());
  }

  /// How often "Automatsko ponovno slanje" looks for orders to send again.
  static const autoResendInterval = Duration(seconds: 30);

  /// Orders older than this are never sent again automatically: the kasa
  /// refuses anything more than 10 minutes old as "zastarjela" (§10), and an
  /// order that old may no longer stand — the waiter decides.
  static const autoResendMaxAge = Duration(minutes: 9);

  static const _key = 'mqtt_outbox_v1';

  final SharedPreferences _prefs;
  final MqttPendingTransfersNotifier _transfers;

  /// Whether sending is open right now (§11.4).
  final bool Function() _canSend;

  /// Called when the kasa refused one of THIS device's orders with "nije
  /// aktiviran" — the code is forgotten and the waiter asked to scan a new one.
  final void Function() _onNotActivated;

  /// Whether "Automatsko ponovno slanje" is on.
  final bool Function() _autoResend;

  StreamSubscription<MqttOrderReply>? _replies;
  Timer? _autoTimer;

  /// Orders with a send in progress right now.
  final _inFlight = <String>{};

  // ── Called by the order screen ────────────────────────────────────────────

  /// Freezes [lines] into a new order for [stol] and saves it. Nothing is
  /// published yet — see [sendNow]. Returns the problem instead when the order
  /// can't be built (then nothing is saved).
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
    state = [...state, order];
    _save();
    return (order: order, problem: null);
  }

  /// Sends a just-frozen [order] and completes as soon as that is decided:
  /// `true` — the broker has it (the wait for the kasa's confirmation carries
  /// on here, and its outcome lands on the order on its own); `false` — it
  /// didn't reach the broker ("Nije poslana").
  Future<bool> sendNow(MqttOutboxOrder order) {
    final delivered = Completer<bool>();
    unawaited(
      _attempt(
        order,
        onPublished: () {
          if (!delivered.isCompleted) delivered.complete(true);
        },
      ).whenComplete(() {
        if (!delivered.isCompleted) delivered.complete(false);
      }),
    );
    return delivered.future;
  }

  /// "Automatsko ponovno slanje": when the setting is on and sending is open,
  /// sends again every order that didn't reach the broker or that the kasa
  /// refused, while it is young enough ([autoResendMaxAge]) — with the same
  /// msg_id, so the kasa never prints one twice.
  ///
  /// Not "Nije potvrđena": the broker already holds that order and hands it
  /// to the kasa when the kasa comes back. "Zastarjela" orders and orders for
  /// another licence are left to the waiter. Called on a timer, when sending opens, and when the
  /// setting is switched on.
  void autoResendNow() {
    if (!mounted || !_autoResend() || !_canSend()) return;
    final licenca = MqttService.instance.licenca;
    if (licenca == null) return;
    final now = DateTime.now();
    final sent = resend(
      allowed: (o) =>
          (o.status == MqttOutboxStatus.notSent ||
              o.status == MqttOutboxStatus.refused) &&
          (o.uredaj?.startsWith('$licenca-') ?? false) &&
          now.difference(o.createdAt) < autoResendMaxAge,
      // Never used: "zastarjela" orders aren't sent automatically.
      groupArticles: false,
    );
    if (sent > 0) debugPrint('MQTT ▸ outbox: auto-resent $sent order(s)');
  }

  // ── Called by "Neposlane narudžbe" ────────────────────────────────────────

  /// "Pošalji ponovno" (§11.6, rule 1) for the orders of [stol] — or of every
  /// table when [stol] is null — that [allowed] permits and that aren't waiting
  /// for an answer already. Returns how many went out.
  ///
  /// * Same msg_id and `poslano` as before: if the kasa did print it and only
  ///   the confirmation was lost, it recognises the number and just confirms.
  /// * After "zastarjela": a new msg_id and `poslano`. The kasa says that only
  ///   about an order it did NOT print, so this can't print twice.
  /// * Sent under an earlier code of the same licence: the same order, now
  ///   under this device's current id.
  /// * Sent under ANOTHER licence — to another kasa: never resent here.
  int resend({
    int? stol,
    required bool Function(MqttOutboxOrder order) allowed,
    required bool groupArticles,
  }) {
    final uredaj = MqttService.instance.clientId;
    final licenca = MqttService.instance.licenca;
    if (!_canSend() || uredaj == null || licenca == null) return 0;
    final toSend = <MqttOutboxOrder>[];
    final next = <MqttOutboxOrder>[];
    var changed = false;
    for (final o in state) {
      final eligible =
          (stol == null || o.stol == stol) &&
          o.canResend &&
          !_inFlight.contains(o.msgId) &&
          allowed(o);
      if (!eligible) {
        next.add(o);
        continue;
      }
      final sentAs = o.uredaj;
      if (sentAs == null || !sentAs.startsWith('$licenca-')) {
        changed = true;
        next.add(
          o.copyWith(
            reason:
                'Poslana u drugi glavni program (drugu licencu), provjerite u '
                'tom glavnom programu.',
          ),
        );
        continue;
      }
      final MqttOutboxOrder ready;
      if (o.status == MqttOutboxStatus.stale) {
        ready = _build(
          stol: o.stol,
          cuser: o.cuser,
          lines: o.lines,
          groupArticles: groupArticles,
        );
      } else if (sentAs != uredaj) {
        ready = o.copyWith(payload: _withUredaj(o.payload, uredaj));
      } else {
        ready = o;
      }
      next.add(ready);
      toSend.add(ready);
    }
    if (!changed && toSend.isEmpty) return 0;
    state = next;
    _save();
    // Each order on its own: one waiting for an answer doesn't hold up the
    // others (§11.5, rule 4).
    for (final o in toSend) {
      unawaited(_attempt(o));
    }
    return toSend.length;
  }

  /// Deletes orders. For an order the kasa may already have printed this does
  /// NOT undo that — the caller must have warned the waiter.
  void remove(Set<String> msgIds) => _removeIds(msgIds);

  // ── Internals ─────────────────────────────────────────────────────────────

  MqttOutboxOrder _build({
    required int stol,
    required String cuser,
    required List<MqttCartLine> lines,
    required bool groupArticles,
  }) {
    // msg_id and `poslano` are set once, here — the order is built only right
    // before it is sent — and never change on a resend of the same order.
    final msgId = newMsgId();
    final now = DateTime.now();
    final copies = [for (final l in lines) l.copy()];
    final sent = groupArticles ? groupCartLines(copies) : copies;
    return MqttOutboxOrder(
      msgId: msgId,
      stol: stol,
      cuser: cuser,
      payload: buildOrderJson(
        msgId: msgId,
        // Guaranteed by precheck() / checked by resend().
        uredaj: MqttService.instance.clientId!,
        poslano: now.millisecondsSinceEpoch,
        stol: stol,
        cuser: cuser,
        lines: sent,
      ),
      lines: copies,
      sentLineCount: sent.length,
      createdAt: now,
      status: MqttOutboxStatus.sending,
    );
  }

  /// One send of [order]: publish once, wait up to 10 s, settle.
  Future<MqttSendResult> _attempt(
    MqttOutboxOrder order, {
    void Function()? onPublished,
  }) async {
    _inFlight.add(order.msgId);
    _update(
      order.msgId,
      (o) => o.copyWith(status: MqttOutboxStatus.sending, reason: ''),
    );
    try {
      final result = await MqttOrderSender.instance.sendPayload(
        msgId: order.msgId,
        payload: order.payload,
        onPublished: onPublished,
      );
      if (mounted) _apply(order.msgId, result);
      return result;
    } finally {
      _inFlight.remove(order.msgId);
    }
  }

  /// A confirmation that arrived outside a send's own wait — late, or delivered
  /// again by the broker after a reconnect. It still settles its order
  /// (§11.6: "potvrda stigne nakon 10 s → ishod prema potvrdi"). A send in
  /// progress takes its own reply; unknown msg_ids are ignored.
  void _onReply(MqttOrderReply reply) {
    if (!mounted || _inFlight.contains(reply.msgId)) return;
    if (_find(reply.msgId) == null) return;
    debugPrint('MQTT ▸ outbox: confirmation for ${reply.msgId} after its wait');
    _apply(reply.msgId, MqttOrderSender.instance.resultFromReply(reply));
  }

  /// Applies an outcome to the saved order (§11.6).
  void _apply(String msgId, MqttSendResult result) {
    final order = _find(msgId);
    if (order == null) return;
    final MqttOutboxStatus status;
    switch (result.outcome) {
      case MqttSendOutcome.ok:
        debugPrint(
          'MQTT ▸ outbox: ${order.msgId} printed (stol ${order.stol})',
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
        return;
      case MqttSendOutcome.nijePotvrdena:
        status = MqttOutboxStatus.unconfirmed;
      case MqttSendOutcome.nijePoslana:
      case MqttSendOutcome.nijeIsporucena:
      case MqttSendOutcome.neispravno:
        status = MqttOutboxStatus.notSent;
      case MqttSendOutcome.zastarjela:
        status = MqttOutboxStatus.stale;
      case MqttSendOutcome.odbijeno:
        status = MqttOutboxStatus.refused;
      case MqttSendOutcome.nijeAktiviran:
        // Only for this device's current code: an answer about an order sent
        // under an earlier code must not wipe the new one.
        if (order.uredaj == MqttService.instance.clientId) _onNotActivated();
        status = MqttOutboxStatus.refused;
    }
    final wentOut =
        result.outcome != MqttSendOutcome.nijePoslana &&
        result.outcome != MqttSendOutcome.neispravno;
    _update(
      msgId,
      (o) => o.copyWith(
        status: status,
        reason: result.message,
        published: o.published || wentOut,
      ),
    );
  }

  MqttOutboxOrder? _find(String msgId) {
    for (final o in state) {
      if (o.msgId == msgId) return o;
    }
    return null;
  }

  void _update(String msgId, MqttOutboxOrder Function(MqttOutboxOrder) change) {
    if (_find(msgId) == null) return;
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
    _replies?.cancel();
    _autoTimer?.cancel();
    super.dispose();
  }
}

final mqttOutboxProvider =
    StateNotifierProvider<MqttOutboxNotifier, List<MqttOutboxOrder>>((ref) {
      final notifier = MqttOutboxNotifier(
        ref.watch(sharedPreferencesProvider),
        ref.read(mqttPendingTransfersProvider.notifier),
        () => ref.read(mqttSendGateProvider).isOpen,
        () => ref.read(mqttConfigProvider.notifier).forgetDevice(),
        () => ref.read(settingsProvider).shouldAutoResend,
      );
      // "Automatsko ponovno slanje" doesn't wait for its timer when sending
      // opens again (kasa back in the sales screen, connection back) or when
      // the setting is switched on.
      ref.listen<MqttSendGate>(mqttSendGateProvider, (prev, next) {
        if (next.isOpen && prev?.isOpen != true) notifier.autoResendNow();
      });
      ref.listen<bool>(
        settingsProvider.select((s) => s.shouldAutoResend),
        (prev, next) {
          if (next) notifier.autoResendNow();
        },
      );
      return notifier;
    });
