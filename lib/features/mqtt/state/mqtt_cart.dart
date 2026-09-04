import 'package:flutter/foundation.dart';

/// One cart line for the MQTT order flow — each tap on an article adds its own
/// line (duplicates of the same article stay separate). Quantity and remarks
/// (napomene) are edited per line.
class MqttCartLine {
  MqttCartLine(this.code);
  final int code;
  double qty = 1;

  /// Selected predefined remark codes (`cnap`) — sent to the kasa as the
  /// order line's `napomene` array (codes, never names).
  final List<String> remarkCodes = [];

  /// Free-text notes typed by the waiter — joined into `napomena_tekst`.
  final List<String> customNotes = [];

  /// The free text for the order payload: the waiter's notes joined with `;`.
  ///
  /// `;` is the kasa's own separator — it joins the predefined remark names
  /// with it and appends this text (protocol doc, 3.4), so several custom notes
  /// joined the same way come out as separate remarks rather than one run-on
  /// line: `["1","4"] + "bez luka;extra ljuto"` → `KRASTAVCI;LOOK;bez
  /// luka;extra ljuto`.
  ///
  /// Each note is still sanitised first — `;` and `,` typed INSIDE a note
  /// become spaces (doc, 3.2), so only our own joins can create separators.
  String get napomenaTekst => customNotes
      .map((n) => n.replaceAll(RegExp('[;,]'), ' ').trim())
      .where((n) => n.isNotEmpty)
      .join(';');

  /// A detached copy (so the session store and the live cart don't share
  /// mutable state).
  MqttCartLine copy() {
    final l = MqttCartLine(code)..qty = qty;
    l.remarkCodes.addAll(remarkCodes);
    l.customNotes.addAll(customNotes);
    return l;
  }
}

/// A local, in-memory order cart shared between the MQTT order screen and its
/// details screen. Nothing here is persisted or sent — it exists only for the
/// duration of the ordering session (Send is a no-op in this flow).
class MqttCart extends ChangeNotifier {
  final List<MqttCartLine> lines = [];

  /// The `msg_id` of the order awaiting a reply.
  ///
  /// Kept so retrying UNCHANGED content reuses the same id (the kasa is
  /// idempotent per msg_id — a new id would book a duplicate). Any edit clears
  /// it via [_touch], because changed content must be sent as a NEW order.
  String? pendingMsgId;

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  /// Notifies listeners and invalidates the pending msg_id (content changed).
  void _touch() {
    pendingMsgId = null;
    notifyListeners();
  }

  void addLine(int code) {
    lines.add(MqttCartLine(code));
    _touch();
  }

  void incrementLine(int i) {
    if (i < 0 || i >= lines.length) return;
    lines[i].qty += 1;
    _touch();
  }

  /// − at 1 removes the line.
  void decrementLine(int i) {
    if (i < 0 || i >= lines.length) return;
    lines[i].qty -= 1;
    if (lines[i].qty <= 0) lines.removeAt(i);
    _touch();
  }

  void setQuantity(int i, double q) {
    if (i < 0 || i >= lines.length) return;
    if (q <= 0) {
      lines.removeAt(i);
    } else {
      lines[i].qty = q;
    }
    _touch();
  }

  void removeLine(int i) {
    if (i < 0 || i >= lines.length) return;
    lines.removeAt(i);
    _touch();
  }

  void clear() {
    lines.clear();
    _touch();
  }

  /// Adds/removes a predefined remark code (`cnap`) on a line.
  void toggleRemarkCode(int i, String cnap) {
    if (i < 0 || i >= lines.length) return;
    final codes = lines[i].remarkCodes;
    codes.contains(cnap) ? codes.remove(cnap) : codes.add(cnap);
    _touch();
  }

  /// Adds a free-text note to a line (ignored when blank or already present).
  void addCustomNote(int i, String text) {
    if (i < 0 || i >= lines.length) return;
    final t = text.trim();
    if (t.isEmpty) return;
    final notes = lines[i].customNotes;
    if (!notes.contains(t)) notes.add(t);
    _touch();
  }

  /// Removes a free-text note from a line.
  void removeCustomNote(int i, String text) {
    if (i < 0 || i >= lines.length) return;
    lines[i].customNotes.remove(text);
    _touch();
  }

  double qtyFor(int code) =>
      lines.where((l) => l.code == code).fold(0.0, (s, l) => s + l.qty);

  /// Replaces the cart contents with copies of [src] (used to restore a saved
  /// order when reopening a table).
  void loadFrom(List<MqttCartLine> src) {
    lines
      ..clear()
      ..addAll([for (final l in src) l.copy()]);
    _touch();
  }
}
