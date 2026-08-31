import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/presentation/bottom_sheet_safe_area.dart';
import '../state/orders_providers.dart';

/// A list of pending (not-yet-sent) orders — the offline queue. Tapping one
/// opens its details. Mirrors the reference client's `OrdersOverviewScreen`.
class OrdersOverviewScreen extends ConsumerWidget {
  const OrdersOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pendingOrdersListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Narudžbe na čekanju')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Greška: $e')),
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(
              child: Text('Nema narudžbi na čekanju.'),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(pendingOrdersListProvider),
            child: ListView.separated(
              padding: EdgeInsets.fromLTRB(
                  12, 12, 12, screenContentBottomPadding(context)),
              itemCount: orders.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, i) {
                final o = orders[i];
                final lineCount = o.items.length;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${o.tableCode}')),
                    title: Text('Stol ${o.tableCode}'),
                    subtitle: Text('Konobar: ${o.userCode} · '
                        '$lineCount ${lineCount == 1 ? 'stavka' : 'stavki'}'),
                    trailing: const Icon(Icons.sync, color: Colors.orange),
                    onTap: () async {
                      await context.push('/order-details/${o.id}');
                      ref.invalidate(pendingOrdersListProvider);
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
