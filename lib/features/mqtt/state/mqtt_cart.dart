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

  // ── By article, for the "Popis" layout ────────────────────────────────────
  //
  // That layout has one row per ARTICLE, not per tap: pressing the same
  // article again raises its quantity instead of starting a second line, and
  // the article drops out of the order when the quantity reaches zero. The
  // lines themselves are unchanged, so everything downstream — napomene,
  // grouping, the payload — works exactly as before.

  /// How many of [code] the order holds, across every line.
  double quantityOf(int code) =>
      lines.where((l) => l.code == code).fold(0.0, (sum, l) => sum + l.qty);

  /// One more of [code], merged into the line already there rather than a new
  /// one. Falls back to a new line when the article isn't in the order yet.
  void addQuantity(int code) {
    final i = lines.lastIndexWhere((l) => l.code == code);
    if (i < 0) {
      addLine(code);
      return;
    }
    incrementLine(i);
  }

  /// One more of [code] that carries no napomena of its own.
  ///
  /// [addQuantity] raises the last line, which is right until that line has an
  /// instruction on it: the new portion would then silently inherit "bez
  /// šećera" from the one before it. When it does, this starts a clean line
  /// directly after it instead, so a napomena is only ever added deliberately
  /// — on the price-list row while the article is a single portion, or per
  /// portion in "Detalji narudžbe".
  void addPlainQuantity(int code) {
    final i = lines.lastIndexWhere((l) => l.code == code);
    if (i < 0) {
      addLine(code);
      return;
    }
    final last = lines[i];
    if (last.remarkCodes.isEmpty && last.customNotes.isEmpty) {
      incrementLine(i);
      return;
    }
    // Next to the portion it follows, so the article's units stay together.
    lines.insert(i + 1, MqttCartLine(code));
    _touch();
  }

  /// One fewer of [code]; at zero the article leaves the order. Works on the
  /// most recent line, so a cart built in the other layout degrades sensibly.
  void removeQuantity(int code) {
    final i = lines.lastIndexWhere((l) => l.code == code);
    if (i >= 0) decrementLine(i);
  }

  /// The line [code] is ordered on, or -1. The napomene editor needs it: that
  /// editor works per line, while the "Popis" layout speaks per article.
  int lineIndexOf(int code) => lines.lastIndexWhere((l) => l.code == code);

  /// One more of [code] as an entry of its own — "ne grupiraj artikle".
  ///
  /// Each press is a portion the kitchen reads on its own line, so it starts a
  /// new line rather than raising the one before it, and never carries that
  /// one's napomena. Inserted directly after the article's last entry, so its
  /// portions stay together on the ticket even when other articles were
  /// ordered in between.
  ///
  /// A quantity TYPED into the number pad is a quantity, not a count of
  /// portions: one line of 3 is one entry of 3. Only + makes entries.
  void addUnit(int code) {
    final i = lines.lastIndexWhere((l) => l.code == code);
    if (i < 0) {
      addLine(code);
      return;
    }
    lines.insert(i + 1, MqttCartLine(code));
    _touch();
  }

  /// Makes the order hold exactly [q] of [code] — what the price-list row's
  /// number pad returns.
  ///
  /// Anything sold by weight or measure needs this: 300 g of steak is typed
  /// once, not pressed three hundred times. Creates the line when the article
  /// isn't in the order yet, and takes it out of the order at zero.
  ///
  /// The row speaks for the whole ARTICLE and shows the SUM of its lines, so
  /// the number typed in is the total. It is adjusted from the END: the
  /// difference lands on the article's last portion, and a decrease drops whole
  /// portions off the back first, so the earlier ones — which may each carry a
  /// napomena of their own — are left alone.
  ///
  /// It replaced a version that wrote to the last line and nothing else. That
  /// was right while an article could only be on one line; once a press of +
  /// started a portion of its own, three portions plus a typed 5 came out as
  /// 1 + 1 + 5 = 7.
  void setTotalOf(int code, double q) {
    final mine = [
      for (final l in lines)
        if (l.code == code) l,
    ];
    if (mine.isEmpty) {
      if (q <= 0) return;
      lines.add(MqttCartLine(code)..qty = q);
      _touch();
      return;
    }
    if (q <= 0) {
      lines.removeWhere((l) => l.code == code);
      _touch();
      return;
    }
    var total = mine.fold(0.0, (s, l) => s + l.qty);
    // Whole portions off the back while they alone already exceed the target.
    while (mine.length > 1 && total - mine.last.qty >= q) {
      total -= mine.last.qty;
      lines.remove(mine.removeLast());
    }
    // Set, not added to: one line left means `q` exactly, with no rounding
    // drift on a measure like 0,3.
    mine.last.qty = q - (total - mine.last.qty);
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

  /// Moves the line at [oldIndex] to [newIndex] (drag-to-reorder in the details
  /// screen), using ReorderableListView's index convention.
  ///
  /// The kasa prints `stavke` in the order we send them, so this genuinely
  /// changes the kitchen ticket — it therefore goes through [_touch] like any
  /// other edit, which invalidates the pending msg_id. Without that, reordering
  /// after a failed send would reuse the id and the kasa would just replay its
  /// old answer, silently discarding the new order.
  void moveLine(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= lines.length) return;
    // ReorderableListView reports the target as an index in the ORIGINAL list,
    // so dropping below the source needs a -1 once the item is lifted out.
    var target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    target = target.clamp(0, lines.length - 1);
    if (target == oldIndex) return;
    lines.insert(target, lines.removeAt(oldIndex));
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
