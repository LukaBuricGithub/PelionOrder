/// ESC/POS bytes for the thermal printer.
///
/// Built by hand rather than with a package: a test print needs six commands,
/// and the awkward part — what a 58 mm printer does with č, ć, ž, š and đ —
/// is not something a library decides for us (see [asciiFold]).
library;

import 'dart:convert';

/// 58 mm paper, font A: 32 characters per line.
const int kLineWidth = 32;

/// Commands, by their ESC/POS names.
const List<int> _init = [0x1B, 0x40]; // ESC @ — reset
const List<int> _alignLeft = [0x1B, 0x61, 0x00]; // ESC a 0
const List<int> _alignCenter = [0x1B, 0x61, 0x01]; // ESC a 1
const List<int> _boldOn = [0x1B, 0x45, 0x01]; // ESC E 1
const List<int> _boldOff = [0x1B, 0x45, 0x00]; // ESC E 0
const List<int> _doubleOn = [0x1D, 0x21, 0x11]; // GS ! — double width+height
const List<int> _doubleOff = [0x1D, 0x21, 0x00];
const List<int> _cut = [0x1D, 0x56, 0x01]; // GS V 1 — partial cut

/// Feed [lines] blank lines (ESC d n).
List<int> feed(int lines) => [0x1B, 0x64, lines];

/// Croatian letters folded to ASCII.
///
/// These printers don't speak UTF-8: they print one byte per character from a
/// code page, and which code page a given model uses (CP852, CP1250, or
/// whatever the factory set) differs per unit. Folding is not pretty, but it
/// is readable on every printer — "Uređaj" prints as "Uredaj" instead of the
/// random glyph an unsupported byte produces. A code page can be selected
/// later (ESC t n), once we know what the venues' printers actually support.
String asciiFold(String text) {
  const map = {
    'č': 'c',
    'ć': 'c',
    'ž': 'z',
    'š': 's',
    'đ': 'd',
    'Č': 'C',
    'Ć': 'C',
    'Ž': 'Z',
    'Š': 'S',
    'Đ': 'D',
  };
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(map[char] ?? char);
  }
  return buffer.toString();
}

/// One line of text, folded and cut to the paper width.
List<int> line(String text) {
  final folded = asciiFold(text);
  final clipped = folded.length > kLineWidth
      ? folded.substring(0, kLineWidth)
      : folded;
  return [...latin1.encode(clipped), 0x0A];
}

/// A full-width rule, e.g. "--------------------------------".
List<int> rule([String char = '-']) => line(char * kLineWidth);

/// The test print from "Postavke uređaja": proves the phone reaches the
/// printer, and shows which device and venue it was sent from.
///
/// The printer can be set up before the phone has a QR code — the two are
/// unrelated — so [venue] and [device] may be empty. The slip then says the
/// device isn't activated yet instead of printing blank fields, which would
/// read like a fault.
List<int> testPrint({
  required String venue,
  required String device,
  required DateTime now,
}) {
  final activated = venue.isNotEmpty || device.isNotEmpty;
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp =
      '${two(now.day)}.${two(now.month)}.${now.year}. '
      '${two(now.hour)}:${two(now.minute)}';

  return [
    ..._init,
    ..._alignCenter,
    ..._doubleOn,
    ..._boldOn,
    ...line('PELION ORDER'),
    ..._doubleOff,
    ...line('PROBNI ISPIS'),
    ..._boldOff,
    ...feed(1),
    ..._alignLeft,
    ...rule(),
    if (activated) ...[
      if (venue.isNotEmpty) ...line('Objekt: $venue'),
      if (device.isNotEmpty) ...line('Uredaj: $device'),
    ] else ...[
      ...line('Uredaj jos nije aktiviran.'),
      ...line('Skenirajte QR kod na blagajni.'),
    ],
    ...line('Vrijeme: $stamp'),
    ...rule(),
    ...line('Pisac je ispravno povezan.'),
    // Paper past the tear-off edge, then a cut for the printers that have a
    // cutter (the others ignore it).
    ...feed(4),
    ..._cut,
  ];
}
