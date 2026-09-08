import 'package:shared_preferences/shared_preferences.dart';

import '../models/menu_view_size.dart';
import '../models/table_view_size.dart';

/// Persists device display / sending preferences in [SharedPreferences],
/// mirroring the reference client's `TABLE_VIEW_SIZE` and
/// `SHOULD_GROUP_ARTICLES_KEY` (default true) plus `BUSINESS_NAME` and the
/// logged-in `USER` code.
class SettingsStorage {
  SettingsStorage(this._prefs);

  final SharedPreferences _prefs;

  static const _tableViewSizeKey = 'table_view_size_v1';
  static const _menuViewSizeKey = 'menu_view_size_v1';
  static const _shouldGroupArticlesKey = 'should_group_articles_v1';
  static const _businessNameKey = 'business_name_v1';
  static const _currentUserCodeKey = 'current_user_code_v1';

  TableViewSize loadTableViewSize() =>
      TableViewSize.fromName(_prefs.getString(_tableViewSizeKey));

  Future<void> saveTableViewSize(TableViewSize size) async {
    await _prefs.setString(_tableViewSizeKey, size.name);
  }

  /// Density of the price-list grid on the order screen. Defaults to the
  /// densest layout — that is what the app shipped with, so an existing device
  /// sees no change until someone chooses otherwise.
  MenuViewSize loadMenuViewSize() =>
      MenuViewSize.fromName(_prefs.getString(_menuViewSizeKey));

  Future<void> saveMenuViewSize(MenuViewSize size) async {
    await _prefs.setString(_menuViewSizeKey, size.name);
  }

  /// Whether identical items are combined into a single line when an order is
  /// sent. Defaults to **false**: each tap stays its own line on the kitchen
  /// ticket, which is how the venue wants orders to read.
  bool loadShouldGroupArticles() =>
      _prefs.getBool(_shouldGroupArticlesKey) ?? false;

  Future<void> saveShouldGroupArticles(bool value) async {
    await _prefs.setBool(_shouldGroupArticlesKey, value);
  }

  /// Venue/business name reported by the `/ping` heartbeat.
  String? loadBusinessName() => _prefs.getString(_businessNameKey);

  Future<void> saveBusinessName(String? name) async {
    if (name == null || name.isEmpty) {
      await _prefs.remove(_businessNameKey);
    } else {
      await _prefs.setString(_businessNameKey, name);
    }
  }

  /// Code of the currently signed-in waiter (set after PIN login).
  String? loadCurrentUserCode() => _prefs.getString(_currentUserCodeKey);

  Future<void> saveCurrentUserCode(String? code) async {
    if (code == null || code.isEmpty) {
      await _prefs.remove(_currentUserCodeKey);
    } else {
      await _prefs.setString(_currentUserCodeKey, code);
    }
  }
}
