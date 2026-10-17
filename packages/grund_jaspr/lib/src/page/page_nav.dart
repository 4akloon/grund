/// Where and how a page appears in the navigation.
final class PageNav {
  /// Creates the navigation entry.
  const PageNav({this.label, this.group = 'main', this.order = 0});

  /// The link text; the page title when `null`.
  final String? label;

  /// The navigation group the entry belongs to.
  final String group;

  /// The position inside the group; lower comes first.
  final int order;
}
