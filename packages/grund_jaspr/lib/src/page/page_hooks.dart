import 'package:grund_http/grund_http.dart';

/// Hook changes for one page, relative to the hooks of its site.
final class PageHooks {
  /// Creates the hook changes.
  const PageHooks({this.skip = const [], this.use = const []});

  /// Hook types of the site that this page skips (only types the site lists
  /// in `skippableHooks`).
  final List<Type> skip;

  /// Hooks that run for this page only, after the site's hooks.
  final List<HookRef<HttpHook>> use;
}
