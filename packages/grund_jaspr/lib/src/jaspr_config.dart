import 'error/jaspr_error.dart';

/// How `JasprModule` serves pages and static files.
final class JasprConfig {
  /// Creates the configuration.
  const JasprConfig({
    this.staticDirectory = 'web',
    this.pageSuffixes = const ['html', 'htm', 'xml'],
    this.liveReloadUrl,
    this.staticPath = '/static',
    this.rootFiles = const [],
    this.sitemapChunkSize = 50000,
    this.sitemapCacheLifetime = const Duration(seconds: 60),
  });

  /// The directory of the static files; a relative path is resolved
  /// against the working directory (run the application from its package
  /// root). A directory that does not exist serves nothing.
  final String staticDirectory;

  /// The file extensions a page path may have, written without the dot
  /// (`xml`, not `.xml`; [validate] refuses a dotted entry, which would
  /// never match); a path with another extension that is not a static file
  /// is a 404 instead of a page, the way Jaspr's own server does it.
  final List<String> pageSuffixes;

  /// Where the live reload script of a page listens for `reload` events;
  /// `null` adds no script. `JasprModule` fills it from the
  /// `GRUND_LIVE_RELOAD_URL` that `grund dev` passes, outside product
  /// builds, when it is `null`.
  final Uri? liveReloadUrl;

  /// The URL prefix under which the static files are served; starts with
  /// `/` and does not end with one.
  final String staticPath;

  /// Names of files of [staticDirectory] that are also served at the root
  /// of the site (`robots.txt`); plain file names, without `/`.
  final List<String> rootFiles;

  /// The most addresses one sitemap file holds; a larger sitemap is split.
  final int sitemapChunkSize;

  /// How long a generated sitemap chunk is reused.
  final Duration sitemapCacheLifetime;

  /// Throws [JasprSetupError] for a [pageSuffixes] entry that starts with
  /// `.`, a malformed [staticPath], a [rootFiles] entry with a `/` or a
  /// [sitemapChunkSize] below 1; `JasprModule` calls it when the
  /// application starts.
  void validate() {
    if (!staticPath.startsWith('/') || staticPath.endsWith('/')) {
      throw JasprSetupError(
        'staticPath must start with "/" and not end with it; got '
        '"$staticPath".',
      );
    }
    for (final file in rootFiles) {
      if (file.contains('/')) {
        throw JasprSetupError(
          'rootFiles entries are plain file names; "$file" contains "/".',
        );
      }
    }
    if (sitemapChunkSize < 1) {
      throw JasprSetupError(
        'sitemapChunkSize must be at least 1; got $sitemapChunkSize.',
      );
    }
    for (final suffix in pageSuffixes) {
      if (suffix.startsWith('.')) {
        throw JasprSetupError(
          'pageSuffixes entries are written without the dot; "$suffix" would '
          'never match (use "${suffix.substring(1)}").',
        );
      }
    }
  }

  /// A copy with [url] as the [liveReloadUrl].
  JasprConfig withLiveReloadUrl(Uri? url) => JasprConfig(
    staticDirectory: staticDirectory,
    pageSuffixes: pageSuffixes,
    liveReloadUrl: url,
    staticPath: staticPath,
    rootFiles: rootFiles,
    sitemapChunkSize: sitemapChunkSize,
    sitemapCacheLifetime: sitemapCacheLifetime,
  );
}
