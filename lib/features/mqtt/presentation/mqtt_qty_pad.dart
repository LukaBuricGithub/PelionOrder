import 'package:flutter/material.dart';

import '../../shared/presentation/app_bottom_sheet.dart';

/// Largest quantity that can be entered, and how many decimals are kept.
/// Both are guards against fat-finger entry: the kasa books whatever we send
/// and the order can't be corrected by message afterwards.
const double _kMaxQty = 999;
const int _kMaxDecimals = 3;

/// Formats a quantity for display in Croatian: `1,5` — never `1.5`. The payload
/// keeps the dot form (jsonEncode of a double), this is UI only.
String formatQty(double q) {
  final s = q == q.roundToDouble()
      ? q.toInt().toString()
      : q.toStringAsFixed(_kMaxDecimals).replaceFirst(RegExp(r'0+$'), '');
  return s.replaceAll('.', ',');
}

/// Quantity + unit as shown on a cart line: `2 kom`, `1,5 kg`, or just `2` when
/// the article has no `jm`.
String formatQtyWithUnit(double q, String unit) {
  final u = unit.trim();
  return u.isEmpty ? formatQty(q) : '${formatQty(q)} $u';
}

/// Opens the numeric quantity pad for one cart line and returns the entered
/// value, or null when cancelled. `0` is a valid result — the caller removes
/// the line (matching `MqttCart.setQuantity`, which drops a line at `<= 0`).
///
/// A purpose-built keypad rather than the OS keyboard: the targets are big
/// enough for one-handed use mid-service, the sheet doesn't collapse the cart
/// behind it, and — the practical one — we emit the decimal separator
/// ourselves. Android's numeric keyboards disagree about whether that key is
/// `.` or `,` (or hide it entirely), which is exactly the kind of thing that
/// wastes a waiter's time.
Future<double?> showMqttQtyPad({
  required BuildContext context,
  required String articleName,
  required String unit,
  required double initial,
}) {
  return showAppBottomSheet<double>(
    context: context,
    sheetBuilder: (ctx) => _QtyPadSheet(
      articleName: articleName,
      unit: unit,
      initial: initial,
    ),
  );
}

/// The quantity control shared by the order and details screens: a chip reading
/// `2 kom` that opens the pad. It doubles as the line's quantity display, which
/// is what lets the order screen fit two editors into the space the old +/−
/// stepper used. [scale] is the caller's `_screenScale(context)`.
class MqttQtyButton extends StatelessWidget {
  const MqttQtyButton({
    super.key,
    required this.qty,
    required this.unit,
    required this.scale,
    required this.onTap,
  });

  final double qty;
  final String unit;
  final double scale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = scale;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(8 * s),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8 * s),
        child: Container(
          height: 28 * s,
          padding: EdgeInsets.symmetric(horizontal: 10 * s),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8 * s),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatQtyWithUnit(qty, unit),
                style: TextStyle(fontSize: 13 * s, fontWeight: FontWeight.w700),
              ),
              SizedBox(width: 4 * s),
              Icon(Icons.edit_outlined,
                  size: 13 * s, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _QtyPadSheet extends StatefulWidget {
  const _QtyPadSheet({
    required this.articleName,
    required this.unit,
    required this.initial,
  });

  final String articleName;
  final String unit;
  final double initial;

  @override
  State<_QtyPadSheet> createState() => _QtyPadSheetState();
}

class _QtyPadSheetState extends State<_QtyPadSheet> {
  /// The raw text being typed, always comma-separated (what the waiter sees).
  late String _text = formatQty(widget.initial);

  /// True until the first keypress: the first digit REPLACES the starting
  /// value rather than appending to it, so retyping a quantity doesn't mean
  /// backspacing over it first.
  bool _fresh = true;

  double? get _value {
    if (_text.isEmpty) return null;
    return double.tryParse(_text.replaceAll(',', '.'));
  }

  bool get _valid {
    final v = _value;
    return v != null && v >= 0 && v <= _kMaxQty;
  }

  void _digit(String d) {
    setState(() {
      if (_fresh) {
        _text = d == ',' ? '0,' : d;
        _fresh = false;
        return;
      }
      if (d == ',') {
        if (_text.contains(',')) return; // only one separator
        _text = _text.isEmpty ? '0,' : '$_text,';
        return;
      }
      // Cap the decimals at entry time rather than rounding behind the
      // waiter's back after they press U redu.
      final sep = _text.indexOf(',');
      if (sep >= 0 && _text.length - sep - 1 >= _kMaxDecimals) return;
      final next = _text == '0' ? d : '$_text$d';
      if ((double.tryParse(next.replaceAll(',', '.')) ?? 0) > _kMaxQty) return;
      _text = next;
    });
  }

  void _backspace() {
    setState(() {
      _fresh = false;
      if (_text.isNotEmpty) _text = _text.substring(0, _text.length - 1);
    });
  }

  void _clear() => setState(() {
        _fresh = false;
        _text = '';
      });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unit = widget.unit.trim();

    return AppBottomSheetScaffold(
      title: widget.articleName,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The value being typed, with the article's own jm beside it.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Text('Količina',
                    style: TextStyle(fontSize: 13, height: 1.2)),
                const Spacer(),
                Text(
                  _text.isEmpty ? '0' : _text,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: _valid ? scheme.onSurface : scheme.error,
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    unit,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Keypad(onDigit: _digit, onBackspace: _backspace, onClear: _clear),
          const SizedBox(height: 4),
          Text(
            'Unesite 0 za uklanjanje stavke.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Odustani'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed:
                  _valid ? () => Navigator.of(context).pop(_value) : null,
              child: const Text('U redu'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 3×4 keypad: 1-9, comma, 0, backspace. Long-press backspace clears.
class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
  });

  final void Function(String) onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget key(Widget child, VoidCallback onTap, {VoidCallback? onLongPress}) =>
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Material(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: onTap,
                onLongPress: onLongPress,
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(height: 56, child: Center(child: child)),
              ),
            ),
          ),
        );

    Widget digit(String d) => key(
          Text(d,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          () => onDigit(d),
        );

    Widget row(List<Widget> children) => Row(children: children);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row([digit('1'), digit('2'), digit('3')]),
        row([digit('4'), digit('5'), digit('6')]),
        row([digit('7'), digit('8'), digit('9')]),
        row([
          digit(','),
          digit('0'),
          key(
            Icon(Icons.backspace_outlined, size: 22, color: scheme.onSurface),
            onBackspace,
            onLongPress: onClear,
          ),
        ]),
      ],
    );
  }
}
