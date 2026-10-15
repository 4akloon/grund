import 'package:grund_http/grund_http.dart';

import 'task.dart';

/// Adds `location: /tasks/<id>` to the response of a handler that returned
/// a [Task]. `after` runs only when the handler succeeded.
final class LocationHook extends HttpHook {
  /// Creates the hook.
  const LocationHook();

  @override
  void after(HttpCtx c, Object? result) {
    if (result case Task(:final id)) {
      c.response.headers.set('location', '/tasks/$id');
    }
  }
}
