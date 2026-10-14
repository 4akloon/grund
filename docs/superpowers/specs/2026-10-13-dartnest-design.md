# dartnest — NestJS-подібний бекенд-фреймворк на Dart без `dart:mirrors`

Дата: 2026-10-13. Статус: чернетка дизайну для рев'ю.
Робоча назва пакетів — `dartnest`; підлягає заміні.

## 1. Мета та контекст

Публічний OSS-фреймворк для серверного Dart (AOT-бінарники) з архітектурою
NestJS: модулі, DI, контролери, GraphQL-резолвери (v2), анотації на рівні
класу та методу, конвеєр guards/interceptors/pipes/filters. HTTP-сервер не
вбудований: ядро працює через адаптери.

Факти, що визначили дизайн (перевірені 2026-10-13):

- `dart:mirrors` не працює в AOT, застарілий. Макроси Dart скасовані в січні
  2025; заміни для «анотацій без кодгену» не буде. Анотації в Dart — константи
  часу компіляції, у рантаймі без mirrors їх прочитати неможливо.
- build_runner 2.16 (серпень 2026) значно швидший за 2024 рік (AOT-скрипт
  збірки, 1.4–4× на білдах), але лишається найважчим інструментом.
- Конкуренти: Revali (анотації + власний CLI на `analyzer`, активний),
  Serinus (явні класи, нуль кодгену, активний). Обидва мають мало
  користувачів. Changelog Revali показує типовий біль самостійного
  використання analyzer (пінінг версій, «corrupt SDK»).
- GraphQL: `leto` завмер, `graphql_server2` живий, але резолвери лише ручні.
  Рішення: власний GraphQL у v2.
- HTTP: shelf — де-факто стандарт (не оновлювався з 2024), `relic` — новий
  від Serverpod.

### Рішення: гібрид (підхід D)

- Ядро має **явний типізований API без кодгену**. Фреймворк повністю
  працює без генерації.
- Анотації — **опція**. Генератор перетворює анотації на код того самого
  явного API. Згенерований код читабельний і дебажиться.
- Генератор відокремлений від драйвера: спочатку власний CLI з watch-режимом,
  потім тонка обгортка під build_runner.
- Валідація DI-графа робиться двічі: статично в генераторі (до запуску) і в
  ядрі на старті (fail-fast).

### Що «краще за Nest»

- Працює без декораторів/кодгену: тести, прототипи, REPL.
- Помилки DI-графа видно до запуску, з ланцюжком залежностей.
- Жадібна синхронна ініціалізація замість лінивого контейнера: передбачуваний
  старт, `forRootAsync` як окреме поняття не потрібен.
- Типізовані токени замість рядкових.
- Генерований файл один на пакет; файли користувача не змінюються.

### Поза межами v1

Request-scoped провайдери, lifecycle-хуки, GraphQL (v2), WebSockets/SSE,
мікросервісний транспорт, scaffolding-CLI (`nest g`),
адаптер `relic`. Hot reload / hot restart — окремий dev-режим (розділ 10),
його реалізація після CLI; у v1 ядро лише дотримується вимог розділу 10.1. Генерація OpenAPI — v1.1; v1 лише закладає для неї
архітектуру (див. розділ 6.5).

## 2. Структура пакетів і шари

Монорепо, pub workspace.

