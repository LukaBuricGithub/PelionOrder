import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/session_provider.dart';
import '../../master_data/models/article.dart';
import '../../master_data/models/article_group.dart';
import '../../master_data/state/master_data_providers.dart';
import '../models/order.dart';
import '../models/order_item.dart';
import 'orders_providers.dart';

@immutable
class NewOrderState {
  const NewOrderState({
    this.loading = true,
    this.groups = const [],
    this.articles = const [],
    this.selectedGroupCode,
    this.query = '',
    required this.order,
    this.sending = false,
  });

  final bool loading;
  final List<ArticleGroup> groups;
  final List<Article> articles;
  final String? selectedGroupCode;
  final String query;
  final Order order;
  final bool sending;

  NewOrderState copyWith({
    bool? loading,
    List<ArticleGroup>? groups,
    List<Article>? articles,
    String? selectedGroupCode,
    String? query,
    Order? order,
    bool? sending,
  }) {
    return NewOrderState(
      loading: loading ?? this.loading,
      groups: groups ?? this.groups,
      articles: articles ?? this.articles,
      selectedGroupCode: selectedGroupCode ?? this.selectedGroupCode,
      query: query ?? this.query,
      order: order ?? this.order,
      sending: sending ?? this.sending,
    );
  }

  bool get isEmptyOrder => order.items.isEmpty;

  /// Articles shown in the grid: name search across everything when the query
  /// is non-empty, otherwise the selected group's articles.
  List<Article> get visibleArticles {
    if (query.trim().isNotEmpty) {
      final q = query.trim().toLowerCase();
      return articles.where((a) => a.name.toLowerCase().contains(q)).toList();
    }
    if (selectedGroupCode == null) return const [];
    return articles.where((a) => a.groupCode == selectedGroupCode).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }
}

/// Backs the New Order screen: loads the menu, tracks live per-article
/// quantities and the running total, and sends / saves the order. Mirrors the
/// reference client's `NewOrderViewModel`.
class NewOrderController extends StateNotifier<NewOrderState> {
  NewOrderController(this._ref, this.tableCode)
      : super(NewOrderState(
          order: Order(orderTime: 0, userCode: '', tableCode: tableCode),
        )) {
    _init();
  }

  final Ref _ref;
  final int tableCode;

  final Map<int, Article> _byCode = {};

  Future<void> _init() async {
    try {
      final master = _ref.read(masterDataRepositoryProvider);
      final groups = await master.cachedGroups()
        ..sort((a, b) => a.order.compareTo(b.order));
      final articles = await master.cachedArticles();
      _byCode
        ..clear()
        ..addEntries(articles.map((a) => MapEntry(a.code, a)));

      final user = _ref.read(currentUserProvider);
      final order =
          await _ref.read(orderRepositoryProvider).getOrCreateOpenOrder(
                tableCode: tableCode,
                userCode: user?.code ?? '',
                nowMillis: DateTime.now().millisecondsSinceEpoch,
              );

      if (!mounted) return;
      state = state.copyWith(
        loading: false,
        groups: groups,
        articles: articles,
        selectedGroupCode: groups.isNotEmpty ? groups.first.code : null,
        order: order,
      );
    } catch (e, st) {
      // Never leave the screen wedged on the spinner: if loading fails for any
      // reason, drop out of the loading state with a fresh empty order so the
      // user can still work / back out.
      debugPrint('NewOrderController init failed: $e\n$st');
      if (!mounted) return;
      state = state.copyWith(loading: false);
    }
  }

  Article? articleFor(int code) => _byCode[code];

  double priceFor(int code) => _byCode[code]?.price ?? 0;

  double qtyFor(int code) => state.order.itemsMap[code] ?? 0;

  double get total {
    var sum = 0.0;
    state.order.itemsMap.forEach((code, qty) {
      sum += priceFor(code) * qty;
    });
    return sum;
  }

  void selectGroup(String code) =>
      state = state.copyWith(selectedGroupCode: code, query: '');

  void setQuery(String q) => state = state.copyWith(query: q);

