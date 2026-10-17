import 'dart:async';

import 'package:grund_http/grund_http.dart';

import 'page_match.dart';

/// Builds the text of an alternate representation of the page [match].
typedef AlternateBuilder = FutureOr<String> Function(
  HttpCtx c,
  PageMatch match,
);

/// Another representation of a page, such as Markdown for agents.
///
/// It is served at the page URL plus [suffix] and at the page URL itself for
/// a request whose `Accept` header names [mediaType] with a quality at least
/// that of `text/html`.
final class PageAlternate {
  /// Creates the alternate of [mediaType] served at the page URL plus
  /// [suffix].
  const PageAlternate({
    required this.mediaType,
    required this.suffix,
    required this.build,
  });

  /// Markdown (`text/markdown`) at the page URL plus `.md`.
  const PageAlternate.markdown(AlternateBuilder build)
    : this(mediaType: 'text/markdown', suffix: '.md', build: build);

  /// The media type, `type/subtype` in lower case.
  final String mediaType;

  /// What the page URL gets at its end, such as `.md`.
  final String suffix;

  /// Builds the text; throws `NotFoundException` for an unknown parameter.
  final AlternateBuilder build;
}
