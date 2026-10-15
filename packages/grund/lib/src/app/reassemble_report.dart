/// What `Application.reassemble` changed in the routes an application
/// serves, each route as `'GET /users/:id'`.
final class ReassembleReport {
  /// Creates the report.
  const ReassembleReport({
    required this.addedRoutes,
    required this.removedRoutes,
  });

  /// Compares the sorted route lists [before] and [after] a reassemble.
  factory ReassembleReport.between(List<String> before, List<String> after) {
    final old = before.toSet();
    final current = after.toSet();
    return ReassembleReport(
      addedRoutes: List.unmodifiable([
        for (final route in after)
          if (!old.contains(route)) route,
      ]),
      removedRoutes: List.unmodifiable([
        for (final route in before)
          if (!current.contains(route)) route,
      ]),
    );
  }

  /// Routes served now and not before, sorted.
  final List<String> addedRoutes;

  /// Routes served before and not now, sorted.
  final List<String> removedRoutes;

  /// How many routes were added or removed.
  int get changedRoutes => addedRoutes.length + removedRoutes.length;

  /// The report as JSON, for the `ext.grund.reassemble` service
  /// extension.
  Map<String, Object> toJson() => {
    'addedRoutes': addedRoutes,
    'removedRoutes': removedRoutes,
  };
}
