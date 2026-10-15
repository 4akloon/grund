# grund — бекенд-платформа на Dart: огляд і рішення

Дата: 2026-10-15. Статус: затверджено як рамка для серії етапних spec-ів.
Цей документ фіксує рішення сесії брейншторму та замінює «Мету та контекст»
spec-у `2026-10-13-dartnest-design.md` у частині позиціонування. Деталі
кожного етапу — в окремих spec-ах; перший: `2026-10-15-grund-core-design.md`.

## 1. Що будуємо і навіщо

**grund** — модульна бекенд-платформа на Dart із permissive-ліцензією (MIT або
BSD-3), конкурент Serverpod. Контракт із клієнтами — звичайний HTTP + OpenAPI
3.1, а не власний RPC. Один процес обслуговує API, realtime і SSR-сайт на
Jaspr. Клієнти будь-якою мовою генеруються зі специфікації; Dart-клієнт —
через `typed_openapi`.

Мета: OSS-екосистема з подальшим комерційним шаром (hosting, підтримка). Тому
важливі цілісний DX, одна документація, одне «обличчя».

Назва `grund` (норд./нім. «основа, ґрунт») обрана 2026-10-15: на pub.dev
вільні `grund`, `grund_cli`, `grund_auth`, `grund_openapi`, `grund_http`;
GitHub-організація — `grund-dev`. Репозиторій `dartnest` перейменовується.

### 1.1 Serverpod сьогодні (перевірено 2026-10-15)

Serverpod 3.x/4.0: endpoint-класи → згенерований Flutter-клієнт; YAML-моделі
→ серіалізація + ORM + міграції (лише Postgres); модульна auth (JWT або
сесії, Email/Google/Apple/GitHub/Facebook/Microsoft/Firebase, 2FA); streaming,
message central через Redis, future calls, кеш, cloud storage; веб-сервер
Relic + `jaspr_serverpod`; у 4.0 клієнтський SQLite + offline sync
(experimental), `serverpod start` з hot reload стеку та embedded Postgres,
MCP-сервер у проєкті, тестовий harness `withServerpod`; Serverpod Cloud та
Insights; ліцензія SSPL.

Слабкі місця за відгуками: власний RPC замість REST/GraphQL, тому не-Flutter
клієнти «проти шерсті»; тільки Postgres; важка структура для малих проєктів;
SSPL; OpenAPI лише стороннім пакетом.

### 1.2 Наявні бібліотеки автора, з яких збирається платформа

| Бібліотека | Роль у grund | Стан |
|---|---|---|
| `dartnest` → `grund` | ядро: модулі, DI, конвеєр; переробляється (етап 1) | 0.1.0, не опубліковано |
| `basalt` | ORM, міграції, SQLite + Postgres | 0.1.0, не опубліковано |
| `typed_openapi` | генерація Dart-клієнта зі специфікації | 0.0.1 |
| `typed_graphql` | GraphQL-адаптер (поза v1) | 0.0.1 |
| `token_manager` | клієнтський життєвий цикл токенів | опубліковано |

Бібліотеки лишаються самостійними і корисними поза платформою. Інтеграційні
модулі `grund_*` живуть в одному репозиторії з ядром (рішення «B»: платформа
всередині репо ядра, бібліотеки — зовнішні залежності).

## 2. Межі v1

**Входить**: ядро + HTTP + генератор + OpenAPI; інтеграція basalt; auth
(сесії, email+password, Google/Apple); realtime (SSE, WebSocket) та Redis
pub/sub; інфра-модулі (jobs, cache, storage, observability); Jaspr SSR
тонким адаптером; CLI `init`/`gen`/`dev`.

**Свідомо не входить** (пишеться прямо в README): клієнтський SQLite /
offline sync, Flutter-специфічний SDK і спільні Dart-моделі між сервером і
клієнтом, managed cloud, повний `start`-TUI зі стеком, embedded Postgres,
2FA/passkeys/magic links, Dart WS-клієнт, `@Transactional`/`@Cached`-подібна
«невидима» поведінка. Перший пункт після v1 — `start` зі стеком.

