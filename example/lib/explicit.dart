/// The same application as `AppModule`, written with the explicit API: no
/// annotations, no generated code. Compare with the `*.g.dart` files next
/// to the annotated classes in `lib/src`, which is what the generator
/// writes for the annotated form.
library;

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:tasks_api/tasks_api.dart';

/// [AppConfig] for every module (`global`).
final class ExplicitConfigModule extends Module {
  /// Creates the module.
  const ExplicitConfigModule();

  @override
  bool get global => true;

  @override
  List<Binding<Object>> get bindings => [
    Singleton<AppConfig>((_) => AppConfig.demo, dependsOn: const []),
  ];

  @override
  List<Object> get exports => const [Key<AppConfig>()];
}

/// The API key check.
final class ExplicitAuthModule extends Module {
  /// Creates the module.
  const ExplicitAuthModule();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<ApiKeyHook>(
      (i) => ApiKeyHook(i<AppConfig>()),
      dependsOn: const [Key<AppConfig>()],
    ),
  ];

  @override
  List<Object> get exports => const [Key<ApiKeyHook>()];
}

/// The routes of [TasksApi] written by hand.
final class ExplicitTasksRoutes extends HttpApi {
  /// Serves [_api] from the module that declares it.
  ExplicitTasksRoutes(super.injector, this._api);

  final TasksApi _api;

  @override
  String get path => '/tasks';

  @override
  List<HookRef<HttpHook>> get use => const [
    HookRef<ApiKeyHook>.type(),
    HookRef<TaskNotFoundHook>.type(),
  ];

  @override
  List<Route> get routes => [
    Route.get('/', (c) => _api.list(done: c.query.booleanOrNull('done'))),
    Route.get('/:id', (c) => _api.find(c.path.integer('id'))),
    Route.post(
      '/',
      (c) async => _api.create(await c.body(CreateTask.fromJson)),
      status: 201,
      use: _editorOnly([const HookRef<LocationHook>.instance(LocationHook())]),
    ),
    Route.patch(
      '/:id',
      (c) async =>
          _api.update(c.path.integer('id'), await c.body(UpdateTask.fromJson)),
      use: _editorOnly(),
    ),
    Route.delete('/:id', (c) {
      _api.remove(c.path.integer('id'));
      return null;
    }, use: _editorOnly()),
  ];

  static List<HookRef<HttpHook>> _editorOnly([
    List<HookRef<HttpHook>> more = const [],
  ]) => [const HookRef<RolesHook>.instance(RolesHook(Role.editor)), ...more];
}

/// Tasks: the store, the service, the API and its error hook.
final class ExplicitTasksModule extends Module {
  /// Creates the module.
  const ExplicitTasksModule();

  @override
  List<Module> get imports => const [ExplicitAuthModule()];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<TaskStore>((_) => InMemoryTaskStore(), dependsOn: const []),
    Singleton<TasksService>(
      (i) => TasksService(i<TaskStore>()),
      dependsOn: const [Key<TaskStore>()],
    ),
    Singleton<TaskNotFoundHook>((_) => TaskNotFoundHook(), dependsOn: const []),
    Singleton<TasksApi>(
      (i) => TasksApi(i<TasksService>()),
      dependsOn: const [Key<TasksService>()],
    ),
    Singleton<ExplicitTasksRoutes>(
      (i) => ExplicitTasksRoutes(i, i<TasksApi>()),
      dependsOn: const [Key<TasksApi>()],
    ),
  ];
}

/// The health check, with an inline `HttpApi`.
final class ExplicitHealthModule extends Module {
  /// Creates the module.
  const ExplicitHealthModule();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<HealthApi>(
      (i) => HealthApi(i<AppConfig>()),
      dependsOn: const [Key<AppConfig>()],
    ),
    Singleton<_HealthRoutes>(
      (i) => _HealthRoutes(i, i<HealthApi>()),
      dependsOn: const [Key<HealthApi>()],
    ),
  ];
}

final class _HealthRoutes extends HttpApi {
  _HealthRoutes(super.injector, this._api);

  final HealthApi _api;

  @override
  String get path => '/health';

  @override
  List<Route> get routes => [Route.get('/', (c) => _api.check())];
}

/// The application with the explicit API.
final class ExplicitAppModule extends Module {
  /// Creates the module.
  const ExplicitAppModule();

  @override
  List<Module> get imports => const [
    ExplicitConfigModule(),
    ExplicitTasksModule(),
    ExplicitHealthModule(),
  ];
}