| Пакет | Відповідальність | Залежності |
|---|---|---|
| `dartnest` | Ядро: `Module`, `Provider`, `Token`, `Injector`, `Controller`, `Route`, роутер, конвеєр, `ExecutionContext`, `Application`, інтерфейс `HttpAdapter`, моделі `HttpRequest`/`HttpResponse`, `TestClient` | Dart SDK; бібліотека `package:dartnest/adapter.dart` відкриває адаптерам `InFlightRequests` і `AdapterLifecycle` (спільний автомат listen/close) |
| `dartnest_annotations` | Лише `const`-класи анотацій | — |
| `dartnest_io` | Адаптер на `dart:io` `HttpServer` | `dartnest` |
| `dartnest_shelf` | Адаптер на shelf; `shelfHandler(app)` для вбудовування | `dartnest`, `shelf` |
| `dartnest_conformance` | Спільний conformance-набір для адаптерів (непублікований тестовий пакет, `package:test` лише тут і в `test/`) | `dartnest`, `test` |
| `dartnest_generator` | Логіка генерації: analyzer `LibraryElement` → код явного API; набір `Construct` | `analyzer`, `code_builder`, `dart_style` |
| `dartnest_cli` | `dart run dartnest_cli gen [--watch]` | `dartnest_generator`, `watcher` |
| `dartnest_build` | Builder для build_runner (агрегуючий, вхід `lib/$lib$`) | `dartnest_generator`, `build` |
| `dartnest_openapi` (v1.1) | `OpenApiConstruct` (статичний `openapi.json` + код документа), модуль `openApiModule` з `/openapi.json` і UI (Scalar/Swagger) | `dartnest`, `dartnest_generator` |
| `dartnest_graphql` (v2) | Виконавець схеми, `Resolver`, `Construct` для резолверів | `dartnest` |

Правила шарування:

1. Ядро не знає про анотації та генератор.
2. Анотації в окремому пакеті без залежностей, щоб застосунок не тягнув
   `analyzer`.
3. Генератор не знає про драйвер: вхід — набір бібліотек пакета, вихід —
   список файлів і діагностик.
4. Конвеєр у ядрі працює з `ExecutionContext`, а не з HTTP. HTTP — один
   транспорт; GraphQL у v2 — другий.

## 3. DI та модулі

### Явний API

```dart
const dbUrl = Token<String>('db.url');

final usersModule = Module(
  id: 'users',
  imports: [databaseModule(url: env('DB_URL'))],
  providers: [
    Provider((i) => UsersRepo(i.get())),       // T виводиться з повернення
    Provider((i) => UsersService(i.get())),    // i.get() виводить T з параметра
    Provider<Clock>((i) => SystemClock()),     // абстракція → реалізація
    Provider.value(appConfig),
    Provider.async((i) async => Db.connect(i.get(dbUrl))),
  ],
  controllers: [usersController],
  exports: [UsersService],
);

Module databaseModule({required String url}) => Module(
  id: 'database',
  providers: [Provider.value(url, token: dbUrl)],
  exports: [dbUrl],
);
```

Типи:

- `Module({required Symbol id, List<Module> imports, List<Provider> providers,
  List<Controller> controllers, List<Object> exports, bool global = false})`.
  `exports` приймає `Type`, `Token` або `Module` (реекспорт імпорту).
- `Provider<T>` — фабрика `FutureOr<T> Function(Injector i)` плюс ключ:
  `Type` (за замовчуванням `T`) або `Token<T>`. Конструктори: `Provider(fn)`,
  `Provider.value(v, {token})`, `Provider.async(fn, {token})`.
- `Token<T>` — `const` клас з ім'ям; рівність — за типом `T` і за ім'ям
  (симетрична, узгоджена з `hashCode`), тож два `Token<String>('db.url')`
  з різних файлів — один ключ. Рядкових токенів немає.
- `Injector` — `T get<T>([Token<T>? token])`, `T? maybeGet<T>(...)`.
  Синхронний, незмінний після старту.

### Семантика

- **Область видимості як у Nest.** Провайдер видимий у своєму модулі та
  в модулях, які його імпортують, лише якщо він у `exports`. `global: true`
  робить експорти видимими всюди. Кожен модуль має власний `Injector`;
  пошук: власні провайдери → експорти прямих імпортів → глобальні.
- **Синглтони, жадібна ініціалізація.** На `Application.create()` граф
  валідується, потім усі провайдери створюються в топологічному порядку.
  Фабрики можуть бути `async`. Контролери створюються після провайдерів
  свого модуля.
