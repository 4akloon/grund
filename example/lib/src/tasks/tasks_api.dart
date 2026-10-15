import 'package:grund_http/annotations.dart';
import 'package:grund_http/grund_http.dart' as http;

import '../auth/api_key_hook.dart';
import '../auth/role.dart';
import '../auth/roles_hook.dart';
import 'create_task.dart';
import 'location_hook.dart';
import 'task.dart';
import 'task_not_found_hook.dart';
import 'tasks_service.dart';
import 'update_task.dart';

part 'tasks_api.g.dart';

/// `/tasks`: every route needs an API key; changes need the editor role.
@Api('/tasks', use: [ApiKeyHook, TaskNotFoundHook])
final class TasksApi {
  /// Serves [service].
  TasksApi(this.service);

  /// The use cases.
  final TasksService service;

  /// `GET /tasks`, optionally `?done=true` or `?done=false`.
  @Get('/')
  List<Task> list({@Query() bool? done}) => service.list(done: done);

  /// `GET /tasks/:id`.
  @Get('/:id')
  Task find(@Path() int id) => service.find(id);

  /// `POST /tasks`: 201 with the new task and its `location`.
  @Post('/', status: 201, use: [RolesHook(Role.editor), LocationHook()])
  Task create(@Body() CreateTask body) => service.create(body);

  /// `PATCH /tasks/:id`: changes the title or the state.
  @Patch('/:id', use: [RolesHook(Role.editor)])
  Task update(@Path() int id, @Body() UpdateTask body) =>
      service.update(id, body);

  /// `DELETE /tasks/:id`: 204.
  @Delete('/:id', use: [RolesHook(Role.editor)])
  void remove(@Path() int id) => service.delete(id);
}
