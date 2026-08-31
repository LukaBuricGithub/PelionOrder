import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../master_data/state/heartbeat_provider.dart';

/// Small pill showing the live venue-server connection status (Online / Offline)
/// driven by the heartbeat. Mirrors the reference client's online indicator.
class OnlineStatusBadge extends ConsumerWidget {
  const OnlineStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(heartbeatProvider);
    final scheme = Theme.of(context).colorScheme;
    final color = online ? const Color(0xFF2E7D32) : scheme.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            online ? 'Online' : 'Offline',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