- **Динамічні модулі** — звичайні функції, що повертають `Module`.
  Дедуплікація за `id`: повторний імпорт із тим самим `id` дає один
  екземпляр; два модулі з одним `id`, але різними конфігураціями (різний
  набір провайдерів/імпортів за структурним порівнянням) — помилка на старті.
- **Валідація у два кроки.** Структура — до створення будь-чого
  (`ModuleGraph.build`): конфлікт `id`, цикл імпортів, дублікат ключа в
  модулі, некоректний export, неоднозначний export (один ключ з двох різних
  модулів-власників). Залежності фабрик ядро без mirrors не бачить, тому
  відсутній провайдер, цикл залежностей і неекспортований провайдер
  виявляються fail-fast під час eager-старту, до повернення контейнера;
  повну статичну перевірку робить генератор (етап 4). Повідомлення містять
  ланцюжок: `UsersService ← UsersRepo ← Db (модуль 'users'): Db не
  знайдено. Експортують Db: 'database' (не імпортовано в 'users')`.

### Анотаційний еквівалент

```dart
@Module(
  imports: [DatabaseModule],
  providers: [UsersRepo, UsersService, Bind<Clock, SystemClock>(), Value(appConfig)],
  controllers: [UsersController],
  exports: [UsersService],
)
class UsersModule {}

@Injectable()
class UsersService {
  UsersService(this.repo, @Inject(dbUrl) this.url);
}
```

Генерується `final usersModule = Module(...)` з фабриками, виведеними
з неіменованого конструктора: кожен параметр → `i.get<T>()` або
`i.get(token)`. Динамічні модулі в анотаційному стилі: статичний метод
`static Module forRoot(...)` у класі з `@Module` — генератор підставляє його
як є (валідація графа для нього часткова, перевіряється на старті).

## 4. Контролери, роути, конвеєр

### Явний API

```dart
class UsersController {
  UsersController(this.service);
  final UsersService service;
  Future<User> findOne(int id) => service.find(id);
  Future<User> create(CreateUserDto dto) => service.create(dto);
}

final usersController = Controller<UsersController>(
  path: '/users',
  create: (i) => UsersController(i.get()),
  guards: [Use<AuthGuard>()],
  routes: [
    Route.get('/:id', (c, ctx) => c.findOne(ctx.param<int>('id'))),
    Route.post('/', (c, ctx) async =>
        c.create(CreateUserDto.fromJson(await ctx.body.json())),
      metadata: [Roles(['admin'])]),
  ],
);
```

- `Controller<T>` — шлях, фабрика, список `Route`, а також `guards`,
  `interceptors`, `pipes`, `filters`, `metadata` рівня контролера. Екземпляр
  `T` створюється один раз на старті через `Injector` свого модуля.
- `Route` — HTTP-метод, шаблон шляху, хендлер `FutureOr<Object?>
  Function(T controller, ExecutionContext ctx)` і ті самі списки рівня роуту.
  `Route` наслідує абстрактний `HandlerSpec` (metadata, guards, interceptors,
  pipes, filters, invoke); у v2 `Field` резолвера наслідує той самий
  `HandlerSpec`, тому конвеєр спільний.
- Компоненти конвеєра реєструються як `Use<T>()` (резолв через DI модуля
  контролера, тому guard може інжектити сервіси) або як готовий екземпляр.

### Порядок виконання запиту

1. Адаптер → `HttpRequest`.
2. Middleware (тільки HTTP, рівень застосунку): `app.use((req, next) => ...)`.
3. Роутер: radix-дерево, статичні сегменти > параметри `:id` > wildcard `*`;
   404 якщо шлях не знайдено, 405 якщо знайдено з іншим методом.
