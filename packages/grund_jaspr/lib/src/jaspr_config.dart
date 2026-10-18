import 'client/client_components.dart';
import 'error/jaspr_error.dart';

/// How `JasprModule` serves pages and static files.
final class JasprConfig {
  /// Creates the configuration.
  const JasprConfig({
    this.staticDirectory = 'web',
    this.pageSuffixes = defaultPageSuffixes,
    this.liveReloadUrl,
    this.staticPath = '/static',
    this.rootFiles = const [],
    this.sitemapChunkSize = 50000,
    this.sitemapCacheLifetime = const Duration(seconds: 60),
    this.clients,
  });

  /// The directory under [staticPath] that holds the client bundle.
  static const String clientDirectory = 'client';

  /// The file name of the compiled client bundle in [clientDirectory].
  static const String clientScript = 'main.client.dart.js';

  /// The default of [pageSuffixes]: `html`, `htm` and `xml`.
  static const defaultPageSuffixes = ['html', 'htm', 'xml'];

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
  ///
  /// The static files carry no hooks: a path inside the territory of a
  /// guarded site (such as `/admin/assets` for a site at `/admin`) serves
  /// them to everyone, so keep it outside the guarded sites.
  final String staticPath;

  /// Names of files of [staticDirectory] that are also served at the root
  /// of the site (`robots.txt`); plain file names, without `/`.
  final List<String> rootFiles;

  /// The most addresses one sitemap file holds; a larger sitemap is split.
  final int sitemapChunkSize;

  /// How long a generated sitemap chunk is reused.
  final Duration sitemapCacheLifetime;

  /// The components that hydrate in the browser; `null` serves pages with
  /// no client script.
  final ClientComponents? clients;

  /// The path of the client script relative to the site root (no leading
  /// `/`), derived from [staticPath]; `null` when [clients] is `null` or
  /// empty. Read it after [validate]: it assumes a valid [staticPath].
  String? get clientId => switch (clients) {
    ClientComponents(components: final list) when list.isNotEmpty =>
      '${staticPath.substring(1)}/$clientDirectory/$clientScript',
    _ => null,
  };

  /// Throws [JasprSetupError] for a [pageSuffixes] entry that starts with
  /// `.`, a malformed [staticPath] (also one with `*` or `:`), a [rootFiles]
  /// entry that is not a plain file name (empty, `.`, `..`, or with `/`, `*`
  /// or `:`), a [sitemapChunkSize] below 1 or any of the [clients] `problems`;
  /// `JasprModule` calls it when the application starts.
  void validate() {
    if (!staticPath.startsWith('/') ||
        staticPath.endsWith('/') ||
        _isRoutePattern(staticPath)) {
      throw JasprSetupError(
        'staticPath must start with "/", not end with it and have no "*" or '
        '":"; got '
        '"$staticPath".',
      );
    }
    for (final file in rootFiles) {
      if (file.isEmpty ||
          file == '.' ||
          file == '..' ||
          file.contains('/') ||
          _isRoutePattern(file)) {
        throw JasprSetupError(
          'rootFiles entries are plain file names; "$file" is not one.',
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
    _validateClients();
  }

  void _validateClients() {
    final problems = clients?.problems ?? const <String>[];
    if (problems.isNotEmpty) {
      throw JasprSetupError('clients has problems: ${problems.join('; ')}.');
    }
  }

  static bool _isRoutePattern(String path) =>
      path.contains('*') || path.contains(':');

  /// A copy with [url] as the [liveReloadUrl].
  JasprConfig withLiveReloadUrl(Uri? url) => JasprConfig(
    staticDirectory: staticDirectory,
    pageSuffixes: pageSuffixes,
    liveReloadUrl: url,
    staticPath: staticPath,
    rootFiles: rootFiles,
    sitemapChunkSize: sitemapChunkSize,
    sitemapCacheLifetime: sitemapCacheLifetime,
    clients: clients,
  );
}