Зв'язок із Flutter навмисно слабкий: клієнт споживає OpenAPI. basalt-ентіті
— серверні; DTO окремі; мапінг явний.

## 3. Принципи

1. **Модуль — основа композиції.** Межа фічі, енкапсуляція через `exports`,
   граф імпортів з перевіркою до старту, lifecycle. Платформні модулі
   (`BasaltModule`, `AuthModule`) — звичайні модулі.
2. **HTTP не в ядрі.** Ядро знає лише модулі, bindings, інжектор, lifecycle,
   `Runner`. Транспорти збирають свої внески з графа за типом binding-у
   (`Provider<Api>`, `Provider<Channel>`, `Provider<Job>`): дженерики Dart
   реїфіковані, mirrors не потрібні.
3. **Класи, не голі функції.** Сервіси, API, хуки, модулі, джоби — класи зі
   звичайними конструкторами. Без Zone, глобальних `inject()`, `Injector` у
   конструкторах сервісів, arity-методів `of1..ofN`.
4. **Wiring пише генератор.** Анотації перелічують (`@Module(providers:
   [...])`), генератор читає конструктори та емітить явну форму. Явна форма
   — ціль генерації та escape hatch. Будь-який рантайм-код конфігурації —
   у `@Provides`-статичних методах модуля, без замикань навіть для сторонніх
   типів.
5. **Const у анотації — ідентичність і флаги; рантайм — у `@Provides`.**
   Модулі з const-конструктором параметризуються прямо в `imports`
   (`BasaltModule(name: 'analytics')`).
6. **Модуль не знає про реалізації.** `grund_basalt` споживає `Connection`,
   драйвер дає `grund_basalt_postgres`/`_sqlite`. Так само `grund_redis` →
   `_cache`/`_pubsub`/`_jobs`, `grund_storage` → `_storage_s3`.
7. **Явне краще за невидиме.** Транзакція — `db.transaction((tx) => ...)`,
   кеш — виклик `Cache`. Жодних AOP-анотацій на методах сервісів.
8. **Стандарти замість власних діалектів** (розділ 5).
9. **CLI ядра знає лише ядро.** Решта — `bin/` своїх пакетів
   (`dart run grund_openapi:export`). Міграції — `basalt` CLI.
10. **Один `main`, усе з графа.** `App(root: AppModule()).run()` запускає всі
    `Runner`-и (HTTP, jobs, scheduler). Ролі — фільтр `--only`, не код.
11. Правила репозиторію лишаються: fail fast до старту, детермінований
    генератор, типізовані помилки з кодами, ліміти розміру файлів.

## 4. Карта пакетів

| Шар | Пакети | Зовнішні залежності |
|---|---|---|
| Ядро | `grund`, `grund_annotations`, `grund_generator`, `grund_build`, `grund_cli` | SDK, meta; analyzer лише в генераторі |
| HTTP | `grund_http`, `grund_io`, `grund_shelf`, `grund_conformance` (тести) | shelf в адаптері |
| Контракт | `grund_openapi` | typed_openapi — зовнішній клієнтський інструмент |
| Дані | `grund_basalt`, `grund_basalt_postgres`, `grund_basalt_sqlite` | basalt* |
| Auth | `grund_auth`, `grund_auth_oauth` | token_manager на клієнті |
| Realtime | `grund_sse`, `grund_ws`, `grund_pubsub` | окрема бібліотека `typed_sse`; redis |
| Інфра | `grund_redis`, `grund_cache`, `grund_jobs`, `grund_storage`, `grund_storage_s3`, `grund_observability` | redis, S3, OpenTelemetry |
| Веб | `grund_jaspr` | jaspr |

Окремий репозиторій-бібліотека **`typed_sse`** (назва `sse` на pub.dev зайнята пакетом команди Dart): кодек WHATWG event-stream у обох
напрямках (`SseDecoder` переїжджає з `typed_openapi_runtime`, додається
`SseEncoder`). Без залежностей і без HTTP; на нього переходять і
`typed_openapi_runtime`, і `grund_sse`.