4. Створення `ExecutionContext`.
5. Guards: app → controller → route; перший `false` → 403.
6. Interceptors (цибулею, app → controller → route): `intercept(ctx, next)`.
7. Хендлер; параметри дістаються з `ctx`, pipes застосовуються на
   `ctx.param/query/body` (route/controller/app-рівень плюс явні в виклику).
8. Серіалізація результату → `HttpResponse`.
9. Будь-який виняток на кроках 5–8 → exception filters: route → controller
   → app → дефолтний.

### ExecutionContext

- `transport` — sealed: `HttpTransport` у v1, `GraphQLTransport` у v2.
- `switchToHttp()` → `HttpContext { request, response builder }`.
- `controllerType`, `handlerName`, `T? metadata<T>()` (роут перекриває
  контролер).
- `items` — `Map<Object, Object?>` для передачі даних між guard і хендлером.
- `param<T>(name)`, `query<T>(name)`, `header(name)`, `body` (`json()`,
  `text()`, `bytes()`, `stream`) — з кешуванням прочитаного тіла.
  Конвертери для `String/int/double/bool/num/DateTime/enum-by-name`; інші
  типи — через явний pipe.

### Інтерфейси

```dart
abstract interface class Guard { FutureOr<bool> canActivate(ExecutionContext ctx); }
abstract interface class Interceptor { FutureOr<Object?> intercept(ExecutionContext ctx, Next next); }
abstract interface class Pipe<I, O> { FutureOr<O> transform(I value, ArgumentMeta meta); }
abstract interface class ExceptionFilter<E extends Object> { FutureOr<Object?> handle(E error, ExecutionContext ctx); }
typedef Middleware = Future<HttpResponse> Function(HttpRequest req, Next<HttpResponse> next);
```

### Серіалізація відповіді

Результат хендлера: `HttpResponse` → як є; `null` → 204; `String` →
`text/plain`; `Map/List/num/bool` → JSON; інакше реєстр
`app.serializers.register<T>(fn)`; інакше динамічний виклик `toJson()`
(працює в AOT); інакше 500 з `SerializationError`.

### Анотаційний еквівалент

```dart
@Controller('/users')
@UseGuards([AuthGuard])
class UsersController {
  UsersController(this.service);
  final UsersService service;

  @Get('/:id')
  Future<User> findOne(@Param('id') int id) => service.find(id);

  @Post()
  @Roles(['admin'])  // class Roles extends RouteMetadata
  Future<User> create(@Body() CreateUserDto dto, @Query('notify') bool? notify) => ...;
}
```

Правила прив'язки параметрів у генераторі: `@Param/@Query/@Header` →
`ctx.param<T>()` тощо, nullable тип → необов'язковий; `@Body()` → `T.fromJson(await ctx.body.json())`, якщо `T`
має `fromJson(Map<String, dynamic>)`, інакше `Map/String/List<int>` напряму;
параметр типу `ExecutionContext`, `HttpRequest` → відповідний об'єкт.
Невідома анотація або неможлива прив'язка — помилка генерації.

## 5. HTTP-адаптер і Application

```dart
abstract interface class HttpAdapter {
  Future<void> listen(RequestHandler handler, {required Object address, required int port});
  Future<void> close({bool force = false});
}
typedef RequestHandler = Future<HttpResponse> Function(HttpRequest request);
```

- `HttpRequest`: `method`, `uri`, `headers` (регістронезалежна мультимапа),
  `body: Stream<List<int>>`, `connectionInfo`.
- `HttpResponse`: `status`, `headers`, `body` (bytes | String | Stream);
  фабрики `HttpResponse.json/text/bytes/stream/redirect`.
- `dartnest_io`: `IoAdapter({SecurityContext?})`.
- `dartnest_shelf`: `ShelfAdapter()` і `Handler shelfHandler(Application app)`
  для вбудовування в наявний shelf-пайплайн.
- Спільний conformance-набір тестів для адаптерів (методи, заголовки,
  потокові тіла в обидва боки, великі тіла, коректне закриття).

