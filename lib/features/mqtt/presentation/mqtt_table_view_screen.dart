import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/mqtt_service.dart';
import '../data/mqtt_table_query_sender.dart';
import '../models/mqtt_table_query.dart';
import '../models/mqtt_tables.dart';
import '../state/mqtt_tables_provider.dart';
import 'mqtt_order_screen.dart';

/// Read-only view of an occupied table: what is actually on it right now, asked
/// from the kasa over `kasa/{licenca}/upiti`.
///
/// Refresh strategy — deliberately not a poll. The answer is a snapshot and is
/// never retained, but `podaci/stolovi_stanje` IS retained and is republished
/// within ~3 s of anything changing on a table, so we re-ask only when THIS
/// table changes there. The one exception is `na_cekanju > 0`: the kasa is
/// still moving order lines onto the table, nothing else will announce it, so
/// we ask again shortly.
class MqttTableViewScreen extends ConsumerStatefulWidget {
  const MqttTableViewScreen({
    super.key,
    required this.state,
    this.tableBroj,
    this.tableNaziv,
  });

  final MqttTableState state;
  final int? tableBroj;
  final String? tableNaziv;

  @override
  ConsumerState<MqttTableViewScreen> createState() =>
      _MqttTableViewScreenState();
}

class _MqttTableViewScreenState extends ConsumerState<MqttTableViewScreen> {
  static final _money = NumberFormat.currency(locale: 'hr_HR', symbol: '€');

  bool _loading = true;
  MqttTableQueryResult? _result;
  Timer? _pendingTimer;

  /// Budget for the "still transferring" re-ask, so it can't run forever if the
  /// kasa never drains. It is REFILLED on every deliberate refresh (opening the
  /// screen, the refresh button, returning from an order, a change announced on
  /// stolovi_stanje) — otherwise one slow transfer would exhaust it and leave
  /// the screen permanently static for as long as it stayed open.
  int _pendingAsks = 0;
  static const _maxPendingAsks = 20; // 20 × 3 s ≈ a minute of watching

  int get _broj => widget.tableBroj ?? widget.state.stol;

  @override
  void initState() {
    super.initState();
    Future.microtask(_ask);
  }

  @override
  void dispose() {
    _pendingTimer?.cancel();
    super.dispose();
  }

  Future<void> _ask({bool silent = false, bool refill = false}) async {
    if (refill) _pendingAsks = 0;
    if (!silent) setState(() => _loading = true);
    final result = await MqttTableQuerySender.instance.ask(_broj);
    if (!mounted) return;

    // Progress means the kasa is working through the queue, so keep watching:
    // refill the budget whenever the pending count actually goes down.
    final previous = _result?.reply?.naCekanju;
    final reply = result.reply;
    if (previous != null && reply != null && reply.naCekanju < previous) {
      _pendingAsks = 0;
    }

    setState(() {
      _loading = false;
      _result = result;
    });

    // Still being transferred → ask again shortly; nothing else will tell us.
    _pendingTimer?.cancel();
    if (reply != null && reply.naCekanju > 0) {
      if (_pendingAsks < _maxPendingAsks) {
        _pendingAsks++;
        _pendingTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) _ask(silent: true);
        });
      } else {
        debugPrint('MQTT ▸ table $_broj still has ${reply.naCekanju} pending '
            'after $_maxPendingAsks asks — the kasa is not draining it');
      }
    }
  }

  /// Opens a NEW order for this table.
  ///
  /// The kasa has no "edit order" — a second nalog for the same stol simply
  /// appends its lines to the open bill (protocol doc, 3.3: corrections happen
  /// on the kasa, never by message). So the cart starts EMPTY and carries only
  /// what is being added; it is never seeded with the lines already on the
  /// table, which the kasa would happily book a second time.
  Future<void> _addItems() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MqttOrderScreen(
        tableBroj: _broj,
        tableNaziv: widget.tableNaziv,
      ),
    ));
    if (!mounted) return;
    // Whatever happened over there, re-read the table — and watch from scratch,
    // since an order that just landed is exactly what we want to see arrive.
    _ask(silent: true, refill: true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final naziv = widget.tableNaziv;
    final title = (naziv != null && naziv.isNotEmpty)
        ? 'Stol $_broj · $naziv'
        : 'Stol $_broj';

    // Re-ask when the kasa republishes a change for THIS table.
    ref.listen<Map<int, MqttTableState>>(mqttOccupiedProvider, (prev, next) {
      final before = prev?[_broj];
      final after = next[_broj];
      final changed = before?.stavki != after?.stavki ||
          before?.iznos != after?.iznos ||
          before?.cuser != after?.cuser;
      if (changed) _ask(silent: true, refill: true);
    });

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
              'Sadržaj stola',
              style:
                  TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Osvježi',
            onPressed: _loading ? null : () => _ask(refill: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _ask(silent: true),
          child: _buildBody(context),
        ),
      ),
      bottomNavigationBar: _AddItemsBar(onTap: _addItems),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _result == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final result = _result;
    if (result == null || !result.isOk) {
      return _Message(
        icon: Icons.cloud_off,
        title: result?.message ?? 'Glavni program ne odgovara.',
        detail: 'Glavni program odgovara samo dok je uključen i dok je '
            'povezan s bazom.',
        onRetry: () => _ask(),
      );
    }

    final reply = result.reply!;
    if (reply.isEmptyTable) {
      return _Message(
        icon: Icons.check_circle_outline,
        title: 'Stol je prazan.',
        detail: reply.naCekanju > 0
            ? 'Glavni program još prenosi ${reply.naCekanju} stavaka na stol…'
            : 'Na stolu nema otvorenih računa.',
        onRetry: () => _ask(),
      );
    }

    final multipleBills = reply.racuni.length > 1;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _StatusBanner(reply: reply, myOd: MqttService.instance.clientId),
        for (final racun in reply.racuni) ...[
          if (multipleBills) _BillHeader(racun: racun, money: _money),
          _BillCard(racun: racun, money: _money),
          const SizedBox(height: 12),
        ],
        _TotalRow(total: _money.format(reply.ukupno)),
      ],
    );
  }
}

