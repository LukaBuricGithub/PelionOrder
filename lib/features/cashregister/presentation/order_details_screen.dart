import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../shared/presentation/app_bottom_sheet.dart';
import '../../shared/presentation/bottom_sheet_safe_area.dart';
import '../models/order_item.dart';
import '../state/order_details_controller.dart';

/// Screen-size-driven UI scale (same logic as the New Order screen): 1.0 ≈ a
/// typical phone (~928 dp diagonal). Fonts, controls and paddings multiply by
/// this so the layout scales with the device. Clamped so it never gets extreme.
double _screenScale(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final diagonal =
      math.sqrt(size.width * size.width + size.height * size.height);
  return (diagonal / 928.0).clamp(0.9, 1.4);
}

/// Fixed width reserved for the line amount, sized to hold up to "9.999,99 €"
/// (4 integer digits + 2 decimals) so amounts stay in a right-aligned column
/// and the name never collides with them.
const double _kAmountBaseWidth = 88;

/// A closer view of the order for fine-tuning each line: quantity, remarks
/// (predefined or custom) and delete — then send. Laid out as a stack of
/// compact per-item cards ("Card Stack Detail"). Mirrors the reference client's
/// `OrderDetailsScreen`.
class OrderDetailsScreen extends ConsumerWidget {
  const OrderDetailsScreen({super.key, required this.orderId});

  final int orderId;

  static final _money =
      NumberFormat.currency(locale: 'hr_HR', symbol: '€', decimalDigits: 2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(orderDetailsControllerProvider(orderId));
    final controller =
        ref.read(orderDetailsControllerProvider(orderId).notifier);
    final order = state.order;

    return MediaQuery(
      // Honour the device's accessibility font scale, capped so a very large
      // system font can't break the layout (matches the New Order screen).
      data: MediaQuery.of(context).copyWith(
        textScaler:
            MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
      ),
      child: Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              order != null ? 'Stol ${order.tableCode}' : 'Narudžba',
              // Use the app-bar's own title style (see app_theme: titleLarge
              // @22/w700) so "Stol X" matches the New Order screen exactly.
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
          if (order != null && order.items.isNotEmpty)
            // "Empty the whole order" — a sweep-trash icon, distinct from the
            // per-line delete_outline used inside each item's dropdown.
            IconButton(
              icon: Icon(Icons.delete_sweep_outlined,
                  color: Theme.of(context).colorScheme.error),
              tooltip: 'Isprazni narudžbu',
              onPressed: () => _confirmClear(context, controller),
            ),
        ],
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : order == null
              ? const Center(child: Text('Narudžba nije pronađena.'))
              : Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                          itemCount: order.items.length + 1,
                          itemBuilder: (context, i) {
                            if (i == order.items.length) {
                              return _AddItemButton(
                                onTap: () => context.pop(),
                              );
                            }
                            final line = order.items[i];
                            return _LineTile(
                              key: ValueKey('line_${line.code}_$i'),
                              index: i,
                              line: line,
                              name: controller.articleName(line.code),
                              lineTotal: _money.format(
                                  controller.priceFor(line.code) *
                                      line.quantity),
                              canChangeQty: state.changeQuantityRight,
                              canDelete: state.deleteRight,
                              controller: controller,
                            );
                          },
                        ),
                      ),
                      _BottomBar(
                        total: _money.format(controller.total),
                        sending: state.sending,
                        canSend: order.items.isNotEmpty && !state.sending,
                        onSend: () async {
                          final ok = await controller.send();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(ok
                                  ? 'Narudžba poslana.'
                                  : 'Nema veze — narudžba spremljena i bit će '
                                      'poslana automatski.'),
                            ),
                          );
                          context.pop('sent');
                        },
                      ),
                    ],
                  ),
      ),
    );
  }

  Future<void> _confirmClear(
      BuildContext context, OrderDetailsController controller) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Isprazni narudžbu'),
          content: const Text('Ukloniti sve stavke iz narudžbe?'),
          actions: [
            // Quiet cancel so a mis-tap defaults to the safe option.
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Odustani'),
            ),
            // Red confirm — matches the New Order screen's clear dialog.
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
    if (ok == true) controller.clearAll();
  }
}

