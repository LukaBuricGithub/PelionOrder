import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/state/session_provider.dart';
import '../../master_data/models/terrace.dart';
import '../../master_data/models/user.dart';
import '../../master_data/models/venue_table.dart';
import '../../shared/presentation/bottom_sheet_safe_area.dart';
import '../state/orders_providers.dart';

/// A read-only map of occupied tables and who owns them, grouped by zone —
/// useful for seeing the floor without opening or changing anything. Mirrors
/// the reference client's `TablesOverviewScreen`.
class TablesOverviewScreen extends ConsumerWidget {
  const TablesOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tablesOverviewProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pregled stolova')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Greška: $e')),
        data: (data) {
          final (terraces, tables) = data;
          final occupied = tables.where((t) => t.userCode.isNotEmpty).toList();
          if (occupied.isEmpty) {
            return const Center(child: Text('Nema zauzetih stolova.'));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(tablesOverviewProvider),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  12, 12, 12, screenContentBottomPadding(context)),
              children: [
                for (final terrace in terraces)
                  ..._terraceSection(context, ref, terrace, occupied, user),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _terraceSection(
    BuildContext context,
    WidgetRef ref,
    Terrace terrace,
    List<VenueTable> occupied,
    User? user,
  ) {
    final inZone = occupied
        .where((t) => terrace.containsTable(t.code))
        .toList()
      ..sort((a, b) => a.code.compareTo(b.code));
    if (inZone.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        child: Text(
          'Zona ${terrace.code}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
      for (final t in inZone)
        Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            leading: CircleAvatar(child: Text('${t.code}')),
            title: Text(t.displayName),
            subtitle: Text('Konobar: ${t.userCode}'),
            trailing: t.itemCount > 0
                ? Chip(label: Text('${t.itemCount}'))
                : null,
            onTap: () => _openDetail(context, ref, t, user),
          ),
        ),
    ];
  }

  void _openDetail(
    BuildContext context,
    WidgetRef ref,
    VenueTable table,
    User? user,
  ) {
    final canOpen = user != null &&
        (table.userCode == user.code || user.allTablesOpenRight);
    if (!canOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nemate pravo pregleda ovog stola.')),
      );
      return;
    }
    context.push('/table-details/${table.code}/${table.userCode}');
  }
}
