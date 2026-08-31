import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/session_provider.dart';
import '../../master_data/models/article.dart';
import '../../master_data/state/master_data_providers.dart';
import '../models/order.dart';
import '../models/order_item.dart';
import 'orders_providers.dart';

@immutable
class OrderDetailsState {
  const OrderDetailsState({
    this.loading = true,
    this.order,
    this.sending = false,
    this.changeQuantityRight = false,
    this.deleteRight = false,
  });

  final bool loading;
  final Order? order;
  final bool sending;
  final bool changeQuantityRight;
  final bool deleteRight;

  OrderDetailsState copyWith({
    bool? loading,
    Order? order,
    bool? sending,
    bool? changeQuantityRight,
    bool? deleteRight,
  }) {
    return OrderDetailsState(
      loading: loading ?? this.loading,
      order: order ?? this.order,
      sending: sending ?? this.sending,
      changeQuantityRight: changeQuantityRight ?? this.changeQuantityRight,
      deleteRight: deleteRight ?? this.deleteRight,
    );
  }
}

/// Backs the Order Details screen: per-line quantity, remarks (predefined +
/// custom), delete and drag-reorder, then send. Every mutation is persisted so
/// the draft stays in sync. Mirrors the reference client's
/// `OrderDetailsViewModel`.
class OrderDetailsController extends StateNotifier<OrderDetailsState> {
  OrderDetailsController(this._ref, this.orderId)
      : super(const OrderDetailsState()) {
    _init();
  }

  final Ref _ref;
  final int orderId;

  final Map<int, Article> _byCode = {};
  final Map<int, List<String>> _remarksByCode = {};

  Future<void> _init() async {
    final master = _ref.read(masterDataRepositoryProvider);
    for (final a in await master.cachedArticles()) {
      _byCode[a.code] = a;
    }
    for (final r in await master.cachedRemarks()) {
      _remarksByCode.putIfAbsent(r.itemId, () => []).add(r.name);
    }
    final order = await _ref.read(orderRepositoryProvider).getOrder(orderId);
    final user = _ref.read(currentUserProvider);
    if (!mounted) return;
    state = state.copyWith(
      loading: false,
      order: order,
      changeQuantityRight: user?.changeQuantityRight ?? false,
      deleteRight: user?.deleteRight ?? false,
    );
  }

  Article? articleFor(int code) => _byCode[code];

  String articleName(int code) => _byCode[code]?.name ?? 'Artikl $code';

  double priceFor(int code) => _byCode[code]?.price ?? 0;

  /// Predefined remarks available for the article on [lineIndex].
  List<String> predefinedRemarksForLine(int lineIndex) {
    final order = state.order;
    if (order == null || lineIndex >= order.items.length) return const [];
    return _remarksByCode[order.items[lineIndex].code] ?? const [];
  }

  double get total {
    final order = state.order;
    if (order == null) return 0;
    var sum = 0.0;
    for (final it in order.items) {
      sum += priceFor(it.code) * it.quantity;
    }
    return sum;
  }

  Future<void> _apply(List<OrderItem> items) async {
    final order = state.order;
    if (order == null) return;
    final updated = order.copyWith(items: items);
    state = state.copyWith(order: updated);
    // Preserve pending/sent so editing a queued order doesn't drop it from the
    // offline send queue.
    await _ref.read(orderRepositoryProvider).updateOrder(updated);
  }

  Future<void> setQuantity(int lineIndex, double quantity) async {
    final order = state.order;
    if (order == null) return;
    final items = [...order.items];
    if (lineIndex < 0 || lineIndex >= items.length) return;
    if (quantity <= 0) {
      items.removeAt(lineIndex);
    } else {
      items[lineIndex] = items[lineIndex].copyWith(quantity: quantity);
    }
    await _apply(items);
  }

  Future<void> deleteLine(int lineIndex) async {
    final order = state.order;
    if (order == null) return;
    final items = [...order.items]..removeAt(lineIndex);
    await _apply(items);
  }

  Future<void> toggleRemark(int lineIndex, String remark) async {
    final order = state.order;
    if (order == null) return;
    final items = [...order.items];
    final line = items[lineIndex];
    final remarks = [...line.remarks];
    if (remarks.contains(remark)) {
      remarks.remove(remark);
    } else {
      remarks.add(remark);
    }
    items[lineIndex] = line.copyWith(remarks: remarks);
    await _apply(items);
  }

  Future<void> addCustomRemark(int lineIndex, String remark) async {
    final trimmed = remark.trim();
    if (trimmed.isEmpty) return;
    final order = state.order;
    if (order == null) return;
    final items = [...order.items];
    final line = items[lineIndex];
    if (line.remarks.contains(trimmed)) return;
    items[lineIndex] = line.copyWith(remarks: [...line.remarks, trimmed]);
    await _apply(items);
  }

  /// Removes every line (the ⋮ "Isprazni narudžbu" action).
  Future<void> clearAll() async {
    if (state.order == null) return;
    await _apply(const []);
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final order = state.order;
    if (order == null) return;
    final items = [...order.items];
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    await _apply(items);
  }

  /// Sends the order. Returns true when acknowledged, false when queued.
  Future<bool> send() async {
    final order = state.order;
    if (order == null) return false;
    state = state.copyWith(sending: true);
    final ok = await _ref.read(orderRepositoryProvider).sendOrder(order);
    if (mounted) state = state.copyWith(sending: false);
    _ref.invalidate(pendingOrdersCountProvider);
    return ok;
  }
}

final orderDetailsControllerProvider = StateNotifierProvider.autoDispose
    .family<OrderDetailsController, OrderDetailsState, int>((ref, orderId) {
  return OrderDetailsController(ref, orderId);
});