String _fmtQty(double q) =>
    q == q.roundToDouble() ? q.toInt().toString() : q.toString();

/// One compact, expandable item row: quantity stepper · name · line total ·
/// chevron. The chevron reveals the napomene (remarks) editor + delete.
class _LineTile extends StatefulWidget {
  const _LineTile({
    super.key,
    required this.index,
    required this.line,
    required this.name,
    required this.lineTotal,
    required this.canChangeQty,
    required this.canDelete,
    required this.controller,
  });

  final int index;
  final OrderItem line;
  final String name;
  final String lineTotal;
  final bool canChangeQty;
  final bool canDelete;
  final OrderDetailsController controller;

  @override
  State<_LineTile> createState() => _LineTileState();
}

class _LineTileState extends State<_LineTile> {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  /// − decrements; at 1 it deletes the line (only if allowed).
  void _onMinus() {
    final q = widget.line.quantity;
    if (q > 1) {
      widget.controller.setQuantity(widget.index, q - 1);
    } else if (widget.canDelete) {
      widget.controller.deleteLine(widget.index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = widget.line;
    final s = _screenScale(context);

    return Padding(
      padding: EdgeInsets.only(bottom: 8 * s),
      // A real Material (not a Container) so the +/- ink ripple is clipped
      // inside the card instead of graying the list background behind it.
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
          // ── Header (always visible) ──────────────────────────────────────
          // Name + total on their own row. The amount sits in a fixed-width,
          // right-aligned column (reserved for up to "9.999,99 €") so a long
          // name has a hard boundary and wraps (up to 2 lines) instead of
          // colliding with the amount.
          Padding(
            padding: EdgeInsets.fromLTRB(12 * s, 7 * s, 6 * s, 4 * s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _toggle,
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
                    if (widget.canChangeQty)
                      _QtyStepper(
                        qty: line.quantity,
                        onMinus: _onMinus,
                        onPlus: () => widget.controller
                            .setQuantity(widget.index, line.quantity + 1),
                        onEdit: () => _editQty(context),
                      )
                    else
                      _StaticQty(qty: line.quantity),
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
          // ── Expandable napomene + delete ─────────────────────────────────
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
                        _NoteRow(
                          remarks: line.remarks,
                          onOpen: () => _editRemarks(context),
                          onRemove: (r) =>
                              widget.controller.toggleRemark(widget.index, r),
                        ),
                        if (widget.canDelete)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () =>
                                  widget.controller.deleteLine(widget.index),
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
      builder: (_) => _QtyDialog(initial: widget.line.quantity),
    );
    if (result != null) widget.controller.setQuantity(widget.index, result);
  }

  Future<void> _editRemarks(BuildContext context) async {
    await showAppBottomSheet<void>(
      context: context,
      sheetBuilder: (ctx) => AppBottomSheetScaffold(
        title: 'Napomene',
        footerDivider: false,
        body: _RemarksBody(
          predefined:
              widget.controller.predefinedRemarksForLine(widget.index),
          selected: widget.line.remarks,
          onToggle: (r) => widget.controller.toggleRemark(widget.index, r),
          onCustom: (r) => widget.controller.addCustomRemark(widget.index, r),
        ),
        footer: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Gotovo'),
          ),
        ),
      ),
    );
  }
}

/// Static quantity display when the user lacks the change-quantity right.
class _StaticQty extends StatelessWidget {
  const _StaticQty({required this.qty});

  final double qty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = _screenScale(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9 * s),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text('${_fmtQty(qty)}×',
          style: TextStyle(fontSize: 14 * s, fontWeight: FontWeight.w700)),
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

/// The "Dodaj napomenu" row — a slim add affordance when empty, or the remark
/// chips (removable) plus an add button when there are notes.
class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.remarks,
    required this.onOpen,
    required this.onRemove,
  });

