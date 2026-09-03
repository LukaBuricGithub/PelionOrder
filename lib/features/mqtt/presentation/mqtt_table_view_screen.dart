import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/mqtt_tables.dart';

/// Read-only view of a table occupied by the current user. The broker only
/// sends a summary (`podaci/stolovi_stanje`) — amount, item count, waiter — so
/// that's all we can show; there is no editing or deleting here. Item-level
/// data can be added later if the broker starts sending it.
class MqttTableViewScreen extends StatelessWidget {
  const MqttTableViewScreen({
    super.key,
    required this.state,
    this.tableBroj,
    this.tableNaziv,
  });

  final MqttTableState state;
  final int? tableBroj;
  final String? tableNaziv;

  static final _money = NumberFormat.currency(locale: 'hr_HR', symbol: '€');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final broj = tableBroj ?? state.stol;
    final naziv = tableNaziv;
    final title = (naziv != null && naziv.isNotEmpty)
        ? 'Stol $broj · $naziv'
        : 'Stol $broj';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: Theme.of(context).appBarTheme.titleTextStyle ??
                  Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              'Pregled (samo za čitanje)',
              style: TextStyle(
                  fontSize: 13.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Column(
                children: [
                  _Row(label: 'Konobar', value: state.konobar),
                  const Divider(height: 1),
                  _Row(label: 'Broj stavki', value: '${state.stavki}'),
                  const Divider(height: 1),
                  _Row(label: 'Iznos', value: _money.format(state.iznos)),
                  if (state.kupac.trim().isNotEmpty) ...[
                    const Divider(height: 1),
                    _Row(label: 'Kupac', value: state.kupac),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Ovaj stol je zauzet vašom narudžbom. Pojedinačne stavke trenutno '
              'nisu dostupne — prikazan je samo sažetak.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14)),
          const Spacer(),
          Flexible(
            child: Text(
              value.isEmpty ? '—' : value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
