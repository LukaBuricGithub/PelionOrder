import 'package:flutter/foundation.dart';

/// One cart line for the MQTT order flow — each tap on an article adds its own
/// line (duplicates of the same article stay separate). Quantity and remarks
/// (napomene) are edited per line.
class MqttCartLine {
  MqttCartLine(this.code);
  final int code;
  double qty = 1;
  final List<String> remarks = [];

  /// A detached copy (so the session store and the live cart don't share
  /// mutable state).
  MqttCartLine copy() {
    final l = MqttCartLine(code)..qty = qty;
    l.remarks.addAll(remarks);
    return l;
  }
}

/// A local, in-memory order cart shared between the MQTT order screen and its
/// details screen. Nothing here is persisted or sent — it exists only for the
/// duration of the ordering session (Send is a no-op in this flow).
class MqttCart extends ChangeNotifier {
  final List<MqttCartLine> lines = [];

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  void addLine(int code) {
    lines.add(MqttCartLine(code));
    notifyListeners();
  }

  void incrementLine(int i) {
    if (i < 0 || i >= lines.length) return;
    lines[i].qty += 1;
    notifyListeners();
  }

  /// − at 1 removes the line.
  void decrementLine(int i) {
    if (i < 0 || i >= lines.length) return;
    lines[i].qty -= 1;
    if (lines[i].qty <= 0) lines.removeAt(i);
    notifyListeners();
  }

  void setQuantity(int i, double q) {
    if (i < 0 || i >= lines.length) return;
    if (q <= 0) {
      lines.removeAt(i);
    } else {
      lines[i].qty = q;
    }
    notifyListeners();
  }

  void removeLine(int i) {
    if (i < 0 || i >= lines.length) return;
    lines.removeAt(i);
    notifyListeners();
  }

  void clear() {
    lines.clear();
    notifyListeners();
  }

  void toggleRemark(int i, String r) {
    if (i < 0 || i >= lines.length) return;
    final rem = lines[i].remarks;
    rem.contains(r) ? rem.remove(r) : rem.add(r);
    notifyListeners();
  }

  void addCustomRemark(int i, String r) {
    if (i < 0 || i >= lines.length) return;
    final t = r.trim();
    if (t.isEmpty) return;
    if (!lines[i].remarks.contains(t)) lines[i].remarks.add(t);
    notifyListeners();
  }

  double qtyFor(int code) =>
      lines.where((l) => l.code == code).fold(0.0, (s, l) => s + l.qty);

  /// Replaces the cart contents with copies of [src] (used to restore a saved
  /// order when reopening a table).
  void loadFrom(List<MqttCartLine> src) {
    lines
      ..clear()
      ..addAll([for (final l in src) l.copy()]);
    notifyListeners();
  }
}
