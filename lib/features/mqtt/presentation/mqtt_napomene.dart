import 'package:flutter/material.dart';

import '../../shared/presentation/app_bottom_sheet.dart';

/// The napomene row for an order line: the current remarks as removable chips
/// plus an "add" affordance (or a slim "Dodaj napomenu" when empty). Tapping
/// opens the remarks sheet via [onOpen]; the ✕ on a chip calls [onRemove].
class MqttNoteRow extends StatelessWidget {
  const MqttNoteRow({
    super.key,
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
            border:
                Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
          ),
          child: Row(
            children: [
              Icon(Icons.chat_bubble_outline,
                  size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: 7),
              Text('Dodaj napomenu',
                  style:
                      TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

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
              child:
                  Icon(Icons.cancel, size: 17, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

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

/// Opens the branded bottom-sheet remarks editor: predefined chips (in a
/// capped, internally-scrolling area) + a custom-note field. Toggling a chip
/// calls [onToggle]; adding a custom note calls [onCustom].
Future<void> showMqttRemarksSheet({
  required BuildContext context,
  required List<String> predefined,
  required List<String> selected,
  required void Function(String) onToggle,
  required void Function(String) onCustom,
}) {
  return showAppBottomSheet<void>(
    context: context,
    sheetBuilder: (ctx) => AppBottomSheetScaffold(
      title: 'Napomene',
      footerDivider: false,
      body: _MqttRemarksBody(
        predefined: predefined,
        selected: selected,
        onToggle: onToggle,
        onCustom: onCustom,
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

class _MqttRemarksBody extends StatefulWidget {
  const _MqttRemarksBody({
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
  State<_MqttRemarksBody> createState() => _MqttRemarksBodyState();
}

class _MqttRemarksBodyState extends State<_MqttRemarksBody> {
  final _custom = TextEditingController();
  late final Set<String> _selected = {...widget.selected};

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show the predefined chips plus any custom napomene the user has added
    // (selected but not in the predefined list), so customs appear here too.
    // Tapping a chip toggles it; a custom one toggled off is removed entirely
    // (it disappears, since it only exists while selected).
    final customs =
        _selected.where((r) => !widget.predefined.contains(r)).toList();
    final chips = [...widget.predefined, ...customs];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (chips.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Nema predefiniranih napomena za ovaj artikl.',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        if (chips.isNotEmpty)
          // Cap the chips area at ~35% of the screen and scroll it internally,
          // so a long list doesn't push the custom-note field and "Gotovo"
          // off-screen. Fewer chips stay at natural size.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.35,
            ),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final r in chips)
                    FilterChip(
                      label: Text(r),
                      showCheckmark: false,
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
            ),
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
