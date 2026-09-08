/// How densely the price-list grid is drawn on the order screen.
///
/// The right density depends on the VENUE, not the phone: a menu of "Kava" and
/// "Pivo" is well served by 16 tiles a page, while one full of "Rižoto s
/// plodovima mora" needs the width. The app cannot infer that, and deriving it
/// from the data would reshuffle the pages whenever the price list changed —
/// waiters remember where things sit — so it is a deliberate, set-once choice.
///
/// Each level carries its own geometry so the grids and the settings screen
/// agree without repeating the numbers.
enum MenuViewSize {
  /// 4 × 4 — the densest layout, fewest page swipes.
  small,

  /// 3 × 4 — a third more width per tile, same number of rows. Width is what
  /// long article names actually need.
  medium,

  /// 3 × 3 — widest and tallest tiles; best in poor light, most swiping.
  large;

  /// Columns in the article grid.
  int get articleColumns => switch (this) {
        MenuViewSize.small => 4,
        MenuViewSize.medium => 3,
        MenuViewSize.large => 3,
      };

  /// Rows of articles per page.
  int get articleRows => switch (this) {
        MenuViewSize.small => 4,
        MenuViewSize.medium => 4,
        MenuViewSize.large => 3,
      };

  int get articlesPerPage => articleColumns * articleRows;

  /// Unscaled article tile height. Chosen so every level fills roughly the same
  /// vertical space — dropping a row without growing the tiles would just leave
  /// a gap under the grid.
  double get articleTileHeight => switch (this) {
        MenuViewSize.small => 58,
        MenuViewSize.medium => 58,
        MenuViewSize.large => 79,
      };

  /// Columns in the group strip. Kept in step with the articles: if the article
  /// tiles grow and the group tiles don't, the two halves stop looking like one
  /// screen.
  int get groupColumns => switch (this) {
        MenuViewSize.small => 4,
        MenuViewSize.medium => 3,
        MenuViewSize.large => 3,
      };

  /// Unscaled group tile height.
  double get groupRowHeight => switch (this) {
        MenuViewSize.small => 44,
        MenuViewSize.medium => 44,
        MenuViewSize.large => 52,
      };

  /// Croatian label for the settings selector.
  String get label => switch (this) {
        MenuViewSize.small => 'Mali',
        MenuViewSize.medium => 'Srednji',
        MenuViewSize.large => 'Veliki',
      };

  static MenuViewSize fromName(String? name) {
    return MenuViewSize.values.firstWhere(
      (v) => v.name == name,
      orElse: () => MenuViewSize.small,
    );
  }
}
