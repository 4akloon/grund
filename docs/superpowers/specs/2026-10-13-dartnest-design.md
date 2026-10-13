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

Request-scoped провайдери, lifecycle-хуки, GraphQL, WebSockets/SSE, OpenAPI,
мікросервісний транспорт, scaffolding-CLI (`nest g`), hot reload,
адаптер `relic`.

## 2. Структура пакетів і шари

Монорепо, pub workspace.

| Пакет | Відповідальність | Залежності |
|---|---|---|
| `dartnest` | Ядро: `Module`, `Provider`, `Token`, `Injector`, `Controller`, `Route`, роутер, конвеєр, `ExecutionContext`, `Application`, інтерфейс `HttpAdapter`, моделі `HttpRequest`/`HttpResponse`, `TestClient` | Dart SDK |
| `dartnest_annotations` | Лише `const`-класи анотацій | — |
| `dartnest_io` | Адаптер на `dart:io` `HttpServer` | `dartnest` |
| `dartnest_shelf` | Адаптер на shelf; `shelfHandler(app)` для вбудовування | `dartnest`, `shelf` |
| `dartnest_generator` | Логіка генерації: analyzer `LibraryElement` → код явного API; набір `Construct` | `analyzer`, `code_builder`, `dart_style` |
| `dartnest_cli` | `dart run dartnest_cli gen [--watch]` | `dartnest_generator`, `watcher` |
| `dartnest_build` | Builder для build_runner (агрегуючий, вхід `lib/$lib$`) | `dartnest_generator`, `build` |
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
  id: #users,
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
  id: #database,
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
- `Token<T>` — `const` клас з ім'ям для діагностики; ідентичність — за
  посиланням на екземпляр (`const` канонізація) або за ім'ям, якщо ввімкнено
  `Token.byName`. Рядкових токенів немає.
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
- **Валідація до створення** будь-чого: відсутній провайдер,
  цикл, спроба взяти неекспортований провайдер, дублікат ключа в модулі,
  конфлікт `id`. Повідомлення містять ланцюжок: `UsersService ← UsersRepo
  ← Db (модуль #users): Db не знайдено. Експортують Db: #database (не
  імпортовано в #users)`.

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
- `Construct` — інтерфейс: `validate(PackageModel) → Iterable<Diagnostic>`,
  `generate(PackageModel) → Iterable<Spec>` (code_builder). У v1: `ModuleConstruct`,
  `ProviderConstruct`, `ControllerConstruct`. У v2 `dartnest_graphql` додає
  `ResolverConstruct`.
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

- Старт: ієрархія `DartnestError` → `InjectionError` (`MissingProvider`,
  `CircularDependency`, `NotExported`, `DuplicateModuleId`), `RoutingError`
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
