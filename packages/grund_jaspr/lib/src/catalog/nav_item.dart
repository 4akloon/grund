/// One entry of a site's navigation.
final class NavItem {
  /// Creates the entry.
  const NavItem({
    required this.label,
    required this.path,
    required this.group,
    required this.order,
  });

  /// The link text.
  final String label;

  /// The full path of the page, site path included.
  final String path;

  /// The navigation group the entry belongs to.
  final String group;

  /// The position inside the group; lower comes first.
  final int order;
}
