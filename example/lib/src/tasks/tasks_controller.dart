import 'package:grund/grund.dart' hide Controller, Module;
import 'package:grund_annotations/grund_annotations.dart';

import '../auth/api_key_guard.dart';
import '../auth/role.dart';
import '../auth/roles.dart';
import '../auth/roles_guard.dart';
import '../common/trim_strings_pipe.dart';
import 'create_task_dto.dart';
import 'task.dart';
import 'task_not_found_filter.dart';
import 'tasks_service.dart';
import 'update_task_dto.dart';

/// `/tasks`: every route needs an API key; changes need the editor role.
@Controller('/tasks')
@UseGuards([ApiKeyGuard])
@UsePipes([TrimStringsPipe])
@UseFilters([TaskNotFoundFilter])
final class TasksController {
  /// Serves [service].
  TasksController(this.service);

  /// The use cases.
  final TasksService service;

  /// `GET /tasks`, optionally `?done=true` or `?done=false`.
  @Get()
  List<Task> list(@Query('done') bool? done) => service.list(done: done);

  /// `GET /tasks/:id`.
  @Get('/:id')
  Task find(@Param('id') int id) => service.find(id);

  /// `POST /tasks`: 201 with the new task and its `location`.
  @Post()
  @UseGuards([RolesGuard])
  @Roles([Role.editor])
  Task create(@Body() CreateTaskDto dto, ExecutionContext context) {
    final task = service.create(dto);
    context.switchToHttp().response
      ..status = StatusCode.created
      ..headers.set('location', '/tasks/${task.id}');
    return task;
  }

  /// `PATCH /tasks/:id`: changes the title or the state.
  @Patch('/:id')
  @UseGuards([RolesGuard])
  @Roles([Role.editor])
  Task update(@Param('id') int id, @Body() UpdateTaskDto dto) =>
      service.update(id, dto);

  /// `DELETE /tasks/:id`: 204.
  @Delete('/:id')
  @UseGuards([RolesGuard])
  @Roles([Role.editor])
  void delete(@Param('id') int id) => service.delete(id);
}
