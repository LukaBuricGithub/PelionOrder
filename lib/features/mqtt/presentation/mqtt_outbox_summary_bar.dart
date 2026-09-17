import 'package:flutter/material.dart';

import '../state/mqtt_outbox_provider.dart';

/// The colours of "where is my order", the same on the floor plan, in the
/// status bar and in "Neposlane narudžbe": blue — items not sent yet; amber — with
/// the broker, waiting for the kasa; red — didn't get through.
Color mqttDraftColor(bool dark) =>
    dark ? const Color(0xFF7FA6DA) : const Color(0xFF4A78B4);
Color mqttAwaitingColor(bool dark) =>
    dark ? const Color(0xFFF4A83A) : const Color(0xFFE8890C);
Color mqttProblemColor(bool dark) =>
    dark ? const Color(0xFFFF7B72) : const Color(0xFFD64541);

/// How many of the waiter's orders are still on their way, sorted by what the
/// waiter should make of them.
class MqttOutboxSummary {
  const MqttOutboxSummary({
    this.drafts = 0,
    this.awaiting = 0,
    this.notSent = 0,
    this.failed = 0,
  });

  factory MqttOutboxSummary.of(
    Iterable<MqttOutboxOrder> orders, {
    int drafts = 0,
  }) {
    var awaiting = 0, notSent = 0, failed = 0;
    for (final o in orders) {
      switch (o.status) {
        case MqttOutboxStatus.sending:
        case MqttOutboxStatus.unconfirmed:
          awaiting++;
        case MqttOutboxStatus.notSent:
          notSent++;
        case MqttOutboxStatus.refused:
        case MqttOutboxStatus.stale:
          failed++;
      }
    }
    return MqttOutboxSummary(
      drafts: drafts,
      awaiting: awaiting,
      notSent: notSent,
      failed: failed,
    );
  }

  /// Tables with items added on this phone and not sent yet (blue).
  final int drafts;

  /// With the broker, waiting for the kasa's confirmation — also "Nije
  /// potvrđena": the broker hands it to the kasa when the kasa comes back
  /// (amber).
  final int awaiting;

  /// Didn't reach the broker — to be sent again (red).
  final int notSent;

  /// Refused by the kasa, or too old ("zastarjela") (red).
  final int failed;

  bool get isEmpty =>
      drafts == 0 && awaiting == 0 && notSent == 0 && failed == 0;
}

/// The strip above the zones on the floor plan: always there, always the same
/// height — "Sve je poslano" when there is nothing to report, otherwise the
/// counters in the colour of the most serious one (red, then amber, then
/// blue). Tapping it opens "Neposlane narudžbe".
///
/// Its fixed height is what keeps the floor plan still: the tables are laid
/// out once for the space below it, and nothing moves when a count changes.
class MqttOutboxStatusBar extends StatelessWidget {
  const MqttOutboxStatusBar({
    super.key,
    required this.summary,
    required this.onTap,
  });

  final MqttOutboxSummary summary;
  final VoidCallback onTap;

  /// The bar's height, margins not included.
  static const height = 40.0;

  static const _duration = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final blue = mqttDraftColor(dark);
    final amber = mqttAwaitingColor(dark);
    final red = mqttProblemColor(dark);
    // The bar takes the colour of the most serious thing it reports.
    final accent = summary.notSent > 0 || summary.failed > 0
        ? red
        : summary.awaiting > 0
        ? amber
        : summary.drafts > 0
        ? blue
        : scheme.outline;

    // Most urgent first: if the line doesn't fit, what is off-screen is the
    // least urgent.
    // Most urgent first: if the line doesn't fit, what is off-screen is the
    // least urgent.
    final counts = <(IconData, Color, String, int)>[
      if (summary.failed > 0)
        (Icons.error_outline, red, 'S greškom', summary.failed),
      if (summary.notSent > 0)
        (Icons.cloud_off_outlined, red, 'Nije poslano', summary.notSent),
      if (summary.awaiting > 0)
        (Icons.hourglass_top_rounded, amber, 'Čeka potvrdu', summary.awaiting),
      if (summary.drafts > 0)
        (Icons.edit_note, blue, 'Neposlano', summary.drafts),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
      child: AnimatedContainer(
        duration: _duration,
        height: height,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: dark ? 0.16 : 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.45)),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
              child: Row(
                children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: _duration,
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.centerLeft,
                        children: [...previous, ?current],
                      ),
                      child: counts.isEmpty
                          ? Row(
                              key: const ValueKey('ok'),
                              children: [
                                Icon(
                                  Icons.check_circle_outline,
                                  size: 18,
                                  color: scheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Sve je poslano',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            )
                          : _Counts(
                              key: const ValueKey('counts'),
                              counts: counts,
                            ),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The counters on ONE line, always with their labels. When they don't fit,
/// the line scrolls sideways — the bar never grows taller — and its right
/// edge fades out to show there is more. A tap still opens the list.
///
/// Whenever the counters change and don't fit, the line "peeks" once: it
/// glides to the end, waits a moment and glides back — then stays still.
class _Counts extends StatefulWidget {
  const _Counts({super.key, required this.counts});

  final List<(IconData, Color, String, int)> counts;

  @override
  State<_Counts> createState() => _CountsState();
}

class _CountsState extends State<_Counts> {
  final _scroll = ScrollController();

  /// Bumped by every new peek, so an older one still running stops.
  int _peekId = 0;

  static const _gap = 14.0;
  static const _fade = 16.0;

  static String _signature(List<(IconData, Color, String, int)> counts) =>
      [for (final (_, _, label, n) in counts) '$label$n'].join('|');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _peek());
  }

  @override
  void didUpdateWidget(_Counts old) {
    super.didUpdateWidget(old);
    if (_signature(old.counts) != _signature(widget.counts)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _peek());
    }
  }

  @override
  void dispose() {
    _peekId++;
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _peek() async {
    final id = ++_peekId;
    bool stale() => !mounted || id != _peekId || !_scroll.hasClients;

    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (stale()) return;
    final end = _scroll.position.maxScrollExtent;
    if (end <= 0) return; // everything fits: nothing to show
    // About a second for a typical overflow, a little longer for a long one.
    final glide = Duration(milliseconds: (end * 6).clamp(700, 1400).round());
    await _scroll.animateTo(end, duration: glide, curve: Curves.easeInOut);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (stale()) return;
    await _scroll.animateTo(0, duration: glide, curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ShaderMask(
      // Only content reaching the right edge — i.e. content that scrolls —
      // is faded there.
      shaderCallback: (rect) => LinearGradient(
        colors: const [Colors.white, Colors.white, Colors.transparent],
        stops: [0, 1 - _fade / rect.width, 1],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: _fade),
        child: Row(
          children: [
            for (final (i, (icon, color, label, n))
                in widget.counts.indexed) ...[
              if (i > 0) const SizedBox(width: _gap),
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 5),
              Text(
                '$label: ',
                style: TextStyle(fontSize: 13, color: scheme.onSurface),
              ),
              Text(
                '$n',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