```dart
final app = await Application.create(
  appModule,
  adapter: IoAdapter(),
  guards: [Use<AuthGuard>()],
  filters: [Use<HttpExceptionFilter>()],
);
await app.listen(port: 3000);
await app.close();
```

`Application.listen` передає адаптеру handler без власного лічильника
запитів: адаптер сам рахує запити в польоті (`InFlightRequests`; автомат
listen/close спільний для адаптерів: `AdapterLifecycle`), щоб
`close` не чекав покинутий хендлер довше за `closeTimeout` адаптера.

`app.handle(HttpRequest)` працює без адаптера; `TestClient(app)` дає
`get/post/...` для тестів.

## 6. Анотації та генератор

### Вихід

Один файл на пакет: `lib/<package>.dartnest.dart` — звичайна бібліотека
(не `part`), імпортує бібліотеки користувача й експортує значення:
`UsersModule` → `usersModule`, `UsersController` → `usersController`.
Файли користувача не змінюються. Форматується `dart_style`. Записується
лише якщо вміст змінився.

Багатопакетні застосунки: кожен пакет генерує свій файл; модуль з пакета A
імпортується в B як звичайне значення.

### Архітектура генератора

```
PackageModel (зібрані анотовані елементи) → [Construct...] → GeneratedUnit + Diagnostic
```

- `Collector`: обходить `LibraryElement` пакета, будує `PackageModel`
  (модулі, injectable-класи, контролери, їхні конструктори та методи).
  Для кожного елемента зберігає `documentationComment` і повний
  `DartType`; для типів, що зустрічаються як тіло запиту або результат
  хендлера, збирає `DtoModel`: поля (ім'я, тип, nullable, значення за
  замовчуванням), `@JsonKey(name:)` з json_serializable/freezed, якщо є.
- `Construct` — інтерфейс: `validate(PackageModel) → Iterable<Diagnostic>`,
  `generate(PackageModel) → Iterable<GeneratedUnit>`. `GeneratedUnit` — це
  або Dart-код (code_builder `Spec`, зливається в один файл пакета), або
  довільний файл (`path`, `contentType: json | yaml | text`), який драйвер
  записує як є. У v1: `ModuleConstruct`, `ProviderConstruct`,
  `ControllerConstruct`. У v1.1 `dartnest_openapi` додає `OpenApiConstruct`,
  у v2 `dartnest_graphql` — `ResolverConstruct`.
- Набір конструктів компілюється в CLI статично (Dart не завантажує код
  динамічно). `dartnest_cli` містить основні; для розширень користувач має
  `tool/dartnest.dart` з трьох рядків (`DartnestGen([core, graphql]).run(args)`),
  шаблон створює `dartnest_cli init`.

### Статична валідація

Ті самі перевірки, що на старті (відсутній провайдер, цикл, експорт, дублікат
`id`), плюс: конструктор публічний і неіменований, усі параметри
інжектовані за типом/токеном (іменовані — лише `required`), повнота анотацій
параметрів хендлера, наявність `fromJson`, дублікати роутів. Діагностика у
форматі `path:line:col: error: message`, ненульовий код виходу.

### Заділ під генерацію документації (реалізація у v1.1)

`OpenApiConstruct` з `PackageModel` будує документ OpenAPI 3.1 без додаткових
анотацій: шлях і метод з `@Controller`/`@Get`, параметри з `@Param/@Query/
@Header` з типами, схема тіла з `DtoModel` `@Body`-параметра, схема
відповіді з типу повернення (`Future<T>`, `List<T>` розгортаються),
описи з `///`-коментарів. Анотації `@ApiTags`, `@ApiResponse(status,
description)`, `@ApiProperty(...)` з `dartnest_annotations` лише доповнюють
те, чого з коду не вивести. Два виходи: статичний `openapi.json` (CI,
клієнт-кодген) і Dart-код `ApiDocument`, який `openApiModule(ui: ...)`
віддає в рантаймі разом зі сторінкою Scalar або Swagger UI. GraphQL у v2
документується власною інтроспекцією. Для v1 обов'язкові лише вимоги до
`Collector` і `GeneratedUnit`, описані вище.

