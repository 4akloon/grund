/// Where in the request a parameter is read from.
enum ParamLocation {
  /// A `:name` segment of the route path.
  path('path parameter', 'path'),

  /// A query string parameter.
  query('query parameter', 'query'),

  /// A request header.
  header('header', 'header'),

  /// A cookie of the `Cookie` header.
  cookie('cookie', 'cookie'),

  /// A field of an `application/x-www-form-urlencoded` body.
  form('form field', 'body');

  const ParamLocation(this.label, this.pointerSegment);

  /// How messages call it: `query parameter "page"`.
  final String label;

  /// The first segment of the JSON pointer: `/query/page`.
  final String pointerSegment;
}
