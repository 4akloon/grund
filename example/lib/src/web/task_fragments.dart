import 'package:grund_auth/grund_auth.dart' as auth;
import 'package:grund_http/grund_http.dart';
import 'package:grund_jaspr/grund_jaspr.dart';

import '../tasks/create_task.dart';
import '../tasks/task_not_found.dart';
import '../tasks/tasks_service.dart';
import 'task_panel.dart';

/// The HTML answers htmx swaps into the home page: the task panel after an
/// add or a delete.
///
/// Both routes need a session (a guest gets 401); the global `SessionHook`
/// also refuses a cross-site write before they run.
final class TaskFragments extends HttpApi {
  /// Changes tasks through [_tasks].
  TaskFragments(super.injector, this._tasks);

  final TasksService _tasks;

  @override
  List<Route> get routes => [
    Route.post('/fragments/tasks', _create),
    Route.delete('/fragments/tasks/:id', _delete),
  ];

  Future<HttpResponse> _create(HttpCtx c) async {
    _requireUser(c);
    final raw = (await c.form()).stringOrNull('title') ?? '';
    try {
      _tasks.create(CreateTask.fromJson({'title': raw}));
    } on FormatException catch (refusal) {
      return Fragments.respond(
        c,
        TaskPanel(
          tasks: _tasks.list(),
          editable: true,
          draft: raw,
          error: refusal.message,
        ),
        status: 422,
      );
    }
    return _panel(c, status: 201);
  }

  Future<HttpResponse> _delete(HttpCtx c) async {
    _requireUser(c);
    try {
      _tasks.delete(c.path.integer('id'));
    } on TaskNotFound catch (missing, stack) {
      throw NotFoundException(
        message: 'No task ${missing.id}.',
        code: 'task_not_found',
        cause: missing,
        causeStackTrace: stack,
      );
    }
    return _panel(c);
  }

  Future<HttpResponse> _panel(HttpCtx c, {int status = 200}) =>
      Fragments.respond(
        c,
        TaskPanel(tasks: _tasks.list(), editable: true),
        status: status,
      );

  static void _requireUser(HttpCtx c) {
    if (c.maybe<auth.CurrentUser>() == null) {
      throw const UnauthorizedException(message: 'Sign in to change tasks.');
    }
  }
}
