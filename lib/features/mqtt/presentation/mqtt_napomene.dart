import 'package:flutter/material.dart';

import '../../shared/presentation/app_bottom_sheet.dart';
import '../models/mqtt_menu.dart';

/// One chip in the note row: a label plus how to remove it. The caller resolves
/// predefined remark codes to their names before building these.
class MqttNoteChip {
  const MqttNoteChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;
}

/// The napomene row for an order line: the line's notes as removable chips plus
/// an "add" affordance (or a slim "Dodaj napomenu" when empty). Tapping opens
/// the remarks sheet via [onOpen].
class MqttNoteRow extends StatelessWidget {
  const MqttNoteRow({
    super.key,
    required this.chips,
    required this.onOpen,
  });

  final List<MqttNoteChip> chips;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (chips.isEmpty) {
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
            for (final chip in chips)
              _RemarkChip(
                  text: chip.label, maxWidth: maxW, onRemove: chip.onRemove),
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

/// Opens the branded bottom-sheet remarks editor: the article's predefined
/// remarks as chips (selected by **code**) plus the line's free-text notes, in a
/// capped, internally-scrolling area, with a field to add a new note.
///
/// Toggling a predefined chip calls [onToggleCode] with its `cnap`; tapping a
/// note chip removes it via [onRemoveNote]; the field adds via [onAddNote].
Future<void> showMqttRemarksSheet({
  required BuildContext context,
  required List<MqttRemark> available,
  required List<String> selectedCodes,
  required List<String> customNotes,
  required void Function(String cnap) onToggleCode,
  required void Function(String note) onAddNote,
  required void Function(String note) onRemoveNote,
}) {
  return showAppBottomSheet<void>(
    context: context,
    sheetBuilder: (ctx) => AppBottomSheetScaffold(
      title: 'Napomene',
      footerDivider: false,
      body: _MqttRemarksBody(
        available: available,
        selectedCodes: selectedCodes,
        customNotes: customNotes,
        onToggleCode: onToggleCode,
        onAddNote: onAddNote,
        onRemoveNote: onRemoveNote,
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
    required this.available,
    required this.selectedCodes,
    required this.customNotes,
    required this.onToggleCode,
    required this.onAddNote,
    required this.onRemoveNote,
  });

  final List<MqttRemark> available;
  final List<String> selectedCodes;
  final List<String> customNotes;
  final void Function(String cnap) onToggleCode;
  final void Function(String note) onAddNote;
  final void Function(String note) onRemoveNote;

  @override
  State<_MqttRemarksBody> createState() => _MqttRemarksBodyState();
}

class _MqttRemarksBodyState extends State<_MqttRemarksBody> {
  final _custom = TextEditingController();
  late final Set<String> _codes = {...widget.selectedCodes};
  late final List<String> _notes = [...widget.customNotes];

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasAny = widget.available.isNotEmpty || _notes.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!hasAny)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Nema predefiniranih napomena za ovaj artikl.',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        if (hasAny)
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
                  // Predefined remarks — selected by code.
                  for (final r in widget.available)
                    FilterChip(
                      label: Text(r.naziv),
                      showCheckmark: false,
                      selected: _codes.contains(r.cnap),
                      onSelected: (_) {
                        setState(() {
                          _codes.contains(r.cnap)
                              ? _codes.remove(r.cnap)
                              : _codes.add(r.cnap);
                        });
                        widget.onToggleCode(r.cnap);
                      },
                    ),
                  // Free-text notes — always selected; tapping deletes them.
                  for (final n in List<String>.from(_notes))
                    FilterChip(
                      label: Text(n),
                      showCheckmark: false,
                      selected: true,
                      onSelected: (_) {
                        setState(() => _notes.remove(n));
                        widget.onRemoveNote(n);
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
    if (t.isEmpty || _notes.contains(t)) return;
    widget.onAddNote(t);
    _custom.clear();
    setState(() => _notes.add(t));
  }
}
