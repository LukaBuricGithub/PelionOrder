import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/presentation/bottom_sheet_safe_area.dart';
import '../models/mqtt_menu.dart';
import '../state/mqtt_cart.dart';
import 'mqtt_napomene.dart';

double _screenScale(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final diagonal =
      math.sqrt(size.width * size.width + size.height * size.height);
  return (diagonal / 928.0).clamp(0.9, 1.4);
}

/// Fixed width reserved for the line amount ("9.999,99 €"), so amounts stay in a
/// right-aligned column and the name never collides with them.
const double _kAmountBaseWidth = 88;

String _fmtQty(double q) =>
    q == q.roundToDouble() ? q.toInt().toString() : q.toString();

/// Details view for the MQTT order — a visual + behavioural clone of the API
/// `OrderDetailsScreen`, operating on the shared [MqttCart]. "Pošalji narudžbu"
/// delegates to [onSend] (owned by the order screen); on success this screen
/// pops with `'sent'`.
class MqttOrderDetailsScreen extends StatefulWidget {
  const MqttOrderDetailsScreen({
    super.key,
    required this.cart,
    required this.byCode,
    required this.remarks,
    required this.money,
    this.tableBroj,
    this.tableNaziv,
    this.onSend,
  });

  final MqttCart cart;
  final Map<int, MqttArticle> byCode;
  final List<MqttRemark> remarks;
  final NumberFormat money;
  final int? tableBroj;
  final String? tableNaziv;

  /// Sends the order (owned by the order screen). Returns true when the kasa
  /// accepted it — this screen then pops with `'sent'`.
  final Future<bool> Function()? onSend;

  @override
  State<MqttOrderDetailsScreen> createState() =>
      _MqttOrderDetailsScreenState();
}

class _MqttOrderDetailsScreenState extends State<MqttOrderDetailsScreen> {
  bool _sending = false;

  MqttCart get cart => widget.cart;
  Map<int, MqttArticle> get byCode => widget.byCode;
  List<MqttRemark> get remarks => widget.remarks;
  NumberFormat get money => widget.money;
  int? get tableBroj => widget.tableBroj;
  String? get tableNaziv => widget.tableNaziv;

  Future<void> _send() async {
    final send = widget.onSend;
    if (send == null || _sending) return;
    setState(() => _sending = true);
    final ok = await send();
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) Navigator.of(context).pop('sent');
  }

  String _name(int code) => byCode[code]?.name ?? 'Artikl $code';
  double _price(int code) => byCode[code]?.price ?? 0;

  /// Predefined remarks available for the article: every global ("sve") remark
  /// plus the ones the article lists by id. Codes (`cnap`) are what gets sent.
  List<MqttRemark> _remarksFor(int code) {
    final a = byCode[code];
    if (a == null) return const [];
    return [
      for (final r in remarks)
        if (r.sve || a.napomene.contains(r.cnap)) r,
    ];
  }

  double get _total =>
      cart.lines.fold(0.0, (s, l) => s + _price(l.code) * l.qty);

  @override
  Widget build(BuildContext context) {
    final broj = tableBroj;
    final naziv = tableNaziv;
    final titleTop = broj == null
        ? 'Narudžba'
        : (naziv != null && naziv.isNotEmpty
            ? 'Stol $broj · $naziv'
            : 'Stol $broj');

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
      ),
      child: ListenableBuilder(
        listenable: cart,
        builder: (context, _) {
          final lines = cart.lines;
          return Scaffold(
            appBar: AppBar(
              titleSpacing: 0,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    titleTop,
                    style: Theme.of(context).appBarTheme.titleTextStyle ??
                        Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    'Detalji narudžbe',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              actions: [
                if (lines.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.delete_sweep_outlined,
                        color: Theme.of(context).colorScheme.error),
                    tooltip: 'Isprazni narudžbu',
                    onPressed: () => _confirmClear(context),
                  ),
              ],
            ),
            body: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    itemCount: lines.length + 1,
                    itemBuilder: (context, i) {
                      if (i == lines.length) {
                        return _AddItemButton(
                          onTap: () => Navigator.of(context).pop(),
                        );
                      }
                      final line = lines[i];
                      return _LineTile(
                        key: ValueKey('line_${line.code}_$i'),
                        index: i,
                        line: line,
                        cart: cart,
                        name: _name(line.code),
                        lineTotal: money.format(_price(line.code) * line.qty),
                        available: _remarksFor(line.code),
                      );
                    },
                  ),
                ),
                _BottomBar(
                  total: money.format(_total),
                  sending: _sending,
                  canSend: lines.isNotEmpty &&
                      !_sending &&
                      widget.onSend != null,
                  onSend: _send,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Isprazni narudžbu'),
          content: const Text('Ukloniti sve stavke iz narudžbe?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Odustani'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Isprazni'),
            ),
          ],
        );
      },
    );
    if (ok == true) cart.clear();
  }
}

/// One compact, expandable item row: quantity stepper · name · line total ·
/// chevron. The chevron reveals the napomene (remarks) editor + delete.
class _LineTile extends StatefulWidget {
  const _LineTile({
    super.key,
    required this.index,
    required this.line,
    required this.cart,
    required this.name,
    required this.lineTotal,
    required this.available,
  });

  final int index;
  final MqttCartLine line;
  final MqttCart cart;
  final String name;
  final String lineTotal;
  final List<MqttRemark> available;

  @override
  State<_LineTile> createState() => _LineTileState();
}

