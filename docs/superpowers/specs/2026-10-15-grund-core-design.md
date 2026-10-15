# grund, етап 1: ядро, HTTP і генератор

Дата: 2026-10-15. Статус: чернетка на рев'ю. Рамка — 
`2026-10-15-grund-platform-design.md`. Цей spec замінює розділи 3–6
`2026-10-13-dartnest-design.md` (DI, контролери, конвеєр, генератор); розділи
про адаптери, помилки ядра, тестування й hot reload лишаються чинними, якщо
нижче не сказано інше.

## 1. Мета етапу

Переписати публічний API dartnest на модель grund, зберігши цінне з v1.0:
перевірку графа до старту, конвеєр перехоплення, hot reload без втрати стану,
`TestClient`, детермінований генератор, адаптери `io`/`shelf` і їхню
conformance-suite.

Критерій готовності: приклад `tasks_api` переписаний на нову модель в
анотованій і явній формах; обидві проходять ті самі e2e-тести на обох
адаптерах; HTTP відсутній у залежностях пакета `grund`.

## 2. Перейменування

Першим окремим комітом: репозиторій і пакети `dartnest*` → `grund*`
(`grund`, `grund_annotations`, `grund_generator`, `grund_build`, `grund_cli`,
`grund_io`, `grund_shelf`, `grund_conformance`), згенерований файл
`lib/<package>.grund.dart`, service extensions `ext.grund.*`. Новий пакет
`grund_http` виділяється з ядра (розділ 5).

## 3. Модуль

### 3.1 Анотована форма (основний DX)

```dart
@Module(
  imports: [AuthModule],
  providers: [TasksService, TasksApi, Bind<TaskStore, InMemoryTaskStore>()],
  exports: [TasksService],
)
final class TasksModule extends Module with $TasksModule {
  @Provides()
  static TasksConfig config(AppConfig app) => TasksConfig(pageSize: app.pageSize);

  @override
  Future<void> onShutdown(Injector i) => i<TaskStore>().close();
}

@Injectable()
final class TasksService {
  TasksService(this.store, this.config);
  final TaskStore store;
  final TasksConfig config;
}
```

- Клас модуля — звичайний підклас `Module`; домішка `$TasksModule` у
  згенерованому файлі реалізує `imports`, `bindings`, `exports`. Клас може
  мати власні `@Provides`-методи й lifecycle.
- `@Injectable()` — клас зі звичайним конструктором; генератор резолвить
  параметри конструктора за типом (і `@Named`), сервіс можна створити руками
  в тесті.
- `@Provides()` — статичний метод модуля; параметри резолвляться так само.
  Повернення `Future<T>` → асинхронна ініціалізація на старті.
  `@Provides(scope: Scope.call)` / `Scope.transient` для інших скоупів.
  Це єдиний спосіб рантайм-конфігурації; const-анотації несуть лише
  ідентичність і флаги.
- `Bind<I, C>()` — інтерфейс `I` реалізує `@Injectable` клас `C`.
- `@Named('x')` на параметрі, класі або `@Provides`-методі — кваліфікатор.

### 3.2 Явна форма (ціль генерації, escape hatch)

```dart
final class TasksModule extends Module {
  @override
  List<Module> get imports => const [AuthModule()];

  @override
  List<Binding> get bindings => [
    Singleton<TaskStore>((i) => InMemoryTaskStore(), dependsOn: const []),
    Singleton((i) => TasksService(i<TaskStore>(), i<TasksConfig>()),
        dependsOn: const [Key<TaskStore>(), Key<TasksConfig>()]),
    Singleton((i) => TasksModule.config(i<AppConfig>()),
        dependsOn: const [Key<AppConfig>()]),
  ];

  @override
  List<Key> get exports => const [Key<TasksService>()];
}
```

Генератор емітить саме цю форму. Замикання в `bindings` — нормальна частина
явної форми; користувач пише її руками лише для сторонніх типів, яких не
можна анотувати, і то переважно через `@Provides`.

### 3.3 Семантика

- **Ідентичність модуля**: `runtimeType` + `Module.qualifier` (`Object?`,
  за замовчуванням `null`, порівнюється через `==`). Той самий модуль,
  імпортований з різних місць, — один інстанс у графі.
  `BasaltModule(name: 'analytics')` має qualifier `'analytics'`.
- **Ключ binding-у**: `Key<T>([String? name])`. Тип виводиться з дженерика
  binding-у.
- **Видимість**: інжектор модуля бачить власні bindings, `exports` прямо
  імпортованих модулів і bindings модулів з `global == true`. Порушення →
  `ProviderNotVisibleError` з ланцюжком імпортів.
- **Реекспорт**: `exports` може містити модуль з `imports` — тоді
  експортується все, що експортує він.
