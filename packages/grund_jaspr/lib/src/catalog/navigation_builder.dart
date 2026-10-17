import '../page/page_address.dart';
import '../page/page_path.dart';
import '../page/site_page.dart';
import 'nav_item.dart';

/// Turns pages into the sorted navigation of a site.
abstract final class NavigationBuilder {
  /// The navigation entries of [pages]: by `order`, then `label`, then
  /// `path`.
  ///
  /// A page is in when it has `meta.nav`, a concrete URL (a path with a
  /// `:param` is left out), and is not left out by its sitemap settings:
  /// `included == false` always leaves it out, and a page with its own
  /// `hooks.use` stays out unless `included == true`.
  static List<NavItem> of(Iterable<SitePage> pages) =>
      [
        for (final page in pages)
          if (_isListed(page)) _itemOf(page),
      ]..sort((a, b) {
        final byOrder = a.order.compareTo(b.order);
        if (byOrder != 0) return byOrder;
        final byLabel = a.label.compareTo(b.label);
        return byLabel != 0 ? byLabel : a.path.compareTo(b.path);
      });

  static bool _isListed(SitePage sitePage) {
    final page = sitePage.page;
    if (page.meta.nav == null) return false;
    final included = page.meta.sitemap.included;
    if (included == false) return false;
    if (page.hooks.use.isNotEmpty && included != true) return false;
    return !PagePath.parse(sitePage.path).hasParams;
  }

  static NavItem _itemOf(SitePage sitePage) {
    final page = sitePage.page;
    final nav = page.meta.nav!;
    return NavItem(
      label: nav.label ?? page.meta.title,
      path: PageAddress.pathOf(
        sitePage.path,
        const {},
        sitePage.site.trailingSlash,
        pageSuffixes: sitePage.pageSuffixes,
      ),
      group: nav.group,
      order: nav.order,
    );
  }
}
