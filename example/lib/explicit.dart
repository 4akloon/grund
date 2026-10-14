/// The tasks API wired by hand with the explicit API: the same classes and
/// the same module graph as the generated `appModule`, without code
/// generation.
library;

import 'package:dartnest/dartnest.dart';

import 'tasks_api.dart';

/// The application root.
Module explicitAppModule() => Module(
  id: 'app',
  imports: [_configModule(), _tasksModule(), _healthModule()],
  providers: [Provider((i) => TimingInterceptor())],
);

Module _configModule() => Module(
  id: 'config',
  providers: [
    Provider<String>.value('tasks_api', token: appName),
    Provider<Map<String, Role>>.value(demoApiKeys, token: apiKeys),
  ],
  exports: [appName, apiKeys],
  global: true,
);

Module _authModule() => Module(
  id: 'auth',
  providers: [
    Provider((i) => ApiKeys(i.get(apiKeys))),
    Provider((i) => ApiKeyGuard(i.get())),
    Provider((i) => RolesGuard()),
  ],
  exports: [ApiKeyGuard, RolesGuard],
);

Module _tasksModule() => Module(
  id: 'tasks',
  imports: [_authModule()],
  providers: [
    Provider<TaskStore>((i) => InMemoryTaskStore()),
    Provider((i) => TasksService(i.get())),
    Provider((i) => TrimStringsPipe()),
    Provider((i) => TaskNotFoundFilter()),
  ],
  controllers: [_tasksController()],
);

const _editorsOnly = Enhancers(guards: [Use<RolesGuard>()]);

Controller<TasksController> _tasksController() => Controller<TasksController>(
  path: '/tasks',
  create: (i) => TasksController(i.get()),
  enhancers: const Enhancers(
    guards: [Use<ApiKeyGuard>()],
    pipes: [Use<TrimStringsPipe>()],
    filters: [Use<TaskNotFoundFilter>()],
  ),
  routes: _tasksRoutes(),
);

List<Route<TasksController>> _tasksRoutes() => [
  Route.get('', (c, ctx) async => c.list(await ctx.query<bool?>('done'))),
  Route.get('/:id', (c, ctx) async => c.find(await ctx.param<int>('id'))),
  Route.post(
    '',
    (c, ctx) async => c.create(await ctx.bodyAs(CreateTaskDto.fromJson), ctx),
    enhancers: _editorsOnly,
    metadata: const [
      Roles([Role.editor]),
    ],
  ),
  Route.patch(
    '/:id',
    (c, ctx) async => c.update(
      await ctx.param<int>('id'),
      await ctx.bodyAs(UpdateTaskDto.fromJson),
    ),
    enhancers: _editorsOnly,
    metadata: const [
      Roles([Role.editor]),
    ],
  ),
  Route.delete(
    '/:id',
    (c, ctx) async {
      c.delete(await ctx.param<int>('id'));
      return null;
    },
    enhancers: _editorsOnly,
    metadata: const [
      Roles([Role.editor]),
    ],
  ),
];

Module _healthModule() => Module(
  id: 'health',
  controllers: [
    Controller<HealthController>(
      path: '/health',
      create: (i) => HealthController(i.get(appName)),
      routes: [Route.get('', (c, _) => c.check())],
    ),
  ],
);