  void addOne(int code) {
    final items = [...state.order.items];
    final idx =
        items.indexWhere((it) => it.code == code && it.remarks.isEmpty);
    if (idx >= 0) {
      items[idx] = items[idx].copyWith(quantity: items[idx].quantity + 1);
    } else {
      items.add(OrderItem(code: code, quantity: 1));
    }
    state = state.copyWith(order: state.order.copyWith(items: items));
  }

  void removeOne(int code) {
    final items = [...state.order.items];
    // Prefer a no-remark line; fall back to the last line for this code.
    var idx = items.indexWhere((it) => it.code == code && it.remarks.isEmpty);
    if (idx < 0) idx = items.lastIndexWhere((it) => it.code == code);
    if (idx < 0) return;
    final q = items[idx].quantity - 1;
    if (q <= 0) {
      items.removeAt(idx);
    } else {
      items[idx] = items[idx].copyWith(quantity: q);
    }
    state = state.copyWith(order: state.order.copyWith(items: items));
  }

  // ── Per-line editing (each tap on an article = its own line) ────────────────
  /// Appends a new line for [code] — never merges into an existing one.
  void addLine(int code) {
    final items = [...state.order.items, OrderItem(code: code, quantity: 1)];
    state = state.copyWith(order: state.order.copyWith(items: items));
  }

  void incrementLine(int index) {
    final items = [...state.order.items];
    if (index < 0 || index >= items.length) return;
    items[index] = items[index].copyWith(quantity: items[index].quantity + 1);
    state = state.copyWith(order: state.order.copyWith(items: items));
  }

  void decrementLine(int index) {
    final items = [...state.order.items];
    if (index < 0 || index >= items.length) return;
    final q = items[index].quantity - 1;
    if (q <= 0) {
      items.removeAt(index);
    } else {
      items[index] = items[index].copyWith(quantity: q);
    }
    state = state.copyWith(order: state.order.copyWith(items: items));
  }

  void removeLine(int index) {
    final items = [...state.order.items];
    if (index < 0 || index >= items.length) return;
    items.removeAt(index);
    state = state.copyWith(order: state.order.copyWith(items: items));
  }

  /// Removes every line for [code] (the cart's per-line ✕).
  void removeArticle(int code) {
    final items =
        state.order.items.where((it) => it.code != code).toList();
    state = state.copyWith(order: state.order.copyWith(items: items));
  }

  /// Clears the whole order.
  void clearItems() {
    state = state.copyWith(order: state.order.copyWith(items: const []));
  }

  /// Persists the current draft and returns its id (needed before opening the
  /// details screen).
  Future<int> saveDraftAndGetId() async {
    final id = await _ref.read(orderRepositoryProvider).saveDraft(state.order);
    state = state.copyWith(order: state.order.copyWith(id: id));
    return id;
  }

  /// Reloads the order from the DB (e.g. after returning from Order Details,
  /// where lines/remarks may have changed).
  Future<void> reloadOrder() async {
    final id = state.order.id;
    if (id == 0) return;
    final fresh = await _ref.read(orderRepositoryProvider).getOrder(id);
    if (fresh != null && mounted) state = state.copyWith(order: fresh);
  }

  /// Sends the order. Returns true when the server acknowledged, false when it
  /// was queued offline.
  Future<bool> send() async {
    state = state.copyWith(sending: true);
    final ok = await _ref.read(orderRepositoryProvider).sendOrder(state.order);
    if (mounted) state = state.copyWith(sending: false);
    _ref.invalidate(pendingOrdersCountProvider);
    return ok;
  }

  /// Called when leaving via Back: save the draft if it has items (keeps the
  /// table reserved), otherwise discard it and release the reservation.
  Future<void> handleBack() async {
    final repo = _ref.read(orderRepositoryProvider);
    if (state.isEmptyOrder) {
      if (state.order.id != 0) await repo.deleteOrder(state.order.id);
      await repo.removeReservation(tableCode);
    } else {
      await repo.saveDraft(state.order);
    }
  }
}

final newOrderControllerProvider = StateNotifierProvider.autoDispose
    .family<NewOrderController, NewOrderState, int>((ref, tableCode) {
  return NewOrderController(ref, tableCode);
});