## 5. Стандарти

Де є загальноприйнята специфікація — беремо її без власних діалектів:

- HTTP: OpenAPI 3.1, JSON Schema 2020-12, помилки RFC 9457 Problem Details,
  пагінація RFC 8288 `Link` + cursor, `ETag`/умовні запити.
- SSE: WHATWG event-stream (`Last-Event-ID`, `retry`), без власних полів.
- WebSocket: RFC 6455; повідомлення — JSON-RPC 2.0; документація AsyncAPI 3.
- Auth: OAuth 2.1 + OIDC, PKCE, cookie RFC 6265bis, argon2id RFC 9106, JWT
  RFC 7519/8725.
- Події між сервісами та в jobs: конверт CloudEvents 1.0.
- Observability: OpenTelemetry (трейси, метрики, логи, OTLP, semantic
  conventions); health `application/health+json` (IETF draft).
- Storage: S3 API.

## 6. Рішення по модулях (стислий дизайн)

### 6.1 Ядро та HTTP — див. `2026-10-15-grund-core-design.md`

### 6.2 `grund_openapi`

Документ будується один раз на старті зі згенерованого `ApiDescription` у
графі, тож завжди відповідає коду, що виконується (включно з хуками, які
додають security, і модулями, увімкненими конфігом). `OpenApiModule(path:,
ui:)` віддає `GET /openapi.json`, `/openapi.yaml` з `ETag` і Scalar UI на
`/docs`. `dart run grund_openapi:export` для CI: піднімає граф без `listen`
і пише той самий документ у файл; обидва виходи байт-ідентичні.

Мапінг: `///` → summary/description; типи Dart → схема (nullable → не
required, default конструктора → `default`, enum, sealed → `oneOf` з
дискримінатором); валідаційні анотації (`@Range`, `@Length`, `@Pattern`,
`@Email`) одночасно виконуються екстрактором і потрапляють у схему; хуки
`implements SecurityScheme` → `securitySchemes` + 401/403; `@Throws(...)` →
responses зі схемами ProblemDetails; `@Deprecated` → `deprecated: true`;
escape hatch `@OpenApi(extra:)` і `openapi.overrides.yaml`. Контрактний тест:
`typed_openapi check` без діагностик.

### 6.3 `grund_basalt` + драйвери

`BasaltModule()` імпортує лише `basalt`: `Db`, request-scoped `Tx`
(опційно, `transactionPerRequest: true`), health-check, метрики пулу.
Споживає binding `Connection`; відсутність → помилка графа з підказкою.
`PostgresDriverModule`/`SqliteDriverModule` — по одному `@Provides
Connection` з конфігом драйвера і закриттям на shutdown. Кілька підключень:
`BasaltModule(name: 'analytics')` + `@Named('analytics')`. Міграції —
`basalt` CLI. Нова вимога до basalt: `QueryObserver` (SQL, тривалість,
рядки, помилка; параметри редаговані за замовчуванням).

### 6.4 `grund_auth`, `grund_auth_oauth`

Сесії як основа (opaque-токен у БД через basalt-міграції модуля, відкликання,
«вийти з усіх пристроїв»); JWT як опційна стратегія; refresh-ротація з
виявленням повторного використання. `IdentityProvider`-інтерфейс; у
`_oauth`: email+password (argon2id), Google, Apple, GitHub. Один `AuthUser` з
кількома identity, об'єднання акаунтів. Хуки `Authenticated()`, `Roles()`,
`Permissions()` кладуть `CurrentUser` у request scope і реалізують
`SecurityScheme`. Транспорт токена: Bearer та `httpOnly` cookie з одного
конфіга. Клієнт: typed_openapi + token_manager, нічого власного.

### 6.5 Realtime