- **Скоупи**: `Singleton` (на застосунок, створюється eagerly на старті в
  порядку залежностей), `Scoped` (на «виклик»: HTTP-запит, WS-повідомлення,
  запуск джоба; дочірній інжектор), `Transient` (новий на кожне
  резолвлення). `Singleton`, що залежить від `Scoped`, — `CaptiveDependencyError`.
- **Валідація**: `ModuleGraph.build` до виклику будь-якої фабрики перевіряє
  цикли імпортів, дублікати ключів у модулі, видимість і captive-залежності
  для всіх bindings з `dependsOn`. Генератор завжди заповнює `dependsOn`;
  binding без нього (рукописний) перевіряється при резолвленні, а для
  singleton-ів це все одно відбувається до `run()`. Генератор додатково
  перевіряє граф статично в межах пакета з `path:line:col`.
- **Колекції за типом**: `container.all<T>()` повертає всі singleton-и
  графа, тип binding-у яких є підтипом `T` (дженерики Dart коваріантні й
  реїфіковані). Так транспорти знаходять свої внески без реєстрів.
- **Lifecycle**: `Module.onInit(Injector)` після створення singleton-ів
  модуля (у топологічному порядку модулів), `Module.onShutdown(Injector)` у
  зворотному. Singleton, що реалізує `Disposable`, отримує `dispose()` у
  зворотному порядку створення після `onShutdown` усіх модулів.

## 4. App, Runner, виклик

```dart
void main(List<String> args) =>
    App(root: AppModule()).run(only: Runners.fromArgs(args));
```

- `App(root:, overrides:)` будує граф і контейнер; `overrides` — список
  bindings, що заміщують однойменні ключі (тести, dev).
- `Runner` — інтерфейс ядра: `String get name`, `Future<void>
  start(Injector)`, `Future<void> stop()`. `run()` стартує всі
  `container.all<Runner>()`; `only` фільтрує за `name` (`--only=http`).
  SIGINT/SIGTERM → stop у зворотному порядку → lifecycle shutdown.
- `CallContext` — база контексту виклику в ядрі: дочірній `Injector`
  скоупу `call`, `CancelSignal`, `set<T>(value, {name})` для значень, які
  кладуть хуки (наприклад `CurrentUser`), і `call<T>()` / `c<T>()` для
  резолвлення з цього скоупу. Транспорти розширюють його (`HttpCtx`).
- `App.start()` / `App.close()` лишаються для вбудовування (shelf) і тестів.
- Hot reload: вимоги розділу 10 старого spec-у переносяться на `App`;
  `reassemble` перебудовує граф і перезапускає `Runner`-и, singleton-и з
  незмінними фабриками зберігаються.

## 5. `grund_http`

### 5.1 API-клас

```dart
/// Tasks of the current workspace.
@Api('/tasks', use: [ApiKeyHook])
final class TasksApi {
  TasksApi(this.service);
  final TasksService service;

  /// Returns one task.
  @Get('/:id')
  Future<Task> find(@Path() int id) => service.find(id);

  @Get('/')
  Future<List<Task>> list(@Query() bool? done,
      @Query(name: 'page_size') @Range(min: 1, max: 100) int pageSize = 20) =>
      service.list(done: done, pageSize: pageSize);

  @Post('/', status: 201, use: [RolesHook(Role.editor)])
  Future<Task> create(@Body() CreateTask dto, CurrentUser user) =>
      service.create(dto, by: user);
}
```

- Параметри: `@Path`, `@Query`, `@Header`, `@Cookie`, `@Body`; `HttpCtx` —
  як є; параметр без анотації резолвиться з call-скоупу за типом
  (`CurrentUser`, `Tx`). Nullable → необов'язковий, default параметра →
  значення за замовчуванням.
- `@Body() T` вимагає `T.fromJson(Map<String, Object?>)` (factory або
  static). grund не генерує серіалізацію DTO: працює з json_serializable,
  freezed, dart_mappable або рукописним кодом.
- Валідатори параметрів: `@Range`, `@Length`, `@Pattern`, `@OneOf`.
  Валідація полів DTO — етап 2 (той самий аналіз, що й схеми OpenAPI).

Генератор емітить для `TasksApi` binding самого класу і binding
`HttpApi`-адаптера:

```dart
final class TasksApiRoutes extends HttpApi {
  TasksApiRoutes(this._api);
  final TasksApi _api;

  @override String get path => '/tasks';
  @override List<HookRef> get use => const [HookRef.type(ApiKeyHook)];
  @override List<Route> get routes => [
    Route.get('/:id', (c) => _api.find(c.path.int('id'))),
    // ...
  ];
}
```

Рукописна явна форма — той самий `HttpApi`-підклас з хендлерами-методами
`(HttpCtx c)`. `HttpServer` збирає `container.all<HttpApi>()`.

