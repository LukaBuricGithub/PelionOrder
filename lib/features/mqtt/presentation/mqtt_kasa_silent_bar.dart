import 'package:flutter/material.dart';

import '../state/mqtt_kasa_silence_provider.dart';

/// A strip under an app bar saying the kasa has stopped confirming orders.
/// Put it in `AppBar.bottom` only while [mqttKasaSilentProvider] is true, so
/// it takes no space the rest of the time — and only when sending is open,
/// because [MqttSendGateBar] then has the better explanation ("glavni program
/// nije u blagajni" is a reason; this is just the symptom).
///
/// It deliberately does nothing when tapped. There is nothing to do here: the
/// orders it is about are frozen in "Neposlane narudžbe", the table's own
/// unconfirmed lines are already red in the list right below, and opening
/// another screen on top of a half-entered order helps nobody. What it buys is
/// that the waiter knows BEFORE they key in the next round — and the send
/// button then asks once more (see the order screen).
///
/// Red, two lines tall and worded without jargon: the waiter's next step is to
/// walk over to the kasa, not to read about MQTT.
class MqttKasaSilentBar extends StatelessWidget implements PreferredSizeWidget {
  const MqttKasaSilentBar({super.key, required this.count});

  /// How many orders in a row went unanswered — only for the log and for
  /// [Semantics]; the strip itself says the short version.
  final int count;

  static const double height = 50;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = dark ? const Color(0xFFFF7B72) : const Color(0xFFD64541);
    final fg = dark ? const Color(0xFF10151C) : Colors.white;
    return Semantics(
      label: '${mqttKasaSilenceText(count)}. Provjerite na kasi.',
      child: Container(
        height: height,
        width: double.infinity,
        color: color,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(Icons.help_outline, size: 18, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Glavni program ne potvrđuje narudžbe · provjerite na kasi',
                maxLines: 2,
                style: TextStyle(
                  height: 1.15,
                  color: fg,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
