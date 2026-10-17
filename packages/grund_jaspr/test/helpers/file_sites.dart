import 'package:grund_jaspr/grund_jaspr.dart';

import 'sites.dart';

/// A root site that serves [files] and has a base URL when [withBaseUrl].
base class FilesSite extends PageSite {
  /// Creates the site.
  FilesSite(super.injector, this.files, {this.withBaseUrl = false});

  @override
  final List<SiteFile> files;

  /// Whether the site has a base URL (and so a sitemap).
  final bool withBaseUrl;

  @override
  Uri? get baseUrl => withBaseUrl ? Uri.parse('https://x.test') : null;
}

/// A site under `/docs` that serves [files].
final class DocsFilesSite extends PageSite {
  /// Creates the site.
  DocsFilesSite(super.injector, this.files);

  @override
  String get path => '/docs';

  @override
  final List<SiteFile> files;
}

/// A guarded site under `/admin` that serves [files].
final class AdminFilesSite extends AdminSite {
  /// Creates the site.
  AdminFilesSite(super.injector, this.files);

  @override
  final List<SiteFile> files;
}

/// A text file with the fixed [text].
SiteFile textFile(
  String path, {
  String mediaType = 'text/plain',
  String? text,
}) =>
    SiteFile(path, mediaType: mediaType, build: (_) => text ?? 'body of $path');
