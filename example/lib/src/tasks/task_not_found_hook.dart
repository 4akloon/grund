import 'package:grund/annotations.dart';
import 'package:grund_http/grund_http.dart';

import 'task_not_found.dart';

/// Answers [TaskNotFound] with 404, so the service stays free of HTTP.
@Injectable()
final class TaskNotFoundHook extends HttpHook {
  @override
  HttpResponse? onError(HttpCtx c, Object error, StackTrace stack) {
    if (error is! TaskNotFound) return null;
    throw NotFoundException(
      message: 'No task ${error.id}.',
      code: 'task_not_found',
      cause: error,
      causeStackTrace: stack,
    );
  }
}
