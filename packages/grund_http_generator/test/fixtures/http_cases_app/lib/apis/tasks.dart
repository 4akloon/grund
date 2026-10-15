// A valid API with every kind of route parameter and result.
import 'dart:typed_data';

import 'package:grund_annotations/grund_annotations.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/grund_http.dart' as http;

part 'tasks_api.g.dart';

/// How urgent a task is.
enum Priority {
  /// Can wait.
  low,

  /// Cannot wait.
  high,
}

/// A task.
final class Task {
  /// Creates the task.
  const Task(this.id);

  /// The identifier.
  final int id;

  /// The JSON form.
  Map<String, Object?> toJson() => {'id': id};
}

/// The body of `create`.
final class CreateTask {
  /// Creates the body.
  const CreateTask(this.title);

  /// Reads the body.
  factory CreateTask.fromJson(Map<String, Object?> json) =>
      CreateTask(json['title']! as String);

  /// The title.
  final String title;
}

/// The caller, set into the call scope by a hook.
final class CurrentUser {}

/// Checks the API key.
@Injectable()
final class ApiKeyHook extends HttpHook {
  /// Creates the hook.
  const ApiKeyHook();
}

/// Checks the role.
final class RolesHook extends HttpHook {
  /// Creates the hook.
  const RolesHook(this.priority);

  /// The minimum priority.
  final Priority priority;
}

/// The tasks of the workspace.
@Api('/tasks', use: [HookRef<ApiKeyHook>.type()])
final class TasksApi {
  /// Creates the API.
  TasksApi(this.store);

  /// Where tasks live.
  final Map<int, Task> store;

  /// Returns one task.
  @Get('/:id')
  Future<Task> find(@Path() int id) async => Task(id);

  /// Lists tasks.
  @Get('/')
  Future<List<Task>> list(
    @Query() bool? done,
    @Query() List<String> tag, {
    @Query(name: 'page_size') @Range(min: 1, max: 100) int pageSize = 20,
    @Query() @Length(min: 1, max: 8) @Pattern(r'^\w+$') String? q,
  }) async => [];

  /// Creates a task.
  @Post(
    '/',
    status: 201,
    use: [HookRef<RolesHook>.instance(RolesHook(Priority.high))],
  )
  Future<Task> create(@Body() CreateTask dto, CurrentUser user) async =>
      Task(1);

  /// Removes a task.
  @Delete('/:id')
  Future<void> remove(
    @Path() int id,
    @Header(name: 'x-trace') String? trace,
  ) async {}

  /// Marks a task.
  @Put('/:id/priority/:priority')
  void mark(@Path() int id, @Path() Priority priority, HttpCtx ctx) {}

  /// Replaces the attachment.
  @Put('/:id/raw')
  Task raw(@Path() int id, @Body() Uint8List data, @Cookie() String session) =>
      Task(id);

  /// Imports tasks.
  @Post('/import')
  Task import(@Body() List<CreateTask> tasks) => const Task(0);

  /// Takes an arbitrary JSON object.
  @Post('/free')
  Task free(@Body() Map<String, Object?> json) => const Task(0);

  /// Streams bytes.
  @Get('/export')
  Stream<List<int>> export(@Query() DateTime since, @Query() Uri? next) =>
      const Stream.empty();
}