  final List<String> remarks;
  final VoidCallback onOpen;
  final void Function(String) onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (remarks.isEmpty) {
      return InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.7)),
          ),
          child: Row(
            children: [
              Icon(Icons.chat_bubble_outline,
                  size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: 7),
              Text('Dodaj napomenu',
                  style: TextStyle(
                      fontSize: 12.5, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    // Constrain each chip to the row width so a long note WRAPS inside the chip
    // (full text, no "…"), and use a positive runSpacing so stacked chips never
    // collide.
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth;
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final r in remarks)
              _RemarkChip(text: r, maxWidth: maxW, onRemove: () => onRemove(r)),
            _AddNoteChip(onTap: onOpen),
          ],
        );
      },
    );
  }
}

/// A remark pill whose text wraps (never truncates); tap the ✕ to remove it.
class _RemarkChip extends StatelessWidget {
  const _RemarkChip({
    required this.text,
    required this.maxWidth,
    required this.onRemove,
  });

  final String text;
  final double maxWidth;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 6, 6, 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                text,
                softWrap: true,
                style: TextStyle(fontSize: 13, color: scheme.onSurface),
              ),
            ),
            const SizedBox(width: 4),
            InkResponse(
              onTap: onRemove,
              radius: 16,
              child: Icon(Icons.cancel,
                  size: 17, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "＋ Napomena" pill that opens the remarks sheet to add more.
class _AddNoteChip extends StatelessWidget {
  const _AddNoteChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 6, 12, 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 16, color: scheme.primary),
            const SizedBox(width: 4),
            Text('Napomena',
                style: TextStyle(fontSize: 13, color: scheme.primary)),
          ],
        ),
      ),
    );
  }
}

/// Full-width "＋ Dodaj stavku" button — returns to the item picker (New Order).
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

/// The remarks editor content, shown inside the shared branded bottom-sheet
/// drawer (`AppBottomSheetScaffold` provides the header + "Gotovo" footer).
class _RemarksBody extends StatefulWidget {
  const _RemarksBody({
    required this.predefined,
    required this.selected,
    required this.onToggle,
    required this.onCustom,
  });

  final List<String> predefined;
  final List<String> selected;
  final void Function(String) onToggle;
  final void Function(String) onCustom;

  @override
  State<_RemarksBody> createState() => _RemarksBodyState();
}

class _RemarksBodyState extends State<_RemarksBody> {
  final _custom = TextEditingController();
  late final Set<String> _selected = {...widget.selected};

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.predefined.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Nema predefiniranih napomena za ovaj artikl.',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        if (widget.predefined.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final r in widget.predefined)
                FilterChip(
                  label: Text(r),
                  selected: _selected.contains(r),
                  onSelected: (_) {
                    setState(() {
                      _selected.contains(r)
                          ? _selected.remove(r)
                          : _selected.add(r);
                    });
                    widget.onToggle(r);
                  },
                ),
            ],
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _custom,
                decoration: const InputDecoration(
                  labelText: 'Vlastita napomena',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: _addCustom,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => _addCustom(_custom.text),
              child: const Text('Dodaj'),
            ),
          ],
        ),
      ],
    );
  }

  void _addCustom(String value) {
    final t = value.trim();
    if (t.isEmpty) return;
    widget.onCustom(t);
    _custom.clear();
    setState(() => _selected.add(t));
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
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s = _screenScale(context);
    // Same teal as the New Order screen's Send action.
    final sendBg = dark ? const Color(0xFF1FA9B6) : const Color(0xFF0E9AA7);
    final sendFg = dark ? const Color(0xFF052A2E) : Colors.white;
    return Container(
      // Distinct footer surface + a top hairline so the total/send bar reads
      // as a separate element from the item cards above it. Extends edge-to-edge
      // and pads its own content clear of the device nav bar.
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
              onPressed: canSend ? () => onSend() : null,
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
