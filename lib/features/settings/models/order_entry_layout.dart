/// How the order-entry screen ("Stol X") is laid out on this phone.
///
/// A per-device choice, like the tile size: it changes nothing about what is
/// sent, only how the waiter works. Venues moving from the older Pelion
/// orderman asked for [list], where the screen opens on the price list and
/// the table's existing items are a tap away rather than in front of you.
enum OrderEntryLayout {
  /// The paged tile grid with the running order beside it — what the app has
  /// always done, and the default.
  grid,

  /// A vertical price list, one row per article, quantity adjusted on the row
  /// itself. The table's existing items are NOT shown here (they are under
  /// "Detalji"), and the total counts only what is being added now.
  list;

  /// Croatian label for the settings selector.
  String get label => switch (this) {
    OrderEntryLayout.grid => 'Mreža',
    OrderEntryLayout.list => 'Popis',
  };

  static OrderEntryLayout fromName(String? name) => OrderEntryLayout.values
      .firstWhere((v) => v.name == name, orElse: () => OrderEntryLayout.grid);
}
