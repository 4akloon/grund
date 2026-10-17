import 'dart:async';

import 'package:grund_http/grund_http.dart';
import 'package:jaspr/server.dart';

import 'page_extension.dart';
import 'page_hooks.dart';
import 'page_meta.dart';

/// Builds the content of a page for the request [c].
typedef PageBuilder = FutureOr<Component> Function(HttpCtx c);

/// A page: a path and the component that renders it.
final class Page {
  /// Creates a page served at [path] (`/`, `/about`, `/projects/:slug`).
  const Page(
    this.path, {
    required this.build,
    this.meta = const PageMeta(),
    this.hooks = const PageHooks(),
    this.extensions = const [],
  });

  /// The path relative to the site.
  final String path;

  /// Builds the content.
  final PageBuilder build;

  /// Title, navigation and sitemap settings.
  final PageMeta meta;

  /// Hook changes for this page.
  final PageHooks hooks;

  /// Capabilities this page opts into.
  final List<PageExtension> extensions;
}
