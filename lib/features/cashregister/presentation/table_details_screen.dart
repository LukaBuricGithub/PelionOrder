import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../state/orders_providers.dart';

/// A read-only summary of what is currently on a specific occupied table — the
/// aggregated items and the running bill total, from the venue's `tableDetail`
/// endpoint. Mirrors the reference client's `TableDetailsScreen`.
class TableDetailsScreen extends ConsumerWidget {
  const TableDetailsScreen({
    super.key,
    required this.tableCode,
    required this.userCode,
  });

  final int tableCode;
  final String userCode;

  static final _money =
      NumberFormat.currency(locale: 'hr_HR', symbol: '€', decimalDigits: 2);

  static String _fmtQty(double q) =>
      q == q.roundToDouble() ? q.toInt().toString() : q.toString();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tableDetailProvider(tableCode));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stol $tableCode'),
            if (userCode.isNotEmpty)
              Text('Konobar: $userCode',
                  style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      body: SafeArea(
        bottom: true,
        child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Pregled stola zahtijeva vezu s poslužiteljem.\n\n$e',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (lines) {
          if (lines.isEmpty) {
            return const Center(child: Text('Stol je prazan.'));
          }
          final total =
              lines.fold<double>(0, (sum, l) => sum + l.amount);
          return Column(
            children: [
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: lines.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final l = lines[i];
                    return ListTile(
                      title: Text(l.itemName),
                      leading: Text(
                        _fmtQty(l.quantity),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      trailing: Text(_money.format(l.amount)),
                    );
                  },
                ),
              ),
              Material(
                elevation: 8,
                color: Theme.of(context).colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Ukupno',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      Text(_money.format(total),
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        ),
      ),
    );
  }
}
