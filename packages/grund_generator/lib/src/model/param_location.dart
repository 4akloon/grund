/// The request part a path, query, header or cookie parameter comes from.
enum ParamLocation {
  /// `@Path`: `c.path`.
  path('path'),

  /// `@Query`: `c.query`.
  query('query'),

  /// `@Header`: `c.headers`.
  header('headers'),

  /// `@Cookie`: `c.cookies`.
  cookie('cookies');

  const ParamLocation(this.reader);

  /// The `HttpCtx` getter that holds the `Params` of this part.
  final String reader;
}