class _LineTileState extends State<_LineTile> {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  /// − decrements; at 1 it deletes the line.
  void _onMinus() {
    final q = widget.line.qty;
    if (q > 1) {
      widget.cart.setQuantity(widget.index, q - 1);
    } else {
      widget.cart.removeLine(widget.index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = widget.line;
    final s = _screenScale(context);

    return Padding(
      padding: EdgeInsets.only(bottom: 8 * s),
      child: Material(
        color: scheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12 * s),
          side:
              BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(12 * s, 7 * s, 6 * s, 4 * s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _toggle,
                          behavior: HitTestBehavior.opaque,
                          child: Text(
                            widget.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 15 * s, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      SizedBox(width: 10 * s),
                      Padding(
                        padding: EdgeInsets.only(top: 1 * s, right: 6 * s),
                        child: SizedBox(
                          width: _kAmountBaseWidth * s,
                          child: Text(
                            widget.lineTotal,
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            style: TextStyle(
                                fontSize: 14 * s, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6 * s),
                  Row(
                    children: [
                      _QtyStepper(
                        qty: line.qty,
                        onMinus: _onMinus,
                        onPlus: () => widget.cart
                            .setQuantity(widget.index, line.qty + 1),
                        onEdit: () => _editQty(context),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _toggle,
                        visualDensity: VisualDensity.compact,
                        icon: AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: Icon(Icons.expand_more,
                              size: 24 * s, color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Padding(
                      padding: EdgeInsets.fromLTRB(12 * s, 0, 10 * s, 6 * s),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MqttNoteRow(
                            chips: [
                              for (final c in line.remarkCodes)
                                MqttNoteChip(
                                  label: _nameFor(c),
                                  onRemove: () => widget.cart
                                      .toggleRemarkCode(widget.index, c),
                                ),
                              for (final n in line.customNotes)
                                MqttNoteChip(
                                  label: n,
                                  onRemove: () => widget.cart
                                      .removeCustomNote(widget.index, n),
                                ),
                            ],
                            onOpen: () => _editRemarks(context),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () =>
                                  widget.cart.removeLine(widget.index),
                              style: TextButton.styleFrom(
                                foregroundColor: scheme.error,
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const Text('Ukloni stavku'),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editQty(BuildContext context) async {
    final result = await showDialog<double>(
      context: context,
      builder: (_) => _QtyDialog(initial: widget.line.qty),
    );
    if (result != null) widget.cart.setQuantity(widget.index, result);
  }

  /// Display name for a selected remark code, resolved from this article's
  /// available remarks (falls back to the code itself).
  String _nameFor(String cnap) {
    for (final r in widget.available) {
      if (r.cnap == cnap) return r.naziv;
    }
    return cnap;
  }

  Future<void> _editRemarks(BuildContext context) async {
    await showMqttRemarksSheet(
      context: context,
      available: widget.available,
      selectedCodes: widget.line.remarkCodes,
      customNotes: widget.line.customNotes,
      onToggleCode: (c) => widget.cart.toggleRemarkCode(widget.index, c),
      onAddNote: (n) => widget.cart.addCustomNote(widget.index, n),
      onRemoveNote: (n) => widget.cart.removeCustomNote(widget.index, n),
    );
  }
}

/// Compact quantity stepper: outlined − / + with the number between (tap to
/// type an exact value).
class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.qty,
    required this.onMinus,
    required this.onPlus,
    required this.onEdit,
  });

  final double qty;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = _screenScale(context);

    Widget btn(IconData icon, VoidCallback onTap) => InkResponse(
          onTap: onTap,
          radius: 22 * s,
          child: Container(
            width: 30 * s,
            height: 30 * s,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8 * s),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.6)),
            ),
            child: Icon(icon, size: 18 * s, color: scheme.primary),
          ),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.remove, onMinus),
        InkWell(
          onTap: onEdit,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 11 * s),
            child: Text(
              _fmtQty(qty),
              style: TextStyle(fontSize: 16 * s, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        btn(Icons.add, onPlus),
      ],
    );
  }
}

/// Full-width "＋ Dodaj stavku" button — returns to the item picker.
class _AddItemButton extends StatelessWidget {
  const _AddItemButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Dodaj stavku'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(46),
        ),
      ),
    );
  }
}

class _QtyDialog extends StatefulWidget {
  const _QtyDialog({required this.initial});
  final double initial;

  @override
  State<_QtyDialog> createState() => _QtyDialogState();
}

class _QtyDialogState extends State<_QtyDialog> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initial == widget.initial.roundToDouble()
        ? widget.initial.toInt().toString()
        : widget.initial.toString(),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Količina'),
      content: TextField(
        controller: _c,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Odustani'),
        ),
        FilledButton(
          onPressed: () {
            final v = double.tryParse(_c.text.replaceAll(',', '.'));
            Navigator.pop(context, v);
          },
          child: const Text('U redu'),
        ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.total,
    required this.sending,
    required this.canSend,
    required this.onSend,
  });

  final String total;
  final bool sending;
  final bool canSend;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s = _screenScale(context);
    final sendBg = dark ? const Color(0xFF1FA9B6) : const Color(0xFF0E9AA7);
    final sendFg = dark ? const Color(0xFF052A2E) : Colors.white;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16 * s, 12 * s, 16 * s,
            screenContentBottomPadding(context, extra: 12 * s)),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Ukupno',
                    style: TextStyle(
                        fontSize: 12 * s, color: scheme.onSurfaceVariant)),
                Text(total,
                    style: TextStyle(
                        fontSize: 20 * s, fontWeight: FontWeight.w800)),
              ],
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: canSend ? onSend : null,
              style: FilledButton.styleFrom(
                backgroundColor: sendBg,
                foregroundColor: sendFg,
              ),
              icon: sending
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: sendFg),
                    )
                  : const Icon(Icons.send),
              label: const Text('Pošalji narudžbu'),
            ),
          ],
        ),
      ),
    );
  }
}
