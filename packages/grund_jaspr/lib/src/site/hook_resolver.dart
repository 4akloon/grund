import 'package:grund_http/grund_http.dart';
import 'package:logging/logging.dart';

import '../error/page_declaration_error.dart';
import '../page/page.dart';
import 'page_site.dart';

/// Works out the hooks of one page: the hooks of its site without the types
/// the page skips, then the hooks of the page itself.
final class HookResolver {
  /// Creates the resolver.
  const HookResolver();

  static final Logger _log = Logger('grund.jaspr');

  /// The hooks of [page] (served at [fullPath]) of [site].
  ///
  /// Throws a `PageDeclarationError` when the page skips a type that the
  /// site does not list in `skippableHooks`, that is not among the hooks of
  /// the site, or that occurs there more than once.
  List<HookRef<HttpHook>> forPage({
    required PageSite site,
    required Page page,
    required String fullPath,
  }) {
    final skipped = page.hooks.skip;
    for (final type in skipped) {
      _check(site, fullPath, type);
      _log.log(
        fullPath.contains(':') ? Level.WARNING : Level.INFO,
        'page $fullPath skips $type (site ${site.path.isEmpty ? '/' : site.path})',
      );
    }
    return [
      for (final hook in site.use)
        if (!skipped.contains(hook.hookType)) hook,
      ...page.hooks.use,
    ];
  }

  void _check(PageSite site, String path, Type type) {
    if (!site.skippableHooks.contains(type)) {
      throw ForbiddenPageSkipError(path: path, type: type);
    }
    final types = [for (final hook in site.use) hook.hookType];
    final count = types.where((candidate) => candidate == type).length;
    if (count == 0) {
      throw UnknownPageSkipError(path: path, type: type, siteHooks: types);
    }
    if (count > 1) throw AmbiguousPageSkipError(path: path, type: type);
  }
}