### 5.2 HttpCtx і екстрактори

`HttpCtx extends CallContext`: `request`, `response` (статус, заголовки),
`path`, `query`, `headers`, `cookies` з типізованими читачами
(`int`, `intOrNull`, `bool`, `string`, `enumOf(values)`, `dateTime`, `uri`),
`body<T>(T Function(Map<String, Object?>))`, `bodyList<T>(...)`, `bytes()`.
Помилка читання → `BadRequest` зі стабільним `code` і `pointer`.

### 5.3 Відповідь

Значення → JSON (`toJson()` або зареєстрований `Codec<T>`), `null` → 204,
`Response` → як є, `Stream<List<int>>` → потік байтів. `Stream<T>`
зарезервовано для `grund_sse` (етап 5): до того — помилка генератора.
Статус: `status:` в анотації або `c.response.status`.

### 5.4 Hook

```dart
abstract class HttpHook {
  FutureOr<void> before(HttpCtx c) {}
  FutureOr<void> after(HttpCtx c, Object? result) {}
  FutureOr<Response?> onError(HttpCtx c, Object error, StackTrace stack) => null;
}
```

Замінює Guard, Interceptor, Pipe і ExceptionFilter. Посилання на хук:
тип (резолвиться з графа, має DI) або const-інстанс (параметризований,
залежності бере через `c<T>()`). Порядок: глобальні (`HttpModule(use:)`) →
API → роут для `before`; зворотний для `after` і `onError`. Виняток у
`before` перериває ланцюг. Перший `onError` з не-null результатом
відповідає; інакше `HttpException` → свій статус, решта → 500 через логер.

`Middleware` (запит → відповідь до маршрутизації) лишається для CORS,
стиснення, request id.

### 5.5 Помилки

Тіло помилки — RFC 9457 `application/problem+json` (`type`, `title`,
`status`, `detail`, `instance`, розширення `code`, `errors`). Це змінює
формат v1.0 (не опубліковано, тож без міграції).

### 5.6 Модуль і адаптери

`HttpModule(use:, middleware:, codecs:)` біндить `HttpServer` (`Runner` з
`name == 'http'`) і `HttpConfig` (адреса, порт, ліміт тіла) через
`@Provides` або аргументи. Адаптер — окремий модуль: `IoAdapterModule()`
(`grund_io`), `ShelfAdapterModule()` (`grund_shelf`) біндять
`HttpAdapter`. `shelfHandler(app)` для вбудовування в чужий shelf-pipeline
лишається.

## 6. Генератор

- Вхід: `@Module`, `@Injectable`, `@Provides`, `@Api` + анотації роутів;
  вихід — один `lib/<package>.grund.dart` на пакет з домішками модулів,
  явними bindings і `HttpApi`-адаптерами.
- Генератор ядра знає про `@Api` через розширюваний набір «емітерів»;
  емітер HTTP живе в `grund_generator` у v1 етапу 1, а не в окремому
  пакеті, бо друга реалізація (`@Channel`, `@Job`) з'явиться лише в етапах
  6–7. Тоді виділення окремим кроком.
- Діагностики зі стабільними кодами й `path:line:col`: невидимий провайдер,
  цикл, captive-залежність, параметр без джерела, `@Body` без `fromJson`,
  непідтримуваний тип повернення, конфлікт роутів.
- Детермінованість, golden-тести, CLI- і build_runner-драйвери — як у v1.0.
- Заділ для етапу 2: генератор будує `ApiDescription` (типи параметрів,
  повернення, `///`, анотації валідації) у моделі, але етап 1 його не
  емітить.

## 7. Що видаляється

`Controller<T>`, `Route.get(path, (c, ctx) => ...)` з контролером,
`Enhancers`, `Use<T>`, `Guard`, `Interceptor`, `Pipe`, `ExceptionFilter`,
`ExecutionContext`, `Token<T>`, `Module(id: ...)` як значення,
`Provider.value/async` (заміна — `@Provides` і `Singleton` з async-фабрикою),
`metadata`-списки роутів (заміна — поля const-хуків).

## 8. Тестування

- `TestApp(root:, overrides:)` + `TestClient` (є) для HTTP; e2e прикладу на
  обох адаптерах; conformance-suite без змін семантики.
- Ядро: unit-тести графа (видимість, реекспорт, global, qualifier-и,
  captive, цикли), lifecycle-порядку, `container.all<T>()`, `Runner`-ів і
  сигналів.
- Генератор: golden-фікстура переписується на нову модель; тест «анотована
  форма ≡ рукописна явна форма» на прикладі.

## 9. Поза етапом

OpenAPI і валідація полів DTO (етап 2), `Stream<T>`/SSE (етап 5),
`@Channel`/`@Job` (етапи 6–7), `init`-шаблони (етап 7).
