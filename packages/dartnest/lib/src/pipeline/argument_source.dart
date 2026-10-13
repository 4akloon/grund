/// Where a handler argument comes from.
enum ArgumentSource {
  /// A `:name` or `*` path parameter.
  path('path parameter'),

  /// A query string parameter.
  query('query parameter'),

  /// The request body.
  body('request body');

  const ArgumentSource(this.label);

  /// Human-readable name used in error messages.
  final String label;
}