### Драйвери

- **CLI** (`dartnest_cli gen`, `gen --watch`): `AnalysisContextCollection`
  живе в пам'яті; `watcher` стежить за `lib/`; на зміну —
  `applyPendingFileChanges`, перерезолв змінених бібліотек, повний прогін
  конструктів (дешевий, у пам'яті). Цілі: холодна генерація < 10 с,
  інкремент < 1 с на пакеті з 200 файлів. Перевіряється бенчмарком у CI.
- **build_runner** (`dartnest_build`): `Builder` з
  `buildExtensions: {r'$lib$': ['<pkg>.dartnest.dart']}`, через
  `findAssets` + `resolver.libraryFor` будує той самий `PackageModel`.
  Реалізується після CLI, в межах v1.

## 7. Помилки

- Старт: ієрархія `DartnestError` → `InjectionError` (`MissingProvider` з підказкою
  `definedIn` замість окремого `NotExported`, `CircularDependency`,
  `DuplicateModuleId`, `CircularModuleImport`, `DuplicateProvider`,
  `InvalidExport`, `AmbiguousProvider`, `AsyncProviderNotReady`,
  `ProviderCreation`), `RoutingError`
  (`DuplicateRoute`). Fail-fast, без часткового старту.
- Рантайм: `HttpException(status, {message, details})` і підкласи
  (`NotFound`, `BadRequest`, `Unauthorized`, `Forbidden`). Дефолтний фільтр →
  JSON `{statusCode, error, message}`. Невідомий виняток → 500, стек у лог;
  у `debug: true` стек у відповідь.
- Генератор: діагностики, не винятки; watch продовжує працювати після помилки.

## 8. Тестування

- Ядро: юніт-тести DI (область видимості, дедуплікація, цикли, порядок
  ініціалізації), роутера, конвеєра (порядок guards/interceptors/filters,
  метадані) — без HTTP, через `app.handle` і `TestClient`.
- Адаптери: один conformance-набір на реальних сокетах (ефемерний порт),
  запускається для `dartnest_io` і `dartnest_shelf`.
- Генератор: golden-тести на fixture-пакетах у `test/fixtures/*`
  (вхід → очікуваний `.dartnest.dart`), тести діагностик (вхід → очікувані
  помилки з позиціями), тест «згенерований код компілюється та проходить ті
  самі e2e-тести, що й явний варіант».
- `example/`: один застосунок у двох стилях (явний і анотаційний), e2e на
  обох адаптерах у CI.

## 9. Порядок реалізації (високорівнево)

1. Ядро: `Token`, `Provider`, `Module`, `Injector`, валідація, жадібна
   ініціалізація.
2. Ядро: `HttpRequest/Response`, роутер, `ExecutionContext`, `Controller/Route`,
   конвеєр, серіалізація, `Application`, `TestClient`.
3. `dartnest_io`, conformance-тести; `dartnest_shelf`.
4. `dartnest_annotations`; `dartnest_generator` (Collector, конструкти,
   валідація, golden-тести).
5. `dartnest_cli` (`gen`, `--watch`, `init`), бенчмарк.
6. `dartnest_build`.
7. `example/` у двох стилях, документація.
8. (v1.1) `dartnest_openapi`: `OpenApiConstruct`, `openApiModule`, UI.

## 10. Hot reload і hot restart (dev-режим)

Мета: правка коду бекенду видна за секунди без ручного перезапуску, у
двох режимах, як у Flutter. Працює лише під JIT (`dart run`), у AOT-збірці
відсутнє. Увімкнення тільки в debug (`!bool.fromEnvironment('dart.vm.product')`),
у production-коді нуль накладних витрат.

- **Hot restart** — завершити застосунок (`app.close()`: адаптер припиняє
  приймати з'єднання, in-flight запити дожидаються до таймауту) і запустити
  заново. Стан скидається. Працює для будь-яких змін.
- **Hot reload** — VM підміняє код методів без перезапуску
  (`reloadSources` через VM service), після чого фреймворк викликає
  `app.reassemble()`. Стан провайдерів зберігається. Змінені тіла методів
  працюють одразу; зміни полів, конструкторів, `const`-значень і
  top-level-ініціалізаторів потребують restart (обмеження Dart VM).

### 10.1 Вимоги до ядра (діють з v1)

1. **Визначення модулів і контролерів перерахуємі.** `Application.create`
   приймає як значення `Module`, так і `Module Function()`. Другий варіант
   дозволяє `reassemble` заново побудувати граф після reload, бо
   top-level `final usersModule = Module(...)` після reload не
   переініціалізується й не побачить нових роутів. Генератор емітить функції
   або getter-и, а не top-level `final`.
2. **`Container.reassemble(Module newRoot)`**: будує новий `ModuleGraph`,
   повторно використовує вже створені екземпляри за ключем
   `(moduleId, key)` для провайдерів, чий ключ і модуль не змінились,
   створює нові, відкидає зниклі. Контролери й роути створюються заново
   (вони без стану).
3. **Таблиця роутів підміняється атомарно**: запит, що вже виконується, до
   кінця йде старою таблицею, нові — новою.
4. **`Application.close()` коректний і повторюваний** (тримає graceful
   shutdown, потрібний для restart).
5. Помилка в `reassemble` (наприклад, нова помилка графа) не валить
   застосунок: лишається попередній стан, помилка друкується з повним
   ланцюжком залежностей.

### 10.2 Інструмент

`dart run dartnest_cli dev [--entry bin/main.dart]`:

1. Запускає `dart --enable-vm-service=0 --no-dds <entry>` дочірнім процесом
   (не `dart run`: без неявного `pub get` на кожен restart і з одним
   процесом, PID якого є PID застосунку).
2. Стежить за `lib/` і `bin/`; на зміну спершу запускає генератор (у тому ж
   процесі CLI), потім:
   - клавіша `r` або автоматично при змінах, що підтримує reload: підключається
     до VM service (пакет `vm_service`), викликає `reloadSources`, потім
     service extension `ext.dartnest.reassemble`, яку `Application`
     реєструє в debug-режимі;
   - клавіша `R`, невдалий reload або зміна, що reload не підтримує: hot
     restart дочірнього процесу. Здебільшого CLI вирішує ще до reload: порівнює
     «форму» змінених файлів (поля, конструктори, змінні верхнього рівня,
     значення enum; `ShapeTracker`) із запам'ятованою і, якщо вона змінилась,
     одразу робить restart; відповідь `reloadSources` (`ReasonForCancellingReload`)
     лише запасний шлях для змін, яких форма не ловить. Зміни поза теками, за
     якими стежить CLI (path-залежності, `tool/`), reload застосовує без
     перевірки форми.
     Виняток: reload, що не компілюється, не призводить до restart —
     друкується помилка, а попередній застосунок продовжує працювати.
3. Виводить результат одним рядком: `reloaded 3 libraries in 180 ms, 2 routes
   changed` або причину, чому зроблено restart.

### 10.3 Тестування

- Юніт: `Container.reassemble` зберігає екземпляри незмінених провайдерів
  (ідентичність), створює нові, відкидає зниклі; помилка графа лишає старий
  стан; атомарна підміна роутів під паралельними запитами.
- Інтеграційний (повільний, окремий таск CI): `dartnest_cli dev` над
  fixture-застосунком; зміна тіла хендлера → відповідь змінилась без
  рестарту процесу (PID той самий); додавання роута → з'являється після
  reload; зміна поля класу → CLI робить restart (PID інший).

