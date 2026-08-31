/// Display preference for how large the table tiles are drawn in the table
/// layout. Mirrors the reference client's `TableViewSize` enum.
enum TableViewSize {
  small,
  medium,
  large;

  /// Croatian label for the settings selector.
  String get label => switch (this) {
        TableViewSize.small => 'Male',
        TableViewSize.medium => 'Srednje',
        TableViewSize.large => 'Velike',
      };

  static TableViewSize fromName(String? name) {
    return TableViewSize.values.firstWhere(
      (v) => v.name == name,
      orElse: () => TableViewSize.medium,
    );
  }
}
