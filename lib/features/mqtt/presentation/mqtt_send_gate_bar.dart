import 'package:flutter/material.dart';

import '../state/mqtt_send_gate_provider.dart';

/// A thin strip under an app bar saying why sending is locked
/// ("Kasa nije u prodaji, slanje je zaključano"). Put it in `AppBar.bottom`
/// only while the gate is closed, so it takes no space when sending is open.
class MqttSendGateBar extends StatelessWidget implements PreferredSizeWidget {
  const MqttSendGateBar({super.key, required this.gate});

  final MqttSendGate gate;

  static const double height = 34;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Amber when the kasa is there but not selling — a normal, passing state.
    // Red when nothing can go out at all: no code, no connection, no kasa.
    final passing = gate == MqttSendGate.kasaNijeUProdaji;
    final color = passing
        ? (dark ? const Color(0xFFF4A83A) : const Color(0xFFE8890C))
        : (dark ? const Color(0xFFFF7B72) : const Color(0xFFD64541));
    final fg = dark ? const Color(0xFF10151C) : Colors.white;
    final icon = switch (gate) {
      MqttSendGate.skenirajKod => Icons.qr_code_scanner,
      MqttSendGate.ordermanNijeSpojen => Icons.wifi_off_rounded,
      MqttSendGate.kasaNijeUProdaji => Icons.point_of_sale_outlined,
      MqttSendGate.kasaNijeSpojena => Icons.cloud_off_outlined,
      MqttSendGate.otkljucano => Icons.lock_open,
    };
    return Container(
      height: height,
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${gate.message}, slanje je zaključano',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