/// The one action available here. Existing lines can never be changed from the
/// phone — this starts a SEPARATE order whose lines the kasa appends to the
/// bill.
class _AddItemsBar extends StatelessWidget {
  const _AddItemsBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.add),
              label: const Text('Dodaj stavke'),
            ),
          ),
        ),
      ),
    );
  }
}

/// Anything the waiter needs to know about the table's state before reading the
/// lines: transfers still in flight, and whether someone holds it on a kasa.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.reply, required this.myOd});

  final MqttTableQueryReply reply;
  final String? myOd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = <Widget>[];

    if (reply.naCekanju > 0) {
      final mine = reply.pendingForDevice(myOd);
      rows.add(_Chip(
        icon: Icons.sync,
        color: const Color(0xFF4A78B4),
        text: mine
            ? 'Vaša narudžba se prenosi na stol (${reply.naCekanju}), '
                'popis se još mijenja.'
            : 'Glavni program prenosi ${reply.naCekanju} stavaka na stol, popis se '
                'još '
                'mijenja.',
      ));
    }
    if (reply.heldByKasa) {
      rows.add(_Chip(
        icon: Icons.lock_outline,
        color: const Color(0xFFD46A5A),
        text: 'Stol je otvoren u glavnom programu (${reply.otvorenNa}).',
      ));
    }

    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in rows)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: r),
          Divider(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 13, height: 1.3, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

/// Only rendered when the table carries more than one open bill (a split).
class _BillHeader extends StatelessWidget {
  const _BillHeader({required this.racun, required this.money});

  final MqttRacun racun;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final who = racun.konobar.isNotEmpty ? racun.konobar : racun.cuser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 2),
      child: Row(
        children: [
          Text('Račun ${racun.crac}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          if (who.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text('· $who',
                style:
                    TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
          ],
          const Spacer(),
          Text(money.format(racun.ukupno),
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _BillCard extends StatelessWidget {
  const _BillCard({required this.racun, required this.money});

  final MqttRacun racun;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < racun.stavke.length; i++) ...[
            if (i > 0) Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
            _StavkaRow(stavka: racun.stavke[i], money: money),
          ],
        ],
      ),
    );
  }
}

class _StavkaRow extends StatelessWidget {
  const _StavkaRow({required this.stavka, required this.money});

  final MqttRacunStavka stavka;
  final NumberFormat money;

  String get _kol {
    final k = stavka.kol;
    final s = k == k.roundToDouble()
        ? k.toInt().toString()
        : k.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
    return s.replaceAll('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 38,
                child: Text('$_kol×',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              Expanded(
                child: Text(
                  stavka.naziv.isEmpty ? 'Artikl ${stavka.cartikl}' : stavka.naziv,
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 10),
              Text(money.format(stavka.iznos),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 38, top: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Sent lines are locked on the kasa; pending ones are not.
                _Tag(
                  text: stavka.poslano ? 'Poslano' : 'Nije poslano',
                  color: stavka.poslano
                      ? const Color(0xFF3E8E7E)
                      : scheme.onSurfaceVariant,
                ),
                Text(
                  '${money.format(stavka.mc)} / kom',
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                if (stavka.hasPopust)
                  Text(
                    'popust ${stavka.popust}% '
                    '(${money.format(stavka.cijenaBezPopusta)})',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          if (stavka.napomena.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 38, top: 5),
              child: Text(
                stavka.napomena,
                style: TextStyle(
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.total});

  final String total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Text('Ukupno',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(total,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onRetry,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(28, 80, 28, 24),
      children: [
        Icon(icon, size: 44, color: scheme.onSurfaceVariant),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13, height: 1.35, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        Center(
          child: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Pokušaj ponovno'),
          ),
        ),
      ],
    );
  }
}
