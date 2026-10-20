import 'package:flutter/material.dart';

/// The drag strip on a reorder row, on the row's **trailing** edge where the
/// thumb holding the phone rests.
///
/// Shared by both reorder modes — Stol X's cart and "Detalji narudžbe" — so
/// the two cannot drift apart. They were separate copies at different widths
/// and in different colours until the user asked for them to be aligned.
///
/// The navy is the "Presloži stavke" button's own colour, as a tint: the mode
/// and the button that started it read as one thing, without a solid block on
/// every row. Dragging starts at once from here; the rest of the row drags
/// after a long press, so a plain vertical swipe still scrolls a long order.
class MqttReorderHandle extends StatelessWidget {
  const MqttReorderHandle({
    super.key,
    required this.index,
    required this.scale,
  });

  /// The row's index in the `ReorderableListView` this handle belongs to.
  final int index;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s = scale;

    return ReorderableDragStartListener(
      index: index,
      child: Container(
        width: 44 * s,
        color: dark ? const Color(0xFF17253C) : const Color(0xFFDDE9F6),
        alignment: Alignment.center,
        child: Icon(
          Icons.drag_handle,
          size: 22 * s,
          color: dark ? const Color(0xFF4F8BE8) : const Color(0xFF2F6FB3),
        ),
      ),
    );
  }
}