`grund_sse`: метод `Api`, що повертає `Stream<T>`, стає SSE-ендпоїнтом;
`@LastEventId()` на параметрі; у OpenAPI — `text/event-stream` зі схемою;
відключення клієнта скасовує стрім через `CancelSignal`.
`grund_ws`: `@Channel('/ws/...')`-класи з `@OnConnect/@OnMessage/
@OnDisconnect`, збираються як `Provider<Channel>`; ті ж хуки для auth;
JSON-RPC 2.0; AsyncAPI 3. `grund_pubsub`: `EventBus` `publish<T>/
subscribe<T>` між інстансами (Redis Pub/Sub; `InMemoryBus` для тестів);
SSE/WS fan-out через нього; конверт CloudEvents.

### 6.6 Інфра

`grund_redis` біндить клієнт/пул. `grund_cache`: `Cache` з TTL і тегами,
Redis + in-memory. `grund_jobs`: Redis Streams з consumer groups,
at-least-once, retry з backoff, dead-letter, відкладені й cron-задачі;
`@Job(queue:, retries:)`-класи з графа; `JobsRunner` обробляє всі джоби
графа; `jobs.enqueue(SendWelcomeEmail, payload, delay:)`.
`grund_storage` + `_s3`: put/get/delete/list, presigned URL; S3-сумісні
(AWS, RustFS, MinIO, R2) і локальна FS для dev.
`grund_observability`: наскрізний трейс «HTTP → Hook → handler → db.query →
redis → job.enqueue» одним `trace_id`; observer-контракти в кожному модулі
(basalt `QueryObserver`, redis-команди, jobs, pubsub, cache hit/miss, auth,
HTTP/Hook/серіалізація, SSE/WS); OTel semantic conventions; структуровані
логи з `trace_id`; `/healthz`, `/readyz` з `HealthCheck`-класів графа.
Без власного UI: `DevExporter` тримає останні N трейсів у пам'яті, віддає
через MCP-ресурс і `dart run grund_observability:tail`; у проді лише OTLP.

### 6.7 `grund_jaspr`

`JasprModule` монтує SSR-роути в той самий `HttpServer`; компоненти
отримують `Injector` і `CurrentUser` через Jaspr-контекст; cookie-сесія
працює без змін; `jaspr serve` у dev стартує наш сервер як бекенд.
Клієнтська частина Jaspr викликає API через typed_openapi-клієнт.

### 6.8 CLI і тести

`grund_cli`: `init` (шаблони api / fullstack-jaspr; один `bin/main.dart` з
`App(...).run()`), `gen`, `gen --watch`, `dev` (hot reload, є). Без команд
про БД, OpenAPI, трейси.
Тести: `TestApp(root:, overrides:)` + `TestClient`; `TestChannel` для WS;
in-memory bus/cache/jobs; SQLite in-memory для basalt; conformance-suite
розширюється на SSE і WS; контрактний тест OpenAPI.

## 7. Порядок етапів

Кожен етап — окремий spec і план; наступний spec пишеться після здачі
попереднього. Платформа виходить релізами 0.x: 0.1.0 після етапів 1–2, далі
по релізу на кожен етап; 1.0.0 — стабілізація після етапу 7, коли зібрано
весь обсяг v1 (розділ 2). Таблиця релізів — у `ROADMAP.md`.

1. **Ядро нового API + `grund_http` + генератор** (переписування наявного;
   spec `2026-10-15-grund-core-design.md`).
2. `grund_openapi` + контрактний тест із typed_openapi.
3. `grund_basalt` + драйвери; `QueryObserver` у basalt.
4. `grund_auth` (сесії, email+password, Google/Apple).
5. Бібліотека `typed_sse`, `grund_sse`, `grund_redis`, `grund_pubsub`.
6. `grund_jobs`, `grund_cache`, `grund_storage`, `grund_observability`.
7. `grund_ws`, `grund_jaspr`, шаблони `init`.

Після v1: `start` зі стеком, GraphQL-адаптер над typed_graphql, 2FA/passkeys,
Dart WS-клієнт.
