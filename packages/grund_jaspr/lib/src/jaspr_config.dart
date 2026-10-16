/// How `JasprModule` serves pages and static files.
final class JasprConfig {
  /// Creates the configuration.
  const JasprConfig({
    this.staticDirectory = 'web',
    this.pageSuffixes = const ['html', 'htm', 'xml'],
  });

  /// The directory of the static files; a relative path is resolved
  /// against the working directory (run the application from its package
  /// root). A directory that does not exist serves nothing.
  final String staticDirectory;

  /// The file extensions a page path may have (`/feed.xml`); a path with
  /// another extension that is not a static file is a 404 instead of a
  /// page, the way Jaspr's own server does it.
  final List<String> pageSuffixes;
}
