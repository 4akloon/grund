import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:jaspr/server.dart';

import 'trailing_slash.dart';

/// A group of pages that share a path prefix, hooks and a page shell.
abstract base class PageSite {
  /// Creates the site; [injector] resolves what its pages need.
  PageSite(this.injector);

  /// The injector of the module that declares the site.
  final Injector injector;

  /// The path prefix: `''` or `/segment[/segment]`.
  String get path => '';

  /// Hooks that run for every page of the site.
  List<HookRef<HttpHook>> get use => const [];

  /// Hook types a page may skip through `PageHooks.skip`.
  List<Type> get skippableHooks => const [];

  /// Wraps the [content] of every page of the site.
  Component shell(Component content) => content;

  /// The component for a request the site's pages do not match.
  Component notFound() => const Component.text('Not found');

  /// The public origin of the site (`https://example.com`), for the sitemap
  /// and absolute URLs; no sitemap and no absolute URLs when `null`.
  Uri? get baseUrl => null;

  /// How page URLs end; see [TrailingSlash].
  TrailingSlash get trailingSlash => TrailingSlash.never;

  /// Media types every page of the site must have an alternate of
  /// (`text/markdown`); a page without one fails at startup.
  List<String> get requiredAlternates => const [];
}
