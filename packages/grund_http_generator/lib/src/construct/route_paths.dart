/// Joins and compares the paths of routes.
abstract final class RoutePaths {
  /// The path of a route as the server sees it: [apiPath] followed by
  /// [routePath], with a leading slash, no empty segments and no trailing
  /// slash (except the root).
  static String join(String apiPath, String routePath) {
    final segments = [
      for (final segment in '$apiPath/$routePath'.split('/'))
        if (segment.isNotEmpty) segment,
    ];
    return '/${segments.join('/')}';
  }

  /// Names of the `:name` parameters and the `*` wildcard of [path].
  static List<String> parameters(String path) => [
    for (final segment in path.split('/'))
      if (segment.startsWith(':'))
        segment.substring(1)
      else if (segment == '*')
        '*',
  ];

  /// [path] with every parameter name erased: two paths with the same shape
  /// match the same requests.
  static String shape(String path) => [
    for (final segment in path.split('/'))
      segment.startsWith(':') ? ':' : segment,
  ].join('/');
}
