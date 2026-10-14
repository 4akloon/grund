import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'task_not_found.dart';

/// Answers [TaskNotFound] with 404, so the service stays free of HTTP.
@Injectable()
final class TaskNotFoundFilter extends ExceptionFilter<TaskNotFound> {
  @override
  Object? handle(TaskNotFound error, ExecutionContext context) =>
      throw NotFoundException(message: 'No task ${error.id}.');
}
