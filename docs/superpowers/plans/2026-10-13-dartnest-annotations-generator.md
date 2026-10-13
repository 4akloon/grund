# dartnest Annotations and Generator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Етап 4 роадмапу: пакет `dartnest_annotations` (анотації без залежностей) і пакет-бібліотека `dartnest_generator`: `PackageCollector` → `PackageModel` (з doc-коментарями, типами й `DtoModel`), конструкти `ModuleConstruct`, `ProviderConstruct`, `ControllerConstruct`, статична валідація з `path:line:col`, golden-тест і той самий e2e-набір для явного та згенерованого графа модулів.

**Architecture:** Три шари всередині `dartnest_generator`. **Collector** (`lib/src/collector/`) читає резолвлені `LibraryElement` пакета й будує незмінну модель (`lib/src/model/`), у якій немає жодного типу analyzer: типи — `TypeModel`, константи анотацій — `ConstantValue`, ключі провайдерів — `ProviderKey`; усе, чого не вдалося прочитати, лишається в моделі як рядок-проблема, collector нічого не кидає й не звітує. **Конструкти** (`lib/src/constructs/`) реалізують інтерфейс `Construct`: `validate(PackageModel)` повертає `Diagnostic` з кодом і `path:line:col`, `generate(PackageModel)` — `DartUnit` з `code_builder`-`Spec`, які будує шар **emit** (`lib/src/emit/`). `DartnestGenerator` запускає всі `validate`; будь-яка діагностика зупиняє генерацію, інакше `LibraryWriter` зливає всі `DartUnit` в одну бібліотеку `lib/<package>.dartnest.dart` (`ImportAllocator` дає префікси, `DartFormatter` форматує). Драйверів (CLI, build_runner) у цьому етапі немає: тести резолвлять фікстурні пакети через `AnalysisContextCollection` так, як це робитиме CLI етапу 5.

**Tech Stack:** Dart SDK ^3.8.0 (без dot shorthands, null-aware elements і primary constructors), `analyzer` `'>=8.1.1 <15.0.0'`, `code_builder` ^4.11.1, `dart_style` ^3.1.2, `path` ^1.9.0, `pub_semver` ^2.1.4 (лише `dartnest_generator`); `package:test` ^1.25.0, `package:lints` ^5.1.0 + strict-casts/inference/raw-types.

**Spec:** `docs/superpowers/specs/2026-10-13-dartnest-design.md` (розділи 3 і 4 «Анотаційний еквівалент», 6 «Анотації та генератор», 7 «Помилки» — генератор, 8 «Тестування» — генератор, 10.1 п. 1); `docs/superpowers/ROADMAP.md`, етап 4.

## Open points

Рішення, які план приймає сам, але які автор може змінити до виконання. Для кожного — таблиця компромісів, варіанти й рекомендація; план написано за рекомендованим варіантом (позначено ✔).

### OP1. Діапазон `analyzer`

| Варіант | Мін. SDK генератора | Хто може поставити генератор | Ризик |
|---|---|---|---|
| A ✔ `'>=8.1.1 <15.0.0'` | 3.8 (analyzer 8.1.1 вимагає ^3.7) | будь-хто на Dart 3.8+ | два API analyzer у підтримці; перевірено обидва краї (див. «Самоперевірка») |
| B `^14.5.0` | 3.11 (analyzer 14.5 вимагає ^3.11) | лише Dart 3.11+ | порушує «Minimum SDK: Dart 3.8 … also for generated code» для всього ланцюжка інструментів |
| C `^8.1.1` (лише 8.x) | 3.8 | будь-хто, але не разом з інструментами на analyzer ≥ 9 | конфлікт версій у проєктах з іншими генераторами (build_runner, freezed) |

Код використовує лише API, спільне для 8.1.1 і 14.x (`nonSynthetic`, `formalParameters`, `displayName`, ім'я неіменованого конструктора не порівнюється). Нюанс: на нижньому краї `package:test` ≥ 1.27 вимагає analyzer ≥ 13, тож перевірка нижнього краю пінить `test` < 1.27; в `dev_dependencies` лишається `^1.25.0`.
**Варіанти:** A — широкий діапазон; B — лише свіжий analyzer і SDK-підлога генератора 3.11; C — лише 8.x. **Рекомендація: A.**

### OP2. Імена `Module` і `Controller` в анотаціях

| Варіант | Як пише користувач | Конфлікт з явним API | Відповідність специфікації |
|---|---|---|---|
| A ✔ імена зі специфікації + `hide` | `import 'package:dartnest/dartnest.dart' hide Controller, Module;` | є, знімається `hide`; явний модуль (`Module x() => Module(...)`) живе в окремому файлі без `hide` | повна (`@Module`, `@Controller`) |
| B `@NestModule`, `@NestController` | без `hide` | немає | відхилення від прикладів розділів 3, 4 |
| C префіксний імпорт `as a` | `@a.Module(...)` | немає | синтаксично шумно |

Фікстура `cases_app` показала ціну A: функція `Module explicitModule()` у файлі з `hide` резолвилась у клас-анотацію; тому `explicit.dart` — окремий файл. **Варіанти:** A, B, C. **Рекомендація: A** (специфікація; README `dartnest_annotations` пояснює `hide`).

### OP3. Модулі, які генератор не бачить наскрізь

Модуль із функції (`imports: [metricsModule]`, `DbModule.forRoot`) або `@Module` з іншого пакета — «непрозорий»: генератор не знає його провайдерів.

| Варіант | Хибні `missing_provider` | Пропущені помилки | Складність |
|---|---|---|---|
| A ✔ є хоч один непрозорий модуль у пакеті → `missing_provider` і `circular_dependency` не перевіряються взагалі (структура перевіряється) | немає | ловить `Application.create` на старті | мала |
| B вимикати лише для модулів, що бачать непрозорий (транзитивно, з урахуванням глобальних) | немає | менше | середня; глобальний непрозорий модуль однаково вимикає все |
| C вимагати моделі інших пакетів (читати їхні `@Module` через analyzer) | немає | найменше | велика; потрібна в CLI етапу 5 |

**Варіанти:** A, B, C. **Рекомендація: A для етапу 4**, C — кандидат для етапу 5 (CLI резолвить залежні пакети).

### OP4. Чи обов'язковий `@Injectable()`

| Варіант | Явність | Помилки користувача |
|---|---|---|
| A ✔ клас у `providers`, `Bind<K, I>` (`I`) мусить мати `@Injectable()`, інакше `not_injectable` | як у Nest; видно, що клас створює DI | забута анотація → зрозуміла діагностика |
| B будь-який клас з публічним неіменованим конструктором | менше анотацій | випадковий клас у `providers` мовчки стає провайдером |

Контролери й компоненти конвеєра `@Injectable()` не потребують (контролер має `@Controller`, компонент — провайдер модуля, OP7). **Рекомендація: A.**

### OP5. Динамічні модулі (`forRoot`) в анотаційному стилі

Специфікація (розділ 3): «статичний метод `static Module forRoot(...)` у класі з `@Module` — генератор підставляє його як є». Аргументи в `const`-анотації передати неможливо (виклик не є константою).

| Варіант | Що пише користувач | Аргументи | Валідація |
|---|---|---|---|
| A ✔ tear-off функції без обов'язкових параметрів, що повертає явний `Module` | `imports: [DbModule.forRoot, metricsModule]` | значення за замовчуванням або всередині функції (`env(...)`) | модуль непрозорий (OP3); перевіряється на старті |
| B окрема анотація `DynamicImport(#forRoot, [args])` | `imports: [DynamicImport(...)]` | лише константи | складніше, ті самі обмеження |

**Рекомендація: A**; конфігурацію з аргументами користувач пише явним API в окремому файлі (як `explicit.dart`).

### OP6. Тіло запиту

Специфікація: `@Body()` → `T.fromJson(await ctx.body.json())`.

| Варіант | Невалідний JSON / DTO | Код |
|---|---|---|
| A ✔ `await ctx.bodyAs(T.fromJson)` (ядро етапу 2) | 400 `BadRequestException`: зіпсований JSON, тіло — не JSON-об'єкт, `FormatException` з `fromJson` | той самий, що пише людина в явному стилі; пайпи тіла працюють |
| B дослівно `T.fromJson(await ctx.body.json())` | тіло-масив → `TypeError` при приведенні до `Map` → 500 | дублює логіку `bodyAs`, без пайпів |

`Map<String, Object?>` → `ctx.bodyAs<Map<String, Object?>>((json) => json)`, `String` → `await ctx.body.text()`, `List<int>` → `await ctx.body.bytes()`. **Рекомендація: A** (e2e перевіряє 400 для обох графів).

### OP7. Компоненти конвеєра в анотаціях

| Варіант | `@UseGuards([AuthGuard])` стає | Залежності guard'а | Перевірка |
|---|---|---|---|
| A ✔ типи → `Use<AuthGuard>()` | провайдер модуля, що бачить контролер | DI, як у Nest | `missing_provider`, якщо модуль його не надає; `invalid_component`, якщо тип не `Guard` |
| B `const`-екземпляри в анотації | `const AuthGuard()` | без DI | лише константи |

**Рекомендація: A.**

### OP8. `id` модуля за замовчуванням

| Варіант | `class UsersModule` без `id` | Стабільність |
|---|---|---|
| A ✔ ім'я класу (`'UsersModule'`) | `id: 'UsersModule'` | змінюється при перейменуванні класу; hot reload (етап 5b) ключує екземпляри за `id` |
| B похідне (`'users'`) | `id: 'users'` | те саме, але неочевидне правило |
| C `id` обов'язковий | помилка | найстабільніше, більше шуму |

**Рекомендація: A** (`users_app` задає `id` явно, як радитиме README).

### OP9. Типи параметрів хендлера

| Прив'язка | Підтримано | Чому |
|---|---|---|
| `@Param`, `@Query` | `String`, `int`, `double`, `num`, `bool`, `DateTime`, enum; `@Query` може бути nullable (необов'язковий) | це типи, які ядро парсить у `ctx.param<T>`/`ctx.query<T>`; enum — через `EnumPipe(T.values)` |
| `@Header` | `String`, `String?` | ядро віддає заголовок рядком; ненульовий тип без заголовка → 400 `Missing header "x".` |
| `@Body` | клас з `fromJson(Map<String, Object?>)` (конструктор або static), `Map<String, Object?>`, `String`, `List<int>` | OP6 |

Варіанти: A ✔ — лише ці типи, решта → `invalid_handler_parameter`/`missing_from_json`; B — дозволити користувацькі pipes для довільних типів (потрібна анотація на зразок `@Query('x', pipes: [...])`). **Рекомендація: A для v1**, B — після запиту користувачів.

### OP10. Де живе e2e-набір

| Варіант | Розташування | Плюс | Мінус |
|---|---|---|---|
| A ✔ `dartnest_generator/test/e2e` на фікстурі `users_app` | один пакет | golden і e2e на одному джерелі | e2e не проганяється на адаптерах |
| B `example/` (етап 7) | окремий застосунок | реальні адаптери | ще не існує |

**Рекомендація: A**; етап 7 повторює набір на адаптерах.

### OP11. `TypeModel` замість «повного `DartType`»

Специфікація: «для кожного елемента зберігає … повний `DartType`».

| Варіант | Конструкти залежать від analyzer | Тести моделі | OpenAPI (v1.1) |
|---|---|---|---|
| A ✔ `TypeModel` (ім'я, вид, бібліотека, аргументи, nullability) + `DtoModel` | ні | будуються в тесті без analyzer | `DtoModel` дає поля; чого бракує — додається в `TypeModel` |
| B `DartType` у моделі | так | лише через резолвлені фікстури | повна інформація |

**Рекомендація: A** — модель незмінна, порівнювана й не прив'язана до версії analyzer (OP1).

### OP12. `@Module` з іншого пакета

| Варіант | Що генерується | Умова |
|---|---|---|
| A ✔ за правилом імен: `class BillingModule` з `package:billing` → `billingModule()` з `package:billing/billing.dartnest.dart` | виклик функції | пакет `billing` теж згенеровано цим генератором |
| B заборонити, вимагати tear-off функції | — | менше магії, більше коду |

**Рекомендація: A** (специфікація, розділ 6: «модуль з пакета A імпортується в B як звичайне значення»).


## Рішення

1. **Вихід — один рядок-бібліотека на пакет.** `DartnestGenerator.generate` повертає `GenerationResult` з текстом `lib/<package>.dartnest.dart` (`library`) і довільними файлами (`files`, `FileUnit`); запис на диск «лише якщо вміст змінився» — справа драйвера (етап 5). Бібліотека починається з `// GENERATED BY dartnest_generator. DO NOT EDIT.` і `/// Generated from the annotations of package:<pkg>.` + `library;`, імпортує ядро як `dartnest` (будь-який `package:dartnest/src/...` перетворюється на barrel), інші бібліотеки — `i1`, `i2`, … у порядку першого використання (`Allocator.simplePrefixing` дає `_i1`, що порушує lint `no_leading_underscores_for_library_prefixes`), `dart:core` без префікса. Оголошення розділені порожнім рядком, текст форматує `DartFormatter` з мовною версією пакета (`languageVersion.package` його бібліотек, обрізаною до `major.minor.0`; пакет без бібліотек — 3.8.0).
2. **Функції, а не top-level `final`** (специфікація 10.1 п. 1 має пріоритет над прикладом `final usersModule` у розділі 3): `dartnest.Module usersModule() => dartnest.Module(...)`, `dartnest.Controller<X> xController() => ...`, фабрики провайдерів — приватні `X _createX(dartnest.Injector i) => X(...)` (не засмічують API пакета). Імена — `GeneratedNames`: `UsersModule` → `usersModule`, `Config` → `configModule`, `UsersController` → `usersController`, `Health` → `healthController`, `UsersService` → `_createUsersService`, пакет `shop` → `package:shop/shop.dartnest.dart`. Два оголошення з одним ім'ям → `duplicate_generated_name`.
3. **Порядок виводу**: `DartnestGenerator.core()` = `[ModuleConstruct(), ControllerConstruct(), ProviderConstruct()]` — спершу модулі, потім контролери, потім фабрики; усередині — порядок бібліотек за URI (а не порядок, у якому драйвер їх передав) і порядок оголошення в джерелі. Той самий вхід дає байт-у-байт той самий текст.
4. **Модель без типів analyzer** (OP11): `TypeModel`, `ConstantValue` (sealed: `NullConstant`, `BoolConstant`, `NumberConstant`, `StringConstant`, `ListConstant`, `SetConstant`, `MapConstant`, `TypeConstant`, `ReferenceConstant` — публічна константа чи значення enum, `ObjectConstant`, `UnsupportedConstant`), `ProviderKey` (`TypeKey`/`TokenKey`), `ModuleReference` (`LocalModuleReference`/`OpaqueModuleReference`), `ParameterBinding` (sealed, з `InvalidBinding`). Публічна константа читається як посилання на неї (`i1.adminRoles`), приватна — як виклик її конструктора; приватний клас у типі або аргументах типу → `UnsupportedConstant` → `unsupported_constant`.
5. **Проблеми — це дані.** Collector не кидає й не звітує: нечитабельний запис модуля стає рядком у `ModuleModel.invalidEntries`, поганий конструктор — `ConstructorModel.invalid(problem)`, поганий параметр — `DependencyModel.invalid`/`InvalidBinding`, поганий хендлер — `RouteModel.problem`. Діагностики (`Diagnostic(code, location, message)`, `toString()` = `path:line:col: error: message [code]`) з'являються лише в `validate` конструктів; `DartnestGenerator` дедуплікує й сортує їх (шлях, рядок, колонка, код); будь-яка діагностика → `GenerationResult.failed`, бібліотека не пишеться.
6. **Валідація графа модулів** (`ModuleConstruct`): спершу структура (`ModuleStructureCheck`: `duplicate_module_id`, `circular_module_import`, `duplicate_provider`, `invalid_export`, `invalid_module_entry`, `unsupported_constant`); лише в структурно чистому графі й без непрозорих модулів (OP3) — `DependencyCheck`: `missing_provider` для залежностей класів-провайдерів, контролерів і компонентів `Use<T>` (видимість як у ядра: власні провайдери, експорти імпортів з реекспортами, глобальні модулі) і `circular_dependency` (один раз на цикл). `ProviderConstruct`: `not_injectable`, `invalid_constructor`, `invalid_dependency`.
7. **Контролери** (`ControllerConstruct`): конструктор (як у провайдера), компоненти (`invalid_component`: тип не реалізує `Guard`/`Interceptor`/`Pipe`/`ExceptionFilter`), метадані (`unsupported_constant`), хендлери (`invalid_route_handler`: static, generic, кілька route-анотацій), параметри (`invalid_handler_parameter`, `missing_from_json`, OP9), `unknown_path_parameter` (`@Param('x')`, якого немає в шляху), `duplicate_route` у межах пакета з нормалізацією `:name` (`/j/:a` і `/j/:b` — дублікат). Прив'язки: `@Param`/`@Query` → `await ctx.param<T>('n')`/`await ctx.query<T?>('n')` (+ `pipes: const [dartnest.EnumPipe(T.values)]` для enum), `@Header` → `ctx.header('n')` (ненульовий: `?? (throw const dartnest.BadRequestException(message: 'Missing header "n".'))`), `@Body` → OP6, `ExecutionContext` → `ctx`, `HttpRequest` → `ctx.switchToHttp().request`. `void`-хендлер → блок `{ c.m(); return null; }` (ядро відповідає 204), `Future<void>` → `async`-блок з `await`.
8. **Метадані й компоненти**: `@UseGuards/@UseInterceptors/@UsePipes/@UseFilters([T])` на класі чи методі → `const dartnest.Enhancers(guards: [dartnest.Use<T>()])` (OP7); анотації-нащадки `RouteMetadata` → `metadata: const [...]` у тому ж порядку; `const` лише на верхньому рівні виразу (lint `unnecessary_const`).
9. **Непрозорі модулі** (OP3, OP5, OP12): у `imports`/`exports` дозволені `@Module`-класи пакета, `@Module`-класи інших пакетів (правило імен) і tear-off публічних top-level або static функцій без обов'язкових параметрів, що повертають `Module` ядра. Решта → `invalid_module_entry` з описом запису (`Annotations.describe`: ім'я типу чи функції, інакше `a value of type T`).
10. **Фікстури й обв'язка тестів**: `test/helpers/fixture_package.dart` (`FixturePackage.open(name)`, `libraries`, `collect`, `read`, `root`) резолвить пакет через `AnalysisContextCollection` один раз на тестовий файл (`setUpAll`). `cases_app` — малі бібліотеки, один сценарій на файл; `users_app` — застосунок e2e ядра в анотаціях, його `users_app.dartnest.dart` закомічено як golden, а `explicit.dart` — той самий граф явним API. Обидві фікстури — члени workspace (`publish_to: none`), бо резолвляться тим самим `package_config`, що й генератор.
11. **Модельні класи — декларативні значення**, як `Module` у `CLAUDE.md`: `ModuleModel`, `RouteModel`, `ControllerModel`, `DtoField` тощо мають > 5 іменованих полів без parameter object; Task 11 фіксує це в таблиці `CLAUDE.md`.
12. **Поза планом**: драйвери (CLI, `--watch`, build_runner — етапи 5, 6), hot reload (5b), запис файлів, `OpenApiConstruct` (v1.1; `DtoModel` і doc-коментарі вже в моделі), анотації `@Head`/`@Options`, користувацькі pipes на параметрах (OP9), перевірка графа крізь пакети (OP3, варіант C).

## Global Constraints

- Ядро `dartnest` не змінюється. `dartnest_annotations` не має залежностей (лише dev: `lints`, `test`). `analyzer`, `code_builder`, `dart_style` — лише в `dartnest_generator` (`CLAUDE.md`: «`analyzer` is allowed only in `dartnest_generator`/`dartnest_cli`»).
- Пакети: `version: 0.1.0-dev`, `publish_to: none`, `environment: sdk: ^3.8.0`, `resolution: workspace`; кожен новий пакет і фікстура додаються до `workspace:` кореневого `pubspec.yaml` у задачі, що їх створює (Tasks 1, 2, 3, 10).
- Залежності генератора: `analyzer: '>=8.1.1 <15.0.0'`, `code_builder: ^4.11.1`, `dart_style: ^3.1.2`, `path: ^1.9.0`, `pub_semver: ^2.1.4`; dev: `cases_app`, `dartnest` і `users_app` (Task 10), `lints: ^5.1.0`, `test: ^1.25.0`. Код не використовує API, якого немає в analyzer 8.1.1 або 14.x, і `declareFinal(name, type:)` (`code_builder` 4.11.1 губить у ньому аргументи типу).
- Згенерований код — звичайний код на публічному API `package:dartnest/dartnest.dart`: жодного `src/`-імпорту, жодних приватних імен користувача; він проходить `dart analyze` з lint'ами репозиторію (golden лежить у члені workspace і аналізується разом з усім).
- Кожен рядок з джерел користувача (id, шлях, ім'я, значення константи) потрапляє в згенерований код лише через `DartString.literal` (екранує `\`, `'`, `$`, керівні символи, `U+2028/2029`).
- Детермінізм: жодної ітерації по hash-порядку при виводі; модель і діагностики сортуються; зміна виводу — це зміна golden у тому ж коміті.
- `CLAUDE.md`: ≤ 300 рядків на файл у `lib/`, ≤ 500 на тестовий файл, ≤ 40 рядків на метод, ≤ 5 параметрів (крім модельних значень, рішення 11), ≤ 3 рівні вкладеності; один публічний клас або sealed-сімейство на файл; немає top-level функцій у `lib/src`; без `!`, `dynamic`, `late` без коментаря, `catch` без `on`; невикористаний параметр колбеку — `_`; dartdoc на кожному публічному члені.
- Публічний API, dartdoc, діагностики, README і повідомлення комітів — англійською.
- Перед кожним комітом: з кореня `dart analyze` — «No issues found!», `dart format --output=none --set-exit-if-changed packages` — 0 змінених файлів; `dart test` зелений у кожному пакеті, якого торкнулась задача.
- `dart` не завжди в `PATH`: `export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"`. Після зміни будь-якого `pubspec.yaml` — `dart pub get` з кореня.
- Відхилення від специфікації, зафіксовані планом: функції замість `final usersModule` (10.1); `TypeModel` замість `DartType` (OP11); `ctx.bodyAs(T.fromJson)` замість `T.fromJson(await ctx.body.json())` (OP6); `forRoot` лише як tear-off без аргументів (OP5); клас `PackageCollector` у ролі `Collector` з роадмапу; приватні фабрики провайдерів.

## Review Focus

1. Рядок користувача з `'`, `$`, `\`, переносом рядка чи `U+2028` у шляху роуту, `id` модуля чи значенні метаданих: згенерований код компілюється й містить рівно цей рядок, без інтерполяції. Закріплено в Task 6 (`user strings are escaped completely`, `// Review Focus 1`).
2. Драйвер передає бібліотеки в іншому порядку (файлова система, інкрементальний перерезолв): вихід байт-у-байт той самий. Закріплено в Task 10 (`the output does not depend on the order of libraries`, `// Review Focus 2`).
3. Метадані або токен через приватну константу чи приватний клас (`const _admin = Roles([...])`, `Token<_Port>`): приватна константа відтворюється викликом конструктора, приватний клас дає `unsupported_constant`, а не код, що не компілюється. Закріплено в Task 3 (`a private constant is rebuilt from its constructor call`, `a private class cannot be written in generated code`, `// Review Focus 3`).
4. Модуль, зібраний функцією (`imports: [explicitModule]`, `forRoot`), надає провайдер, якого генератор не бачить: жодного хибного `missing_provider`; перевірку робить `Application.create`. Закріплено в Task 8 (`a module built by a function turns the check off`, `// Review Focus 4`).
5. Два хендлери на `/users/:id` і `/users/:userId`: діагностика `duplicate_route` під час генерації, а не `RoutingError` на старті. Закріплено в Task 9 (`handlers, parameters, components and routes it rejects`, `// Review Focus 5`).

---

## File Structure

```
pubspec.yaml                                      # workspace: + annotations (T1), generator (T2), cases_app (T3), users_app (T10)
CLAUDE.md                                         # golden command, model values, fixtures, hide (T11)
docs/superpowers/ROADMAP.md                       # stage 4 row links this plan (T11)
packages/dartnest_annotations/                    # NEW, no dependencies (T1)
  pubspec.yaml, analysis_options.yaml, README.md (T11)
  lib/dartnest_annotations.dart                   # barrel
  lib/src/module.dart                             # @Module(id, imports, providers, controllers, exports, global)
  lib/src/injectable.dart, inject.dart            # @Injectable(), @Inject(token)
  lib/src/bind.dart, value.dart                   # Bind<K, I>(), Value(value, token:)
  lib/src/controller.dart                         # @Controller([path])
  lib/src/route_annotation.dart                   # sealed RouteAnnotation: Get, Post, Put, Patch, Delete
  lib/src/argument_annotation.dart                # sealed ArgumentAnnotation: Param, Query, Header, Body
  lib/src/use_components.dart                     # sealed UseComponents: UseGuards, UseInterceptors, UsePipes, UseFilters
  lib/src/route_metadata.dart                     # abstract RouteMetadata (user metadata base)
  test/annotations_test.dart
packages/dartnest_generator/                      # NEW (T2–T10)
  pubspec.yaml, analysis_options.yaml, README.md (T11)
  lib/dartnest_generator.dart                     # barrel: collector, constructs, model, diagnostics (T2, T6, T10)
  lib/src/diagnostic/                             # SourceLocation, DiagnosticCode (18 codes), Diagnostic (T2)
  lib/src/model/                                  # 21 model files + GeneratedNames (T2)
  lib/src/collector/                              # analyzer elements → model (T3 readers, T4 modules, T5 controllers)
    annotations.dart, type_reader.dart, source_locations.dart, constant_reader.dart, token_reader.dart   (T3)
    entry_read.dart, constructor_reader.dart, injectable_reader.dart, module_reference_reader.dart,
    provider_entry_reader.dart, module_reader.dart, package_collector.dart                              (T4, T5)
    body_kind_reader.dart, handler_parameter_reader.dart, enhancers_reader.dart, route_reader.dart,
    controller_reader.dart, dto_reader.dart                                                             (T5)
  lib/src/construct/                              # Construct, GeneratedUnit, GenerationResult, DartnestGenerator (T6, T10)
  lib/src/emit/                                   # model → code_builder (T6 base, T7 modules, T9 controllers)
    dart_string.dart, import_allocator.dart, type_emitter.dart, constant_emitter.dart, library_writer.dart (T6)
    injection_emitter.dart, module_emitter.dart                                                          (T7)
    argument_emitter.dart, enhancers_emitter.dart, route_emitter.dart, controller_emitter.dart           (T9)
  lib/src/constructs/                             # the v1 constructs and their checks
    constructor_check.dart, provider_construct.dart, module_structure_check.dart, module_construct.dart (T7, T8)
    module_scope.dart, dependency_check.dart                                                             (T8)
    controller_check.dart, controller_construct.dart                                                     (T9)
  test/helpers/fixture_package.dart               # FixturePackage: resolve a fixture like a driver (T3, T4)
  test/model/model_test.dart                      # T2
  test/collector/constant_reader_test.dart        # T3
  test/collector/module_collector_test.dart       # T4
  test/collector/controller_collector_test.dart   # T5
  test/emit/emit_test.dart                        # T6
  test/construct/dartnest_generator_test.dart     # T6
  test/constructs/module_construct_test.dart      # T7
  test/constructs/provider_construct_test.dart    # T7
  test/constructs/dependency_check_test.dart      # T8
  test/constructs/controller_construct_test.dart  # T9
  test/golden/golden_test.dart                    # T10
  test/e2e/users_app_e2e_test.dart                # T10: one suite on the explicit and the generated graph
  test/fixtures/cases_app/                        # scenario libraries (T3: constants; T4: modules/, providers/constructors;
                                                  #   T5: controllers/; T7: modules/structure_errors, providers/provider_module;
                                                  #   T8: dependencies/)
  test/fixtures/users_app/                        # T10: lib/src/{auth,users,greeting,modules}.dart, users_app.dart,
                                                  #   explicit.dart, users_app.dartnest.dart (golden)
```

Залежності задач: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11; кожна наступна використовує модель і читачі попередніх. Кількості тестів у кроках «Expected» — для пакета `dartnest_generator` наростаючим підсумком: T2 `+6`, T3 `+13`, T4 `+21`, T5 `+29`, T6 `+38`, T7 `+44`, T8 `+48`, T9 `+50`, T10 `+69`; `dartnest_annotations` — `+6`.


### Task 1: Пакет `dartnest_annotations`

Анотації, які пише користувач, — `const`-класи без поведінки й без залежностей. Генератор читає їх за іменем класу та бібліотекою (`package:dartnest_annotations/...`), тож пакет не імпортує ядро: `Token` у `@Inject(token)`/`Value(token:)` і компоненти в `@UseGuards` типізовані як `Object`/`Type`. Сімейства з однаковою роллю — sealed (`RouteAnnotation`, `ArgumentAnnotation`, `UseComponents`), щоб генератор і тести могли перебирати їх `switch`. `RouteMetadata` — `abstract` (не `sealed`): її розширює користувач (`class Roles extends RouteMetadata`).

Імена `Module` і `Controller` збігаються з класами ядра (OP2); dartdoc barrel пояснює `hide Controller, Module`.

**Files:**
- Create: `packages/dartnest_annotations/pubspec.yaml`
- Create: `packages/dartnest_annotations/analysis_options.yaml`
- Create: `packages/dartnest_annotations/lib/dartnest_annotations.dart`
- Create: `packages/dartnest_annotations/lib/src/module.dart`
- Create: `packages/dartnest_annotations/lib/src/injectable.dart`
- Create: `packages/dartnest_annotations/lib/src/inject.dart`
- Create: `packages/dartnest_annotations/lib/src/bind.dart`
- Create: `packages/dartnest_annotations/lib/src/value.dart`
- Create: `packages/dartnest_annotations/lib/src/controller.dart`
- Create: `packages/dartnest_annotations/lib/src/route_annotation.dart`
- Create: `packages/dartnest_annotations/lib/src/argument_annotation.dart`
- Create: `packages/dartnest_annotations/lib/src/use_components.dart`
- Create: `packages/dartnest_annotations/lib/src/route_metadata.dart`
- Modify: `pubspec.yaml`
- Test: `packages/dartnest_annotations/test/annotations_test.dart`

**Interfaces:**
- Consumes: нічого (пакет без залежностей).
- Produces (`package:dartnest_annotations/dartnest_annotations.dart`), які читає генератор (Tasks 3–9) і фікстури:
  - `final class Module { const Module({String? id, List<Object> imports = const [], List<Object> providers = const [], List<Type> controllers = const [], List<Object> exports = const [], bool global = false}); }`
  - `final class Injectable { const Injectable(); }`, `final class Inject { const Inject(Object token); final Object token; }`
  - `final class Bind<K extends Object, I extends K> { const Bind(); }`, `final class Value { const Value(Object value, {Object? token}); }`
  - `final class Controller { const Controller([String path = '']); final String path; }`
  - `sealed class RouteAnnotation { final String method; final String path; }`: `Get`, `Post`, `Put`, `Patch`, `Delete` (`const Get([String path = ''])`).
  - `sealed class ArgumentAnnotation`: `Param(String name)`, `Query(String name)`, `Header(String name)`, `Body()`.
  - `sealed class UseComponents { final List<Type> types; }`: `UseGuards`, `UseInterceptors`, `UsePipes`, `UseFilters`.
  - `abstract class RouteMetadata { const RouteMetadata(); }`.

- [ ] **Step 1: Scaffold the package and write the failing test**

Новий пакет і запис у `workspace:` кореневого `pubspec.yaml` (повний файл):

`packages/dartnest_annotations/pubspec.yaml`:

```yaml
name: dartnest_annotations
description: >-
  Annotations for dartnest applications; dartnest_generator turns them into
  the explicit dartnest API. No dependencies.
version: 0.1.0-dev
publish_to: none
environment:
  sdk: ^3.8.0
resolution: workspace
dev_dependencies:
  lints: ^5.1.0
  test: ^1.25.0
```

`packages/dartnest_annotations/analysis_options.yaml`:

```yaml
include: ../../analysis_options.yaml
```

`pubspec.yaml`:

```yaml
name: dartnest_workspace
publish_to: none
environment:
  sdk: ^3.8.0
workspace:
  - packages/dartnest
  - packages/dartnest_annotations
  - packages/dartnest_conformance
  - packages/dartnest_io
  - packages/dartnest_shelf
```

`packages/dartnest_annotations/test/annotations_test.dart`:

```dart
import 'package:dartnest_annotations/dartnest_annotations.dart';
import 'package:test/test.dart';

final class _Roles extends RouteMetadata {
  const _Roles(this.names);
  final List<String> names;
}

void main() {
  test('Module defaults to an empty, non-global module named by its class', () {
    const module = Module();

    expect(module.id, isNull);
    expect(module.imports, isEmpty);
    expect(module.providers, isEmpty);
    expect(module.controllers, isEmpty);
    expect(module.exports, isEmpty);
    expect(module.global, isFalse);
  });

  test('route annotations carry their HTTP method and path', () {
    const routes = <RouteAnnotation>[
      Get('/:id'),
      Post(),
      Put('/a'),
      Patch('/b'),
      Delete('/c'),
    ];

    expect(
      [for (final route in routes) '${route.method} ${route.path}'],
      ['GET /:id', 'POST ', 'PUT /a', 'PATCH /b', 'DELETE /c'],
    );
  });

  test('argument annotations name the request part', () {
    const arguments = <ArgumentAnnotation>[
      Param('id'),
      Query('limit'),
      Header('authorization'),
      Body(),
    ];

    final names = [
      for (final argument in arguments)
        switch (argument) {
          Param(:final name) => 'param $name',
          Query(:final name) => 'query $name',
          Header(:final name) => 'header $name',
          Body() => 'body',
        },
    ];
    expect(names, ['param id', 'query limit', 'header authorization', 'body']);
  });

  test('component annotations keep the types in order', () {
    const guards = UseGuards([int, String]);
    const filters = UseFilters([double]);

    expect(guards.types, [int, String]);
    expect(filters.types, [double]);
  });

  test('provider annotations hold their constants', () {
    const value = Value('postgres://localhost', token: #db);
    const inject = Inject(#db);

    expect(
      (value.value, value.token, inject.token),
      ('postgres://localhost', #db, #db),
    );
    expect(const Bind<Object, String>(), isA<Bind<Object, String>>());
  });

  test('Controller defaults to an empty path; RouteMetadata is const', () {
    expect(const Controller().path, '');
    expect(const Controller('/users').path, '/users');
    expect(const _Roles(['admin']).names, ['admin']);
  });
}
```

Run: `dart pub get`
Expected: `Got dependencies!` (з кореня репозиторію)

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/dartnest_annotations && dart test`
Expected: FAIL: компіляція — `package:dartnest_annotations/dartnest_annotations.dart` не існує

- [ ] **Step 3: Write the annotations**

Кожен клас — у власному файлі; barrel експортує всі.

`packages/dartnest_annotations/lib/dartnest_annotations.dart`:

```dart
/// Annotations for dartnest applications.
///
/// `dartnest_generator` reads them and writes ordinary code on the explicit
/// `package:dartnest` API into `lib/<package>.dartnest.dart`. The
/// annotations have no runtime behavior and this package has no
/// dependencies.
///
/// `Module` and `Controller` share their names with the explicit API; a
/// library that needs both imports `package:dartnest/dartnest.dart` with
/// `hide Controller, Module`.
library;

export 'src/argument_annotation.dart';
export 'src/bind.dart';
export 'src/controller.dart';
export 'src/inject.dart';
export 'src/injectable.dart';
export 'src/module.dart';
export 'src/route_annotation.dart';
export 'src/route_metadata.dart';
export 'src/use_components.dart';
export 'src/value.dart';
```

`packages/dartnest_annotations/lib/src/module.dart`:

```dart
/// Declares a module; the generator writes a function that returns the
/// explicit `Module` (`UsersModule` → `Module usersModule()`).
///
/// ```dart
/// @Module(
///   imports: [DatabaseModule],
///   providers: [UsersService, Bind<Clock, SystemClock>(), Value(appConfig)],
///   controllers: [UsersController],
///   exports: [UsersService],
/// )
/// class UsersModule {}
/// ```
///
/// [imports] takes classes annotated with [Module] and tear-offs of
/// functions that return an explicit `Module` and need no arguments
/// (`imports: [metricsModule]`); the generator calls them. [providers]
/// takes classes annotated with `Injectable`, [Bind] and [Value].
/// [exports] takes provider classes, `Token` constants, and imported
/// modules (re-export).
final class Module {
  /// Creates the annotation. [id] defaults to the class name.
  const Module({
    this.id,
    this.imports = const [],
    this.providers = const [],
    this.controllers = const [],
    this.exports = const [],
    this.global = false,
  });

  /// Module id; `null` means the class name.
  final String? id;

  /// Imported modules.
  final List<Object> imports;

  /// Providers declared by the module.
  final List<Object> providers;

  /// Classes annotated with `Controller`.
  final List<Type> controllers;

  /// What importers of the module can see.
  final List<Object> exports;

  /// Whether the exports are visible to every module.
  final bool global;
}
```

`packages/dartnest_annotations/lib/src/injectable.dart`:

```dart
/// Marks a class that dependency injection creates through its unnamed
/// constructor; list it in `Module.providers`.
///
/// Every constructor parameter is resolved by its type, or by the token of
/// its `Inject` annotation. Named parameters must be `required`.
///
/// ```dart
/// @Injectable()
/// class UsersService {
///   UsersService(this.repo, @Inject(dbUrl) this.url);
///   final UsersRepo repo;
///   final String url;
/// }
/// ```
final class Injectable {
  /// Creates the annotation.
  const Injectable();
}
```

`packages/dartnest_annotations/lib/src/inject.dart`:

```dart
/// Resolves a constructor parameter by a `Token` instead of its type.
///
/// ```dart
/// const dbUrl = Token<String>('db.url');
///
/// @Injectable()
/// class Db {
///   Db(@Inject(dbUrl) this.url);
///   final String url;
/// }
/// ```
final class Inject {
  /// Creates the annotation for [token], a `Token` constant.
  const Inject(this.token);

  /// The `Token` to resolve.
  final Object token;
}
```

`packages/dartnest_annotations/lib/src/bind.dart`:

```dart
/// A provider for the key [K] created by the `Injectable` class [I].
///
/// ```dart
/// @Module(providers: [Bind<Clock, SystemClock>()])
/// class TimeModule {}
/// ```
final class Bind<K extends Object, I extends K> {
  /// Creates the binding.
  const Bind();
}
```

`packages/dartnest_annotations/lib/src/value.dart`:

```dart
/// A provider for an already built constant [value], keyed by its static
/// type or by [token].
///
/// ```dart
/// const dbUrl = Token<String>('db.url');
///
/// @Module(providers: [Value('postgres://localhost/app', token: dbUrl)])
/// class DatabaseModule {}
/// ```
final class Value {
  /// Creates the provider.
  const Value(this.value, {this.token});

  /// The provided constant.
  final Object value;

  /// The `Token` to provide [value] under; `null` keys it by its type.
  final Object? token;
}
```

`packages/dartnest_annotations/lib/src/controller.dart`:

```dart
/// Declares a controller; the generator writes a function that returns the
/// explicit `Controller` (`UsersController` → `usersController()`).
///
/// The instance is created through the unnamed constructor with the same
/// rules as an `Injectable`. Methods annotated with `Get`, `Post`, `Put`,
/// `Patch` or `Delete` become routes.
///
/// ```dart
/// @Controller('/users')
/// class UsersController {
///   UsersController(this.service);
///   final UsersService service;
///
///   @Get('/:id')
///   User findOne(@Param('id') int id) => service.find(id);
/// }
/// ```
final class Controller {
  /// Creates the annotation with the path prefix of every route.
  const Controller([this.path = '']);

  /// Path prefix of every route.
  final String path;
}
```

`packages/dartnest_annotations/lib/src/route_annotation.dart`:

```dart
/// Makes a controller method an HTTP route.
///
/// [path] is relative to the controller path and may contain `:name`
/// parameters and a trailing `*`, as in the explicit `Route`.
sealed class RouteAnnotation {
  /// Creates the annotation for [method] and [path].
  const RouteAnnotation(this.method, this.path);

  /// The upper-cased HTTP method.
  final String method;

  /// Path relative to the controller path.
  final String path;
}

/// A `GET` route.
final class Get extends RouteAnnotation {
  /// Creates the annotation.
  const Get([String path = '']) : super('GET', path);
}

/// A `POST` route.
final class Post extends RouteAnnotation {
  /// Creates the annotation.
  const Post([String path = '']) : super('POST', path);
}

/// A `PUT` route.
final class Put extends RouteAnnotation {
  /// Creates the annotation.
  const Put([String path = '']) : super('PUT', path);
}

/// A `PATCH` route.
final class Patch extends RouteAnnotation {
  /// Creates the annotation.
  const Patch([String path = '']) : super('PATCH', path);
}

/// A `DELETE` route.
final class Delete extends RouteAnnotation {
  /// Creates the annotation.
  const Delete([String path = '']) : super('DELETE', path);
}
```

`packages/dartnest_annotations/lib/src/argument_annotation.dart`:

```dart
/// Binds a handler parameter to a part of the request.
///
/// A parameter without one of these annotations must have the type
/// `ExecutionContext` or `HttpRequest`.
sealed class ArgumentAnnotation {
  /// Creates the annotation.
  const ArgumentAnnotation();
}

/// The path parameter [name] (`:name` in the route path), converted to the
/// parameter type like `ExecutionContext.param`.
final class Param extends ArgumentAnnotation {
  /// Creates the annotation.
  const Param(this.name);

  /// The path parameter name, without the colon.
  final String name;
}

/// The query parameter [name], converted like `ExecutionContext.query`; a
/// nullable parameter type makes it optional.
final class Query extends ArgumentAnnotation {
  /// Creates the annotation.
  const Query(this.name);

  /// The query parameter name.
  final String name;
}

/// The request header [name]; the parameter type is `String` (a missing
/// header is a 400) or `String?`.
final class Header extends ArgumentAnnotation {
  /// Creates the annotation.
  const Header(this.name);

  /// The header name (case-insensitive).
  final String name;
}

/// The request body: `T.fromJson` when the type has a `fromJson` factory or
/// static method taking a JSON map, otherwise a `Map<String, Object?>`,
/// `String` or `List<int>` directly.
final class Body extends ArgumentAnnotation {
  /// Creates the annotation.
  const Body();
}
```

`packages/dartnest_annotations/lib/src/use_components.dart`:

```dart
/// Attaches pipeline components to a controller or a route; each type is
/// resolved through dependency injection (`Use<T>()` in the explicit API),
/// so it must be a provider visible in the controller's module.
sealed class UseComponents {
  /// Creates the annotation for [types].
  const UseComponents(this.types);

  /// The component classes, in order.
  final List<Type> types;
}

/// Guards; each type implements `Guard`.
final class UseGuards extends UseComponents {
  /// Creates the annotation.
  const UseGuards(super.types);
}

/// Interceptors; each type implements `Interceptor`.
final class UseInterceptors extends UseComponents {
  /// Creates the annotation.
  const UseInterceptors(super.types);
}

/// Pipes; each type implements `Pipe`.
final class UsePipes extends UseComponents {
  /// Creates the annotation.
  const UsePipes(super.types);
}

/// Exception filters; each type extends `ExceptionFilter`.
final class UseFilters extends UseComponents {
  /// Creates the annotation.
  const UseFilters(super.types);
}
```

`packages/dartnest_annotations/lib/src/route_metadata.dart`:

```dart
/// Base class of user metadata attached to a controller or a route and read
/// with `ExecutionContext.metadata<T>()`; route metadata overrides
/// controller metadata.
///
/// The generator copies the annotation into the explicit `metadata` list,
/// so a subclass needs a `const` constructor whose parameters initialize
/// fields of the same name (`this.names` or `super.x`).
///
/// ```dart
/// final class Roles extends RouteMetadata {
///   const Roles(this.names);
///   final List<String> names;
/// }
///
/// @Post()
/// @Roles(['admin'])
/// User create(@Body() CreateUserDto dto) => ...;
/// ```
abstract class RouteMetadata {
  /// Creates the metadata.
  const RouteMetadata();
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/dartnest_annotations && dart test`
Expected: `+6: All tests passed!`

- [ ] **Step 5: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 6: Commit**

```bash
git add \
  packages/dartnest_annotations/pubspec.yaml \
  packages/dartnest_annotations/analysis_options.yaml \
  pubspec.yaml \
  packages/dartnest_annotations/test/annotations_test.dart \
  packages/dartnest_annotations/lib/dartnest_annotations.dart \
  packages/dartnest_annotations/lib/src/module.dart \
  packages/dartnest_annotations/lib/src/injectable.dart \
  packages/dartnest_annotations/lib/src/inject.dart \
  packages/dartnest_annotations/lib/src/bind.dart \
  packages/dartnest_annotations/lib/src/value.dart \
  packages/dartnest_annotations/lib/src/controller.dart \
  packages/dartnest_annotations/lib/src/route_annotation.dart \
  packages/dartnest_annotations/lib/src/argument_annotation.dart \
  packages/dartnest_annotations/lib/src/use_components.dart \
  packages/dartnest_annotations/lib/src/route_metadata.dart
git commit -m "feat(annotations): add dartnest_annotations package"
```

### Task 2: Каркас `dartnest_generator`: діагностики й модель пакета

Модель — незмінні значення без типів analyzer (рішення 4, OP11), тож її тестують без резолву: `model_test.dart` будує значення вручну. `TypeModel` порівнюється за бібліотекою, ім'ям, аргументами й nullability (ключ провайдера); `TokenKey` — за типом значення й іменем константи; `RouteModel.pathParameters` — імена `:name` у порядку шляху; `Diagnostic` сортується за шляхом, рядком, колонкою, кодом і має `==`/`hashCode` (дедуплікація в Task 6). `GeneratedNames` — єдине місце правил імен (рішення 2).

Модель — flat-каталог декларативних значень: класи з > 5 іменованими полями (`ModuleModel`, `RouteModel`, …) — свідомий виняток із правила параметрів, як `Module` (рішення 11).

`pubspec.yaml` генератора одразу містить усі runtime-залежності етапу; dev-залежності `cases_app` (Task 3), `dartnest` і `users_app` (Task 10) додаються пізніше.

**Files:**
- Create: `packages/dartnest_generator/pubspec.yaml`
- Create: `packages/dartnest_generator/analysis_options.yaml`
- Create: `packages/dartnest_generator/lib/src/diagnostic/source_location.dart`
- Create: `packages/dartnest_generator/lib/src/diagnostic/diagnostic_code.dart`
- Create: `packages/dartnest_generator/lib/src/diagnostic/diagnostic.dart`
- Create: `packages/dartnest_generator/lib/src/model/type_kind.dart`
- Create: `packages/dartnest_generator/lib/src/model/type_model.dart`
- Create: `packages/dartnest_generator/lib/src/model/constant_value.dart`
- Create: `packages/dartnest_generator/lib/src/model/provider_key.dart`
- Create: `packages/dartnest_generator/lib/src/model/module_reference.dart`
- Create: `packages/dartnest_generator/lib/src/model/module_export.dart`
- Create: `packages/dartnest_generator/lib/src/model/dependency_model.dart`
- Create: `packages/dartnest_generator/lib/src/model/constructor_model.dart`
- Create: `packages/dartnest_generator/lib/src/model/injectable_model.dart`
- Create: `packages/dartnest_generator/lib/src/model/provider_model.dart`
- Create: `packages/dartnest_generator/lib/src/model/module_model.dart`
- Create: `packages/dartnest_generator/lib/src/model/body_kind.dart`
- Create: `packages/dartnest_generator/lib/src/model/parameter_binding.dart`
- Create: `packages/dartnest_generator/lib/src/model/handler_parameter.dart`
- Create: `packages/dartnest_generator/lib/src/model/component_reference.dart`
- Create: `packages/dartnest_generator/lib/src/model/enhancers_model.dart`
- Create: `packages/dartnest_generator/lib/src/model/route_model.dart`
- Create: `packages/dartnest_generator/lib/src/model/controller_model.dart`
- Create: `packages/dartnest_generator/lib/src/model/dto_field.dart`
- Create: `packages/dartnest_generator/lib/src/model/dto_model.dart`
- Create: `packages/dartnest_generator/lib/src/model/package_model.dart`
- Create: `packages/dartnest_generator/lib/src/model/generated_names.dart`
- Create: `packages/dartnest_generator/lib/dartnest_generator.dart`
- Modify: `pubspec.yaml`
- Test: `packages/dartnest_generator/test/model/model_test.dart`

**Interfaces:**
- Consumes: нічого з попередніх задач у коді (анотації читаються за іменами в Task 3).
- Produces (усе в `packages/dartnest_generator/lib/src/`):
  - `diagnostic/source_location.dart`: `final class SourceLocation implements Comparable<SourceLocation> { const SourceLocation(String path, int line, int column); String toString() => '$path:$line:$column'; }`
  - `diagnostic/diagnostic_code.dart`: `enum DiagnosticCode { duplicateModuleId, circularModuleImport, duplicateProvider, invalidExport, invalidModuleEntry, missingProvider, circularDependency, notInjectable, invalidConstructor, invalidDependency, invalidComponent, unsupportedConstant, invalidRouteHandler, invalidHandlerParameter, missingFromJson, unknownPathParameter, duplicateRoute, duplicateGeneratedName; final String id; }` (`id` — snake_case)
  - `diagnostic/diagnostic.dart`: `final class Diagnostic implements Comparable<Diagnostic> { const Diagnostic(DiagnosticCode code, SourceLocation location, String message); String toString() => '$location: error: $message [${code.id}]'; }` з `==`/`hashCode`
  - `model/type_model.dart`: `TypeModel({required String name, required TypeKind kind, String? libraryUri, List<TypeModel> typeArguments = const [], bool isNullable = false})`, `display`, `nonNullable`, `isDeclaredAs(name, libraryUri)`, `static const voidType`; `model/type_kind.dart`: `enum TypeKind`
  - `model/constant_value.dart`: sealed `ConstantValue` (рішення 4); `model/provider_key.dart`: sealed `ProviderKey` (`TypeKey(TypeModel)`, `TokenKey({valueType, name, expression})`, `display`, `valueType`)
  - `model/module_reference.dart` (`LocalModuleReference(TypeModel)`, `OpaqueModuleReference({name, libraryUri, enclosingName})`), `model/module_export.dart` (`KeyExport(ProviderKey)`, `ModuleReexport(ModuleReference)`), `model/provider_model.dart` (`ClassProvider(key, InjectableModel)`, `ValueProvider(key, ConstantValue)`)
  - `model/dependency_model.dart` (`DependencyModel.injected({name, isNamed, location, key})`, `.invalid({name, isNamed, location, problem})`), `model/constructor_model.dart` (`ConstructorModel(List<DependencyModel>)`, `.invalid(String problem)`), `model/injectable_model.dart` (`{type, isAnnotated, constructor, location, documentation}`)
  - `model/module_model.dart` (`{type, id, location, imports, providers, controllers, exports, isGlobal, invalidEntries, documentation}`)
  - `model/parameter_binding.dart` (sealed: `PathBinding`, `QueryBinding`, `HeaderBinding`, `BodyBinding(BodyKind)`, `ContextBinding`, `RequestBinding`, `InvalidBinding(problem)`), `model/body_kind.dart`, `model/handler_parameter.dart`, `model/component_reference.dart`, `model/enhancers_model.dart`, `model/route_model.dart` (`pathParameters`, `problem`), `model/controller_model.dart`, `model/dto_field.dart`, `model/dto_model.dart`
  - `model/package_model.dart`: `PackageModel({required String packageName, required Version languageVersion, List<ModuleModel> modules, List<InjectableModel> injectables, List<ControllerModel> controllers, List<DtoModel> dtos})`
  - `model/generated_names.dart`: `GeneratedNames.module/controller/factory/library(String)`

- [ ] **Step 1: Scaffold the package and write the failing test**

Пакет, `analysis_options.yaml` (той самий, що в інших пакетах) і новий член workspace:

`packages/dartnest_generator/pubspec.yaml`:

```yaml
name: dartnest_generator
description: >-
  Turns dartnest annotations into ordinary code on the explicit dartnest API,
  with static validation of the module graph.
version: 0.1.0-dev
publish_to: none
environment:
  sdk: ^3.8.0
resolution: workspace
dependencies:
  analyzer: '>=8.1.1 <15.0.0'
  code_builder: ^4.11.1
  dart_style: ^3.1.2
  path: ^1.9.0
  pub_semver: ^2.1.4
dev_dependencies:
  lints: ^5.1.0
  test: ^1.25.0
```

`packages/dartnest_generator/analysis_options.yaml`:

```yaml
include: ../../analysis_options.yaml
```

`pubspec.yaml`:

```yaml
name: dartnest_workspace
publish_to: none
environment:
  sdk: ^3.8.0
workspace:
  - packages/dartnest
  - packages/dartnest_annotations
  - packages/dartnest_conformance
  - packages/dartnest_generator
  - packages/dartnest_io
  - packages/dartnest_shelf
```

`packages/dartnest_generator/test/model/model_test.dart`:

```dart
import 'package:dartnest_generator/src/diagnostic/diagnostic.dart';
import 'package:dartnest_generator/src/diagnostic/diagnostic_code.dart';
import 'package:dartnest_generator/src/diagnostic/source_location.dart';
import 'package:dartnest_generator/src/model/constant_value.dart';
import 'package:dartnest_generator/src/model/generated_names.dart';
import 'package:dartnest_generator/src/model/provider_key.dart';
import 'package:dartnest_generator/src/model/route_model.dart';
import 'package:dartnest_generator/src/model/type_kind.dart';
import 'package:dartnest_generator/src/model/type_model.dart';
import 'package:test/test.dart';

const _users = 'package:app/users.dart';

TypeModel _type(
  String name, {
  bool nullable = false,
  List<TypeModel> args = const [],
}) => TypeModel(
  name: name,
  kind: TypeKind.interface,
  libraryUri: _users,
  typeArguments: args,
  isNullable: nullable,
);

void main() {
  test('a diagnostic prints as path:line:col: error: message [code]', () {
    final diagnostic = Diagnostic(
      DiagnosticCode.missingProvider,
      const SourceLocation('lib/users.dart', 3, 7),
      'No provider for Repo in module "users".',
    );

    expect(
      '$diagnostic',
      'lib/users.dart:3:7: error: No provider for Repo in module "users". '
          '[missing_provider]',
    );
  });

  test('diagnostics sort by path, line, column, then code', () {
    Diagnostic at(String path, int line, int column, DiagnosticCode code) =>
        Diagnostic(code, SourceLocation(path, line, column), 'm');
    final sorted = [
      at('lib/b.dart', 1, 1, DiagnosticCode.duplicateRoute),
      at('lib/a.dart', 9, 1, DiagnosticCode.duplicateRoute),
      at('lib/a.dart', 2, 5, DiagnosticCode.notInjectable),
      at('lib/a.dart', 2, 5, DiagnosticCode.missingProvider),
      at('lib/a.dart', 2, 1, DiagnosticCode.duplicateRoute),
    ]..sort();

    expect(
      [for (final d in sorted) '${d.location} ${d.code.id}'],
      [
        'lib/a.dart:2:1 duplicate_route',
        'lib/a.dart:2:5 missing_provider',
        'lib/a.dart:2:5 not_injectable',
        'lib/a.dart:9:1 duplicate_route',
        'lib/b.dart:1:1 duplicate_route',
      ],
    );
  });

  test('type models compare by library, name, arguments and nullability', () {
    final list = _type('List', args: [_type('User')]);

    expect(list, _type('List', args: [_type('User')]));
    expect(list.display, 'List<User>');
    expect(_type('User', nullable: true).display, 'User?');
    expect(_type('User', nullable: true).nonNullable, _type('User'));
    expect(_type('User'), isNot(_type('User', nullable: true)));
    expect(_type('User').isDeclaredAs('User', _users), isTrue);
  });

  test('provider keys: a type, or a token by value type and name', () {
    TokenKey token(String name, String expression) => TokenKey(
      valueType: _type('String'),
      name: name,
      expression: StringConstant(expression),
    );

    expect(TypeKey(_type('Repo')), TypeKey(_type('Repo')));
    expect(token('db.url', 'a'), token('db.url', 'b'));
    expect(token('db.url', 'a'), isNot(token('db.host', 'a')));
    expect(token('db.url', 'a').display, 'Token<String>(db.url)');
    expect(TypeKey(_type('Repo')).display, 'Repo');
  });

  test('route path parameters in declaration order', () {
    final route = RouteModel(
      method: 'GET',
      path: '/:org/users/:id/*',
      handlerName: 'find',
      returnType: TypeModel.voidType,
      location: const SourceLocation('lib/a.dart', 1, 1),
    );

    expect(route.pathParameters, ['org', 'id', '*']);
  });

  test('generated names derive from class names', () {
    expect(GeneratedNames.module('UsersModule'), 'usersModule');
    expect(GeneratedNames.module('Config'), 'configModule');
    expect(GeneratedNames.controller('UsersController'), 'usersController');
    expect(GeneratedNames.controller('Health'), 'healthController');
    expect(GeneratedNames.factory('UsersService'), '_createUsersService');
    expect(GeneratedNames.library('shop'), 'package:shop/shop.dartnest.dart');
  });
}
```

Run: `dart pub get`
Expected: `Got dependencies!` (з кореня репозиторію)

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/dartnest_generator && dart test test/model/model_test.dart`
Expected: FAIL: компіляція — `lib/src/diagnostic/…` і `lib/src/model/…` не існують

- [ ] **Step 3: Write the diagnostics**

`packages/dartnest_generator/lib/src/diagnostic/source_location.dart`:

```dart
/// A position in a source file, printed as `path:line:column`.
///
/// [path] is relative to the package root (`lib/users.dart`) for files of
/// the generated package, and the library URI for anything else.
final class SourceLocation implements Comparable<SourceLocation> {
  /// Creates a location; [line] and [column] start at 1.
  const SourceLocation(this.path, this.line, this.column);

  /// File path relative to the package root, or a library URI.
  final String path;

  /// One-based line.
  final int line;

  /// One-based column.
  final int column;

  @override
  int compareTo(SourceLocation other) {
    final byPath = path.compareTo(other.path);
    if (byPath != 0) return byPath;
    final byLine = line.compareTo(other.line);
    return byLine != 0 ? byLine : column.compareTo(other.column);
  }

  @override
  bool operator ==(Object other) =>
      other is SourceLocation &&
      other.path == path &&
      other.line == line &&
      other.column == column;

  @override
  int get hashCode => Object.hash(path, line, column);

  @override
  String toString() => '$path:$line:$column';
}
```

`packages/dartnest_generator/lib/src/diagnostic/diagnostic_code.dart`:

```dart
/// Every problem the generator reports, with a stable [id] that tools and
/// tests may rely on.
///
/// A flat catalog without logic. Renaming a Dart identifier here is fine;
/// changing an [id] is a breaking change.
enum DiagnosticCode {
  /// Two modules of the package have the same id.
  duplicateModuleId('duplicate_module_id'),

  /// Modules import each other in a cycle.
  circularModuleImport('circular_module_import'),

  /// A module declares the same provider key twice.
  duplicateProvider('duplicate_provider'),

  /// A module exports a key it does not provide or a module it does not
  /// import.
  invalidExport('invalid_export'),

  /// An entry of `@Module` the generator cannot use.
  invalidModuleEntry('invalid_module_entry'),

  /// A dependency is not visible in the module that needs it.
  missingProvider('missing_provider'),

  /// Providers depend on each other in a cycle.
  circularDependency('circular_dependency'),

  /// A class provider is not annotated with `@Injectable()`.
  notInjectable('not_injectable'),

  /// A provider or controller class cannot be created through its unnamed
  /// constructor.
  invalidConstructor('invalid_constructor'),

  /// A constructor parameter cannot be injected.
  invalidDependency('invalid_dependency'),

  /// A `@UseGuards`, `@UseInterceptors`, `@UsePipes` or `@UseFilters` type
  /// is not a component of that kind.
  invalidComponent('invalid_component'),

  /// A constant (metadata, `Value`, token) cannot be written as Dart code.
  unsupportedConstant('unsupported_constant'),

  /// A route annotation is on a method that cannot handle requests.
  invalidRouteHandler('invalid_route_handler'),

  /// A handler parameter cannot be bound to the request.
  invalidHandlerParameter('invalid_handler_parameter'),

  /// A `@Body()` type has no `fromJson` and is not read directly.
  missingFromJson('missing_from_json'),

  /// A `@Param` name is not a parameter of the route path.
  unknownPathParameter('unknown_path_parameter'),

  /// Two routes have the same method and path.
  duplicateRoute('duplicate_route'),

  /// Two generated declarations would have the same name.
  duplicateGeneratedName('duplicate_generated_name');

  const DiagnosticCode(this.id);

  /// The stable identifier printed with the message.
  final String id;
}
```

`packages/dartnest_generator/lib/src/diagnostic/diagnostic.dart`:

```dart
import 'diagnostic_code.dart';
import 'source_location.dart';

/// A problem found in the annotated sources; generation does not write
/// code while any diagnostic exists.
///
/// Printed as `path:line:column: error: message [code]`.
final class Diagnostic implements Comparable<Diagnostic> {
  /// Creates a diagnostic.
  const Diagnostic(this.code, this.location, this.message);

  /// What kind of problem this is.
  final DiagnosticCode code;

  /// Where the problem is.
  final SourceLocation location;

  /// One or more sentences describing the problem and its fix.
  final String message;

  /// Orders by location, then by code and message, so output is stable.
  @override
  int compareTo(Diagnostic other) {
    final byLocation = location.compareTo(other.location);
    if (byLocation != 0) return byLocation;
    final byCode = code.id.compareTo(other.code.id);
    return byCode != 0 ? byCode : message.compareTo(other.message);
  }

  @override
  bool operator ==(Object other) =>
      other is Diagnostic &&
      other.code == code &&
      other.location == location &&
      other.message == message;

  @override
  int get hashCode => Object.hash(code, location, message);

  @override
  String toString() => '$location: error: $message [${code.id}]';
}
```

- [ ] **Step 4: Write the model**

Кожен файл — один клас або одне sealed-сімейство.

`packages/dartnest_generator/lib/src/model/type_kind.dart`:

```dart
/// What kind of Dart type a `TypeModel` describes.
enum TypeKind {
  /// A class, mixin or other interface type.
  interface,

  /// An enum type.
  enumeration,

  /// `void`.
  voidType,

  /// `dynamic`.
  dynamicType,

  /// A function, record, type parameter or other type the generator does
  /// not reference by name.
  unsupported,
}
```

`packages/dartnest_generator/lib/src/model/type_model.dart`:

```dart
import 'type_kind.dart';

/// A Dart type as the generator needs it: enough to emit a reference to it
/// and to compare it with other types, without analyzer objects.
final class TypeModel {
  /// Creates the description of a named type.
  const TypeModel({
    required this.name,
    required this.kind,
    this.libraryUri,
    this.typeArguments = const [],
    this.isNullable = false,
  });

  /// The `void` type.
  static const voidType = TypeModel(name: 'void', kind: TypeKind.voidType);

  /// The class or enum name; the display string for [TypeKind.unsupported].
  final String name;

  /// What kind of type this is.
  final TypeKind kind;

  /// URI of the declaring library (`dart:core`, `package:a/a.dart`);
  /// `null` for `void`, `dynamic` and unsupported types.
  final String? libraryUri;

  /// Type arguments, in order.
  final List<TypeModel> typeArguments;

  /// Whether the type is nullable (`String?`).
  final bool isNullable;

  /// The type as written in Dart, for messages: `List<int>?`.
  String get display {
    final arguments = typeArguments.isEmpty
        ? ''
        : '<${typeArguments.map((t) => t.display).join(', ')}>';
    return '$name$arguments${isNullable ? '?' : ''}';
  }

  /// The same type without `?`.
  TypeModel get nonNullable => TypeModel(
    name: name,
    kind: kind,
    libraryUri: libraryUri,
    typeArguments: typeArguments,
  );

  /// Whether this is the type [name] declared in [libraryUri], ignoring
  /// type arguments and nullability.
  bool isDeclaredAs(String name, String libraryUri) =>
      this.name == name && this.libraryUri == libraryUri;

  String get _identity =>
      '$libraryUri#$name<${typeArguments.map((t) => t._identity).join(',')}>'
      '${isNullable ? '?' : ''}';

  @override
  bool operator ==(Object other) =>
      other is TypeModel && other._identity == _identity;

  @override
  int get hashCode => _identity.hashCode;

  @override
  String toString() => display;
}
```

`packages/dartnest_generator/lib/src/model/constant_value.dart`:

```dart
import 'type_model.dart';

/// A compile-time constant read from an annotation, in a form the
/// generator can write back as Dart code.
sealed class ConstantValue {
  /// Creates the value.
  const ConstantValue();

  /// The first part of this value that cannot be written as code, or
  /// `null` when all of it can.
  UnsupportedConstant? get unsupported => switch (this) {
    final UnsupportedConstant self => self,
    ListConstant(:final elements) ||
    SetConstant(:final elements) => _firstUnsupported(elements),
    MapConstant(:final entries) => _firstUnsupported([
      for (final (key, value) in entries) ...[key, value],
    ]),
    ObjectConstant(:final positional, :final named) => _firstUnsupported([
      ...positional,
      ...named.values,
    ]),
    _ => null,
  };

  static UnsupportedConstant? _firstUnsupported(List<ConstantValue> values) {
    for (final value in values) {
      if (value.unsupported case final found?) return found;
    }
    return null;
  }
}

/// `null`.
final class NullConstant extends ConstantValue {
  /// Creates the value.
  const NullConstant();
}

/// `true` or `false`.
final class BoolConstant extends ConstantValue {
  /// Creates the value.
  const BoolConstant(this.value);

  /// The value.
  final bool value;
}

/// An `int` or `double`, kept as its Dart literal.
final class NumberConstant extends ConstantValue {
  /// Creates the value from its literal, for example `42` or `0.5`.
  const NumberConstant(this.literal);

  /// The Dart literal.
  final String literal;
}

/// A `String`.
final class StringConstant extends ConstantValue {
  /// Creates the value.
  const StringConstant(this.value);

  /// The string, unescaped.
  final String value;
}

/// A list literal.
final class ListConstant extends ConstantValue {
  /// Creates the value.
  const ListConstant(this.elementType, this.elements);

  /// The element type argument.
  final TypeModel elementType;

  /// The elements.
  final List<ConstantValue> elements;
}

/// A set literal.
final class SetConstant extends ConstantValue {
  /// Creates the value.
  const SetConstant(this.elementType, this.elements);

  /// The element type argument.
  final TypeModel elementType;

  /// The elements.
  final List<ConstantValue> elements;
}

/// A map literal.
final class MapConstant extends ConstantValue {
  /// Creates the value.
  const MapConstant(this.keyType, this.valueType, this.entries);

  /// The key type argument.
  final TypeModel keyType;

  /// The value type argument.
  final TypeModel valueType;

  /// The entries, in order.
  final List<(ConstantValue, ConstantValue)> entries;
}

/// A type literal such as `UsersService`.
final class TypeConstant extends ConstantValue {
  /// Creates the value.
  const TypeConstant(this.type);

  /// The type.
  final TypeModel type;
}

/// A named constant: a top-level `const`, a static `const` field or an
/// enum value.
final class ReferenceConstant extends ConstantValue {
  /// Creates the reference.
  const ReferenceConstant({
    required this.name,
    required this.libraryUri,
    this.enclosingName,
  });

  /// The variable name.
  final String name;

  /// URI of the declaring library.
  final String libraryUri;

  /// The class or enum that declares a static field; `null` for top-level.
  final String? enclosingName;
}

/// A `const` constructor call.
final class ObjectConstant extends ConstantValue {
  /// Creates the value.
  const ObjectConstant({
    required this.type,
    required this.constructorName,
    this.positional = const [],
    this.named = const {},
  });

  /// The created type, with its type arguments.
  final TypeModel type;

  /// The constructor name; empty for the unnamed constructor.
  final String constructorName;

  /// Positional arguments.
  final List<ConstantValue> positional;

  /// Named arguments, in source order.
  final Map<String, ConstantValue> named;
}

/// A constant the generator cannot write as code.
final class UnsupportedConstant extends ConstantValue {
  /// Creates the value with the reason.
  const UnsupportedConstant(this.reason);

  /// Why the constant cannot be written, as a sentence fragment.
  final String reason;
}
```

`packages/dartnest_generator/lib/src/model/provider_key.dart`:

```dart
import 'constant_value.dart';
import 'type_model.dart';

/// What a provider is looked up by: a type or a `Token`.
sealed class ProviderKey {
  /// Creates the key.
  const ProviderKey();

  /// The key as dartnest prints it: `UsersService` or
  /// `Token<String>(db.url)`.
  String get display;

  @override
  bool operator ==(Object other) =>
      other is ProviderKey &&
      other.runtimeType == runtimeType &&
      other._identity == _identity;

  @override
  int get hashCode => _identity.hashCode;

  Object get _identity;

  @override
  String toString() => display;
}

/// A provider keyed by its [type].
final class TypeKey extends ProviderKey {
  /// Creates the key.
  const TypeKey(this.type);

  /// The provided type.
  final TypeModel type;

  @override
  String get display => type.display;

  @override
  Object get _identity => type;
}

/// A provider keyed by a `Token<T>`; tokens are equal by [valueType] and
/// [name], like `Token` itself.
final class TokenKey extends ProviderKey {
  /// Creates the key.
  const TokenKey({
    required this.valueType,
    required this.name,
    required this.expression,
  });

  /// The `T` of `Token<T>`.
  final TypeModel valueType;

  /// The token name.
  final String name;

  /// How to write the token in code (a reference or a `Token(...)` call).
  final ConstantValue expression;

  @override
  String get display => 'Token<${valueType.display}>($name)';

  @override
  Object get _identity => (valueType, name);
}
```

`packages/dartnest_generator/lib/src/model/module_reference.dart`:

```dart
import 'type_model.dart';

/// A module listed in `@Module(imports: ...)` or re-exported.
sealed class ModuleReference {
  /// Creates the reference.
  const ModuleReference();

  /// The reference as written in the annotation, for messages.
  String get display;
}

/// A class annotated with `@Module` in the generated package.
final class LocalModuleReference extends ModuleReference {
  /// Creates the reference.
  const LocalModuleReference(this.type);

  /// The module class.
  final TypeModel type;

  @override
  String get display => type.display;

  @override
  bool operator ==(Object other) =>
      other is LocalModuleReference && other.type == type;

  @override
  int get hashCode => type.hashCode;
}

/// A module the generator cannot see into: a class annotated with
/// `@Module` in another package (its generated function), or a function
/// that returns an explicit `Module`. The graph check is partial for it;
/// the core checks the rest at startup.
final class OpaqueModuleReference extends ModuleReference {
  /// Creates the reference to the function [name] of [libraryUri],
  /// declared in [enclosingName] when it is a static method.
  const OpaqueModuleReference({
    required this.name,
    required this.libraryUri,
    this.enclosingName,
  });

  /// The function name.
  final String name;

  /// URI of the library that declares the function.
  final String libraryUri;

  /// The class that declares a static method; `null` for a top-level
  /// function.
  final String? enclosingName;

  @override
  String get display => enclosingName == null ? name : '$enclosingName.$name';

  @override
  bool operator ==(Object other) =>
      other is OpaqueModuleReference &&
      other.name == name &&
      other.libraryUri == libraryUri &&
      other.enclosingName == enclosingName;

  @override
  int get hashCode => Object.hash(name, libraryUri, enclosingName);
}
```

`packages/dartnest_generator/lib/src/model/module_export.dart`:

```dart
import 'module_reference.dart';
import 'provider_key.dart';

/// One entry of `@Module(exports: ...)`.
sealed class ModuleExport {
  /// Creates the export.
  const ModuleExport();
}

/// An exported provider key.
final class KeyExport extends ModuleExport {
  /// Creates the export.
  const KeyExport(this.key);

  /// The exported key.
  final ProviderKey key;
}

/// A re-exported imported module.
final class ModuleReexport extends ModuleExport {
  /// Creates the export.
  const ModuleReexport(this.module);

  /// The re-exported module.
  final ModuleReference module;
}
```

`packages/dartnest_generator/lib/src/model/dependency_model.dart`:

```dart
import '../diagnostic/source_location.dart';
import 'provider_key.dart';

/// A constructor parameter that dependency injection fills.
///
/// Exactly one of [key] and [problem] is set.
final class DependencyModel {
  /// A parameter resolved by [key].
  const DependencyModel.injected({
    required this.name,
    required this.isNamed,
    required this.location,
    required ProviderKey this.key,
  }) : problem = null;

  /// A parameter that cannot be injected, because of [problem].
  const DependencyModel.invalid({
    required this.name,
    required this.isNamed,
    required this.location,
    required String this.problem,
  }) : key = null;

  /// The parameter name.
  final String name;

  /// Whether the parameter is named (passed as `name: value`).
  final bool isNamed;

  /// Where the parameter is declared.
  final SourceLocation location;

  /// The provider key to resolve; `null` when [problem] is set.
  final ProviderKey? key;

  /// Why the parameter cannot be injected, as a sentence.
  final String? problem;
}
```

`packages/dartnest_generator/lib/src/model/constructor_model.dart`:

```dart
import 'dependency_model.dart';

/// How dependency injection calls the unnamed constructor of a provider or
/// controller class.
final class ConstructorModel {
  /// A usable constructor with its [dependencies] in parameter order.
  const ConstructorModel(this.dependencies) : problem = null;

  /// A class that cannot be created, because of [problem].
  const ConstructorModel.invalid(String this.problem) : dependencies = const [];

  /// The parameters, in declaration order.
  final List<DependencyModel> dependencies;

  /// Why the class cannot be created, as a sentence; `null` when it can.
  final String? problem;
}
```

`packages/dartnest_generator/lib/src/model/injectable_model.dart`:

```dart
import '../diagnostic/source_location.dart';
import 'constructor_model.dart';
import 'type_model.dart';

/// A class that a module provides through its constructor: a class in
/// `@Module(providers: ...)` or the implementation of a `Bind`.
final class InjectableModel {
  /// Creates the model.
  const InjectableModel({
    required this.type,
    required this.isAnnotated,
    required this.constructor,
    required this.location,
    this.documentation,
  });

  /// The class.
  final TypeModel type;

  /// Whether the class is annotated with `@Injectable()`.
  final bool isAnnotated;

  /// How to create an instance.
  final ConstructorModel constructor;

  /// Where the class is declared.
  final SourceLocation location;

  /// The `///` comment of the class, if any.
  final String? documentation;
}
```

`packages/dartnest_generator/lib/src/model/provider_model.dart`:

```dart
import 'constant_value.dart';
import 'injectable_model.dart';
import 'provider_key.dart';

/// One entry of `@Module(providers: ...)`.
sealed class ProviderModel {
  /// Creates the provider.
  const ProviderModel(this.key);

  /// What the provider is looked up by.
  final ProviderKey key;
}

/// A class created through its constructor: `UsersService` or
/// `Bind<Clock, SystemClock>()`.
final class ClassProvider extends ProviderModel {
  /// Creates the provider.
  const ClassProvider(super.key, this.injectable);

  /// The class that is created.
  final InjectableModel injectable;
}

/// An already built constant: `Value(appConfig)`.
final class ValueProvider extends ProviderModel {
  /// Creates the provider.
  const ValueProvider(super.key, this.value);

  /// The provided constant.
  final ConstantValue value;
}
```

`packages/dartnest_generator/lib/src/model/module_model.dart`:

```dart
import '../diagnostic/source_location.dart';
import 'module_export.dart';
import 'module_reference.dart';
import 'provider_model.dart';
import 'type_model.dart';

/// A class annotated with `@Module`.
final class ModuleModel {
  /// Creates the model.
  const ModuleModel({
    required this.type,
    required this.id,
    required this.location,
    this.imports = const [],
    this.providers = const [],
    this.controllers = const [],
    this.exports = const [],
    this.isGlobal = false,
    this.invalidEntries = const [],
    this.documentation,
  });

  /// The module class.
  final TypeModel type;

  /// The module id: `@Module(id:)` or the class name.
  final String id;

  /// Where the class is declared.
  final SourceLocation location;

  /// Imported modules, in order.
  final List<ModuleReference> imports;

  /// Providers, in order.
  final List<ProviderModel> providers;

  /// Controller classes (annotated with `@Controller`), in order.
  final List<TypeModel> controllers;

  /// Exports, in order.
  final List<ModuleExport> exports;

  /// Whether the module is global.
  final bool isGlobal;

  /// One sentence per annotation entry the generator cannot use.
  final List<String> invalidEntries;

  /// The `///` comment of the class, if any.
  final String? documentation;
}
```

`packages/dartnest_generator/lib/src/model/body_kind.dart`:

```dart
/// How a `@Body()` parameter is read.
enum BodyKind {
  /// `T.fromJson(json)`.
  fromJson,

  /// The decoded JSON object as a `Map<String, Object?>`.
  jsonObject,

  /// The body as text.
  text,

  /// The body as bytes.
  bytes,

  /// No way to read the type: it has no `fromJson`.
  unsupported,
}
```

`packages/dartnest_generator/lib/src/model/parameter_binding.dart`:

```dart
import 'body_kind.dart';

/// Where a handler parameter's value comes from.
sealed class ParameterBinding {
  /// Creates the binding.
  const ParameterBinding();
}

/// `@Param(name)`: a path parameter.
final class PathBinding extends ParameterBinding {
  /// Creates the binding.
  const PathBinding(this.name);

  /// The path parameter name.
  final String name;
}

/// `@Query(name)`: a query parameter.
final class QueryBinding extends ParameterBinding {
  /// Creates the binding.
  const QueryBinding(this.name);

  /// The query parameter name.
  final String name;
}

/// `@Header(name)`: a request header.
final class HeaderBinding extends ParameterBinding {
  /// Creates the binding.
  const HeaderBinding(this.name);

  /// The header name.
  final String name;
}

/// `@Body()`: the request body.
final class BodyBinding extends ParameterBinding {
  /// Creates the binding.
  const BodyBinding(this.kind);

  /// How the body is read.
  final BodyKind kind;
}

/// A parameter of type `ExecutionContext`.
final class ContextBinding extends ParameterBinding {
  /// Creates the binding.
  const ContextBinding();
}

/// A parameter of type `HttpRequest`.
final class RequestBinding extends ParameterBinding {
  /// Creates the binding.
  const RequestBinding();
}

/// A parameter that cannot be bound, because of [problem].
final class InvalidBinding extends ParameterBinding {
  /// Creates the binding.
  const InvalidBinding(this.problem);

  /// Why the parameter cannot be bound, as a sentence fragment.
  final String problem;
}
```

`packages/dartnest_generator/lib/src/model/handler_parameter.dart`:

```dart
import '../diagnostic/source_location.dart';
import 'parameter_binding.dart';
import 'type_model.dart';

/// A parameter of a route handler method.
final class HandlerParameter {
  /// Creates the model.
  const HandlerParameter({
    required this.name,
    required this.type,
    required this.binding,
    required this.isNamed,
    required this.location,
  });

  /// The parameter name.
  final String name;

  /// The declared type.
  final TypeModel type;

  /// Where the value comes from.
  final ParameterBinding binding;

  /// Whether the parameter is named.
  final bool isNamed;

  /// Where the parameter is declared.
  final SourceLocation location;
}
```

`packages/dartnest_generator/lib/src/model/component_reference.dart`:

```dart
import 'type_model.dart';

/// A type listed in `@UseGuards`, `@UseInterceptors`, `@UsePipes` or
/// `@UseFilters`.
final class ComponentReference {
  /// Creates the reference.
  const ComponentReference(this.type, {required this.isValid});

  /// The component class.
  final TypeModel type;

  /// Whether the class is a component of the kind its annotation needs (a
  /// `Guard` for `@UseGuards`, ...).
  final bool isValid;
}
```

`packages/dartnest_generator/lib/src/model/enhancers_model.dart`:

```dart
import 'component_reference.dart';

/// The `@Use...` components of a controller or a route.
final class EnhancersModel {
  /// Creates the model; every list defaults to empty.
  const EnhancersModel({
    this.guards = const [],
    this.interceptors = const [],
    this.pipes = const [],
    this.filters = const [],
  });

  /// From `@UseGuards`.
  final List<ComponentReference> guards;

  /// From `@UseInterceptors`.
  final List<ComponentReference> interceptors;

  /// From `@UsePipes`.
  final List<ComponentReference> pipes;

  /// From `@UseFilters`.
  final List<ComponentReference> filters;

  /// Every component, guards first.
  List<ComponentReference> get all => [
    ...guards,
    ...interceptors,
    ...pipes,
    ...filters,
  ];
}
```

`packages/dartnest_generator/lib/src/model/route_model.dart`:

```dart
import '../diagnostic/source_location.dart';
import 'constant_value.dart';
import 'enhancers_model.dart';
import 'handler_parameter.dart';
import 'type_model.dart';

/// A controller method annotated with `@Get`, `@Post`, `@Put`, `@Patch` or
/// `@Delete`.
final class RouteModel {
  /// Creates the model.
  const RouteModel({
    required this.method,
    required this.path,
    required this.handlerName,
    required this.returnType,
    required this.location,
    this.parameters = const [],
    this.enhancers = const EnhancersModel(),
    this.metadata = const [],
    this.documentation,
    this.problem,
  });

  /// The upper-cased HTTP method.
  final String method;

  /// The path relative to the controller path.
  final String path;

  /// The method name.
  final String handlerName;

  /// The declared return type.
  final TypeModel returnType;

  /// Where the method is declared.
  final SourceLocation location;

  /// The parameters, in declaration order.
  final List<HandlerParameter> parameters;

  /// Route-level components.
  final EnhancersModel enhancers;

  /// Route-level `RouteMetadata` annotations.
  final List<ConstantValue> metadata;

  /// The `///` comment of the method, if any.
  final String? documentation;

  /// Why the method cannot be a handler, as a sentence; `null` when it can.
  final String? problem;

  /// Names of the `:name` parameters and the `*` wildcard of [path].
  List<String> get pathParameters => [
    for (final segment in path.split('/'))
      if (segment.startsWith(':'))
        segment.substring(1)
      else if (segment == '*')
        '*',
  ];
}
```

`packages/dartnest_generator/lib/src/model/controller_model.dart`:

```dart
import '../diagnostic/source_location.dart';
import 'constant_value.dart';
import 'constructor_model.dart';
import 'enhancers_model.dart';
import 'route_model.dart';
import 'type_model.dart';

/// A class annotated with `@Controller`.
final class ControllerModel {
  /// Creates the model.
  const ControllerModel({
    required this.type,
    required this.path,
    required this.constructor,
    required this.location,
    this.enhancers = const EnhancersModel(),
    this.metadata = const [],
    this.routes = const [],
    this.documentation,
  });

  /// The controller class.
  final TypeModel type;

  /// The path prefix of every route.
  final String path;

  /// How to create the instance.
  final ConstructorModel constructor;

  /// Where the class is declared.
  final SourceLocation location;

  /// Controller-level components.
  final EnhancersModel enhancers;

  /// Controller-level `RouteMetadata` annotations.
  final List<ConstantValue> metadata;

  /// The routes, in declaration order.
  final List<RouteModel> routes;

  /// The `///` comment of the class, if any.
  final String? documentation;
}
```

`packages/dartnest_generator/lib/src/model/dto_field.dart`:

```dart
import 'type_model.dart';

/// A field of a `DtoModel`.
final class DtoField {
  /// Creates the field.
  const DtoField({
    required this.name,
    required this.jsonName,
    required this.type,
    this.defaultValue,
    this.documentation,
  });

  /// The Dart field name.
  final String name;

  /// The JSON key: `@JsonKey(name:)` when present, otherwise [name].
  final String jsonName;

  /// The declared type; nullable fields have a nullable type.
  final TypeModel type;

  /// The default value of the matching constructor parameter, as source.
  final String? defaultValue;

  /// The `///` comment of the field, if any.
  final String? documentation;
}
```

`packages/dartnest_generator/lib/src/model/dto_model.dart`:

```dart
import 'dto_field.dart';
import 'type_model.dart';

/// The shape of a class that is a request body or a handler result,
/// collected for documentation generators (OpenAPI in a later version).
final class DtoModel {
  /// Creates the model.
  const DtoModel({
    required this.type,
    required this.fields,
    required this.hasFromJson,
    this.documentation,
  });

  /// The class.
  final TypeModel type;

  /// Public instance fields, in declaration order.
  final List<DtoField> fields;

  /// Whether the class has a `fromJson` that takes a JSON object.
  final bool hasFromJson;

  /// The `///` comment of the class, if any.
  final String? documentation;
}
```

`packages/dartnest_generator/lib/src/model/package_model.dart`:

```dart
import 'package:pub_semver/pub_semver.dart';

import 'controller_model.dart';
import 'dto_model.dart';
import 'injectable_model.dart';
import 'module_model.dart';

/// Everything the generator collected from one package: the input of every
/// `Construct`.
final class PackageModel {
  /// Creates the model.
  const PackageModel({
    required this.packageName,
    required this.languageVersion,
    this.modules = const [],
    this.injectables = const [],
    this.controllers = const [],
    this.dtos = const [],
  });

  /// The package name; the output is `lib/<packageName>.dartnest.dart`.
  final String packageName;

  /// The package's language version, used to format the output.
  final Version languageVersion;

  /// Classes annotated with `@Module`, sorted by name and library.
  final List<ModuleModel> modules;

  /// Classes provided through their constructor, sorted by name and
  /// library, each once.
  final List<InjectableModel> injectables;

  /// Classes annotated with `@Controller`, sorted by name and library.
  final List<ControllerModel> controllers;

  /// Request bodies and handler results, sorted by name and library.
  final List<DtoModel> dtos;
}
```

`packages/dartnest_generator/lib/src/model/generated_names.dart`:

```dart
/// Names of the declarations the generator emits, derived from class names.
///
/// `UsersModule` → `usersModule`, `Config` (a `@Module`) → `configModule`,
/// `UsersController` → `usersController`, `UsersService` →
/// `_createUsersService` (factories stay private to the generated library).
/// Another package's `@Module` class is imported by the same rule from that
/// package's `<package>.dartnest.dart`.
abstract final class GeneratedNames {
  /// The function that builds the module of `@Module` class [className].
  static String module(String className) => _suffixed(className, 'Module');

  /// The function that builds the controller of `@Controller` class
  /// [className].
  static String controller(String className) =>
      _suffixed(className, 'Controller');

  /// The private factory function of injectable class [className].
  static String factory(String className) => '_create$className';

  /// The generated library of package [packageName].
  static String library(String packageName) =>
      'package:$packageName/$packageName.dartnest.dart';

  static String _suffixed(String className, String suffix) {
    final name = className.endsWith(suffix) ? className : '$className$suffix';
    return '${name[0].toLowerCase()}${name.substring(1)}';
  }
}
```

- [ ] **Step 5: Write the barrel**

Поки що barrel відкриває лише модель і діагностики; Task 6 і Task 10 додають решту.

`packages/dartnest_generator/lib/dartnest_generator.dart`:

```dart
/// Turns dartnest annotations into ordinary code on the explicit dartnest
/// API, and checks the module graph before the application starts.
///
/// The model and the diagnostics are public so later packages (OpenAPI,
/// GraphQL) can read them.
library;

export 'src/diagnostic/diagnostic.dart';
export 'src/diagnostic/diagnostic_code.dart';
export 'src/diagnostic/source_location.dart';
export 'src/model/body_kind.dart';
export 'src/model/component_reference.dart';
export 'src/model/constant_value.dart';
export 'src/model/constructor_model.dart';
export 'src/model/controller_model.dart';
export 'src/model/dependency_model.dart';
export 'src/model/dto_field.dart';
export 'src/model/dto_model.dart';
export 'src/model/enhancers_model.dart';
export 'src/model/generated_names.dart';
export 'src/model/handler_parameter.dart';
export 'src/model/injectable_model.dart';
export 'src/model/module_export.dart';
export 'src/model/module_model.dart';
export 'src/model/module_reference.dart';
export 'src/model/package_model.dart';
export 'src/model/parameter_binding.dart';
export 'src/model/provider_key.dart';
export 'src/model/provider_model.dart';
export 'src/model/route_model.dart';
export 'src/model/type_kind.dart';
export 'src/model/type_model.dart';
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd packages/dartnest_generator && dart test`
Expected: `+6: All tests passed!`

- [ ] **Step 7: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 8: Commit**

```bash
git add \
  packages/dartnest_generator/pubspec.yaml \
  packages/dartnest_generator/analysis_options.yaml \
  pubspec.yaml \
  packages/dartnest_generator/test/model/model_test.dart \
  packages/dartnest_generator/lib/src/diagnostic/source_location.dart \
  packages/dartnest_generator/lib/src/diagnostic/diagnostic_code.dart \
  packages/dartnest_generator/lib/src/diagnostic/diagnostic.dart \
  packages/dartnest_generator/lib/src/model/type_kind.dart \
  packages/dartnest_generator/lib/src/model/type_model.dart \
  packages/dartnest_generator/lib/src/model/constant_value.dart \
  packages/dartnest_generator/lib/src/model/provider_key.dart \
  packages/dartnest_generator/lib/src/model/module_reference.dart \
  packages/dartnest_generator/lib/src/model/module_export.dart \
  packages/dartnest_generator/lib/src/model/dependency_model.dart \
  packages/dartnest_generator/lib/src/model/constructor_model.dart \
  packages/dartnest_generator/lib/src/model/injectable_model.dart \
  packages/dartnest_generator/lib/src/model/provider_model.dart \
  packages/dartnest_generator/lib/src/model/module_model.dart \
  packages/dartnest_generator/lib/src/model/body_kind.dart \
  packages/dartnest_generator/lib/src/model/parameter_binding.dart \
  packages/dartnest_generator/lib/src/model/handler_parameter.dart \
  packages/dartnest_generator/lib/src/model/component_reference.dart \
  packages/dartnest_generator/lib/src/model/enhancers_model.dart \
  packages/dartnest_generator/lib/src/model/route_model.dart \
  packages/dartnest_generator/lib/src/model/controller_model.dart \
  packages/dartnest_generator/lib/src/model/dto_field.dart \
  packages/dartnest_generator/lib/src/model/dto_model.dart \
  packages/dartnest_generator/lib/src/model/package_model.dart \
  packages/dartnest_generator/lib/src/model/generated_names.dart \
  packages/dartnest_generator/lib/dartnest_generator.dart
git commit -m "feat(generator): add diagnostics and the package model"
```

### Task 3: Читачі констант, типів і позицій; фікстура `cases_app`

Нижній шар collector'а. `Annotations` знаходить анотації `dartnest_annotations` за іменем класу й бібліотекою (а не за типом: генератор не залежить від пакета анотацій) і читає поля через ланцюжок `super`. `TypeReader` перетворює `DartType` на `TypeModel`; `SourceLocations` дає `path:line:col` відносно кореня пакета (за `nonSynthetic`-елементом, тож поле `this.x` вказує на параметр). `ConstantReader` — серце рішення 4: публічна константа → `ReferenceConstant` (посилання), приватна → виклик конструктора з аргументами (`ObjectConstant`), значення enum → посилання, приватний клас у типі чи в аргументах типу або приватний конструктор → `UnsupportedConstant` (Review Focus 3). `TokenReader` читає `Token<T>('name')` ядра в `TokenKey` разом з типом значення (для перевірки `@Inject` у Task 4).

Тести резолвлять справжній пакет: `FixturePackage` (тестовий хелпер) відкриває `test/fixtures/<name>` через `AnalysisContextCollection`, як CLI етапу 5. Фікстура `cases_app` — член workspace, залежить від `dartnest` і `dartnest_annotations`; у цій задачі в ній лише `lib/constants.dart`.

**Files:**
- Create: `packages/dartnest_generator/test/fixtures/cases_app/pubspec.yaml`
- Create: `packages/dartnest_generator/test/fixtures/cases_app/analysis_options.yaml`
- Create: `packages/dartnest_generator/test/fixtures/cases_app/lib/constants.dart`
- Create: `packages/dartnest_generator/lib/src/collector/annotations.dart`
- Create: `packages/dartnest_generator/lib/src/collector/type_reader.dart`
- Create: `packages/dartnest_generator/lib/src/collector/source_locations.dart`
- Create: `packages/dartnest_generator/lib/src/collector/constant_reader.dart`
- Create: `packages/dartnest_generator/lib/src/collector/token_reader.dart`
- Modify: `pubspec.yaml`
- Modify: `packages/dartnest_generator/pubspec.yaml`
- Test: `packages/dartnest_generator/test/helpers/fixture_package.dart`
- Test: `packages/dartnest_generator/test/collector/constant_reader_test.dart`

**Interfaces:**
- Consumes: модель і `SourceLocation` (Task 2); класи `dartnest_annotations` (Task 1) і `Token` ядра — лише як імена в джерелах фікстури.
- Produces (`packages/dartnest_generator/lib/src/collector/`):
  - `Annotations`: `static DartObject? find(Element element, String name)`, `static List<DartObject> all(Element element, Set<String> names)`, `static List<DartObject> routeMetadata(Element element)`, `static DartObject? field(DartObject object, String name)`, `static String describe(DartObject entry)`
  - `TypeReader`: `static TypeModel read(DartType type)`, `static bool isDartnest(DartType? type, String name)`, `static bool hasSupertype(...)` (чи реалізує тип клас ядра)
  - `SourceLocations(String packageRoot)`: `SourceLocation of(Element element)`
  - `ConstantReader`: `static ConstantValue read(DartObject? object)`
  - `TokenReader`: `static (TokenKey, DartType)? read(DartObject? object)`
- Produces (тести): `test/helpers/fixture_package.dart` — `FixturePackage.open(String name)`, `name`, `root`, `Future<List<LibraryElement>> libraries([List<String>? paths])`, `String read(String path)`; Task 4 додає `collect`.

- [ ] **Step 1: Add the fixture package and the test helper**

Фікстура стає членом workspace, генератор отримує її як dev-залежність:

`pubspec.yaml`:

```yaml
name: dartnest_workspace
publish_to: none
environment:
  sdk: ^3.8.0
workspace:
  - packages/dartnest
  - packages/dartnest_annotations
  - packages/dartnest_conformance
  - packages/dartnest_generator
  - packages/dartnest_generator/test/fixtures/cases_app
  - packages/dartnest_io
  - packages/dartnest_shelf
```

`packages/dartnest_generator/pubspec.yaml`:

```yaml
name: dartnest_generator
description: >-
  Turns dartnest annotations into ordinary code on the explicit dartnest API,
  with static validation of the module graph.
version: 0.1.0-dev
publish_to: none
environment:
  sdk: ^3.8.0
resolution: workspace
dependencies:
  analyzer: '>=8.1.1 <15.0.0'
  code_builder: ^4.11.1
  dart_style: ^3.1.2
  path: ^1.9.0
  pub_semver: ^2.1.4
dev_dependencies:
  cases_app: ^0.1.0-dev
  lints: ^5.1.0
  test: ^1.25.0
```

`packages/dartnest_generator/test/fixtures/cases_app/pubspec.yaml`:

```yaml
name: cases_app
description: Small annotated libraries, one scenario each, for dartnest_generator tests.
version: 0.1.0-dev
publish_to: none
environment:
  sdk: ^3.8.0
resolution: workspace
dependencies:
  dartnest: ^0.1.0-dev
  dartnest_annotations: ^0.1.0-dev
```

`packages/dartnest_generator/test/fixtures/cases_app/analysis_options.yaml`:

```yaml
include: ../../../../../analysis_options.yaml
```

`packages/dartnest_generator/test/fixtures/cases_app/lib/constants.dart`:

```dart
// Constants for ConstantReader tests: each annotation on [Holder] is read
// by name.
import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

/// A public token.
const dbUrl = Token<String>('db.url');

const _secret = Token<int>('secret');

/// Statuses.
enum Status { active, banned }

/// Metadata with every kind of field.
final class Tagged extends RouteMetadata {
  /// Creates the metadata.
  const Tagged(
    this.label, {
    this.count = 0,
    this.ratio = 0.5,
    this.flags = const {},
    this.extra = const {},
    this.status,
    this.type,
    this.nothing,
  });

  /// A string.
  final String label;

  /// An int.
  final int count;

  /// A double.
  final double ratio;

  /// A set.
  final Set<String> flags;

  /// A map.
  final Map<String, int> extra;

  /// An enum value.
  final Status? status;

  /// A type.
  final Type? type;

  /// Always null.
  final Object? nothing;
}

/// Metadata holding a private object.
final class Wrapped extends RouteMetadata {
  /// Creates the metadata.
  const Wrapped(this.value);

  /// The wrapped value.
  final Object value;
}

final class _Hidden {
  const _Hidden();
}

/// Carries the annotations the tests read.
@Tagged(
  'it\'s \$5',
  count: 3,
  flags: {'a'},
  extra: {'x': 1},
  status: Status.banned,
  type: Holder,
)
@Wrapped(_Hidden())
@Inject(dbUrl)
@Value(_secret)
@UseGuards([Holder])
class Holder {}
```

`packages/dartnest_generator/test/helpers/fixture_package.dart`:

```dart
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:path/path.dart' as p;

/// A fixture package under `test/fixtures/<name>`, resolved with the
/// analyzer the way a driver would: every library of its `lib/` except the
/// generated `*.dartnest.dart`.
///
/// One instance holds one analysis context; open it once per test file
/// (`setUpAll`), because resolving the SDK takes a few seconds.
final class FixturePackage {
  FixturePackage._(this.name, this.root, this._collection);

  /// Opens `test/fixtures/<name>`; tests run from the package directory.
  factory FixturePackage.open(String name) {
    final root = p.normalize(p.absolute('test', 'fixtures', name));
    return FixturePackage._(
      name,
      root,
      AnalysisContextCollection(includedPaths: [root]),
    );
  }

  /// The package name (also the directory name).
  final String name;

  /// Absolute path of the package root.
  final String root;

  final AnalysisContextCollection _collection;

  /// The resolved libraries of [paths] (relative to [root], for example
  /// `lib/users.dart`), or of every library in `lib/` when [paths] is
  /// `null`, in path order.
  Future<List<LibraryElement>> libraries([List<String>? paths]) async {
    final files = paths == null
        ? _libraryFiles()
        : [for (final path in paths) p.join(root, path)];
    return [for (final file in files) await _resolve(file)];
  }

  /// The source of [path] (relative to [root]).
  String read(String path) => File(p.join(root, path)).readAsStringSync();

  List<String> _libraryFiles() {
    final files = Directory(p.join(root, 'lib'))
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => file.path)
        .where((path) => path.endsWith('.dart'))
        .where((path) => !path.endsWith('.dartnest.dart'))
        .toList();
    return files..sort();
  }

  Future<LibraryElement> _resolve(String file) async {
    final session = _collection.contextFor(file).currentSession;
    final result = await session.getResolvedLibrary(file);
    if (result is! ResolvedLibraryResult) {
      throw StateError('Cannot resolve $file: $result');
    }
    return result.element;
  }
}
```

Run: `dart pub get`
Expected: `Got dependencies!` (з кореня репозиторію)

- [ ] **Step 2: Write the failing test**

`packages/dartnest_generator/test/collector/constant_reader_test.dart`:

```dart
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartnest_generator/src/collector/constant_reader.dart';
import 'package:dartnest_generator/src/collector/source_locations.dart';
import 'package:dartnest_generator/src/collector/token_reader.dart';
import 'package:dartnest_generator/src/model/constant_value.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  late FixturePackage fixture; // Set in setUpAll.
  late ClassElement holder; // Set in setUpAll.

  setUpAll(() async {
    fixture = FixturePackage.open('cases_app');
    final library = (await fixture.libraries(['lib/constants.dart'])).single;
    holder = library.classes.firstWhere((c) => c.name == 'Holder');
  });

  DartObject annotation(String name) => [
    for (final a in holder.metadata.annotations)
      if (a.computeConstantValue() case final value?) value,
  ].firstWhere((value) => value.type?.element?.name == name);

  test('an object constant keeps its constructor arguments', () {
    final tagged = ConstantReader.read(annotation('Tagged')) as ObjectConstant;

    expect(tagged.type.display, 'Tagged');
    expect(tagged.constructorName, '');
    expect((tagged.positional.single as StringConstant).value, r"it's $5");
    expect((tagged.named['count'] as NumberConstant).literal, '3');
    expect(
      (tagged.named['flags'] as SetConstant).elements.single,
      isA<StringConstant>(),
    );
    final extra = tagged.named['extra'] as MapConstant;
    expect('${extra.keyType} ${extra.valueType}', 'String int');
    final status = tagged.named['status'] as ReferenceConstant;
    expect('${status.enclosingName}.${status.name}', 'Status.banned');
    expect((tagged.named['type'] as TypeConstant).type.display, 'Holder');
    expect(tagged.unsupported, isNull);
  });

  test('a public constant is read as a reference to it', () {
    final inject = ConstantReader.read(annotation('Inject')) as ObjectConstant;
    final token = inject.positional.single as ReferenceConstant;

    expect(token.name, 'dbUrl');
    expect(token.libraryUri, 'package:cases_app/constants.dart');
    expect(token.enclosingName, isNull);
  });

  // Review Focus 3: private constants and classes in annotations.
  test('a private constant is rebuilt from its constructor call', () {
    final value = ConstantReader.read(annotation('Value')) as ObjectConstant;
    final token = value.positional.single as ObjectConstant;

    expect(token.type.display, 'Token<int>');
    expect((token.positional.single as StringConstant).value, 'secret');
  });

  // Review Focus 3.
  test('a private class cannot be written in generated code', () {
    final wrapped = ConstantReader.read(annotation('Wrapped'));

    expect(wrapped.unsupported?.reason, '_Hidden is private');
  });

  test('a list of types', () {
    final guards = ConstantReader.read(annotation('UseGuards'));
    final types = (guards as ObjectConstant).positional.single as ListConstant;

    expect(types.elementType.display, 'Type');
    expect((types.elements.single as TypeConstant).type.display, 'Holder');
  });

  test('a token reads as a key with its value type', () {
    final inject = annotation('Inject');
    final (key, valueType) =
        TokenReader.read(inject.getField('token')) ?? fail('not a token');

    expect(key.display, 'Token<String>(db.url)');
    expect(valueType.isDartCoreString, isTrue);
    expect(key.expression, isA<ReferenceConstant>());
    expect(TokenReader.read(annotation('Tagged')), isNull);
  });

  test('locations are relative to the package root', () {
    final location = SourceLocations(fixture.root).of(holder);
    final source = fixture.read('lib/constants.dart').split('\n');

    expect(location.path, 'lib/constants.dart');
    expect(source[location.line - 1].indexOf('Holder'), location.column - 1);
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd packages/dartnest_generator && dart test test/collector/constant_reader_test.dart`
Expected: FAIL: компіляція — `lib/src/collector/constant_reader.dart` не існує

- [ ] **Step 4: Write the readers**

`packages/dartnest_generator/lib/src/collector/annotations.dart`:

```dart
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// Reads `package:dartnest_annotations` annotations from elements.
abstract final class Annotations {
  /// URI prefix of the annotations package.
  static const packageUri = 'package:dartnest_annotations/';

  /// The value of the first annotation on [element] whose class is [name]
  /// from the annotations package.
  static DartObject? find(Element element, String name) =>
      all(element, {name}).firstOrNull;

  /// The values of every annotation on [element] whose class is one of
  /// [names] from the annotations package, in source order.
  static List<DartObject> all(Element element, Set<String> names) => [
    for (final annotation in element.metadata.annotations)
      if (annotation.computeConstantValue() case final value?)
        if (_isAnnotation(value.type, names)) value,
  ];

  /// The values of every annotation on [element] whose class extends
  /// `RouteMetadata`, in source order.
  static List<DartObject> routeMetadata(Element element) => [
    for (final annotation in element.metadata.annotations)
      if (annotation.computeConstantValue() case final value?)
        if (value.type case InterfaceType(:final element))
          if (element.allSupertypes.any(
            (type) => _isAnnotation(type, const {'RouteMetadata'}),
          ))
            value,
  ];

  /// Field [name] of [object], looked up in its superclasses too.
  static DartObject? field(DartObject object, String name) {
    for (DartObject? current = object; current != null;) {
      final value = current.getField(name);
      if (value != null) return value;
      current = current.getField('(super)');
    }
    return null;
  }

  /// [entry] of an annotation list as a diagnostic shows it: a type or
  /// function by name, anything else as `a value of type T`.
  static String describe(DartObject entry) =>
      entry.toTypeValue()?.getDisplayString() ??
      entry.toFunctionValue()?.displayName ??
      'a value of type ${entry.type?.getDisplayString() ?? 'unknown'}';

  static bool _isAnnotation(DartType? type, Set<String> names) =>
      type is InterfaceType &&
      names.contains(type.element.name) &&
      '${type.element.library.uri}'.startsWith(packageUri);
}
```

`packages/dartnest_generator/lib/src/collector/type_reader.dart`:

```dart
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/type_kind.dart';
import '../model/type_model.dart';

/// Converts analyzer types to [TypeModel]s.
abstract final class TypeReader {
  /// The model of [type].
  static TypeModel read(DartType type) => switch (type) {
    VoidType() => TypeModel.voidType,
    DynamicType() => const TypeModel(
      name: 'dynamic',
      kind: TypeKind.dynamicType,
    ),
    InterfaceType(:final element, :final typeArguments) => TypeModel(
      name: element.name ?? element.displayName,
      kind: element is EnumElement ? TypeKind.enumeration : TypeKind.interface,
      libraryUri: '${element.library.uri}',
      typeArguments: [for (final argument in typeArguments) read(argument)],
      isNullable: type.nullabilitySuffix == NullabilitySuffix.question,
    ),
    _ => TypeModel(name: type.getDisplayString(), kind: TypeKind.unsupported),
  };

  /// Whether [type] is the class [name] of a `package:dartnest` library.
  static bool isDartnest(DartType? type, String name) =>
      type is InterfaceType &&
      type.element.name == name &&
      _isIn(type.element.library, 'package:dartnest/');

  /// Whether [element] or one of its supertypes is the class [name] of a
  /// library under [uriPrefix].
  static bool hasSupertype(
    InterfaceElement element,
    String name,
    String uriPrefix,
  ) => [element.thisType, ...element.allSupertypes].any(
    (type) =>
        type.element.name == name && _isIn(type.element.library, uriPrefix),
  );

  static bool _isIn(LibraryElement library, String uriPrefix) =>
      '${library.uri}'.startsWith(uriPrefix);
}
```

`packages/dartnest_generator/lib/src/collector/source_locations.dart`:

```dart
import 'package:analyzer/dart/element/element.dart';
import 'package:path/path.dart' as p;

import '../diagnostic/source_location.dart';

/// Turns elements into [SourceLocation]s relative to the package root.
final class SourceLocations {
  /// Creates the reader for the package at [packageRoot] (absolute path).
  SourceLocations(this.packageRoot);

  /// Absolute path of the package root.
  final String packageRoot;

  /// Where [element]'s name is declared. Files outside [packageRoot] are
  /// shown by library URI.
  SourceLocation of(Element element) {
    final fragment = element.firstFragment;
    final libraryFragment = fragment.libraryFragment;
    if (libraryFragment == null) {
      return SourceLocation('${element.library?.uri}', 1, 1);
    }
    final offset = fragment.nameOffset ?? fragment.offset;
    final position = libraryFragment.lineInfo.getLocation(offset);
    return SourceLocation(
      _display(libraryFragment.source.fullName, element.library?.uri),
      position.lineNumber,
      position.columnNumber,
    );
  }

  String _display(String file, Uri? libraryUri) {
    if (!p.isWithin(packageRoot, file)) return '$libraryUri';
    return p.posix.joinAll(p.split(p.relative(file, from: packageRoot)));
  }
}
```

`packages/dartnest_generator/lib/src/collector/constant_reader.dart`:

```dart
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/constant_value.dart';
import 'type_reader.dart';

/// Converts analyzer constants to [ConstantValue]s that the generator can
/// write back as code.
///
/// A constant that is a public named constant is kept as a reference
/// (`dbUrl`, `Status.active`); anything else is rebuilt from its value.
abstract final class ConstantReader {
  /// The model of [object].
  static ConstantValue read(DartObject? object) {
    if (object == null || !object.hasKnownValue) {
      return const UnsupportedConstant('its value is not known');
    }
    if (_reference(object.variable) case final reference?) return reference;
    if (object.isNull) return const NullConstant();
    final private =
        _privateClass(object.toTypeValue()) ?? _privateClass(object.type);
    if (private != null) return UnsupportedConstant('$private is private');
    return _primitive(object) ?? _collection(object) ?? _object(object);
  }

  static ReferenceConstant? _reference(VariableElement? variable) {
    final name = variable?.name;
    if (variable == null || name == null || !variable.isPublic) return null;
    final library = variable.library;
    if (library == null) return null;
    return switch (variable.enclosingElement) {
      LibraryElement() => ReferenceConstant(
        name: name,
        libraryUri: '${library.uri}',
      ),
      InterfaceElement(name: final owner?) when !owner.startsWith('_') =>
        ReferenceConstant(
          name: name,
          libraryUri: '${library.uri}',
          enclosingName: owner,
        ),
      _ => null,
    };
  }

  static ConstantValue? _primitive(DartObject object) {
    if (object.toBoolValue() case final value?) return BoolConstant(value);
    if (object.toIntValue() case final value?) return NumberConstant('$value');
    if (object.toDoubleValue() case final value?) {
      return value.isFinite
          ? NumberConstant('$value')
          : UnsupportedConstant('$value is not a finite number');
    }
    if (object.toStringValue() case final value?) return StringConstant(value);
    if (object.toTypeValue() case final type?) {
      return TypeConstant(TypeReader.read(type));
    }
    return null;
  }

  static ConstantValue? _collection(DartObject object) {
    final type = object.type;
    if (type is! InterfaceType) return null;
    final arguments = [for (final t in type.typeArguments) TypeReader.read(t)];
    if (object.toListValue() case final list?) {
      return ListConstant(arguments.single, [for (final e in list) read(e)]);
    }
    if (object.toSetValue() case final set?) {
      return SetConstant(arguments.single, [for (final e in set) read(e)]);
    }
    if (object.toMapValue() case final map?) {
      return MapConstant(arguments.first, arguments.last, [
        for (final MapEntry(:key, :value) in map.entries)
          (read(key), read(value)),
      ]);
    }
    return null;
  }

  static ConstantValue _object(DartObject object) {
    final invocation = object.constructorInvocation;
    final type = object.type;
    if (invocation == null || type is! InterfaceType) {
      return UnsupportedConstant(
        '${object.type?.getDisplayString() ?? 'it'} is not a constructor call, '
        'a literal or a public constant',
      );
    }
    final constructor = invocation.constructor;
    if (constructor.isPrivate) {
      return UnsupportedConstant(
        'the constructor ${constructor.displayName} is private',
      );
    }
    return ObjectConstant(
      type: TypeReader.read(type),
      constructorName: _constructorName(constructor),
      positional: [
        for (final value in invocation.positionalArguments) read(value),
      ],
      named: {
        for (final MapEntry(:key, :value) in invocation.namedArguments.entries)
          key: read(value),
      },
    );
  }

  /// The name of a private class in [type] or its type arguments.
  static String? _privateClass(DartType? type) {
    if (type is! InterfaceType) return null;
    final name = type.element.name ?? '';
    if (name.startsWith('_')) return name;
    return type.typeArguments.map(_privateClass).nonNulls.firstOrNull;
  }

  /// `''` for the unnamed constructor, whose name differs between analyzer
  /// versions (`''`, `new` or `null`).
  static String _constructorName(ConstructorElement constructor) =>
      switch (constructor.name) {
        null || '' || 'new' => '',
        final name => name,
      };
}
```

`packages/dartnest_generator/lib/src/collector/token_reader.dart`:

```dart
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/provider_key.dart';
import 'constant_reader.dart';
import 'type_reader.dart';

/// Reads `Token` constants of `package:dartnest`.
abstract final class TokenReader {
  /// The key of [object] and its `T`, or `null` when [object] is not a
  /// `Token`.
  static (TokenKey, DartType)? read(DartObject? object) {
    final type = object?.type;
    final name = object?.getField('name')?.toStringValue();
    if (object == null ||
        name == null ||
        type is! InterfaceType ||
        !TypeReader.isDartnest(type, 'Token')) {
      return null;
    }
    final valueType = type.typeArguments.single;
    final key = TokenKey(
      valueType: TypeReader.read(valueType),
      name: name,
      expression: ConstantReader.read(object),
    );
    return (key, valueType);
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd packages/dartnest_generator && dart test test/collector/constant_reader_test.dart`
Expected: `+7: All tests passed!`

Run: `cd packages/dartnest_generator && dart test`
Expected: `+13: All tests passed!`

- [ ] **Step 6: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 7: Commit**

```bash
git add \
  pubspec.yaml \
  packages/dartnest_generator/pubspec.yaml \
  packages/dartnest_generator/test/fixtures/cases_app/pubspec.yaml \
  packages/dartnest_generator/test/fixtures/cases_app/analysis_options.yaml \
  packages/dartnest_generator/test/fixtures/cases_app/lib/constants.dart \
  packages/dartnest_generator/test/helpers/fixture_package.dart \
  packages/dartnest_generator/test/collector/constant_reader_test.dart \
  packages/dartnest_generator/lib/src/collector/annotations.dart \
  packages/dartnest_generator/lib/src/collector/type_reader.dart \
  packages/dartnest_generator/lib/src/collector/source_locations.dart \
  packages/dartnest_generator/lib/src/collector/constant_reader.dart \
  packages/dartnest_generator/lib/src/collector/token_reader.dart
git commit -m "feat(generator): read annotation constants, types and locations"
```

### Task 4: Збір модулів і injectable-класів

`PackageCollector` (роль `Collector` з роадмапу) обходить бібліотеки в порядку URI (пропускаючи `*.dartnest.dart`) і будує `PackageModel` з модулями й injectable-класами; контролери додає Task 5. `ModuleReader` читає `@Module`: `imports` і `exports` через `ModuleReferenceReader` (локальний `@Module`, `@Module` іншого пакета за правилом імен — OP12, tear-off функції — OP5), `providers` через `ProviderEntryReader` (клас, `Bind<K, I>()`, `Value(v, token:)` — з перевіркою, що значення підходить токену), `exports` — ще й типи та `Token`-константи. Кожен запис дає `EntryRead<T>` (sealed `ReadEntry`/`InvalidEntry`); `EntryRead.values`/`problems` розкладають список без мутації аргументів. `ConstructorReader` описує, як DI викликає неіменований конструктор: кожен параметр — тип (`i.get<T>()`) або `@Inject(token)` (`i.get(token)`); необов'язкові параметри, nullable/`Object`-типи, токен невідповідного типу → `DependencyModel.invalid`; приватний, generic, абстрактний клас без factory або клас без неіменованого конструктора → `ConstructorModel.invalid`.

Фікстури цієї задачі: `modules/basic.dart` (`DbModule`, глобальний, з `Value` і токеном), `modules/explicit.dart` (функція `explicitModule()` явним API — окремий файл без `hide`, OP2), `modules/app.dart` (`AppModule` імпортує обидва й реекспортує `DbModule`), `modules/invalid_entries.dart`, `providers/constructors.dart`.

**Files:**
- Create: `packages/dartnest_generator/test/fixtures/cases_app/lib/modules/basic.dart`
- Create: `packages/dartnest_generator/test/fixtures/cases_app/lib/modules/explicit.dart`
- Create: `packages/dartnest_generator/test/fixtures/cases_app/lib/modules/app.dart`
- Create: `packages/dartnest_generator/test/fixtures/cases_app/lib/modules/invalid_entries.dart`
- Create: `packages/dartnest_generator/test/fixtures/cases_app/lib/providers/constructors.dart`
- Create: `packages/dartnest_generator/lib/src/collector/entry_read.dart`
- Create: `packages/dartnest_generator/lib/src/collector/constructor_reader.dart`
- Create: `packages/dartnest_generator/lib/src/collector/injectable_reader.dart`
- Create: `packages/dartnest_generator/lib/src/collector/module_reference_reader.dart`
- Create: `packages/dartnest_generator/lib/src/collector/provider_entry_reader.dart`
- Create: `packages/dartnest_generator/lib/src/collector/module_reader.dart`
- Create: `packages/dartnest_generator/lib/src/collector/package_collector.dart`
- Modify: `packages/dartnest_generator/test/helpers/fixture_package.dart`
- Test: `packages/dartnest_generator/test/collector/module_collector_test.dart`

**Interfaces:**
- Consumes: Task 2 (модель), Task 3 (`Annotations`, `TypeReader`, `SourceLocations`, `ConstantReader`, `TokenReader`, `FixturePackage`).
- Produces (`packages/dartnest_generator/lib/src/collector/`):
  - `sealed class EntryRead<T>`: `ReadEntry<T>(T value)`, `InvalidEntry<T>(String problem)`; `static List<T> values<T>(Iterable<EntryRead<T>> reads)`, `static List<String> problems(Iterable<EntryRead<Object>> reads)`
  - `ConstructorReader(SourceLocations locations)`: `ConstructorModel read(InterfaceElement element)`
  - `InjectableReader(SourceLocations locations)`: `InjectableModel read(InterfaceElement element)`
  - `ModuleReferenceReader(String packageName)`: `ModuleReference? read(DartObject entry)`, `static bool isModuleClass(DartType type)`
  - `ProviderEntryReader(InjectableReader injectables, TypeSystem typeSystem)`: `EntryRead<ProviderModel> read(DartObject entry)`
  - `ModuleReader(String packageName, SourceLocations locations)`: `ModuleModel read(ClassElement element, DartObject annotation)`
  - `PackageCollector(String packageName, String packageRoot)`: `PackageModel collect(Iterable<LibraryElement> libraries)` — модулі й injectable-класи, відсортовані за URI бібліотеки
- Produces (тести): `FixturePackage.collect([List<String>? paths])` → `Future<PackageModel>`.

- [ ] **Step 1: Add the fixtures and the collect helper**

`FixturePackage` отримує `collect` (повний файл):

`packages/dartnest_generator/test/helpers/fixture_package.dart`:

```dart
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartnest_generator/src/collector/package_collector.dart';
import 'package:dartnest_generator/src/model/package_model.dart';
import 'package:path/path.dart' as p;

/// A fixture package under `test/fixtures/<name>`, resolved with the
/// analyzer the way a driver would: every library of its `lib/` except the
/// generated `*.dartnest.dart`.
///
/// One instance holds one analysis context; open it once per test file
/// (`setUpAll`), because resolving the SDK takes a few seconds.
final class FixturePackage {
  FixturePackage._(this.name, this.root, this._collection);

  /// Opens `test/fixtures/<name>`; tests run from the package directory.
  factory FixturePackage.open(String name) {
    final root = p.normalize(p.absolute('test', 'fixtures', name));
    return FixturePackage._(
      name,
      root,
      AnalysisContextCollection(includedPaths: [root]),
    );
  }

  /// The package name (also the directory name).
  final String name;

  /// Absolute path of the package root.
  final String root;

  final AnalysisContextCollection _collection;

  /// The resolved libraries of [paths] (relative to [root], for example
  /// `lib/users.dart`), or of every library in `lib/` when [paths] is
  /// `null`, in path order.
  Future<List<LibraryElement>> libraries([List<String>? paths]) async {
    final files = paths == null
        ? _libraryFiles()
        : [for (final path in paths) p.join(root, path)];
    return [for (final file in files) await _resolve(file)];
  }

  /// The [PackageModel] of [paths], as [libraries] reads them.
  Future<PackageModel> collect([List<String>? paths]) async =>
      PackageCollector(name, root).collect(await libraries(paths));

  /// The source of [path] (relative to [root]).
  String read(String path) => File(p.join(root, path)).readAsStringSync();

  List<String> _libraryFiles() {
    final files = Directory(p.join(root, 'lib'))
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => file.path)
        .where((path) => path.endsWith('.dart'))
        .where((path) => !path.endsWith('.dartnest.dart'))
        .toList();
    return files..sort();
  }

  Future<LibraryElement> _resolve(String file) async {
    final session = _collection.contextFor(file).currentSession;
    final result = await session.getResolvedLibrary(file);
    if (result is! ResolvedLibraryResult) {
      throw StateError('Cannot resolve $file: $result');
    }
    return result.element;
  }
}
```

`packages/dartnest_generator/test/fixtures/cases_app/lib/modules/basic.dart`:

```dart
// A valid global module: class, Bind and Value providers and a token.
import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

/// The database URL.
const dbUrl = Token<String>('db.url');

/// Application settings.
final class AppConfig {
  /// Creates the settings.
  const AppConfig(this.name);

  /// The application name.
  final String name;
}

/// The settings value.
const appConfig = AppConfig('demo');

/// A clock.
abstract interface class Clock {
  /// The current time.
  DateTime now();
}

/// The system clock.
@Injectable()
final class SystemClock implements Clock {
  @override
  DateTime now() => DateTime.now();
}

/// A repository.
@Injectable()
final class Repo {
  /// Creates the repository.
  Repo(this.clock, @Inject(dbUrl) this.url, {required this.config});

  /// The clock.
  final Clock clock;

  /// The database URL.
  final String url;

  /// The settings.
  final AppConfig config;
}

/// Database access.
@Module(
  id: 'db',
  providers: [
    Repo,
    Bind<Clock, SystemClock>(),
    Value('postgres://localhost', token: dbUrl),
    Value(appConfig),
  ],
  exports: [Repo, dbUrl],
  global: true,
)
class DbModule {}
```

`packages/dartnest_generator/test/fixtures/cases_app/lib/modules/explicit.dart`:

```dart
// A module written with the explicit API; it imports package:dartnest
// unhidden, so `Module` here is the core class.
import 'package:dartnest/dartnest.dart';

/// A module the generator cannot look into.
Module explicitModule() => Module(id: 'explicit');
```

`packages/dartnest_generator/test/fixtures/cases_app/lib/modules/app.dart`:

```dart
// A root module importing an annotated module and an explicit one.
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'basic.dart';
import 'explicit.dart';

/// The root.
@Module(imports: [DbModule, explicitModule], exports: [DbModule])
class AppModule {}
```

`packages/dartnest_generator/test/fixtures/cases_app/lib/modules/invalid_entries.dart`:

```dart
// Module entries the generator cannot read.
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'basic.dart';

/// Every list holds something wrong.
@Module(
  imports: [String, 'db'],
  providers: [
    42,
    dbUrl,
    Value(1, token: dbUrl),
  ],
  controllers: [Repo],
  exports: [3],
)
class BrokenModule {}
```

`packages/dartnest_generator/test/fixtures/cases_app/lib/providers/constructors.dart`:

```dart
// Classes whose constructors dependency injection cannot or can call.
import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

import '../modules/basic.dart';

/// Not annotated.
final class Plain {}

/// Abstract.
@Injectable()
abstract class Shape {}

/// Generic.
@Injectable()
final class Box<T> {}

/// Only a named constructor.
@Injectable()
final class Named {
  /// Creates it.
  Named.create();
}

/// An optional parameter.
@Injectable()
final class Optional {
  /// Creates it.
  Optional([this.clock]);

  /// The clock.
  final Clock? clock;
}

/// A nullable required parameter and a function parameter.
@Injectable()
final class Odd {
  /// Creates it.
  Odd(this.clock, this.callback);

  /// The clock.
  final Clock? clock;

  /// A callback.
  final void Function() callback;
}

/// Tokens that do not fit.
@Injectable()
final class BadTokens {
  /// Creates it.
  BadTokens(@Inject(dbUrl) this.port, @Inject('db.url') this.url);

  /// Declared int, but the token is a String.
  final int port;

  /// Not a token.
  final String url;
}

/// A token of a subtype fits a supertype parameter.
const portToken = Token<int>('port');

/// Injects through every accepted form.
@Injectable()
final class Fine {
  /// Creates it.
  Fine(this.clock, @Inject(portToken) this.port, {required this.repo});

  /// The clock.
  final Clock clock;

  /// The port, as a num.
  final num port;

  /// The repository.
  final Repo repo;
}
```

- [ ] **Step 2: Write the failing test**

`packages/dartnest_generator/test/collector/module_collector_test.dart`:

```dart
import 'package:dartnest_generator/src/collector/package_collector.dart';
import 'package:dartnest_generator/src/model/constant_value.dart';
import 'package:dartnest_generator/src/model/dependency_model.dart';
import 'package:dartnest_generator/src/model/injectable_model.dart';
import 'package:dartnest_generator/src/model/module_export.dart';
import 'package:dartnest_generator/src/model/module_model.dart';
import 'package:dartnest_generator/src/model/module_reference.dart';
import 'package:dartnest_generator/src/model/package_model.dart';
import 'package:dartnest_generator/src/model/provider_model.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  late PackageModel package; // Set in setUpAll.

  setUpAll(() async {
    final fixture = FixturePackage.open('cases_app');
    final libraries = await fixture.libraries([
      'lib/providers/constructors.dart',
      'lib/modules/invalid_entries.dart',
      'lib/modules/basic.dart',
      'lib/modules/app.dart',
    ]);
    package = PackageCollector('cases_app', fixture.root).collect(libraries);
  });

  ModuleModel module(String name) =>
      package.modules.firstWhere((m) => m.type.name == name);

  InjectableModel injectable(String name) =>
      package.injectables.firstWhere((i) => i.type.name == name);

  List<String> dependencies(String name) => [
    for (final dependency in injectable(name).constructor.dependencies)
      switch (dependency) {
        DependencyModel(:final key?) => '${dependency.name}: $key',
        DependencyModel(:final problem) => '${dependency.name}: $problem',
      },
  ];

  test('modules and injectables in library URI order', () {
    expect(package.languageVersion.toString(), '3.8.0');
    expect(
      [for (final m in package.modules) m.type.name],
      ['AppModule', 'DbModule', 'BrokenModule'],
    );
    expect(package.injectables.first.type.name, 'SystemClock');
    expect(package.injectables.last.type.name, 'Fine');
  });

  test('a module keeps its id, flags, location and documentation', () {
    final db = module('DbModule');

    expect(db.id, 'db');
    expect(db.isGlobal, isTrue);
    expect(db.documentation, '/// Database access.');
    expect(db.location.path, 'lib/modules/basic.dart');
    expect(module('AppModule').id, 'AppModule');
    expect(db.invalidEntries, isEmpty);
  });

  test('class, Bind and Value providers', () {
    final providers = module('DbModule').providers;

    expect(
      [for (final p in providers) '${p.key}'],
      ['Repo', 'Clock', 'Token<String>(db.url)', 'AppConfig'],
    );
    expect((providers[1] as ClassProvider).injectable.type.name, 'SystemClock');
    final url = (providers[2] as ValueProvider).value as StringConstant;
    expect(url.value, 'postgres://localhost');
    final config = (providers[3] as ValueProvider).value as ReferenceConstant;
    expect(config.name, 'appConfig');
  });

  test('imports and exports: local class, function tear-off, keys', () {
    final app = module('AppModule');
    final db = module('DbModule');

    expect(app.invalidEntries, isEmpty);
    expect(app.imports.first, isA<LocalModuleReference>());
    final explicit = app.imports.last as OpaqueModuleReference;
    expect(explicit.name, 'explicitModule');
    expect(explicit.libraryUri, 'package:cases_app/modules/explicit.dart');
    final reexport = app.exports.single as ModuleReexport;
    expect(reexport.module.display, 'DbModule');
    expect(
      [for (final e in db.exports) '${(e as KeyExport).key}'],
      ['Repo', 'Token<String>(db.url)'],
    );
  });

  test('entries the generator cannot read become problems', () {
    final broken = module('BrokenModule');

    expect(broken.invalidEntries, [
      'imports: String is not a module.',
      'imports: a value of type String is not a module.',
      'providers: a value of type int is not a class, Bind<K, I>() or '
          'Value(v).',
      'providers: a value of type Token<String> is not a class, Bind<K, I>() '
          'or Value(v).',
      'providers: Value(...) of type int cannot be provided as '
          'Token<String>(db.url).',
      'controllers: Repo is not a @Controller class of this package.',
      'exports: a value of type int is not a class, token or module.',
    ]);
    expect(broken.imports, isEmpty);
    expect(broken.providers, isEmpty);
  });

  test('dependencies by type, by token and by required name', () {
    expect(dependencies('Repo'), [
      'clock: Clock',
      'url: Token<String>(db.url)',
      'config: AppConfig',
    ]);
    expect(injectable('Repo').constructor.dependencies.last.isNamed, isTrue);
    expect(dependencies('Fine'), [
      'clock: Clock',
      'port: Token<int>(port)',
      'repo: Repo',
    ]);
  });

  test('classes dependency injection cannot create', () {
    expect(injectable('Shape').constructor.problem, 'Shape is abstract.');
    expect(
      injectable('Box').constructor.problem,
      'Box is generic; provide a subclass with fixed type arguments.',
    );
    expect(
      injectable('Named').constructor.problem,
      'Named has no unnamed constructor; dartnest creates it with Named(...).',
    );
  });

  test('parameters dependency injection cannot fill', () {
    expect(dependencies('Optional'), [
      'clock: Parameter clock of Optional is optional; dartnest injects '
          'required positional and required named parameters only.',
    ]);
    expect(dependencies('Odd'), [
      'clock: Parameter clock of Odd has type Clock?; dartnest injects '
          'non-nullable class types, or a Token with @Inject(token).',
      'callback: Parameter callback of Odd has type void Function(); dartnest '
          'injects non-nullable class types, or a Token with @Inject(token).',
    ]);
    expect(dependencies('BadTokens'), [
      'port: Parameter port of BadTokens has type int, but '
          'Token<String>(db.url) provides String.',
      'url: The @Inject argument of Parameter url of BadTokens is not a Token.',
    ]);
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd packages/dartnest_generator && dart test test/collector/module_collector_test.dart`
Expected: FAIL: компіляція — `lib/src/collector/package_collector.dart` не існує

- [ ] **Step 4: Write the entry and constructor readers**

`packages/dartnest_generator/lib/src/collector/entry_read.dart`:

```dart
/// The outcome of reading one entry of an annotation list, such as
/// `@Module(providers: [...])`: a value, or a sentence on why it is invalid.
sealed class EntryRead<T> {
  const EntryRead();

  /// The values of the [ReadEntry] items of [reads], in order.
  static List<T> values<T>(Iterable<EntryRead<T>> reads) => [
    for (final read in reads)
      if (read case ReadEntry<T>(:final value)) value,
  ];

  /// The problems of the [InvalidEntry] items of [reads], in order.
  static List<String> problems(Iterable<EntryRead<Object>> reads) => [
    for (final read in reads)
      if (read case InvalidEntry<Object>(:final problem)) problem,
  ];
}

/// An entry read into [value].
final class ReadEntry<T> extends EntryRead<T> {
  /// Creates the outcome.
  const ReadEntry(this.value);

  /// The value read.
  final T value;
}

/// An entry the generator cannot use.
final class InvalidEntry<T> extends EntryRead<T> {
  /// Creates the outcome.
  const InvalidEntry(this.problem);

  /// Why the entry is invalid, as a sentence.
  final String problem;
}
```

`packages/dartnest_generator/lib/src/collector/constructor_reader.dart`:

```dart
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/constructor_model.dart';
import '../model/dependency_model.dart';
import '../model/provider_key.dart';
import 'annotations.dart';
import 'source_locations.dart';
import 'token_reader.dart';
import 'type_reader.dart';

/// Reads how dependency injection creates a class: its unnamed constructor
/// and what each parameter resolves to.
final class ConstructorReader {
  /// Creates the reader.
  ConstructorReader(this.locations);

  /// Locations of parameters.
  final SourceLocations locations;

  /// The constructor model of [element].
  ConstructorModel read(InterfaceElement element) {
    final name = element.displayName;
    final constructor = element.unnamedConstructor;
    if (element is! ClassElement) {
      return ConstructorModel.invalid('$name is not a class.');
    }
    if (element.isPrivate) return ConstructorModel.invalid('$name is private.');
    if (element.typeParameters.isNotEmpty) {
      return ConstructorModel.invalid(
        '$name is generic; provide a subclass with fixed type arguments.',
      );
    }
    if (constructor == null) {
      return ConstructorModel.invalid(
        '$name has no unnamed constructor; dartnest creates it with '
        '$name(...).',
      );
    }
    if (element.isAbstract && !constructor.isFactory) {
      return ConstructorModel.invalid('$name is abstract.');
    }
    return ConstructorModel([
      for (final parameter in constructor.formalParameters)
        _dependency(element, parameter),
    ]);
  }

  DependencyModel _dependency(
    ClassElement owner,
    FormalParameterElement parameter,
  ) {
    final where = 'Parameter ${parameter.displayName} of ${owner.displayName}';
    if (parameter.isOptional) {
      return _invalid(
        parameter,
        '$where is optional; dartnest injects required positional and '
        'required named parameters only.',
      );
    }
    final inject = Annotations.find(parameter, 'Inject');
    if (inject != null) return _tokenDependency(owner, parameter, inject);
    if (!_isInjectable(parameter.type)) {
      return _invalid(
        parameter,
        '$where has type ${parameter.type.getDisplayString()}; dartnest '
        'injects non-nullable class types, or a Token with @Inject(token).',
      );
    }
    return _injected(parameter, TypeKey(TypeReader.read(parameter.type)));
  }

  DependencyModel _tokenDependency(
    ClassElement owner,
    FormalParameterElement parameter,
    DartObject inject,
  ) {
    final where = 'Parameter ${parameter.displayName} of ${owner.displayName}';
    final token = TokenReader.read(Annotations.field(inject, 'token'));
    if (token == null) {
      return _invalid(
        parameter,
        'The @Inject argument of $where is not a Token.',
      );
    }
    final (key, valueType) = token;
    if (!owner.library.typeSystem.isAssignableTo(valueType, parameter.type)) {
      return _invalid(
        parameter,
        '$where has type ${parameter.type.getDisplayString()}, but '
        '${key.display} provides ${key.valueType.display}.',
      );
    }
    return _injected(parameter, key);
  }

  DependencyModel _invalid(FormalParameterElement parameter, String problem) =>
      DependencyModel.invalid(
        name: parameter.displayName,
        isNamed: parameter.isNamed,
        location: locations.of(parameter),
        problem: problem,
      );

  DependencyModel _injected(
    FormalParameterElement parameter,
    ProviderKey key,
  ) => DependencyModel.injected(
    name: parameter.displayName,
    isNamed: parameter.isNamed,
    location: locations.of(parameter),
    key: key,
  );

  static bool _isInjectable(DartType type) =>
      type is InterfaceType &&
      type.nullabilitySuffix == NullabilitySuffix.none &&
      !type.isDartCoreObject;
}
```

`packages/dartnest_generator/lib/src/collector/injectable_reader.dart`:

```dart
import 'package:analyzer/dart/element/element.dart';

import '../model/injectable_model.dart';
import 'annotations.dart';
import 'constructor_reader.dart';
import 'source_locations.dart';
import 'type_reader.dart';

/// Reads a class that dependency injection creates: a provider class, a
/// `Bind` implementation or a controller.
final class InjectableReader {
  /// Creates the reader.
  InjectableReader(this.locations)
    : _constructors = ConstructorReader(locations);

  /// Locations of classes and parameters.
  final SourceLocations locations;

  final ConstructorReader _constructors;

  /// The model of [element].
  InjectableModel read(InterfaceElement element) => InjectableModel(
    type: TypeReader.read(element.thisType),
    isAnnotated: Annotations.find(element, 'Injectable') != null,
    constructor: _constructors.read(element),
    location: locations.of(element),
    documentation: element.documentationComment,
  );
}
```

`packages/dartnest_generator/lib/src/collector/module_reference_reader.dart`:

```dart
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/generated_names.dart';
import '../model/module_reference.dart';
import 'annotations.dart';
import 'type_reader.dart';

/// Reads a module reference in `imports` or `exports` of `@Module`: a
/// `@Module` class, or a tear-off of a function without required
/// parameters that returns a core `Module`.
final class ModuleReferenceReader {
  /// Creates the reader for package [packageName].
  ModuleReferenceReader(this.packageName);

  /// The package being generated.
  final String packageName;

  /// The reference [entry] denotes, or `null` when it is not a module.
  ModuleReference? read(DartObject entry) {
    if (entry.toTypeValue() case final InterfaceType type) {
      return _class(type);
    }
    if (entry.toFunctionValue() case final function?) {
      return _function(function);
    }
    return null;
  }

  /// Whether [type] is a `@Module` class.
  static bool isModuleClass(DartType type) =>
      type is InterfaceType && Annotations.find(type.element, 'Module') != null;

  ModuleReference? _class(InterfaceType type) {
    if (!isModuleClass(type)) return null;
    final uri = type.element.library.uri;
    if (uri.scheme != 'package' || uri.pathSegments.isEmpty) return null;
    final owner = uri.pathSegments.first;
    if (owner == packageName) {
      return LocalModuleReference(TypeReader.read(type));
    }
    return OpaqueModuleReference(
      name: GeneratedNames.module(type.element.displayName),
      libraryUri: GeneratedNames.library(owner),
    );
  }

  ModuleReference? _function(ExecutableElement function) {
    final name = function.name;
    final library = function.library;
    final enclosing = function.enclosingElement;
    final ok =
        name != null &&
        !function.formalParameters.any((p) => p.isRequired) &&
        TypeReader.isDartnest(function.returnType, 'Module') &&
        function.isPublic &&
        (function is TopLevelFunctionElement ||
            (function is MethodElement && function.isStatic));
    if (!ok) return null;
    return OpaqueModuleReference(
      name: name,
      libraryUri: '${library.uri}',
      enclosingName: enclosing is InterfaceElement ? enclosing.name : null,
    );
  }
}
```

`packages/dartnest_generator/lib/src/collector/provider_entry_reader.dart`:

```dart
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_system.dart';

import '../model/provider_key.dart';
import '../model/provider_model.dart';
import 'annotations.dart';
import 'constant_reader.dart';
import 'entry_read.dart';
import 'injectable_reader.dart';
import 'token_reader.dart';
import 'type_reader.dart';

/// Reads one entry of `@Module(providers: [...])`: a class, `Bind<K, I>()`
/// or `Value(v, token: t)`.
final class ProviderEntryReader {
  /// Creates the reader; [typeSystem] checks `Value` against its token.
  ProviderEntryReader(this.injectables, this.typeSystem);

  /// Reads provider classes.
  final InjectableReader injectables;

  /// The type system of the library being read.
  final TypeSystem typeSystem;

  /// The provider [entry] declares.
  EntryRead<ProviderModel> read(DartObject entry) {
    final type = entry.type;
    if (entry.toTypeValue() case final InterfaceType provided) {
      final key = TypeKey(TypeReader.read(provided));
      return ReadEntry(ClassProvider(key, injectables.read(provided.element)));
    }
    if (type is InterfaceType && _isAnnotation(type, 'Bind')) {
      return _bind(type);
    }
    if (type is InterfaceType && _isAnnotation(type, 'Value')) {
      return _value(entry);
    }
    return InvalidEntry(
      'providers: ${Annotations.describe(entry)} is not a class, Bind<K, I>() or '
      'Value(v).',
    );
  }

  EntryRead<ProviderModel> _bind(InterfaceType bind) {
    final [key, implementation] = bind.typeArguments;
    if (key is! InterfaceType || implementation is! InterfaceType) {
      return InvalidEntry(
        'providers: ${bind.getDisplayString()} must bind a class to a class.',
      );
    }
    return ReadEntry(
      ClassProvider(
        TypeKey(TypeReader.read(key)),
        injectables.read(implementation.element),
      ),
    );
  }

  EntryRead<ProviderModel> _value(DartObject entry) {
    final value = Annotations.field(entry, 'value');
    final valueType = value?.type;
    final tokenObject = Annotations.field(entry, 'token');
    if (value == null || valueType is! InterfaceType) {
      return const InvalidEntry(
        'providers: the value of Value(...) is not an object.',
      );
    }
    final expression = ConstantReader.read(value);
    if (tokenObject == null || tokenObject.isNull) {
      return ReadEntry(
        ValueProvider(TypeKey(TypeReader.read(valueType)), expression),
      );
    }
    final token = TokenReader.read(tokenObject);
    if (token == null) {
      return const InvalidEntry(
        'providers: the token of Value(...) is not a Token.',
      );
    }
    final (key, tokenType) = token;
    if (!typeSystem.isAssignableTo(valueType, tokenType)) {
      return InvalidEntry(
        'providers: Value(...) of type ${valueType.getDisplayString()} '
        'cannot be provided as ${key.display}.',
      );
    }
    return ReadEntry(ValueProvider(key, expression));
  }

  static bool _isAnnotation(InterfaceType type, String name) =>
      type.element.name == name &&
      '${type.element.library.uri}'.startsWith(Annotations.packageUri);
}
```

`packages/dartnest_generator/lib/src/collector/module_reader.dart`:

```dart
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/module_export.dart';
import '../model/module_model.dart';
import '../model/module_reference.dart';
import '../model/provider_key.dart';
import '../model/type_model.dart';
import 'annotations.dart';
import 'entry_read.dart';
import 'injectable_reader.dart';
import 'module_reference_reader.dart';
import 'provider_entry_reader.dart';
import 'source_locations.dart';
import 'token_reader.dart';
import 'type_reader.dart';

/// Reads a `@Module` class into a [ModuleModel]. Entries it cannot read go
/// to [ModuleModel.invalidEntries]; the module construct reports them.
final class ModuleReader {
  /// Creates the reader for package [packageName].
  ModuleReader(this.packageName, this.locations)
    : _references = ModuleReferenceReader(packageName),
      _injectables = InjectableReader(locations);

  /// The package being generated.
  final String packageName;

  /// Locations of declarations.
  final SourceLocations locations;

  final ModuleReferenceReader _references;

  final InjectableReader _injectables;

  /// The module declared by [element], whose `@Module` is [annotation].
  ModuleModel read(ClassElement element, DartObject annotation) {
    final providerReader = ProviderEntryReader(
      _injectables,
      element.library.typeSystem,
    );
    final imports = [for (final e in _list(annotation, 'imports')) _import(e)];
    final providers = [
      for (final e in _list(annotation, 'providers')) providerReader.read(e),
    ];
    final controllers = [
      for (final e in _list(annotation, 'controllers')) _controller(e),
    ];
    final exports = [for (final e in _list(annotation, 'exports')) _export(e)];
    return ModuleModel(
      type: TypeReader.read(element.thisType),
      id:
          Annotations.field(annotation, 'id')?.toStringValue() ??
          element.displayName,
      location: locations.of(element),
      imports: EntryRead.values(imports),
      providers: EntryRead.values(providers),
      controllers: EntryRead.values(controllers),
      exports: EntryRead.values(exports),
      isGlobal: Annotations.field(annotation, 'global')?.toBoolValue() ?? false,
      invalidEntries: EntryRead.problems([
        ...imports,
        ...providers,
        ...controllers,
        ...exports,
      ]),
      documentation: element.documentationComment,
    );
  }

  EntryRead<ModuleReference> _import(DartObject entry) =>
      switch (_references.read(entry)) {
        final reference? => ReadEntry(reference),
        null => _invalid('imports', entry, 'is not a module'),
      };

  EntryRead<TypeModel> _controller(DartObject entry) {
    final type = entry.toTypeValue();
    final local =
        type is InterfaceType &&
        Annotations.find(type.element, 'Controller') != null &&
        '${type.element.library.uri}'.startsWith('package:$packageName/');
    return local
        ? ReadEntry(TypeReader.read(type))
        : _invalid(
            'controllers',
            entry,
            'is not a @Controller class of this package',
          );
  }

  EntryRead<ModuleExport> _export(DartObject entry) {
    if (_references.read(entry) case final reference?) {
      return ReadEntry(ModuleReexport(reference));
    }
    if (entry.toTypeValue() case final InterfaceType type) {
      return ReadEntry(KeyExport(TypeKey(TypeReader.read(type))));
    }
    if (TokenReader.read(entry) case (final key, _)) {
      return ReadEntry(KeyExport(key));
    }
    return _invalid('exports', entry, 'is not a class, token or module');
  }

  static List<DartObject> _list(DartObject annotation, String name) =>
      Annotations.field(annotation, name)?.toListValue() ?? const [];

  static InvalidEntry<T> _invalid<T>(
    String field,
    DartObject entry,
    String what,
  ) => InvalidEntry('$field: ${Annotations.describe(entry)} $what.');
}
```

- [ ] **Step 5: Write the package collector**

Версія без контролерів; Task 5 замінює файл повністю.

`packages/dartnest_generator/lib/src/collector/package_collector.dart`:

```dart
import 'package:analyzer/dart/element/element.dart';
import 'package:pub_semver/pub_semver.dart';

import '../model/injectable_model.dart';
import '../model/module_model.dart';
import '../model/package_model.dart';
import 'annotations.dart';
import 'injectable_reader.dart';
import 'module_reader.dart';
import 'source_locations.dart';

/// Builds the [PackageModel] of one package from its resolved libraries.
///
/// The driver resolves every library of `lib/` (the CLI with an
/// `AnalysisContextCollection`, build_runner with its resolver) and passes
/// them here; the generated `*.dartnest.dart` is skipped.
final class PackageCollector {
  /// Creates the collector of package [packageName] rooted at
  /// [packageRoot] (an absolute path; locations are relative to it).
  PackageCollector(this.packageName, String packageRoot)
    : _locations = SourceLocations(packageRoot);

  /// The package being generated.
  final String packageName;

  final SourceLocations _locations;

  /// The model of [libraries], in library URI order whatever the input
  /// order.
  PackageModel collect(Iterable<LibraryElement> libraries) {
    final sorted = [
      for (final library in libraries)
        if (!'${library.uri}'.endsWith('.dartnest.dart')) library,
    ]..sort((a, b) => '${a.uri}'.compareTo('${b.uri}'));
    final modules = ModuleReader(packageName, _locations);
    final injectables = InjectableReader(_locations);
    final moduleModels = <ModuleModel>[];
    final injectableModels = <InjectableModel>[];
    for (final library in sorted) {
      for (final element in library.classes) {
        if (Annotations.find(element, 'Module') case final annotation?) {
          moduleModels.add(modules.read(element, annotation));
        }
        if (Annotations.find(element, 'Injectable') != null) {
          injectableModels.add(injectables.read(element));
        }
      }
    }
    return PackageModel(
      packageName: packageName,
      languageVersion: _languageVersion(sorted),
      modules: moduleModels,
      injectables: injectableModels,
    );
  }

  static Version _languageVersion(List<LibraryElement> libraries) {
    final version = libraries.firstOrNull?.languageVersion.package;
    return version == null
        ? Version(3, 8, 0)
        : Version(version.major, version.minor, 0);
  }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd packages/dartnest_generator && dart test test/collector/module_collector_test.dart`
Expected: `+8: All tests passed!`

Run: `cd packages/dartnest_generator && dart test`
Expected: `+21: All tests passed!`

- [ ] **Step 7: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 8: Commit**

```bash
git add \
  packages/dartnest_generator/test/helpers/fixture_package.dart \
  packages/dartnest_generator/test/fixtures/cases_app/lib/modules/basic.dart \
  packages/dartnest_generator/test/fixtures/cases_app/lib/modules/explicit.dart \
  packages/dartnest_generator/test/fixtures/cases_app/lib/modules/app.dart \
  packages/dartnest_generator/test/fixtures/cases_app/lib/modules/invalid_entries.dart \
  packages/dartnest_generator/test/fixtures/cases_app/lib/providers/constructors.dart \
  packages/dartnest_generator/test/collector/module_collector_test.dart \
  packages/dartnest_generator/lib/src/collector/entry_read.dart \
  packages/dartnest_generator/lib/src/collector/constructor_reader.dart \
  packages/dartnest_generator/lib/src/collector/injectable_reader.dart \
  packages/dartnest_generator/lib/src/collector/module_reference_reader.dart \
  packages/dartnest_generator/lib/src/collector/provider_entry_reader.dart \
  packages/dartnest_generator/lib/src/collector/module_reader.dart \
  packages/dartnest_generator/lib/src/collector/package_collector.dart
git commit -m "feat(generator): collect modules and injectable classes"
```

### Task 5: Збір контролерів, роутів і DTO

`ControllerReader` читає `@Controller(path)`: тип, конструктор (той самий `ConstructorReader`), компоненти класу (`EnhancersReader`: `@UseGuards/@UseInterceptors/@UsePipes/@UseFilters`, кожен тип позначено `isValid`, якщо він реалізує відповідний інтерфейс ядра), метадані (`Annotations.routeMetadata` → `ConstantValue`) і роути. `RouteReader` бере лише методи з `@Get/@Post/@Put/@Patch/@Delete` у порядку оголошення; static, generic або метод з кількома route-анотаціями отримує `problem`. `HandlerParameterReader` визначає `ParameterBinding` кожного параметра (OP9); що не вдається прив'язати, стає `InvalidBinding(problem)` з поясненням. `BodyKindReader` вирішує, як читати `@Body()` (OP6: `fromJson` — конструктор або static метод з одним параметром `Map<String, Object?>`/`Map<String, dynamic>`). `DtoReader` збирає `DtoModel` (поля, JSON-ім'я з `@JsonKey(name:)` будь-якої бібліотеки, тип, значення за замовчуванням, doc-коментар) для тіл і результатів хендлерів, розгортаючи `Future`, `List`, `Map`.

`PackageCollector` отримує контролери й DTO (повна заміна файлу). Фікстури: `controllers/components.dart` (guard, interceptor, pipe, filter, `Roles extends RouteMetadata`), `controllers/users.dart` (повний набір прив'язок, власний клас `JsonKey`), `controllers/invalid_handlers.dart` (усе, що Task 9 відхиляє).

**Files:**
- Create: `packages/dartnest_generator/test/fixtures/cases_app/lib/controllers/components.dart`
- Create: `packages/dartnest_generator/test/fixtures/cases_app/lib/controllers/users.dart`
- Create: `packages/dartnest_generator/test/fixtures/cases_app/lib/controllers/invalid_handlers.dart`
- Create: `packages/dartnest_generator/lib/src/collector/body_kind_reader.dart`
- Create: `packages/dartnest_generator/lib/src/collector/handler_parameter_reader.dart`
- Create: `packages/dartnest_generator/lib/src/collector/enhancers_reader.dart`
- Create: `packages/dartnest_generator/lib/src/collector/route_reader.dart`
- Create: `packages/dartnest_generator/lib/src/collector/controller_reader.dart`
- Create: `packages/dartnest_generator/lib/src/collector/dto_reader.dart`
- Modify: `packages/dartnest_generator/lib/src/collector/package_collector.dart`
- Test: `packages/dartnest_generator/test/collector/controller_collector_test.dart`

**Interfaces:**
- Consumes: Tasks 2–4 (`ConstructorReader`, `Annotations`, `TypeReader`, `ConstantReader`, `SourceLocations`, `EntryRead`).
- Produces (`packages/dartnest_generator/lib/src/collector/`):
  - `BodyKindReader`: `static BodyKind read(DartType type)`, `static bool hasFromJson(InterfaceElement element)`
  - `HandlerParameterReader(SourceLocations locations)`: `HandlerParameter read(FormalParameterElement parameter)`
  - `EnhancersReader`: `static EnhancersModel read(Element element)`
  - `RouteReader(SourceLocations locations)`: `List<RouteModel> read(ClassElement controller)`; `static const annotations = {'Get', 'Post', 'Put', 'Patch', 'Delete'}`
  - `ControllerReader(SourceLocations locations)`: `ControllerModel read(ClassElement element, DartObject annotation)`
  - `DtoReader`: `static List<DtoModel> read(Iterable<DartType> roots)` — відсортовані за бібліотекою й іменем
  - `PackageCollector.collect` тепер заповнює `controllers` і `dtos`

- [ ] **Step 1: Add the controller fixtures**

`packages/dartnest_generator/test/fixtures/cases_app/lib/controllers/components.dart`:

```dart
// Pipeline components and metadata shared by the controller scenarios.
import 'dart:async';

import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

/// Roles allowed to call a handler.
final class Roles extends RouteMetadata {
  /// Creates the metadata.
  const Roles(this.names);

  /// The role names.
  final List<String> names;
}

/// Lets every request through.
final class OpenGuard implements Guard {
  @override
  bool canActivate(ExecutionContext context) => true;
}

/// Passes the result through.
final class PassInterceptor implements Interceptor {
  @override
  FutureOr<Object?> intercept(ExecutionContext context, Next<Object?> next) =>
      next();
}

/// Trims strings.
final class TrimPipe implements Pipe<Object?, Object?> {
  @override
  Object? transform(Object? value, ArgumentMeta meta) =>
      value is String ? value.trim() : value;
}

/// Maps [StateError] to 404.
final class StateFilter extends ExceptionFilter<StateError> {
  @override
  Object? handle(StateError error, ExecutionContext context) =>
      throw const NotFoundException(message: 'Gone');
}
```

`packages/dartnest_generator/test/fixtures/cases_app/lib/controllers/users.dart`:

```dart
// A controller using every supported binding.
import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'components.dart';

/// Renames a JSON field, like `JsonKey` of json_serializable; the
/// generator matches it by name.
final class JsonKey {
  /// Creates the annotation.
  const JsonKey({this.name});

  /// The JSON name.
  final String? name;
}

/// User status.
enum Status { active, banned }

/// A user.
final class User {
  /// Creates a user.
  const User(this.id, this.name, {this.status = Status.active});

  /// The id.
  final int id;

  /// The display name.
  @JsonKey(name: 'display_name')
  final String name;

  /// The status.
  final Status status;

  /// The JSON form.
  Map<String, Object?> toJson() => {'id': id, 'display_name': name};
}

/// Body of `POST /users`.
final class CreateUser {
  /// Creates the body.
  const CreateUser(this.name);

  /// Reads the body.
  factory CreateUser.fromJson(Map<String, dynamic> json) =>
      CreateUser(json['name'] as String);

  /// The name.
  final String name;
}

/// Users.
@Controller('/users')
@UseGuards([OpenGuard])
@Roles(['admin'])
final class UsersController {
  /// Lists users.
  @Get()
  @UseInterceptors([PassInterceptor])
  Future<List<User>> list(
    @Query('limit') int? limit,
    @Query('status') Status? status,
  ) async => const [];

  /// Finds one user.
  @Get('/:id')
  User find(@Param('id') int id, @Header('x-trace') String? trace) =>
      User(id, 'ann');

  /// Creates a user.
  @Post()
  @UsePipes([TrimPipe])
  @UseFilters([StateFilter])
  @Roles(['owner'])
  User create(@Body() CreateUser body, ExecutionContext context) =>
      User(1, body.name);

  /// Stores a text body.
  @Put('/:id/note')
  void note(@Param('id') String id, @Body() String text, HttpRequest request) {}

  /// Stores a binary body.
  @Put('/:id/avatar')
  Future<void> avatar(@Param('id') String id, @Body() List<int> bytes) async {}

  /// Merges a JSON object.
  @Patch('/:id')
  Map<String, Object?> merge(@Body() Map<String, Object?> patch) => patch;

  /// Removes every user.
  @Delete()
  void clear() {}

  /// Not a route.
  void helper() {}
}
```

`packages/dartnest_generator/test/fixtures/cases_app/lib/controllers/invalid_handlers.dart`:

```dart
// Handlers and components the generator rejects.
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'components.dart';

/// No fromJson.
final class Opaque {
  /// The value.
  final int value = 0;
}

/// Every handler is wrong.
@Controller('/broken')
@UseGuards([PassInterceptor, String])
final class BrokenController {
  /// Unbound parameter.
  @Get('/a')
  int unbound(int value) => value;

  /// Two binding annotations.
  @Get('/b/:id')
  int twice(@Param('id') @Query('id') int id) => id;

  /// A list query.
  @Get('/c')
  int list(@Query('tags') List<String> tags) => tags.length;

  /// An int header.
  @Get('/d')
  int header(@Header('x-count') int count) => count;

  /// A body without fromJson.
  @Post('/e')
  int body(@Body() Opaque opaque) => opaque.value;

  /// Two routes.
  @Get('/f')
  @Post('/f')
  void twoRoutes() {}

  /// Static.
  @Get('/g')
  static void notInstance() {}

  /// Generic.
  @Get('/h')
  T generic<T>() => throw UnimplementedError();

  /// A path parameter the path does not declare.
  @Get('/i/:id')
  String unknown(@Param('slug') String slug) => slug;

  /// The first of two routes with one shape.
  @Get('/j/:a')
  void first() {}

  /// The second of two routes with one shape.
  @Get('/j/:b')
  void second() {}
}
```

- [ ] **Step 2: Write the failing test**

`packages/dartnest_generator/test/collector/controller_collector_test.dart`:

```dart
import 'package:dartnest_generator/src/collector/package_collector.dart';
import 'package:dartnest_generator/src/model/body_kind.dart';
import 'package:dartnest_generator/src/model/constant_value.dart';
import 'package:dartnest_generator/src/model/controller_model.dart';
import 'package:dartnest_generator/src/model/package_model.dart';
import 'package:dartnest_generator/src/model/parameter_binding.dart';
import 'package:dartnest_generator/src/model/route_model.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

String _binding(ParameterBinding binding) => switch (binding) {
  PathBinding(:final name) => 'path $name',
  QueryBinding(:final name) => 'query $name',
  HeaderBinding(:final name) => 'header $name',
  BodyBinding(:final kind) => 'body ${kind.name}',
  ContextBinding() => 'context',
  RequestBinding() => 'request',
  InvalidBinding(:final problem) => problem,
};

void main() {
  late PackageModel package; // Set in setUpAll.

  setUpAll(() async {
    final fixture = FixturePackage.open('cases_app');
    final libraries = await fixture.libraries([
      'lib/controllers/users.dart',
      'lib/controllers/invalid_handlers.dart',
    ]);
    package = PackageCollector('cases_app', fixture.root).collect(libraries);
  });

  ControllerModel controller(String name) =>
      package.controllers.firstWhere((c) => c.type.name == name);

  RouteModel route(String controllerName, String handler) => controller(
    controllerName,
  ).routes.firstWhere((r) => r.handlerName == handler);

  List<String> bindings(String controllerName, String handler) => [
    for (final p in route(controllerName, handler).parameters)
      '${p.name}: ${_binding(p.binding)}',
  ];

  test('a controller keeps its path, enhancers and metadata', () {
    final users = controller('UsersController');

    expect(users.path, '/users');
    expect(users.documentation, '/// Users.');
    expect(
      [for (final g in users.enhancers.guards) g.type.name],
      ['OpenGuard'],
    );
    final roles = users.metadata.single as ObjectConstant;
    expect(roles.type.name, 'Roles');
    expect(users.constructor.dependencies, isEmpty);
  });

  test('routes in declaration order, without plain methods', () {
    expect(
      [
        for (final r in controller('UsersController').routes)
          '${r.method} ${r.path} ${r.handlerName}',
      ],
      [
        'GET  list',
        'GET /:id find',
        'POST  create',
        'PUT /:id/note note',
        'PUT /:id/avatar avatar',
        'PATCH /:id merge',
        'DELETE  clear',
      ],
    );
    expect(
      route('UsersController', 'list').returnType.display,
      'Future<List<User>>',
    );
  });

  test('route enhancers and metadata', () {
    final create = route('UsersController', 'create');

    expect(create.enhancers.pipes.single.type.name, 'TrimPipe');
    expect(create.enhancers.filters.single.isValid, isTrue);
    expect(create.metadata.single, isA<ObjectConstant>());
    expect(
      route('UsersController', 'list').enhancers.interceptors.single.isValid,
      isTrue,
    );
    expect(create.problem, isNull);
  });

  test('parameters bind to path, query, header, body, context, request', () {
    expect(bindings('UsersController', 'list'), [
      'limit: query limit',
      'status: query status',
    ]);
    expect(bindings('UsersController', 'find'), [
      'id: path id',
      'trace: header x-trace',
    ]);
    expect(bindings('UsersController', 'create'), [
      'body: body fromJson',
      'context: context',
    ]);
    expect(bindings('UsersController', 'note'), [
      'id: path id',
      'text: body text',
      'request: request',
    ]);
    expect(bindings('UsersController', 'avatar').last, 'bytes: body bytes');
    expect(bindings('UsersController', 'merge'), ['patch: body jsonObject']);
  });

  test('parameters the generator cannot bind', () {
    expect(bindings('BrokenController', 'unbound'), [
      'value: Parameter value (int) needs @Param, @Query, @Header or @Body, '
          'or the type ExecutionContext or HttpRequest.',
    ]);
    expect(bindings('BrokenController', 'twice'), [
      'id: Parameter id (int) has more than one of @Param, @Query, @Header '
          'and @Body.',
    ]);
    expect(bindings('BrokenController', 'list'), [
      'tags: Parameter tags (List<String>): @Query supports String, int, '
          'double, num, bool, DateTime and enums, nullable or not.',
    ]);
    expect(bindings('BrokenController', 'header'), [
      'count: Parameter count (int): a @Header parameter is String or '
          'String?.',
    ]);
    expect(
      route('BrokenController', 'body').parameters.single.binding,
      isA<BodyBinding>().having((b) => b.kind, 'kind', BodyKind.unsupported),
    );
  });

  test('handlers that cannot be routes', () {
    expect(
      route('BrokenController', 'twoRoutes').problem,
      'Handler BrokenController.twoRoutes has more than one route annotation.',
    );
    expect(
      route('BrokenController', 'notInstance').problem,
      'Handler BrokenController.notInstance is static.',
    );
    expect(
      route('BrokenController', 'generic').problem,
      'Handler BrokenController.generic is generic.',
    );
  });

  test('components of the wrong kind are invalid', () {
    final guards = controller('BrokenController').enhancers.guards;

    expect(
      [for (final g in guards) '${g.type.name} ${g.isValid}'],
      ['PassInterceptor false', 'String false'],
    );
  });

  test('data classes of bodies and results', () {
    expect(
      [for (final d in package.dtos) d.type.name],
      ['Opaque', 'CreateUser', 'User'],
    );
    final user = package.dtos.last;
    expect(user.hasFromJson, isFalse);
    expect(
      [for (final f in user.fields) '${f.name}/${f.jsonName}: ${f.type}'],
      ['id/id: int', 'name/display_name: String', 'status/status: Status'],
    );
    expect(user.fields.last.defaultValue, 'Status.active');
    expect(package.dtos[1].hasFromJson, isTrue);
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd packages/dartnest_generator && dart test test/collector/controller_collector_test.dart`
Expected: FAIL: `+0 -8` — collector ще не читає контролери й DTO (`Bad state: No element` у пошуку контролера, `Actual: []` для DTO)

- [ ] **Step 4: Write the controller readers**

`packages/dartnest_generator/lib/src/collector/body_kind_reader.dart`:

```dart
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/body_kind.dart';

/// Decides how a `@Body()` parameter of a given type is read.
abstract final class BodyKindReader {
  /// The body kind of [type]: a class with `fromJson(Map<String, ...>)`, a
  /// JSON object map, `String` text or `List<int>` bytes.
  static BodyKind read(DartType type) {
    if (type is! InterfaceType ||
        type.nullabilitySuffix != NullabilitySuffix.none) {
      return BodyKind.unsupported;
    }
    if (type.isDartCoreString) return BodyKind.text;
    if (type.isDartCoreList && type.typeArguments.single.isDartCoreInt) {
      return BodyKind.bytes;
    }
    if (_isJsonObject(type)) return BodyKind.jsonObject;
    return hasFromJson(type.element) ? BodyKind.fromJson : BodyKind.unsupported;
  }

  /// Whether [element] has a `fromJson` constructor or static method whose
  /// only required parameter takes a `Map<String, ...>`.
  static bool hasFromJson(InterfaceElement element) {
    final ExecutableElement? fromJson =
        element.getNamedConstructor('fromJson') ??
        element.getMethod('fromJson');
    if (fromJson == null ||
        (fromJson is MethodElement && !fromJson.isStatic) ||
        element.typeParameters.isNotEmpty) {
      return false;
    }
    final required = [
      for (final parameter in fromJson.formalParameters)
        if (parameter.isRequired) parameter,
    ];
    return required.length == 1 &&
        required.single.isPositional &&
        _isJsonObject(required.single.type);
  }

  static bool _isJsonObject(DartType type) =>
      type is InterfaceType &&
      type.isDartCoreMap &&
      type.typeArguments.first.isDartCoreString &&
      switch (type.typeArguments.last) {
        DynamicType() => true,
        final InterfaceType value =>
          value.isDartCoreObject &&
              value.nullabilitySuffix == NullabilitySuffix.question,
        _ => false,
      };
}
```

`packages/dartnest_generator/lib/src/collector/handler_parameter_reader.dart`:

```dart
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/handler_parameter.dart';
import '../model/parameter_binding.dart';
import 'annotations.dart';
import 'body_kind_reader.dart';
import 'source_locations.dart';
import 'type_reader.dart';

/// Reads how a handler parameter is filled from the request.
final class HandlerParameterReader {
  /// Creates the reader.
  HandlerParameterReader(this.locations);

  /// Locations of parameters.
  final SourceLocations locations;

  static const _arguments = {'Param', 'Query', 'Header', 'Body'};

  static const _scalars = {
    'String',
    'int',
    'double',
    'num',
    'bool',
    'DateTime',
  };

  /// The model of [parameter].
  HandlerParameter read(FormalParameterElement parameter) => HandlerParameter(
    name: parameter.displayName,
    type: TypeReader.read(parameter.type),
    binding: _binding(parameter),
    isNamed: parameter.isNamed,
    location: locations.of(parameter),
  );

  ParameterBinding _binding(FormalParameterElement parameter) {
    final type = parameter.type;
    final annotations = Annotations.all(parameter, _arguments);
    final shown = '${parameter.displayName} (${type.getDisplayString()})';
    if (annotations.length > 1) {
      return InvalidBinding(
        'Parameter $shown has more than one of @Param, '
        '@Query, @Header and @Body.',
      );
    }
    if (annotations.isEmpty) return _unannotated(type, shown);
    final annotation = annotations.single;
    final name = Annotations.field(annotation, 'name')?.toStringValue() ?? '';
    return switch (annotation.type?.element?.name) {
      'Param' when _isScalar(type) => PathBinding(name),
      'Query' when _isScalar(type) => QueryBinding(name),
      'Header' when type.isDartCoreString => HeaderBinding(name),
      'Header' => InvalidBinding(
        'Parameter $shown: a @Header parameter is String or String?.',
      ),
      'Body' => BodyBinding(BodyKindReader.read(type)),
      _ => _unsupportedScalar(annotation, shown),
    };
  }

  static ParameterBinding _unannotated(DartType type, String shown) {
    if (TypeReader.isDartnest(type, 'ExecutionContext')) {
      return const ContextBinding();
    }
    if (TypeReader.isDartnest(type, 'HttpRequest')) {
      return const RequestBinding();
    }
    return InvalidBinding(
      'Parameter $shown needs @Param, @Query, @Header or @Body, or the type '
      'ExecutionContext or HttpRequest.',
    );
  }

  static bool _isScalar(DartType type) =>
      type is InterfaceType &&
      (type.element is EnumElement ||
          (type.element.library.isDartCore &&
              _scalars.contains(type.element.name)));

  static ParameterBinding _unsupportedScalar(
    DartObject annotation,
    String shown,
  ) => InvalidBinding(
    'Parameter $shown: @${annotation.type?.element?.name} supports String, '
    'int, double, num, bool, DateTime and enums, nullable or not.',
  );
}
```

`packages/dartnest_generator/lib/src/collector/enhancers_reader.dart`:

```dart
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/component_reference.dart';
import '../model/enhancers_model.dart';
import '../model/type_kind.dart';
import '../model/type_model.dart';
import 'annotations.dart';
import 'type_reader.dart';

/// Reads `@UseGuards`, `@UseInterceptors`, `@UsePipes` and `@UseFilters`
/// of a controller class or a handler method.
abstract final class EnhancersReader {
  /// The enhancers declared on [element]; several annotations of one kind
  /// add up in declaration order.
  static EnhancersModel read(Element element) => EnhancersModel(
    guards: _components(element, 'UseGuards', 'Guard'),
    interceptors: _components(element, 'UseInterceptors', 'Interceptor'),
    pipes: _components(element, 'UsePipes', 'Pipe'),
    filters: _components(element, 'UseFilters', 'ExceptionFilter'),
  );

  static List<ComponentReference> _components(
    Element element,
    String annotation,
    String interface,
  ) => [
    for (final use in Annotations.all(element, {annotation}))
      for (final type in _types(use)) _component(type, interface),
  ];

  static List<DartType?> _types(DartObject use) => [
    for (final entry
        in Annotations.field(use, 'types')?.toListValue() ??
            const <DartObject>[])
      entry.toTypeValue(),
  ];

  static ComponentReference _component(DartType? type, String interface) =>
      switch (type) {
        InterfaceType(:final element) => ComponentReference(
          TypeReader.read(type),
          isValid: TypeReader.hasSupertype(
            element,
            interface,
            'package:dartnest/',
          ),
        ),
        _ => ComponentReference(
          TypeModel(name: '$type', kind: TypeKind.unsupported),
          isValid: false,
        ),
      };
}
```

`packages/dartnest_generator/lib/src/collector/route_reader.dart`:

```dart
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';

import '../model/route_model.dart';
import 'annotations.dart';
import 'constant_reader.dart';
import 'enhancers_reader.dart';
import 'handler_parameter_reader.dart';
import 'source_locations.dart';
import 'type_reader.dart';

/// Reads the handler methods of a `@Controller` class.
final class RouteReader {
  /// Creates the reader.
  RouteReader(this.locations) : _parameters = HandlerParameterReader(locations);

  /// Locations of methods and parameters.
  final SourceLocations locations;

  final HandlerParameterReader _parameters;

  /// The names of the route annotations.
  static const annotations = {'Get', 'Post', 'Put', 'Patch', 'Delete'};

  /// The routes of [controller]: one per method with a route annotation,
  /// in declaration order.
  List<RouteModel> read(ClassElement controller) => [
    for (final method in controller.methods)
      if (Annotations.all(method, annotations) case [
        final first,
        ...final rest,
      ])
        _route(method, first, rest.isEmpty),
  ];

  RouteModel _route(MethodElement method, DartObject route, bool isSingle) =>
      RouteModel(
        method: Annotations.field(route, 'method')?.toStringValue() ?? 'GET',
        path: Annotations.field(route, 'path')?.toStringValue() ?? '',
        handlerName: method.displayName,
        returnType: TypeReader.read(method.returnType),
        location: locations.of(method),
        parameters: [
          for (final parameter in method.formalParameters)
            _parameters.read(parameter),
        ],
        enhancers: EnhancersReader.read(method),
        metadata: [
          for (final value in Annotations.routeMetadata(method))
            ConstantReader.read(value),
        ],
        documentation: method.documentationComment,
        problem: _problem(method, isSingle),
      );

  static String? _problem(MethodElement method, bool isSingle) {
    final name =
        '${method.enclosingElement?.displayName}.${method.displayName}';
    if (!isSingle) return 'Handler $name has more than one route annotation.';
    if (method.isStatic) return 'Handler $name is static.';
    if (method.isPrivate) return 'Handler $name is private.';
    if (method.typeParameters.isNotEmpty) return 'Handler $name is generic.';
    return null;
  }
}
```

`packages/dartnest_generator/lib/src/collector/controller_reader.dart`:

```dart
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';

import '../model/controller_model.dart';
import 'annotations.dart';
import 'constant_reader.dart';
import 'constructor_reader.dart';
import 'enhancers_reader.dart';
import 'route_reader.dart';
import 'source_locations.dart';
import 'type_reader.dart';

/// Reads a `@Controller` class into a [ControllerModel].
final class ControllerReader {
  /// Creates the reader.
  ControllerReader(this.locations)
    : _constructors = ConstructorReader(locations),
      _routes = RouteReader(locations);

  /// Locations of declarations.
  final SourceLocations locations;

  final ConstructorReader _constructors;

  final RouteReader _routes;

  /// The controller declared by [element], whose `@Controller` is
  /// [annotation].
  ControllerModel read(ClassElement element, DartObject annotation) =>
      ControllerModel(
        type: TypeReader.read(element.thisType),
        path: Annotations.field(annotation, 'path')?.toStringValue() ?? '',
        constructor: _constructors.read(element),
        location: locations.of(element),
        enhancers: EnhancersReader.read(element),
        metadata: [
          for (final value in Annotations.routeMetadata(element))
            ConstantReader.read(value),
        ],
        routes: _routes.read(element),
        documentation: element.documentationComment,
      );
}
```

`packages/dartnest_generator/lib/src/collector/dto_reader.dart`:

```dart
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/dto_field.dart';
import '../model/dto_model.dart';
import 'body_kind_reader.dart';
import 'type_reader.dart';

/// Collects the data classes that travel as request bodies and handler
/// results, for the documentation constructs of later versions.
abstract final class DtoReader {
  static const _containers = {'Future', 'FutureOr', 'List', 'Iterable', 'Set'};

  /// The data classes reachable from [roots] (body and return types), each
  /// once, following `Future`, `FutureOr`, `List`, `Iterable`, `Set` and
  /// field types; sorted by library URI and name.
  static List<DtoModel> read(Iterable<DartType> roots) {
    final seen = <InterfaceElement>{};
    final pending = [
      for (final root in roots)
        if (_dataClass(root) case final element?) element,
    ];
    final dtos = <DtoModel>[];
    while (pending.isNotEmpty) {
      final element = pending.removeLast();
      if (!seen.add(element)) continue;
      dtos.add(_dto(element));
      for (final field in _fields(element)) {
        if (_dataClass(field.type) case final nested?) pending.add(nested);
      }
    }
    return dtos..sort(
      (a, b) => '${a.type.libraryUri}#${a.type.name}'.compareTo(
        '${b.type.libraryUri}#${b.type.name}',
      ),
    );
  }

  static InterfaceElement? _dataClass(DartType type) {
    if (type is! InterfaceType) return null;
    final element = type.element;
    if (_containers.contains(element.name) && element.library.isInSdk) {
      return type.typeArguments.isEmpty
          ? null
          : _dataClass(type.typeArguments.single);
    }
    final uri = '${element.library.uri}';
    final isData =
        element is ClassElement &&
        element.typeParameters.isEmpty &&
        !element.library.isInSdk &&
        !uri.startsWith('package:dartnest/');
    return isData ? element : null;
  }

  static DtoModel _dto(InterfaceElement element) => DtoModel(
    type: TypeReader.read(element.thisType),
    fields: [
      for (final field in _fields(element))
        DtoField(
          name: field.displayName,
          jsonName: _jsonName(field) ?? field.displayName,
          type: TypeReader.read(field.type),
          defaultValue: _defaultValue(element, field.displayName),
          documentation: field.documentationComment,
        ),
    ],
    hasFromJson: BodyKindReader.hasFromJson(element),
    documentation: element.documentationComment,
  );

  static List<FieldElement> _fields(InterfaceElement element) => [
    for (final field in element.fields)
      if (!field.isStatic && field.isPublic && field.nonSynthetic == field)
        field,
  ];

  static String? _jsonName(FieldElement field) {
    for (final annotation in field.metadata.annotations) {
      final value = annotation.computeConstantValue();
      if (value?.type?.element?.name == 'JsonKey') {
        return value?.getField('name')?.toStringValue();
      }
    }
    return null;
  }

  static String? _defaultValue(InterfaceElement element, String name) => element
      .unnamedConstructor
      ?.formalParameters
      .where((parameter) => parameter.displayName == name)
      .firstOrNull
      ?.defaultValueCode;
}
```

- [ ] **Step 5: Collect controllers and data classes**

Повна заміна `package_collector.dart`:

`packages/dartnest_generator/lib/src/collector/package_collector.dart`:

```dart
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:pub_semver/pub_semver.dart';

import '../model/controller_model.dart';
import '../model/injectable_model.dart';
import '../model/module_model.dart';
import '../model/package_model.dart';
import 'annotations.dart';
import 'controller_reader.dart';
import 'dto_reader.dart';
import 'injectable_reader.dart';
import 'module_reader.dart';
import 'route_reader.dart';
import 'source_locations.dart';

/// Builds the [PackageModel] of one package from its resolved libraries.
///
/// The driver resolves every library of `lib/` (the CLI with an
/// `AnalysisContextCollection`, build_runner with its resolver) and passes
/// them here; the generated `*.dartnest.dart` is skipped.
final class PackageCollector {
  /// Creates the collector of package [packageName] rooted at
  /// [packageRoot] (an absolute path; locations are relative to it).
  PackageCollector(this.packageName, String packageRoot)
    : _locations = SourceLocations(packageRoot);

  /// The package being generated.
  final String packageName;

  final SourceLocations _locations;

  /// The model of [libraries], in library URI order whatever the input
  /// order.
  PackageModel collect(Iterable<LibraryElement> libraries) {
    final sorted = [
      for (final library in libraries)
        if (!'${library.uri}'.endsWith('.dartnest.dart')) library,
    ]..sort((a, b) => '${a.uri}'.compareTo('${b.uri}'));
    final modules = ModuleReader(packageName, _locations);
    final injectables = InjectableReader(_locations);
    final controllers = ControllerReader(_locations);
    final moduleModels = <ModuleModel>[];
    final injectableModels = <InjectableModel>[];
    final controllerModels = <ControllerModel>[];
    final dtoRoots = <DartType>[];
    for (final element in [for (final l in sorted) ...l.classes]) {
      if (Annotations.find(element, 'Module') case final annotation?) {
        moduleModels.add(modules.read(element, annotation));
      }
      if (Annotations.find(element, 'Injectable') != null) {
        injectableModels.add(injectables.read(element));
      }
      if (Annotations.find(element, 'Controller') case final annotation?) {
        controllerModels.add(controllers.read(element, annotation));
        dtoRoots.addAll(_dtoRoots(element));
      }
    }
    return PackageModel(
      packageName: packageName,
      languageVersion: _languageVersion(sorted),
      modules: moduleModels,
      injectables: injectableModels,
      controllers: controllerModels,
      dtos: DtoReader.read(dtoRoots),
    );
  }

  static List<DartType> _dtoRoots(ClassElement controller) => [
    for (final method in controller.methods)
      if (Annotations.all(method, RouteReader.annotations).isNotEmpty) ...[
        method.returnType,
        for (final parameter in method.formalParameters)
          if (Annotations.find(parameter, 'Body') != null) parameter.type,
      ],
  ];

  static Version _languageVersion(List<LibraryElement> libraries) {
    final version = libraries.firstOrNull?.languageVersion.package;
    return version == null
        ? Version(3, 8, 0)
        : Version(version.major, version.minor, 0);
  }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd packages/dartnest_generator && dart test test/collector/controller_collector_test.dart`
Expected: `+8: All tests passed!`

Run: `cd packages/dartnest_generator && dart test`
Expected: `+29: All tests passed!`

- [ ] **Step 7: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 8: Commit**

```bash
git add \
  packages/dartnest_generator/test/fixtures/cases_app/lib/controllers/components.dart \
  packages/dartnest_generator/test/fixtures/cases_app/lib/controllers/users.dart \
  packages/dartnest_generator/test/fixtures/cases_app/lib/controllers/invalid_handlers.dart \
  packages/dartnest_generator/test/collector/controller_collector_test.dart \
  packages/dartnest_generator/lib/src/collector/body_kind_reader.dart \
  packages/dartnest_generator/lib/src/collector/handler_parameter_reader.dart \
  packages/dartnest_generator/lib/src/collector/enhancers_reader.dart \
  packages/dartnest_generator/lib/src/collector/route_reader.dart \
  packages/dartnest_generator/lib/src/collector/controller_reader.dart \
  packages/dartnest_generator/lib/src/collector/dto_reader.dart \
  packages/dartnest_generator/lib/src/collector/package_collector.dart
git commit -m "feat(generator): collect controllers, routes and data classes"
```

### Task 6: API конструктів, `DartnestGenerator` і запис бібліотеки

Інтерфейс розширення зі специфікації (розділ 6): `Construct.validate(PackageModel) → Iterable<Diagnostic>`, `Construct.generate(PackageModel) → Iterable<GeneratedUnit>`. `GeneratedUnit` — sealed: `DartUnit` (ім'я, `code_builder`-`Spec`, `origin` для діагностики дубліката імені) або `FileUnit` (`path`, `ContentType` `json|yaml|text`, `content`), який драйвер запише як є. `DartnestGenerator(constructs).generate(package)` спершу запускає всі `validate`; якщо є хоч одна діагностика, `generate` конструктів не викликається, а результат — `GenerationResult.failed` з дедуплікованими й відсортованими діагностиками. Інакше `DartUnit` з однаковим `name` дають `duplicate_generated_name` (на `origin` кожного, крім першого), а решта йде в `LibraryWriter.write` (рішення 1).

Шар emit: `DartString.literal` (Review Focus 1), `ImportAllocator`, `TypeEmitter.reference` (аргументи типу й `?`), `ConstantEmitter.expression`/`list` (`const` лише на верхньому рівні; `UnsupportedConstant` кидає `StateError` — конструкти не пропускають його до генерації). `DartnestGenerator.core()` з'явиться в Task 10, коли існуватимуть усі три конструкти.

Тест `types keep arguments and nullability` будує тип через `Method.returns`, а не `declareFinal(name, type:)`: у `code_builder` 4.11.1 (нижній край залежності) `declareFinal` губить аргументи типу.

**Files:**
- Create: `packages/dartnest_generator/lib/src/emit/dart_string.dart`
- Create: `packages/dartnest_generator/lib/src/emit/import_allocator.dart`
- Create: `packages/dartnest_generator/lib/src/emit/type_emitter.dart`
- Create: `packages/dartnest_generator/lib/src/emit/constant_emitter.dart`
- Create: `packages/dartnest_generator/lib/src/emit/library_writer.dart`
- Create: `packages/dartnest_generator/lib/src/construct/construct.dart`
- Create: `packages/dartnest_generator/lib/src/construct/generated_unit.dart`
- Create: `packages/dartnest_generator/lib/src/construct/generation_result.dart`
- Create: `packages/dartnest_generator/lib/src/construct/dartnest_generator.dart`
- Modify: `packages/dartnest_generator/lib/dartnest_generator.dart`
- Test: `packages/dartnest_generator/test/emit/emit_test.dart`
- Test: `packages/dartnest_generator/test/construct/dartnest_generator_test.dart`

**Interfaces:**
- Consumes: модель і діагностики (Task 2).
- Produces:
  - `construct/construct.dart`: `abstract interface class Construct { Iterable<Diagnostic> validate(PackageModel package); Iterable<GeneratedUnit> generate(PackageModel package); }`
  - `construct/generated_unit.dart`: `sealed class GeneratedUnit`; `DartUnit({required String name, required Spec spec, required SourceLocation origin})`; `enum ContentType { json, yaml, text }`; `FileUnit({required String path, required ContentType contentType, required String content})`
  - `construct/generation_result.dart`: `GenerationResult.failed(List<Diagnostic> diagnostics)`, `GenerationResult.generated({required String library, List<FileUnit> files = const []})`, `bool get isSuccess`
  - `construct/dartnest_generator.dart`: `const DartnestGenerator(List<Construct> constructs)`, `GenerationResult generate(PackageModel package)`
  - `emit/`: `DartString.literal(String) → String`; `ImportAllocator` (`static const dartnest = 'package:dartnest/dartnest.dart'`); `TypeEmitter.reference(TypeModel) → TypeReference`; `ConstantEmitter.expression(ConstantValue) → Expression`, `ConstantEmitter.list(List<ConstantValue>) → Expression` (`const [...]`); `LibraryWriter.write({required String packageName, required Version languageVersion, required List<Spec> declarations}) → String`, `LibraryWriter.header`
  - barrel: + `PackageCollector`, `Construct`, `GeneratedUnit`, `GenerationResult`, `DartnestGenerator`, `LibraryWriter`

- [ ] **Step 1: Write the failing tests**

`packages/dartnest_generator/test/emit/emit_test.dart`:

```dart
import 'package:code_builder/code_builder.dart';
import 'package:dartnest_generator/src/emit/constant_emitter.dart';
import 'package:dartnest_generator/src/emit/dart_string.dart';
import 'package:dartnest_generator/src/emit/library_writer.dart';
import 'package:dartnest_generator/src/emit/type_emitter.dart';
import 'package:dartnest_generator/src/model/constant_value.dart';
import 'package:dartnest_generator/src/model/type_kind.dart';
import 'package:dartnest_generator/src/model/type_model.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

const _app = 'package:app/roles.dart';

const _string = TypeModel(
  name: 'String',
  kind: TypeKind.interface,
  libraryUri: 'dart:core',
);

const _roles = TypeModel(
  name: 'Roles',
  kind: TypeKind.interface,
  libraryUri: _app,
);

String _library(List<Spec> declarations) => LibraryWriter.write(
  packageName: 'app',
  languageVersion: Version(3, 8, 0),
  declarations: declarations,
);

Spec _final(String name, Expression value) =>
    declareFinal(name).assign(value).statement;

void main() {
  // Review Focus 1: quotes, dollars, backslashes and line separators.
  test('user strings are escaped completely', () {
    expect(DartString.literal(r"it's $id \ ok"), r"'it\'s \$id \\ ok'");
    expect(DartString.literal('a\nb\tc\u0001 '), r"'a\nb\tc\u{1}\u{2028}'");
    expect(DartString.literal('привіт'), "'привіт'");
  });

  test('a library imports dartnest by name and the rest as i1, i2', () {
    final source = _library([
      _final('a', refer('Module', 'package:dartnest/src/di/module.dart')),
      _final('b', refer('Roles', _app)),
      _final('c', refer('Other', 'package:app/other.dart')),
      _final('d', refer('Roles', _app)),
    ]);

    expect(source, startsWith('${LibraryWriter.header}\n'));
    expect(source, contains("import 'package:app/other.dart' as i2;"));
    expect(source, contains("import 'package:app/roles.dart' as i1;"));
    expect(
      source,
      contains("import 'package:dartnest/dartnest.dart' as dartnest;"),
    );
    expect(source, contains('final a = dartnest.Module;'));
    expect(source, contains('final d = i1.Roles;'));
  });

  test('a constructor call is const at the top only', () {
    final roles = ObjectConstant(
      type: _roles,
      constructorName: '',
      positional: [
        ListConstant(_string, [StringConstant(r'a$')]),
      ],
      named: {'level': NumberConstant('2')},
    );

    expect(
      _library([_final('x', ConstantEmitter.expression(roles))]),
      contains(r"final x = const i1.Roles(<String>['a\$'], level: 2);"),
    );
    expect(
      _library([
        _final('x', ConstantEmitter.list([roles])),
      ]),
      contains(
        'final x = const [\n'
        r"  i1.Roles(<String>['a\$'], level: 2),"
        '\n];',
      ),
    );
  });

  test('references, enum values, types, maps and sets', () {
    final values = [
      const ReferenceConstant(name: 'dbUrl', libraryUri: _app),
      const ReferenceConstant(
        name: 'banned',
        libraryUri: _app,
        enclosingName: 'Status',
      ),
      const TypeConstant(_roles),
      MapConstant(_string, _string, [
        (const StringConstant('k'), const NullConstant()),
      ]),
      SetConstant(_string, [const BoolConstant(true)]),
    ];

    final source = _library([
      for (final (index, value) in values.indexed)
        _final('v$index', ConstantEmitter.expression(value)),
    ]);

    expect(source, contains('final v0 = i1.dbUrl;'));
    expect(source, contains('final v1 = i1.Status.banned;'));
    expect(source, contains('final v2 = i1.Roles;'));
    expect(source, contains("final v3 = const <String, String>{'k': null};"));
    expect(source, contains('final v4 = const <String>{true};'));
  });

  test('types keep arguments and nullability', () {
    const list = TypeModel(
      name: 'List',
      kind: TypeKind.interface,
      libraryUri: 'dart:core',
      typeArguments: [_roles],
      isNullable: true,
    );

    expect(
      _library([
        Method(
          (b) => b
            ..name = 't'
            ..returns = TypeEmitter.reference(list)
            ..lambda = true
            ..body = literalNull.code,
        ),
      ]),
      contains('List<i1.Roles>? t() => null;'),
    );
  });

  test('an unsupported constant never reaches generation', () {
    expect(
      () => ConstantEmitter.expression(const UnsupportedConstant('x')),
      throwsStateError,
    );
  });
}
```

`packages/dartnest_generator/test/construct/dartnest_generator_test.dart`:

```dart
import 'package:code_builder/code_builder.dart';
import 'package:dartnest_generator/src/construct/construct.dart';
import 'package:dartnest_generator/src/construct/dartnest_generator.dart';
import 'package:dartnest_generator/src/construct/generated_unit.dart';
import 'package:dartnest_generator/src/diagnostic/diagnostic.dart';
import 'package:dartnest_generator/src/diagnostic/diagnostic_code.dart';
import 'package:dartnest_generator/src/diagnostic/source_location.dart';
import 'package:dartnest_generator/src/model/package_model.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

final _package = PackageModel(
  packageName: 'app',
  languageVersion: Version(3, 8, 0),
);

/// A construct with fixed output.
final class _FixedConstruct implements Construct {
  _FixedConstruct({this.diagnostics = const [], this.units = const []});

  final List<Diagnostic> diagnostics;

  final List<GeneratedUnit> units;

  int generated = 0;

  @override
  Iterable<Diagnostic> validate(PackageModel package) => diagnostics;

  @override
  Iterable<GeneratedUnit> generate(PackageModel package) {
    generated++;
    return units;
  }
}

DartUnit _function(String name, int line) => DartUnit(
  name: name,
  spec: Method(
    (b) => b
      ..name = name
      ..returns = refer('int')
      ..lambda = true
      ..body = literalNum(line).code,
  ),
  origin: SourceLocation('lib/app.dart', line, 1),
);

Diagnostic _error(int line) => Diagnostic(
  DiagnosticCode.missingProvider,
  SourceLocation('lib/app.dart', line, 1),
  'No provider.',
);

void main() {
  test('joins the Dart units of every construct into one library', () {
    final result = DartnestGenerator([
      _FixedConstruct(units: [_function('one', 1)]),
      _FixedConstruct(
        units: [
          _function('two', 2),
          const FileUnit(
            path: 'doc/api.json',
            contentType: ContentType.json,
            content: '{}',
          ),
        ],
      ),
    ]).generate(_package);

    expect(result.isSuccess, isTrue);
    expect(result.library, contains('int one() => 1;\n\nint two() => 2;\n'));
    expect([for (final f in result.files) f.path], ['doc/api.json']);
  });

  test('any diagnostic stops generation; they come sorted, once', () {
    final later = _FixedConstruct(units: [_function('one', 1)]);
    final result = DartnestGenerator([
      _FixedConstruct(diagnostics: [_error(9), _error(2)]),
      _FixedConstruct(diagnostics: [_error(2)]),
      later,
    ]).generate(_package);

    expect(result.isSuccess, isFalse);
    expect(result.library, isNull);
    expect([for (final d in result.diagnostics) d.location.line], [2, 9]);
    expect(later.generated, 0);
  });

  test('two units with one name are a diagnostic', () {
    final result = DartnestGenerator([
      _FixedConstruct(units: [_function('usersModule', 3)]),
      _FixedConstruct(units: [_function('usersModule', 8)]),
    ]).generate(_package);

    expect(
      result.diagnostics.single.toString(),
      'lib/app.dart:8:1: error: Generated name usersModule is used twice: for '
      'the declaration at lib/app.dart:3:1 and for this one. Rename one of '
      'them. [duplicate_generated_name]',
    );
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/dartnest_generator && dart test test/emit test/construct`
Expected: FAIL: компіляція — `lib/src/emit/…` і `lib/src/construct/…` не існують

- [ ] **Step 3: Write the emit layer**

`packages/dartnest_generator/lib/src/emit/dart_string.dart`:

```dart
/// Writes user strings (ids, paths, names) as Dart string literals.
///
/// `code_builder`'s `literalString` escapes only quotes and newlines; a
/// user string reaches generated code only through [literal], which also
/// escapes `\`, `$` and every control character.
abstract final class DartString {
  /// [value] as a single-quoted Dart literal.
  static String literal(String value) {
    final buffer = StringBuffer("'");
    for (final rune in value.runes) {
      buffer.write(_escape(rune));
    }
    buffer.write("'");
    return '$buffer';
  }

  static String _escape(int rune) => switch (rune) {
    0x5C => r'\\',
    0x27 => r"\'",
    0x24 => r'\$',
    0x0A => r'\n',
    0x0D => r'\r',
    0x09 => r'\t',
    < 0x20 || 0x7F || 0x2028 || 0x2029 => '\\u{${rune.toRadixString(16)}}',
    _ => String.fromCharCode(rune),
  };
}
```

`packages/dartnest_generator/lib/src/emit/import_allocator.dart`:

```dart
import 'package:code_builder/code_builder.dart';

/// Prefixes every import of the generated library: `dartnest` for the
/// core barrel, `i1`, `i2`, … for the others in order of first use;
/// `dart:core` stays unprefixed. Declarations of `package:dartnest/src/`
/// are imported from the barrel.
///
/// `Allocator.simplePrefixing` names prefixes `_i1`, which the
/// `no_leading_underscores_for_library_prefixes` lint rejects.
final class ImportAllocator implements Allocator {
  /// The core barrel every generated library imports.
  static const dartnest = 'package:dartnest/dartnest.dart';

  final Map<String, String> _prefixes = {};

  @override
  String allocate(Reference reference) {
    final symbol = reference.symbol ?? '';
    final url = switch (reference.url) {
      final String url when url.startsWith('package:dartnest/') => dartnest,
      final url => url,
    };
    if (url == null || url == 'dart:core') return symbol;
    final prefix = _prefixes.putIfAbsent(
      url,
      () => url == dartnest ? 'dartnest' : 'i${_numbered + 1}',
    );
    return '$prefix.$symbol';
  }

  int get _numbered => _prefixes.keys.where((url) => url != dartnest).length;

  @override
  Iterable<Directive> get imports => [
    for (final MapEntry(key: url, value: prefix) in _prefixes.entries)
      Directive.import(url, as: prefix),
  ];
}
```

`packages/dartnest_generator/lib/src/emit/type_emitter.dart`:

```dart
import 'package:code_builder/code_builder.dart';

import '../model/type_model.dart';

/// Writes [TypeModel]s as `code_builder` references.
abstract final class TypeEmitter {
  /// [type] with its type arguments and nullability.
  static TypeReference reference(TypeModel type) => TypeReference(
    (b) => b
      ..symbol = type.name
      ..url = type.libraryUri
      ..isNullable = type.isNullable
      ..types.addAll(type.typeArguments.map(reference)),
  );
}
```

`packages/dartnest_generator/lib/src/emit/constant_emitter.dart`:

```dart
import 'package:code_builder/code_builder.dart';

import '../model/constant_value.dart';
import 'dart_string.dart';
import 'type_emitter.dart';

/// Writes [ConstantValue]s as expressions.
abstract final class ConstantEmitter {
  /// [value] as an expression; a collection or constructor call is `const`
  /// at the top and plain inside, as the lints expect. An
  /// [UnsupportedConstant] must have been reported before generation.
  static Expression expression(ConstantValue value) =>
      _write(value, isConst: true);

  /// [values] as one `const` list literal.
  static Expression list(List<ConstantValue> values) =>
      literalConstList([for (final value in values) _write(value)]);

  static Expression _write(ConstantValue value, {bool isConst = false}) =>
      switch (value) {
        NullConstant() => literalNull,
        BoolConstant(:final value) => literalBool(value),
        NumberConstant(:final literal) => CodeExpression(Code(literal)),
        StringConstant(:final value) => CodeExpression(
          Code(DartString.literal(value)),
        ),
        TypeConstant(:final type) => TypeEmitter.reference(type),
        ReferenceConstant(
          :final name,
          :final libraryUri,
          :final enclosingName,
        ) =>
          enclosingName == null
              ? refer(name, libraryUri)
              : refer(enclosingName, libraryUri).property(name),
        ListConstant(:final elementType, :final elements) =>
          (isConst ? literalConstList : literalList)([
            for (final element in elements) _write(element),
          ], TypeEmitter.reference(elementType)),
        SetConstant(:final elementType, :final elements) =>
          (isConst ? literalConstSet : literalSet)({
            for (final element in elements) _write(element),
          }, TypeEmitter.reference(elementType)),
        MapConstant(:final keyType, :final valueType, :final entries) =>
          (isConst ? literalConstMap : literalMap)(
            {for (final (key, value) in entries) _write(key): _write(value)},
            TypeEmitter.reference(keyType),
            TypeEmitter.reference(valueType),
          ),
        ObjectConstant() => _object(value, isConst: isConst),
        UnsupportedConstant(:final reason) => throw StateError(
          'An unsupported constant reached generation: $reason.',
        ),
      };

  static Expression _object(ObjectConstant value, {required bool isConst}) {
    final type = TypeEmitter.reference(value.type);
    final positional = [for (final v in value.positional) _write(v)];
    final named = {
      for (final MapEntry(:key, :value) in value.named.entries)
        key: _write(value),
    };
    final name = value.constructorName;
    if (isConst) {
      return name.isEmpty
          ? type.constInstance(positional, named)
          : type.constInstanceNamed(name, positional, named);
    }
    return name.isEmpty
        ? type.newInstance(positional, named)
        : type.newInstanceNamed(name, positional, named);
  }
}
```

`packages/dartnest_generator/lib/src/emit/library_writer.dart`:

```dart
import 'package:code_builder/code_builder.dart';
import 'package:dart_style/dart_style.dart';
import 'package:pub_semver/pub_semver.dart';

import 'import_allocator.dart';

/// Joins the Dart declarations of all constructs into the formatted source
/// of `lib/<package>.dartnest.dart`.
abstract final class LibraryWriter {
  /// The header of every generated library.
  static const header = '// GENERATED BY dartnest_generator. DO NOT EDIT.';

  /// The source of the library of [packageName] holding [declarations], in
  /// order and separated by blank lines, formatted for [languageVersion].
  static String write({
    required String packageName,
    required Version languageVersion,
    required List<Spec> declarations,
  }) {
    final library = Library(
      (b) => b
        ..comments.add(header.substring(3))
        ..docs.add(
          '/// Generated from the annotations of package:$packageName.',
        )
        ..body.addAll([
          for (final (index, declaration) in declarations.indexed) ...[
            if (index > 0) const Code('\n\n'),
            declaration,
          ],
        ]),
    );
    final emitter = DartEmitter(
      allocator: ImportAllocator(),
      orderDirectives: true,
      useNullSafetySyntax: true,
    );
    final source = '${library.accept(emitter)}';
    return DartFormatter(languageVersion: languageVersion).format(source);
  }
}
```

- [ ] **Step 4: Write the construct API and the generator**

`dartnest_generator.dart` — без `DartnestGenerator.core()` (Task 10).

`packages/dartnest_generator/lib/src/construct/construct.dart`:

```dart
import '../diagnostic/diagnostic.dart';
import '../model/package_model.dart';
import 'generated_unit.dart';

/// One generation step over the whole [PackageModel]: it checks what it
/// generates and produces it.
///
/// v1 has `ModuleConstruct`, `ProviderConstruct` and `ControllerConstruct`;
/// later packages add their own (OpenAPI, GraphQL), and the CLI compiles
/// the set in statically.
abstract interface class Construct {
  /// The problems that make [package] impossible to generate.
  Iterable<Diagnostic> validate(PackageModel package);

  /// The output for [package]; called only when no construct reported a
  /// diagnostic.
  Iterable<GeneratedUnit> generate(PackageModel package);
}
```

`packages/dartnest_generator/lib/src/construct/generated_unit.dart`:

```dart
import 'package:code_builder/code_builder.dart';

import '../diagnostic/source_location.dart';

/// A piece of generator output: a Dart declaration of the package's
/// generated library, or a file of its own.
sealed class GeneratedUnit {
  const GeneratedUnit();
}

/// A top-level declaration [name] of `lib/<package>.dartnest.dart`,
/// generated for the declaration at [origin].
final class DartUnit extends GeneratedUnit {
  /// Creates the unit.
  const DartUnit({
    required this.name,
    required this.spec,
    required this.origin,
  });

  /// The declared name; two units must not share it.
  final String name;

  /// The declaration.
  final Spec spec;

  /// The user declaration it is generated from.
  final SourceLocation origin;
}

/// The kind of a [FileUnit].
enum ContentType {
  /// JSON.
  json,

  /// YAML.
  yaml,

  /// Plain text.
  text,
}

/// A file the driver writes as is, at [path] relative to the package root.
final class FileUnit extends GeneratedUnit {
  /// Creates the unit.
  const FileUnit({
    required this.path,
    required this.contentType,
    required this.content,
  });

  /// The path relative to the package root, with `/` separators.
  final String path;

  /// The kind of [content].
  final ContentType contentType;

  /// The file content.
  final String content;
}
```

`packages/dartnest_generator/lib/src/construct/generation_result.dart`:

```dart
import '../diagnostic/diagnostic.dart';
import 'generated_unit.dart';

/// The outcome of one generation: either diagnostics, or the generated
/// library source and the other files.
final class GenerationResult {
  /// A failed generation.
  const GenerationResult.failed(this.diagnostics)
    : library = null,
      files = const [];

  /// A successful generation.
  const GenerationResult.generated({
    required String this.library,
    this.files = const [],
  }) : diagnostics = const [];

  /// The problems, sorted by location; empty on success.
  final List<Diagnostic> diagnostics;

  /// The source of `lib/<package>.dartnest.dart`, or `null` on failure.
  final String? library;

  /// The other files, in construct order.
  final List<FileUnit> files;

  /// Whether generation succeeded.
  bool get isSuccess => library != null;
}
```

`packages/dartnest_generator/lib/src/construct/dartnest_generator.dart`:

```dart
import 'package:code_builder/code_builder.dart';

import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../emit/library_writer.dart';
import '../model/package_model.dart';
import 'construct.dart';
import 'generated_unit.dart';
import 'generation_result.dart';

/// Runs a set of [Construct]s over a [PackageModel].
///
/// Every construct validates first; any diagnostic stops generation, so a
/// package with an error never gets a half-generated library.
final class DartnestGenerator {
  /// Creates the generator; [constructs] run in order.
  const DartnestGenerator(this.constructs);

  /// The constructs.
  final List<Construct> constructs;

  /// Validates and generates [package].
  GenerationResult generate(PackageModel package) {
    final diagnostics = {
      for (final construct in constructs) ...construct.validate(package),
    }.toList()..sort();
    if (diagnostics.isNotEmpty) return GenerationResult.failed(diagnostics);
    final units = [
      for (final construct in constructs) ...construct.generate(package),
    ];
    final dartUnits = units.whereType<DartUnit>().toList();
    final duplicates = _duplicateNames(dartUnits);
    if (duplicates.isNotEmpty) return GenerationResult.failed(duplicates);
    return GenerationResult.generated(
      library: LibraryWriter.write(
        packageName: package.packageName,
        languageVersion: package.languageVersion,
        declarations: <Spec>[for (final unit in dartUnits) unit.spec],
      ),
      files: units.whereType<FileUnit>().toList(),
    );
  }

  static List<Diagnostic> _duplicateNames(List<DartUnit> units) {
    final first = <String, DartUnit>{};
    return [
      for (final unit in units)
        if (first.putIfAbsent(unit.name, () => unit) case final other
            when other != unit)
          Diagnostic(
            DiagnosticCode.duplicateGeneratedName,
            unit.origin,
            'Generated name ${unit.name} is used twice: for the declaration '
            'at ${other.origin} and for this one. Rename one of them.',
          ),
    ]..sort();
  }
}
```

- [ ] **Step 5: Export the API**

Повна заміна barrel; Task 10 додає три конструкти й приклад драйвера.

`packages/dartnest_generator/lib/dartnest_generator.dart`:

```dart
/// Turns dartnest annotations into ordinary code on the explicit dartnest
/// API, and checks the module graph before the application starts.
///
/// A driver (the CLI, build_runner) resolves the libraries of a package,
/// builds its model with [PackageCollector] and runs a [DartnestGenerator].
///
/// The model and [Construct] are public so later packages (OpenAPI,
/// GraphQL) can add constructs of their own.
library;

export 'src/collector/package_collector.dart';
export 'src/construct/construct.dart';
export 'src/construct/dartnest_generator.dart';
export 'src/construct/generated_unit.dart';
export 'src/construct/generation_result.dart';
export 'src/diagnostic/diagnostic.dart';
export 'src/diagnostic/diagnostic_code.dart';
export 'src/diagnostic/source_location.dart';
export 'src/emit/library_writer.dart';
export 'src/model/body_kind.dart';
export 'src/model/component_reference.dart';
export 'src/model/constant_value.dart';
export 'src/model/constructor_model.dart';
export 'src/model/controller_model.dart';
export 'src/model/dependency_model.dart';
export 'src/model/dto_field.dart';
export 'src/model/dto_model.dart';
export 'src/model/enhancers_model.dart';
export 'src/model/generated_names.dart';
export 'src/model/handler_parameter.dart';
export 'src/model/injectable_model.dart';
export 'src/model/module_export.dart';
export 'src/model/module_model.dart';
export 'src/model/module_reference.dart';
export 'src/model/package_model.dart';
export 'src/model/parameter_binding.dart';
export 'src/model/provider_key.dart';
export 'src/model/provider_model.dart';
export 'src/model/route_model.dart';
export 'src/model/type_kind.dart';
export 'src/model/type_model.dart';
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd packages/dartnest_generator && dart test test/emit test/construct`
Expected: `+9: All tests passed!`

Run: `cd packages/dartnest_generator && dart test`
Expected: `+38: All tests passed!`

- [ ] **Step 7: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 8: Commit**

```bash
git add \
  packages/dartnest_generator/test/emit/emit_test.dart \
  packages/dartnest_generator/test/construct/dartnest_generator_test.dart \
  packages/dartnest_generator/lib/src/emit/dart_string.dart \
  packages/dartnest_generator/lib/src/emit/import_allocator.dart \
  packages/dartnest_generator/lib/src/emit/type_emitter.dart \
  packages/dartnest_generator/lib/src/emit/constant_emitter.dart \
  packages/dartnest_generator/lib/src/emit/library_writer.dart \
  packages/dartnest_generator/lib/src/construct/construct.dart \
  packages/dartnest_generator/lib/src/construct/generated_unit.dart \
  packages/dartnest_generator/lib/src/construct/generation_result.dart \
  packages/dartnest_generator/lib/src/construct/dartnest_generator.dart \
  packages/dartnest_generator/lib/dartnest_generator.dart
git commit -m "feat(generator): add the construct API and the library writer"
```

### Task 7: `ModuleConstruct` і `ProviderConstruct`: структура графа, модулі й фабрики

`ModuleStructureCheck` повторює структурні перевірки `ModuleGraph.build` ядра до запуску: `duplicate_module_id` (на кожному модулі з тим самим `id`), `circular_module_import` (цикл по локальних імпортах, шлях у повідомленні), `duplicate_provider` (один ключ двічі в одному модулі), `invalid_export` (експорт того, чого модуль не надає й не імпортує), `invalid_module_entry` (`ModuleModel.invalidEntries`), `unsupported_constant` (значення `Value` чи токен, які не можна записати в код). `ModuleConstruct` у цій задачі валідує лише структуру; `DependencyCheck` додає Task 8. `ModuleEmitter` пише `dartnest.Module xModule() => dartnest.Module(id:, imports:, providers:, controllers:, exports:, global: true)` без порожніх списків; `imports` викликають функції модулів (`dbModule()`, `i1.explicitModule()`, `i1.DbModule.forRoot()`), `controllers` — функції контролерів (Task 9).

`ProviderConstruct` перевіряє кожен injectable-клас, що його надає модуль (`not_injectable` без `@Injectable()`, далі `ConstructorCheck`: `invalid_constructor`, `invalid_dependency`, `unsupported_constant` токена) і генерує по одній приватній фабриці на клас у порядку модулів: `X _createX(dartnest.Injector i) => X(i.get<A>(), i.get(token), name: i.get<B>())` (`InjectionEmitter`). Провайдер класу в модулі — `dartnest.Provider<K>(_createI)`, значення — `dartnest.Provider<T>.value(v, token: t)`.

Фікстури: `modules/structure_errors.dart` (усі структурні помилки), `providers/provider_module.dart` (провайдери з поганими конструкторами й токен `Token<_Port>`).

**Files:**
- Create: `packages/dartnest_generator/test/fixtures/cases_app/lib/modules/structure_errors.dart`
- Create: `packages/dartnest_generator/test/fixtures/cases_app/lib/providers/provider_module.dart`
- Create: `packages/dartnest_generator/lib/src/emit/injection_emitter.dart`
- Create: `packages/dartnest_generator/lib/src/emit/module_emitter.dart`
- Create: `packages/dartnest_generator/lib/src/constructs/constructor_check.dart`
- Create: `packages/dartnest_generator/lib/src/constructs/provider_construct.dart`
- Create: `packages/dartnest_generator/lib/src/constructs/module_structure_check.dart`
- Create: `packages/dartnest_generator/lib/src/constructs/module_construct.dart`
- Test: `packages/dartnest_generator/test/constructs/module_construct_test.dart`
- Test: `packages/dartnest_generator/test/constructs/provider_construct_test.dart`

**Interfaces:**
- Consumes: Tasks 2–6 (модель, collector, `Construct`, `DartUnit`, `TypeEmitter`, `ConstantEmitter`, `DartString`, `ImportAllocator`, `DartnestGenerator`).
- Produces:
  - `constructs/constructor_check.dart`: `ConstructorCheck.check(TypeModel type, ConstructorModel constructor, SourceLocation location) → Iterable<Diagnostic>` (Task 9 використовує для контролерів)
  - `constructs/module_structure_check.dart`: `ModuleStructureCheck.check(List<ModuleModel> modules) → Iterable<Diagnostic>`
  - `constructs/module_construct.dart`: `const ModuleConstruct()` (структура; Task 8 додає залежності)
  - `constructs/provider_construct.dart`: `const ProviderConstruct()`
  - `emit/injection_emitter.dart`: `InjectionEmitter.injector` (`Parameter` `dartnest.Injector i`), `create(TypeModel type, ConstructorModel constructor) → Expression`, `get(ProviderKey key) → Expression`
  - `emit/module_emitter.dart`: `ModuleEmitter.function(ModuleModel) → Method`, `ModuleEmitter.reference(ModuleReference) → Expression`

- [ ] **Step 1: Add the fixtures**

`packages/dartnest_generator/test/fixtures/cases_app/lib/modules/structure_errors.dart`:

```dart
// Module graphs Application.create would reject.
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'basic.dart';

final class _Secret {
  const _Secret();
}

/// Shares its id with [SecondModule].
@Module(id: 'shared')
class FirstModule {}

/// Shares its id with [FirstModule].
@Module(id: 'shared')
class SecondModule {}

/// Imports [PongModule], which imports it back.
@Module(imports: [PongModule])
class PingModule {}

/// Imports [PingModule].
@Module(imports: [PingModule])
class PongModule {}

/// Declares a provider twice, exports what it does not have, and provides
/// a value generated code cannot write.
@Module(
  providers: [SystemClock, SystemClock, Value(_Secret())],
  exports: [Repo, SecondModule],
)
class SloppyModule {}
```

`packages/dartnest_generator/test/fixtures/cases_app/lib/providers/provider_module.dart`:

```dart
// A module providing classes whose constructors fail the checks.
import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

import '../modules/basic.dart';
import 'constructors.dart';

final class _Port {}

const _port = Token<_Port>('port');

/// Injects a token of a private type.
@Injectable()
final class PrivateToken {
  /// Creates it.
  PrivateToken(@Inject(_port) this.port);

  /// The port.
  final Object port;
}

/// Provides every class of `constructors.dart` worth checking.
@Module(
  providers: [
    Plain,
    Shape,
    Optional,
    BadTokens,
    PrivateToken,
    Fine,
    SystemClock,
  ],
)
class ProvidersModule {}
```

- [ ] **Step 2: Write the failing tests**

`packages/dartnest_generator/test/constructs/module_construct_test.dart`:

```dart
import 'package:dartnest_generator/src/construct/dartnest_generator.dart';
import 'package:dartnest_generator/src/construct/generation_result.dart';
import 'package:dartnest_generator/src/constructs/module_construct.dart';
import 'package:dartnest_generator/src/constructs/provider_construct.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

const _generator = DartnestGenerator([ModuleConstruct(), ProviderConstruct()]);

void main() {
  late FixturePackage fixture; // Set in setUpAll.

  setUpAll(() => fixture = FixturePackage.open('cases_app'));

  Future<GenerationResult> generate(List<String> paths) async =>
      _generator.generate(await fixture.collect(paths));

  test('one function per module, on the explicit API', () async {
    final result = await generate([
      'lib/modules/basic.dart',
      'lib/modules/app.dart',
    ]);

    expect(result.diagnostics, isEmpty);
    expect(
      result.library,
      contains('''
/// The module of `AppModule`.
dartnest.Module appModule() => dartnest.Module(
  id: 'AppModule',
  imports: [dbModule(), i1.explicitModule()],
  exports: [dbModule()],
);

/// The module of `DbModule`.
dartnest.Module dbModule() => dartnest.Module(
  id: 'db',
  providers: [
    dartnest.Provider<i2.Repo>(_createRepo),
    dartnest.Provider<i2.Clock>(_createSystemClock),
    dartnest.Provider<String>.value('postgres://localhost', token: i2.dbUrl),
    dartnest.Provider<i2.AppConfig>.value(i2.appConfig),
  ],
  exports: [i2.Repo, i2.dbUrl],
  global: true,
);
'''),
    );
  });

  test(
    'imports are prefixed in order of first use, dartnest by name',
    () async {
      final result = await generate([
        'lib/modules/basic.dart',
        'lib/modules/app.dart',
      ]);

      expect(
        result.library,
        contains('''
import 'package:cases_app/modules/basic.dart' as i2;
import 'package:cases_app/modules/explicit.dart' as i1;
import 'package:dartnest/dartnest.dart' as dartnest;
'''),
      );
    },
  );

  test('ids, import cycles, duplicate providers, exports, constants', () async {
    final result = await generate([
      'lib/modules/structure_errors.dart',
      'lib/modules/basic.dart',
    ]);

    expect(result.library, isNull);
    expect(result.diagnostics.map((d) => '$d'), [
      'lib/modules/structure_errors.dart:16:7: error: Modules FirstModule and '
          'SecondModule share the id "shared". Give each @Module its own id. '
          '[duplicate_module_id]',
      'lib/modules/structure_errors.dart:20:7: error: Module imports form a '
          'cycle: PingModule -> PongModule -> PingModule. Move the shared '
          'providers into a third module imported by both. '
          '[circular_module_import]',
      'lib/modules/structure_errors.dart:32:7: error: Module "SloppyModule" '
          'declares SystemClock more than once. [duplicate_provider]',
      'lib/modules/structure_errors.dart:32:7: error: Module "SloppyModule" '
          'exports Repo, which is neither one of its providers nor one of its '
          'imports. [invalid_export]',
      'lib/modules/structure_errors.dart:32:7: error: Module "SloppyModule" '
          'exports module SecondModule, which is neither one of its providers '
          'nor one of its imports. [invalid_export]',
      'lib/modules/structure_errors.dart:32:7: error: Module "SloppyModule": '
          'the value of _Secret cannot be written in generated code: _Secret '
          'is private. Use public constants and const constructors of public '
          'classes. [unsupported_constant]',
    ]);
  });

  test('every unreadable entry is reported at its module', () async {
    final result = await generate([
      'lib/modules/invalid_entries.dart',
      'lib/modules/basic.dart',
    ]);

    expect(result.diagnostics, hasLength(7));
    expect(result.diagnostics.map((d) => d.code.id).toSet(), {
      'invalid_module_entry',
    });
    expect(
      '${result.diagnostics.first}',
      'lib/modules/invalid_entries.dart:17:7: error: Module "BrokenModule": '
          'controllers: Repo is not a @Controller class of this package. '
          '[invalid_module_entry]',
    );
  });
}
```

`packages/dartnest_generator/test/constructs/provider_construct_test.dart`:

```dart
import 'package:dartnest_generator/src/construct/dartnest_generator.dart';
import 'package:dartnest_generator/src/constructs/module_construct.dart';
import 'package:dartnest_generator/src/constructs/provider_construct.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  late FixturePackage fixture; // Set in setUpAll.

  setUpAll(() => fixture = FixturePackage.open('cases_app'));

  test('constructors and parameters injection cannot use', () async {
    final package = await fixture.collect([
      'lib/providers/provider_module.dart',
      'lib/providers/constructors.dart',
      'lib/modules/basic.dart',
    ]);

    expect(const ProviderConstruct().validate(package).map((d) => '$d'), [
      'lib/providers/constructors.dart:8:13: error: Plain is a provider of '
          'module "ProvidersModule" but is not annotated with @Injectable(). '
          '[not_injectable]',
      'lib/providers/constructors.dart:12:16: error: Shape is abstract. '
          '[invalid_constructor]',
      'lib/providers/constructors.dart:29:18: error: Parameter clock of '
          'Optional is optional; dartnest injects required positional and '
          'required named parameters only. [invalid_dependency]',
      'lib/providers/constructors.dart:52:33: error: Parameter port of '
          'BadTokens has type int, but Token<String>(db.url) provides String. '
          '[invalid_dependency]',
      'lib/providers/constructors.dart:52:62: error: The @Inject argument of '
          'Parameter url of BadTokens is not a Token. [invalid_dependency]',
      'lib/providers/provider_module.dart:16:36: error: The token of '
          'parameter port of PrivateToken cannot be written in generated '
          'code: _Port is private. Use a public constant token. '
          '[unsupported_constant]',
      'lib/providers/constructors.dart:16:13: error: Box is generic; provide '
          'a subclass with fixed type arguments. [invalid_constructor]',
      'lib/providers/constructors.dart:20:13: error: Named has no unnamed '
          'constructor; dartnest creates it with Named(...). '
          '[invalid_constructor]',
      'lib/providers/constructors.dart:39:12: error: Parameter clock of Odd '
          'has type Clock?; dartnest injects non-nullable class types, or a '
          'Token with @Inject(token). [invalid_dependency]',
      'lib/providers/constructors.dart:39:24: error: Parameter callback of '
          'Odd has type void Function(); dartnest injects non-nullable class '
          'types, or a Token with @Inject(token). [invalid_dependency]',
    ]);
  });

  test('one private factory per provided class, in module order', () async {
    final result = const DartnestGenerator([
      ModuleConstruct(),
      ProviderConstruct(),
    ]).generate(await fixture.collect(['lib/modules/basic.dart']));

    expect(
      result.library,
      endsWith('''
i1.Repo _createRepo(dartnest.Injector i) =>
    i1.Repo(i.get<i1.Clock>(), i.get(i1.dbUrl), config: i.get<i1.AppConfig>());

i1.SystemClock _createSystemClock(dartnest.Injector i) => i1.SystemClock();
'''),
    );
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd packages/dartnest_generator && dart test test/constructs`
Expected: FAIL: компіляція — `lib/src/constructs/…` не існують

- [ ] **Step 4: Write the injection and module emitters**

`packages/dartnest_generator/lib/src/emit/injection_emitter.dart`:

```dart
import 'package:code_builder/code_builder.dart';

import '../model/constructor_model.dart';
import '../model/provider_key.dart';
import '../model/type_model.dart';
import 'constant_emitter.dart';
import 'type_emitter.dart';

/// Writes how dependency injection creates a class: its constructor call
/// with one `injector.get` per parameter.
abstract final class InjectionEmitter {
  /// The `Injector` parameter of a factory: `dartnest.Injector i`.
  static final injector = Parameter(
    (b) => b
      ..name = 'i'
      ..type = refer('Injector', 'package:dartnest/dartnest.dart'),
  );

  /// `Type(i.get<A>(), i.get(token), name: i.get<B>())` for [type] created
  /// through [constructor].
  static Expression create(TypeModel type, ConstructorModel constructor) {
    final positional = <Expression>[];
    final named = <String, Expression>{};
    for (final dependency in constructor.dependencies) {
      final key = dependency.key;
      if (key == null) {
        throw StateError('An invalid dependency reached generation.');
      }
      if (dependency.isNamed) {
        named[dependency.name] = get(key);
      } else {
        positional.add(get(key));
      }
    }
    return TypeEmitter.reference(type).newInstance(positional, named);
  }

  /// `i.get<T>()` for a type key, `i.get(token)` for a token key.
  static Expression get(ProviderKey key) => switch (key) {
    TypeKey(:final type) => refer(
      'i',
    ).property('get').call(const [], const {}, [TypeEmitter.reference(type)]),
    TokenKey(:final expression) => refer(
      'i',
    ).property('get').call([ConstantEmitter.expression(expression)]),
  };
}
```

`packages/dartnest_generator/lib/src/emit/module_emitter.dart`:

```dart
import 'package:code_builder/code_builder.dart';

import '../model/generated_names.dart';
import '../model/module_export.dart';
import '../model/module_model.dart';
import '../model/module_reference.dart';
import '../model/provider_key.dart';
import '../model/provider_model.dart';
import 'constant_emitter.dart';
import 'dart_string.dart';
import 'import_allocator.dart';
import 'type_emitter.dart';

/// Writes a [ModuleModel] as a function returning the core `Module`.
abstract final class ModuleEmitter {
  /// `Module usersModule() => Module(id: 'users', ...)`; empty lists and
  /// `global: false` are left out.
  static Method function(ModuleModel module) => Method(
    (b) => b
      ..docs.add('/// The module of `${module.type.name}`.')
      ..name = GeneratedNames.module(module.type.name)
      ..returns = _core('Module')
      ..lambda = true
      ..body = _core('Module').newInstance(const [], {
        'id': CodeExpression(Code(DartString.literal(module.id))),
        if (module.imports.isNotEmpty)
          'imports': literalList(module.imports.map(reference)),
        if (module.providers.isNotEmpty)
          'providers': literalList(module.providers.map(_provider)),
        if (module.controllers.isNotEmpty)
          'controllers': literalList([
            for (final type in module.controllers)
              refer(GeneratedNames.controller(type.name)).call(const []),
          ]),
        if (module.exports.isNotEmpty)
          'exports': literalList(module.exports.map(_export)),
        if (module.isGlobal) 'global': literalTrue,
      }).code,
  );

  /// The call that builds the module [reference] points to.
  static Expression reference(ModuleReference reference) => switch (reference) {
    LocalModuleReference(:final type) => refer(
      GeneratedNames.module(type.name),
    ).call(const []),
    OpaqueModuleReference(
      :final name,
      :final libraryUri,
      :final enclosingName?,
    ) =>
      refer(enclosingName, libraryUri).property(name).call(const []),
    OpaqueModuleReference(:final name, :final libraryUri) => refer(
      name,
      libraryUri,
    ).call(const []),
  };

  static Expression _provider(ProviderModel provider) {
    final (type, token) = switch (provider.key) {
      TypeKey(:final type) => (type, null),
      TokenKey(:final valueType, :final expression) => (
        valueType,
        ConstantEmitter.expression(expression),
      ),
    };
    final generic = TypeReference(
      (b) => b
        ..symbol = 'Provider'
        ..url = ImportAllocator.dartnest
        ..types.add(TypeEmitter.reference(type)),
    );
    final named = {'token': ?token};
    return switch (provider) {
      ClassProvider(:final injectable) => generic.newInstance([
        refer(GeneratedNames.factory(injectable.type.name)),
      ], named),
      ValueProvider(:final value) => generic.newInstanceNamed('value', [
        ConstantEmitter.expression(value),
      ], named),
    };
  }

  static Expression _export(ModuleExport export) => switch (export) {
    KeyExport(key: TypeKey(:final type)) => TypeEmitter.reference(type),
    KeyExport(key: TokenKey(:final expression)) => ConstantEmitter.expression(
      expression,
    ),
    ModuleReexport(:final module) => reference(module),
  };

  static Reference _core(String name) => refer(name, ImportAllocator.dartnest);
}
```

- [ ] **Step 5: Write the checks and the constructs**

`module_construct.dart` — лише структура; Task 8 замінює файл.

`packages/dartnest_generator/lib/src/constructs/constructor_check.dart`:

```dart
import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../diagnostic/source_location.dart';
import '../model/constructor_model.dart';
import '../model/provider_key.dart';
import '../model/type_model.dart';

/// Reports why dependency injection cannot call a constructor; shared by
/// providers and controllers.
abstract final class ConstructorCheck {
  /// The problems of [constructor] of [type] declared at [location].
  static Iterable<Diagnostic> check(
    TypeModel type,
    ConstructorModel constructor,
    SourceLocation location,
  ) sync* {
    if (constructor.problem case final problem?) {
      yield Diagnostic(DiagnosticCode.invalidConstructor, location, problem);
    }
    for (final dependency in constructor.dependencies) {
      if (dependency.problem case final problem?) {
        yield Diagnostic(
          DiagnosticCode.invalidDependency,
          dependency.location,
          problem,
        );
      }
      if (dependency.key case TokenKey(:final expression)) {
        if (expression.unsupported case final unsupported?) {
          yield Diagnostic(
            DiagnosticCode.unsupportedConstant,
            dependency.location,
            'The token of parameter ${dependency.name} of $type cannot be '
            'written in generated code: ${unsupported.reason}. Use a public '
            'constant token.',
          );
        }
      }
    }
  }
}
```

`packages/dartnest_generator/lib/src/constructs/provider_construct.dart`:

```dart
import 'package:code_builder/code_builder.dart';

import '../construct/construct.dart';
import '../construct/generated_unit.dart';
import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../emit/injection_emitter.dart';
import '../emit/type_emitter.dart';
import '../model/generated_names.dart';
import '../model/injectable_model.dart';
import '../model/package_model.dart';
import '../model/provider_model.dart';
import '../model/type_model.dart';
import 'constructor_check.dart';

/// Checks the constructors of injectable classes and generates one private
/// factory per class a module provides:
/// `Repo _createRepo(Injector i) => Repo(i.get<Clock>())`.
final class ProviderConstruct implements Construct {
  /// Creates the construct.
  const ProviderConstruct();

  @override
  Iterable<Diagnostic> validate(PackageModel package) sync* {
    final provided = _provided(package);
    final checked = <TypeModel>{};
    for (final (injectable, moduleId) in provided) {
      if (!checked.add(injectable.type)) continue;
      if (!injectable.isAnnotated) {
        yield Diagnostic(
          DiagnosticCode.notInjectable,
          injectable.location,
          '${injectable.type} is a provider of module "$moduleId" but is not '
          'annotated with @Injectable().',
        );
      }
      yield* ConstructorCheck.check(
        injectable.type,
        injectable.constructor,
        injectable.location,
      );
    }
    for (final injectable in package.injectables) {
      if (checked.add(injectable.type)) {
        yield* ConstructorCheck.check(
          injectable.type,
          injectable.constructor,
          injectable.location,
        );
      }
    }
  }

  @override
  Iterable<GeneratedUnit> generate(PackageModel package) sync* {
    final generated = <TypeModel>{};
    for (final (injectable, _) in _provided(package)) {
      if (generated.add(injectable.type)) yield _factory(injectable);
    }
  }

  /// Each class provider of every module with the id of its module, in
  /// module order.
  static List<(InjectableModel, String)> _provided(PackageModel package) => [
    for (final module in package.modules)
      for (final provider in module.providers)
        if (provider case ClassProvider(:final injectable))
          (injectable, module.id),
  ];

  static DartUnit _factory(InjectableModel injectable) {
    final name = GeneratedNames.factory(injectable.type.name);
    return DartUnit(
      name: name,
      spec: Method(
        (b) => b
          ..name = name
          ..returns = TypeEmitter.reference(injectable.type)
          ..requiredParameters.add(InjectionEmitter.injector)
          ..lambda = true
          ..body = InjectionEmitter.create(
            injectable.type,
            injectable.constructor,
          ).code,
      ),
      origin: injectable.location,
    );
  }
}
```

`packages/dartnest_generator/lib/src/constructs/module_structure_check.dart`:

```dart
import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../model/constant_value.dart';
import '../model/module_export.dart';
import '../model/module_model.dart';
import '../model/module_reference.dart';
import '../model/provider_key.dart';
import '../model/provider_model.dart';

/// The startup checks of the module graph that need no dependency
/// resolution: ids, import cycles, duplicate providers, exports, unreadable
/// entries and constants generated code cannot write.
abstract final class ModuleStructureCheck {
  /// The structural problems of [modules].
  static Iterable<Diagnostic> check(List<ModuleModel> modules) sync* {
    yield* _duplicateIds(modules);
    yield* _importCycles(modules);
    for (final module in modules) {
      yield* _entries(module);
      yield* _duplicateProviders(module);
      yield* _exports(module);
      yield* _constants(module);
    }
  }

  static Iterable<Diagnostic> _duplicateIds(List<ModuleModel> modules) sync* {
    final first = <String, ModuleModel>{};
    for (final module in modules) {
      final other = first.putIfAbsent(module.id, () => module);
      if (other != module) {
        yield Diagnostic(
          DiagnosticCode.duplicateModuleId,
          module.location,
          'Modules ${other.type} and ${module.type} share the id '
          '"${module.id}". Give each @Module its own id.',
        );
      }
    }
  }

  static Iterable<Diagnostic> _importCycles(List<ModuleModel> modules) sync* {
    final byType = {for (final m in modules) m.type: m};
    final reported = <ModuleModel>{};
    for (final start in modules) {
      final cycle = _cycleFrom(start, byType, [start]);
      if (cycle == null || cycle.any(reported.contains)) continue;
      reported.addAll(cycle);
      yield Diagnostic(
        DiagnosticCode.circularModuleImport,
        start.location,
        'Module imports form a cycle: '
        '${[...cycle, start].map((m) => m.id).join(' -> ')}. Move the shared '
        'providers into a third module imported by both.',
      );
    }
  }

  /// The import path from [path].first back to itself, if any.
  static List<ModuleModel>? _cycleFrom(
    ModuleModel start,
    Map<Object, ModuleModel> byType,
    List<ModuleModel> path,
  ) {
    for (final reference in path.last.imports) {
      if (reference is! LocalModuleReference) continue;
      final next = byType[reference.type];
      if (next == null || (next != start && path.contains(next))) continue;
      if (next == start) return path;
      if (_cycleFrom(start, byType, [...path, next]) case final cycle?) {
        return cycle;
      }
    }
    return null;
  }

  static Iterable<Diagnostic> _entries(ModuleModel module) => [
    for (final problem in module.invalidEntries)
      Diagnostic(
        DiagnosticCode.invalidModuleEntry,
        module.location,
        'Module "${module.id}": $problem',
      ),
  ];

  static Iterable<Diagnostic> _duplicateProviders(ModuleModel module) sync* {
    final seen = <ProviderKey>{};
    for (final provider in module.providers) {
      if (!seen.add(provider.key)) {
        yield Diagnostic(
          DiagnosticCode.duplicateProvider,
          module.location,
          'Module "${module.id}" declares ${provider.key} more than once.',
        );
      }
    }
  }

  static Iterable<Diagnostic> _exports(ModuleModel module) sync* {
    final keys = {for (final p in module.providers) p.key};
    for (final export in module.exports) {
      final (isValid, what) = switch (export) {
        KeyExport(:final key) => (keys.contains(key), '$key'),
        ModuleReexport(module: final reexported) => (
          module.imports.contains(reexported),
          'module ${reexported.display}',
        ),
      };
      if (!isValid) {
        yield Diagnostic(
          DiagnosticCode.invalidExport,
          module.location,
          'Module "${module.id}" exports $what, which is neither one of its '
          'providers nor one of its imports.',
        );
      }
    }
  }

  static Iterable<Diagnostic> _constants(ModuleModel module) {
    final constants = <(String, ConstantValue)>[
      for (final provider in module.providers) ...[
        if (provider case ValueProvider(:final value))
          ('the value of ${provider.key}', value),
        if (provider.key case TokenKey(:final expression))
          ('the token ${provider.key}', expression),
      ],
      for (final export in module.exports)
        if (export case KeyExport(key: final TokenKey key))
          ('the token ${key.display}', key.expression),
    ];
    return [
      for (final (what, value) in constants)
        if (value.unsupported case final unsupported?)
          Diagnostic(
            DiagnosticCode.unsupportedConstant,
            module.location,
            'Module "${module.id}": $what cannot be written in generated '
            'code: ${unsupported.reason}. Use public constants and const '
            'constructors of public classes.',
          ),
    ];
  }
}
```

`packages/dartnest_generator/lib/src/constructs/module_construct.dart`:

```dart
import '../construct/construct.dart';
import '../construct/generated_unit.dart';
import '../diagnostic/diagnostic.dart';
import '../emit/module_emitter.dart';
import '../model/generated_names.dart';
import '../model/package_model.dart';
import 'module_structure_check.dart';

/// Checks the module graph the way `Application.create` would and
/// generates one function per `@Module` class.
final class ModuleConstruct implements Construct {
  /// Creates the construct.
  const ModuleConstruct();

  @override
  Iterable<Diagnostic> validate(PackageModel package) =>
      ModuleStructureCheck.check(package.modules);

  @override
  Iterable<GeneratedUnit> generate(PackageModel package) => [
    for (final module in package.modules)
      DartUnit(
        name: GeneratedNames.module(module.type.name),
        spec: ModuleEmitter.function(module),
        origin: module.location,
      ),
  ];
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd packages/dartnest_generator && dart test test/constructs`
Expected: `+6: All tests passed!`

Run: `cd packages/dartnest_generator && dart test`
Expected: `+44: All tests passed!`

- [ ] **Step 7: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 8: Commit**

```bash
git add \
  packages/dartnest_generator/test/fixtures/cases_app/lib/modules/structure_errors.dart \
  packages/dartnest_generator/test/fixtures/cases_app/lib/providers/provider_module.dart \
  packages/dartnest_generator/test/constructs/module_construct_test.dart \
  packages/dartnest_generator/test/constructs/provider_construct_test.dart \
  packages/dartnest_generator/lib/src/emit/injection_emitter.dart \
  packages/dartnest_generator/lib/src/emit/module_emitter.dart \
  packages/dartnest_generator/lib/src/constructs/constructor_check.dart \
  packages/dartnest_generator/lib/src/constructs/provider_construct.dart \
  packages/dartnest_generator/lib/src/constructs/module_structure_check.dart \
  packages/dartnest_generator/lib/src/constructs/module_construct.dart
git commit -m "feat(generator): generate modules and provider factories"
```

### Task 8: `DependencyCheck`: відсутні провайдери й цикли залежностей

Перевірки, які ядро робить у `Container.create`, тепер до запуску. `ModuleScope` обчислює (з мемоізацією) провайдерів, видимих у модулі, за правилами ядра: власні провайдери, експорти імпортованих модулів (з реекспортами модулів), потім експорти глобальних модулів; `declaring(key)` — модулі, що оголошують ключ (підказка «export it there» як у `MissingProviderError` ядра). `DependencyCheck.check(package)` повертає `missing_provider` на позиції параметра для залежностей класів-провайдерів, контролерів (у модулі, що їх оголошує) і компонентів `Use<T>` контролерів і роутів, та `circular_dependency` один раз на цикл (`Circular dependency: Engine -> Wheel -> Engine.`). Якщо в пакеті є непрозорий модуль (OP3), перевірка повертає порожній список (Review Focus 4).

`ModuleConstruct.validate` запускає `DependencyCheck` лише тоді, коли структура чиста: інакше одна помилка (наприклад, дубльований `id`) повторювалась би десятком `missing_provider`.

**Files:**
- Create: `packages/dartnest_generator/test/fixtures/cases_app/lib/dependencies/graph.dart`
- Create: `packages/dartnest_generator/lib/src/constructs/module_scope.dart`
- Create: `packages/dartnest_generator/lib/src/constructs/dependency_check.dart`
- Modify: `packages/dartnest_generator/lib/src/constructs/module_construct.dart`
- Test: `packages/dartnest_generator/test/constructs/dependency_check_test.dart`

**Interfaces:**
- Consumes: Task 7 (`ModuleConstruct`, `ModuleStructureCheck`), модель контролерів (Task 5).
- Produces:
  - `constructs/module_scope.dart`: `typedef ScopedProvider = ({ModuleModel owner, ProviderModel provider})`; `ModuleScope(List<ModuleModel> modules)`, `Map<ProviderKey, ScopedProvider> visibleIn(ModuleModel module)`, `List<String> declaring(ProviderKey key)`
  - `constructs/dependency_check.dart`: `DependencyCheck.check(PackageModel package) → List<Diagnostic>`
  - `ModuleConstruct.validate` = структура, а якщо вона чиста — залежності

- [ ] **Step 1: Add the fixture**

`packages/dartnest_generator/test/fixtures/cases_app/lib/dependencies/graph.dart`:

```dart
// Dependencies that cannot be resolved, and one that resolves through a
// global module.
import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

import '../controllers/components.dart';
import '../modules/basic.dart';

/// Needs a [Wheel].
@Injectable()
final class Engine {
  /// Creates it.
  Engine(this.wheel);

  /// The wheel.
  final Wheel wheel;
}

/// Needs an [Engine].
@Injectable()
final class Wheel {
  /// Creates it.
  Wheel(this.engine);

  /// The engine.
  final Engine engine;
}

/// The SMTP URL; nobody provides it.
const smtpUrl = Token<String>('smtp.url');

/// Needs a clock, which only `DbModule` declares, and an unprovided token.
@Injectable()
final class Mailer {
  /// Creates it.
  Mailer(this.clock, @Inject(smtpUrl) this.url, this.repo);

  /// The clock.
  final Clock clock;

  /// The SMTP URL.
  final String url;

  /// The repository, exported by the global `DbModule`.
  final Repo repo;
}

/// Needs a [Mailer] and is guarded by an unprovided guard.
@Controller('/mail')
@UseGuards([OpenGuard])
final class MailController {
  /// Creates it.
  MailController(this.mailer, this.engine);

  /// The mailer.
  final Mailer mailer;

  /// Not visible in `MailModule`.
  final Engine engine;

  /// Sends nothing.
  @Post()
  void send() {}
}

/// Two classes that need each other.
@Module(providers: [Engine, Wheel])
class CarModule {}

/// A mailer without its dependencies.
@Module(providers: [Mailer], controllers: [MailController])
class MailModule {}
```

- [ ] **Step 2: Write the failing test**

`packages/dartnest_generator/test/constructs/dependency_check_test.dart`:

```dart
import 'package:dartnest_generator/src/constructs/module_construct.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  late FixturePackage fixture; // Set in setUpAll.

  setUpAll(() => fixture = FixturePackage.open('cases_app'));

  Future<List<String>> diagnostics(List<String> paths) async {
    final package = await fixture.collect(paths);
    return [
      for (final d
          in const ModuleConstruct().validate(package).toList()..sort())
        '$d',
    ];
  }

  test('missing providers of classes, controllers and components', () async {
    final found = await diagnostics([
      'lib/dependencies/graph.dart',
      'lib/modules/basic.dart',
    ]);

    expect(found.where((d) => d.endsWith('[missing_provider]')), [
      'lib/dependencies/graph.dart:36:15: error: No provider for Clock in '
          'module "MailModule" (resolving: Mailer). It is declared in '
          'module(s) [db]; export it there and import that module into '
          '"MailModule". [missing_provider]',
      'lib/dependencies/graph.dart:36:44: error: No provider for '
          'Token<String>(smtp.url) in module "MailModule" (resolving: '
          'Mailer). [missing_provider]',
      'lib/dependencies/graph.dart:51:13: error: No provider for OpenGuard '
          'in module "MailModule" (resolving: MailController). '
          '[missing_provider]',
      'lib/dependencies/graph.dart:53:36: error: No provider for Engine in '
          'module "MailModule" (resolving: MailController). It is declared in '
          'module(s) [CarModule]; export it there and import that module into '
          '"MailModule". [missing_provider]',
    ]);
  });

  test('a circular dependency is reported once', () async {
    final found = await diagnostics([
      'lib/dependencies/graph.dart',
      'lib/modules/basic.dart',
    ]);

    expect(found.where((d) => d.endsWith('[circular_dependency]')), [
      'lib/dependencies/graph.dart:11:13: error: Circular dependency: Engine '
          '-> Wheel -> Engine. [circular_dependency]',
    ]);
  });

  // Review Focus 4: no false missing_provider next to an opaque module.
  test('a module built by a function turns the check off', () async {
    final found = await diagnostics([
      'lib/dependencies/graph.dart',
      'lib/modules/basic.dart',
      'lib/modules/app.dart',
    ]);

    expect(found, isEmpty);
  });

  test('structural errors come alone, without resolution noise', () async {
    final found = await diagnostics([
      'lib/dependencies/graph.dart',
      'lib/modules/structure_errors.dart',
      'lib/modules/basic.dart',
    ]);

    expect(found, hasLength(6));
    expect(found.where((d) => d.contains('[missing_provider]')), isEmpty);
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd packages/dartnest_generator && dart test test/constructs/dependency_check_test.dart`
Expected: FAIL: 2 тести з 4 (`missing providers of classes, controllers and components`, `a circular dependency is reported once`) — `ModuleConstruct` ще не перевіряє залежності; два інші вже зелені й мають такими лишитися

- [ ] **Step 4: Write the scope and the check**

`packages/dartnest_generator/lib/src/constructs/module_scope.dart`:

```dart
import '../model/module_export.dart';
import '../model/module_model.dart';
import '../model/module_reference.dart';
import '../model/provider_key.dart';
import '../model/provider_model.dart';
import '../model/type_model.dart';

/// A provider as one module sees it: the provider and the module that
/// declares it.
typedef ScopedProvider = ({ModuleModel owner, ProviderModel provider});

/// What each module of a package can inject, by the rules of the core
/// injector: own providers, then exports of imports (with re-exports), then
/// exports of global modules.
///
/// Built only for a graph of `@Module` classes of this package with no
/// import cycles.
final class ModuleScope {
  /// Creates the scope of [modules].
  ModuleScope(this.modules)
    : _byType = {for (final module in modules) module.type: module};

  /// The modules.
  final List<ModuleModel> modules;

  final Map<TypeModel, ModuleModel> _byType;

  final Map<ModuleModel, Map<ProviderKey, ScopedProvider>> _visible = {};

  /// The providers [module] can inject, by key; computed once per module.
  Map<ProviderKey, ScopedProvider> visibleIn(ModuleModel module) =>
      _visible.putIfAbsent(module, () => _computeVisible(module));

  Map<ProviderKey, ScopedProvider> _computeVisible(ModuleModel module) => {
    for (final global in modules.reversed)
      if (global.isGlobal && global != module) ..._exported(global),
    for (final reference in module.imports.reversed)
      if (_local(reference) case final imported?) ..._exported(imported),
    for (final provider in module.providers.reversed)
      provider.key: (owner: module, provider: provider),
  };

  /// The ids of the modules that declare [key].
  List<String> declaring(ProviderKey key) => [
    for (final module in modules)
      if (module.providers.any((p) => p.key == key)) module.id,
  ];

  Map<ProviderKey, ScopedProvider> _exported(ModuleModel module) => {
    for (final export in module.exports.reversed)
      ...switch (export) {
        KeyExport(:final key) => {
          for (final provider in module.providers)
            if (provider.key == key) key: (owner: module, provider: provider),
        },
        ModuleReexport(module: final reference) => switch (_local(reference)) {
          final reexported? => _exported(reexported),
          null => const <ProviderKey, ScopedProvider>{},
        },
      },
  };

  ModuleModel? _local(ModuleReference reference) => switch (reference) {
    LocalModuleReference(:final type) => _byType[type],
    OpaqueModuleReference() => null,
  };
}
```

`packages/dartnest_generator/lib/src/constructs/dependency_check.dart`:

```dart
import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../diagnostic/source_location.dart';
import '../model/constructor_model.dart';
import '../model/controller_model.dart';
import '../model/module_export.dart';
import '../model/module_model.dart';
import '../model/module_reference.dart';
import '../model/package_model.dart';
import '../model/provider_key.dart';
import '../model/provider_model.dart';
import '../model/type_model.dart';
import 'module_scope.dart';

/// The startup checks that resolve dependencies: a missing provider and a
/// circular dependency, for provider classes, controllers and the pipeline
/// components controllers use.
///
/// A module built by a function (an explicit module or another package's)
/// can provide anything, so a package whose modules import one is not
/// checked here; `Application.create` still checks it at startup.
final class DependencyCheck {
  DependencyCheck._(this.package, this.scope);

  /// The package.
  final PackageModel package;

  /// What each module can inject.
  final ModuleScope scope;

  /// The dependency problems of [package].
  static List<Diagnostic> check(PackageModel package) {
    final opaque = package.modules.any(
      (m) => [
        ...m.imports,
        for (final e in m.exports)
          if (e case ModuleReexport(:final module)) module,
      ].any((r) => r is OpaqueModuleReference),
    );
    if (opaque) return const [];
    final check = DependencyCheck._(package, ModuleScope(package.modules));
    return [
      for (final module in package.modules) ...[
        ...check._missingInProviders(module),
        ...check._missingInControllers(module),
      ],
      ...check._cycles(),
    ];
  }

  Iterable<Diagnostic> _missingInProviders(ModuleModel module) sync* {
    for (final provider in module.providers) {
      if (provider case ClassProvider(:final injectable)) {
        yield* _missing(module, injectable.type, injectable.constructor);
      }
    }
  }

  Iterable<Diagnostic> _missingInControllers(ModuleModel module) sync* {
    final visible = scope.visibleIn(module);
    for (final type in module.controllers) {
      final controller = package.controllers
          .where((c) => c.type == type)
          .firstOrNull;
      if (controller == null) continue;
      yield* _missing(module, type, controller.constructor);
      for (final component in _components(controller)) {
        if (!visible.containsKey(TypeKey(component))) {
          yield _diagnostic(
            module,
            TypeKey(component),
            type,
            controller.location,
          );
        }
      }
    }
  }

  Iterable<Diagnostic> _missing(
    ModuleModel module,
    TypeModel owner,
    ConstructorModel constructor,
  ) sync* {
    final visible = scope.visibleIn(module);
    for (final dependency in constructor.dependencies) {
      final key = dependency.key;
      if (key != null && !visible.containsKey(key)) {
        yield _diagnostic(module, key, owner, dependency.location);
      }
    }
  }

  Diagnostic _diagnostic(
    ModuleModel module,
    ProviderKey key,
    TypeModel owner,
    SourceLocation location,
  ) {
    final declaring = scope.declaring(key);
    return Diagnostic(
      DiagnosticCode.missingProvider,
      location,
      'No provider for $key in module "${module.id}" (resolving: $owner).'
      '${declaring.isEmpty ? '' : ' It is declared in module(s) '
                '[${declaring.join(', ')}]; export it there and import that '
                'module into "${module.id}".'}',
    );
  }

  static List<TypeModel> _components(ControllerModel controller) => [
    for (final component in [
      ...controller.enhancers.all,
      for (final route in controller.routes) ...route.enhancers.all,
    ])
      if (component.isValid) component.type,
  ];

  Iterable<Diagnostic> _cycles() sync* {
    final reported = <ScopedProvider>{};
    for (final module in package.modules) {
      for (final provider in module.providers) {
        if (provider is! ClassProvider) continue;
        final start = (owner: module, provider: provider);
        final cycle = _cycleFrom(start, [start]);
        if (cycle == null || cycle.any(reported.contains)) continue;
        reported.addAll(cycle);
        yield Diagnostic(
          DiagnosticCode.circularDependency,
          provider.injectable.location,
          'Circular dependency: '
          '${[...cycle, start].map((p) => p.provider.key).join(' -> ')}.',
        );
      }
    }
  }

  List<ScopedProvider>? _cycleFrom(
    ScopedProvider start,
    List<ScopedProvider> path,
  ) {
    final current = path.last;
    if (current.provider case ClassProvider(:final injectable)) {
      final visible = scope.visibleIn(current.owner);
      for (final dependency in injectable.constructor.dependencies) {
        final next = visible[dependency.key];
        if (next == null || (next != start && path.contains(next))) continue;
        if (next == start) return path;
        if (_cycleFrom(start, [...path, next]) case final cycle?) return cycle;
      }
    }
    return null;
  }
}
```

- [ ] **Step 5: Resolve dependencies in a valid graph**

Повна заміна `module_construct.dart`:

`packages/dartnest_generator/lib/src/constructs/module_construct.dart`:

```dart
import '../construct/construct.dart';
import '../construct/generated_unit.dart';
import '../diagnostic/diagnostic.dart';
import '../emit/module_emitter.dart';
import '../model/generated_names.dart';
import '../model/package_model.dart';
import 'dependency_check.dart';
import 'module_structure_check.dart';

/// Checks the module graph the way `Application.create` would and
/// generates one function per `@Module` class.
final class ModuleConstruct implements Construct {
  /// Creates the construct.
  const ModuleConstruct();

  /// Dependencies are resolved only in a structurally valid graph, so one
  /// mistake is not reported again as missing providers.
  @override
  Iterable<Diagnostic> validate(PackageModel package) {
    final structure = ModuleStructureCheck.check(package.modules).toList();
    return structure.isEmpty ? DependencyCheck.check(package) : structure;
  }

  @override
  Iterable<GeneratedUnit> generate(PackageModel package) => [
    for (final module in package.modules)
      DartUnit(
        name: GeneratedNames.module(module.type.name),
        spec: ModuleEmitter.function(module),
        origin: module.location,
      ),
  ];
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd packages/dartnest_generator && dart test test/constructs/dependency_check_test.dart`
Expected: `+4: All tests passed!`

Run: `cd packages/dartnest_generator && dart test`
Expected: `+48: All tests passed!`

- [ ] **Step 7: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 8: Commit**

```bash
git add \
  packages/dartnest_generator/test/fixtures/cases_app/lib/dependencies/graph.dart \
  packages/dartnest_generator/test/constructs/dependency_check_test.dart \
  packages/dartnest_generator/lib/src/constructs/module_scope.dart \
  packages/dartnest_generator/lib/src/constructs/dependency_check.dart \
  packages/dartnest_generator/lib/src/constructs/module_construct.dart
git commit -m "feat(generator): check missing providers and dependency cycles"
```

### Task 9: `ControllerConstruct`: контролери, роути й прив'язки параметрів

`ControllerCheck.check(controller)` збирає всі перевірки одного контролера (рішення 7): конструктор через `ConstructorCheck`, `invalid_component` для компонентів класу й роутів, `unsupported_constant` для метаданих, `invalid_route_handler` з `RouteModel.problem`, `invalid_handler_parameter` у форматі `Controller.handler: problem`, `missing_from_json`, `unknown_path_parameter` (порівнюється з `RouteModel.pathParameters` повного шляху). `ControllerCheck.fullPath` склеює шлях контролера й роуту; `ControllerConstruct` шукає `duplicate_route` по всьому пакету: метод + шлях, у якому кожен `:name` замінено на `:` (Review Focus 5).

Генерація: `ControllerEmitter.function` пише `dartnest.Controller<X> xController() => dartnest.Controller<X>(path:, create: (i) => X(...), enhancers:, metadata:, routes: [...])` (`create: (_) => X()` без залежностей); `RouteEmitter.route` — `dartnest.Route.get('/p', (c, ctx) async => c.m(...), name: 'm', enhancers:, metadata:)` (`ctx` → `_`, якщо хендлеру контекст не потрібен; `async` лише коли є `await`); `ArgumentEmitter` — вираз кожної прив'язки (рішення 7, OP6, OP9); `EnhancersEmitter` — `const dartnest.Enhancers(guards: [dartnest.Use<T>()], …)` або нічого.

**Files:**
- Create: `packages/dartnest_generator/lib/src/emit/argument_emitter.dart`
- Create: `packages/dartnest_generator/lib/src/emit/enhancers_emitter.dart`
- Create: `packages/dartnest_generator/lib/src/emit/route_emitter.dart`
- Create: `packages/dartnest_generator/lib/src/emit/controller_emitter.dart`
- Create: `packages/dartnest_generator/lib/src/constructs/controller_check.dart`
- Create: `packages/dartnest_generator/lib/src/constructs/controller_construct.dart`
- Test: `packages/dartnest_generator/test/constructs/controller_construct_test.dart`

**Interfaces:**
- Consumes: Tasks 5–7 (`ControllerModel`, `RouteModel`, `HandlerParameter`, `ConstructorCheck`, `InjectionEmitter`, `ConstantEmitter`, `TypeEmitter`, `DartString`).
- Produces:
  - `constructs/controller_check.dart`: `ControllerCheck.check(ControllerModel controller) → Iterable<Diagnostic>`, `ControllerCheck.fullPath(ControllerModel controller, RouteModel route) → RouteModel`
  - `constructs/controller_construct.dart`: `const ControllerConstruct()`
  - `emit/argument_emitter.dart`: `ArgumentEmitter.argument(HandlerParameter) → Expression`, `ArgumentEmitter.awaits(HandlerParameter) → bool`
  - `emit/enhancers_emitter.dart`: `EnhancersEmitter.enhancers(EnhancersModel) → Expression?`
  - `emit/route_emitter.dart`: `RouteEmitter.route(RouteModel) → Expression`
  - `emit/controller_emitter.dart`: `ControllerEmitter.function(ControllerModel) → Method`

- [ ] **Step 1: Write the failing test**

`packages/dartnest_generator/test/constructs/controller_construct_test.dart`:

```dart
import 'package:dartnest_generator/src/construct/dartnest_generator.dart';
import 'package:dartnest_generator/src/constructs/controller_construct.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

const _generator = DartnestGenerator([ControllerConstruct()]);

void main() {
  late FixturePackage fixture; // Set in setUpAll.

  setUpAll(() => fixture = FixturePackage.open('cases_app'));

  test('one function per controller, every binding on the context', () async {
    final result = _generator.generate(
      await fixture.collect(['lib/controllers/users.dart']),
    );

    expect(result.diagnostics, isEmpty);
    expect(
      result.library,
      contains(r'''
/// The controller of `UsersController`.
dartnest.Controller<i1.UsersController> usersController() =>
    dartnest.Controller<i1.UsersController>(
      path: '/users',
      create: (_) => i1.UsersController(),
      enhancers: const dartnest.Enhancers(
        guards: [dartnest.Use<i2.OpenGuard>()],
      ),
      metadata: const [
        i2.Roles(<String>['admin']),
      ],
      routes: [
        dartnest.Route.get(
          '',
          (c, ctx) async => c.list(
            await ctx.query<int?>('limit'),
            await ctx.query<i1.Status?>(
              'status',
              pipes: const [dartnest.EnumPipe(i1.Status.values)],
            ),
          ),
          name: 'list',
          enhancers: const dartnest.Enhancers(
            interceptors: [dartnest.Use<i2.PassInterceptor>()],
          ),
        ),
        dartnest.Route.get(
          '/:id',
          (c, ctx) async =>
              c.find(await ctx.param<int>('id'), ctx.header('x-trace')),
          name: 'find',
        ),
        dartnest.Route.post(
          '',
          (c, ctx) async =>
              c.create(await ctx.bodyAs(i1.CreateUser.fromJson), ctx),
          name: 'create',
          enhancers: const dartnest.Enhancers(
            pipes: [dartnest.Use<i2.TrimPipe>()],
            filters: [dartnest.Use<i2.StateFilter>()],
          ),
          metadata: const [
            i2.Roles(<String>['owner']),
          ],
        ),
        dartnest.Route.put('/:id/note', (c, ctx) async {
          c.note(
            await ctx.param<String>('id'),
            await ctx.body.text(),
            ctx.switchToHttp().request,
          );
'''),
    );
  });

  // Review Focus 5: /j/:a and /j/:b are one route.
  test('handlers, parameters, components and routes it rejects', () async {
    final result = _generator.generate(
      await fixture.collect([
        'lib/controllers/invalid_handlers.dart',
        'lib/controllers/users.dart',
      ]),
    );

    expect(result.diagnostics.map((d) => '$d'), [
      'lib/controllers/invalid_handlers.dart:15:13: error: '
          'PassInterceptor in @UseGuards of BrokenController is not a '
          'Guard. [invalid_component]',
      'lib/controllers/invalid_handlers.dart:15:13: error: String in '
          '@UseGuards of BrokenController is not a Guard. '
          '[invalid_component]',
      'lib/controllers/invalid_handlers.dart:18:19: error: '
          'BrokenController.unbound: Parameter value (int) needs @Param, '
          '@Query, @Header or @Body, or the type ExecutionContext or '
          'HttpRequest. [invalid_handler_parameter]',
      'lib/controllers/invalid_handlers.dart:22:43: error: '
          'BrokenController.twice: Parameter id (int) has more than one '
          'of @Param, @Query, @Header and @Body. '
          '[invalid_handler_parameter]',
      'lib/controllers/invalid_handlers.dart:26:40: error: '
          'BrokenController.list: Parameter tags (List<String>): @Query '
          'supports String, int, double, num, bool, DateTime and enums, '
          'nullable or not. [invalid_handler_parameter]',
      'lib/controllers/invalid_handlers.dart:30:37: error: '
          'BrokenController.header: Parameter count (int): a @Header '
          'parameter is String or String?. [invalid_handler_parameter]',
      'lib/controllers/invalid_handlers.dart:34:27: error: @Body '
          'parameter opaque of BrokenController.body has type Opaque; '
          '@Body needs a class with a fromJson(Map<String, Object?>) '
          'constructor or static method, Map<String, Object?>, String or '
          'List<int>. [missing_from_json]',
      'lib/controllers/invalid_handlers.dart:39:8: error: Handler '
          'BrokenController.twoRoutes has more than one route annotation. '
          '[invalid_route_handler]',
      'lib/controllers/invalid_handlers.dart:43:15: error: Handler '
          'BrokenController.notInstance is static. '
          '[invalid_route_handler]',
      'lib/controllers/invalid_handlers.dart:47:5: error: Handler '
          'BrokenController.generic is generic. [invalid_route_handler]',
      'lib/controllers/invalid_handlers.dart:51:40: error: '
          "@Param('slug') of BrokenController.unknown is not in the route "
          'path; it declares id. [unknown_path_parameter]',
      'lib/controllers/invalid_handlers.dart:59:8: error: Route GET '
          '/broken/j/:b is declared twice: by BrokenController.first and '
          'by BrokenController.second. Parameter names do not distinguish '
          'routes. [duplicate_route]',
    ]);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/dartnest_generator && dart test test/constructs/controller_construct_test.dart`
Expected: FAIL: компіляція — `lib/src/constructs/controller_construct.dart` не існує

- [ ] **Step 3: Write the controller emitters**

`packages/dartnest_generator/lib/src/emit/argument_emitter.dart`:

```dart
import 'package:code_builder/code_builder.dart';

import '../model/body_kind.dart';
import '../model/handler_parameter.dart';
import '../model/parameter_binding.dart';
import '../model/type_kind.dart';
import '../model/type_model.dart';
import 'dart_string.dart';
import 'import_allocator.dart';
import 'type_emitter.dart';

/// Writes the expression that fills one handler parameter from the
/// `ExecutionContext` named `ctx`.
abstract final class ArgumentEmitter {
  static final _context = refer('ctx');

  /// The argument for [parameter]; an `await` expression for path, query
  /// and body bindings.
  static Expression argument(HandlerParameter parameter) =>
      switch (parameter.binding) {
        PathBinding(:final name) => _converted('param', name, parameter.type),
        QueryBinding(:final name) => _converted('query', name, parameter.type),
        HeaderBinding(:final name) => _header(name, parameter.type),
        BodyBinding(:final kind) => _body(kind, parameter.type),
        ContextBinding() => _context,
        RequestBinding() =>
          _context.property('switchToHttp').call(const []).property('request'),
        InvalidBinding(:final problem) => throw StateError(
          'An invalid parameter reached generation: $problem',
        ),
      };

  /// Whether the argument for [parameter] awaits.
  static bool awaits(HandlerParameter parameter) => switch (parameter.binding) {
    PathBinding() || QueryBinding() || BodyBinding() => true,
    _ => false,
  };

  static Expression _converted(String method, String name, TypeModel type) =>
      _context.property(method).call(
        [_string(name)],
        {
          if (type.kind == TypeKind.enumeration)
            'pipes': literalConstList([
              refer('EnumPipe', ImportAllocator.dartnest).call([
                TypeEmitter.reference(type.nonNullable).property('values'),
              ]),
            ]),
        },
        [TypeEmitter.reference(type)],
      ).awaited;

  static Expression _header(String name, TypeModel type) {
    final header = _context.property('header').call([_string(name)]);
    if (type.isNullable) return header;
    final missing = refer('BadRequestException', ImportAllocator.dartnest)
        .constInstance(const [], {
          'message': _string('Missing header "$name".'),
        })
        .thrown
        .parenthesized;
    return header.ifNullThen(missing);
  }

  static Expression _body(BodyKind kind, TypeModel type) => switch (kind) {
    BodyKind.fromJson => _context.property('bodyAs').call([
      TypeEmitter.reference(type).property('fromJson'),
    ]),
    BodyKind.jsonObject =>
      _context
          .property('bodyAs')
          .call(
            [
              Method(
                (b) => b
                  ..requiredParameters.add(Parameter((p) => p..name = 'json'))
                  ..lambda = true
                  ..body = refer('json').code,
              ).closure,
            ],
            const {},
            [TypeEmitter.reference(type)],
          ),
    BodyKind.text => _context.property('body').property('text').call(const []),
    BodyKind.bytes =>
      _context.property('body').property('bytes').call(const []),
    BodyKind.unsupported => throw StateError(
      'A body without fromJson reached generation.',
    ),
  }.awaited;

  static Expression _string(String value) =>
      CodeExpression(Code(DartString.literal(value)));
}
```

`packages/dartnest_generator/lib/src/emit/enhancers_emitter.dart`:

```dart
import 'package:code_builder/code_builder.dart';

import '../model/component_reference.dart';
import '../model/enhancers_model.dart';
import 'import_allocator.dart';
import 'type_emitter.dart';

/// Writes [EnhancersModel]s as `const Enhancers(...)` of `Use<T>()`
/// components, resolved from the module's injector.
abstract final class EnhancersEmitter {
  /// `const Enhancers(guards: [Use<AuthGuard>()])`, or `null` when
  /// [enhancers] is empty.
  static Expression? enhancers(EnhancersModel enhancers) {
    final lists = {
      'guards': enhancers.guards,
      'interceptors': enhancers.interceptors,
      'pipes': enhancers.pipes,
      'filters': enhancers.filters,
    };
    if (lists.values.every((list) => list.isEmpty)) return null;
    return refer(
      'Enhancers',
      ImportAllocator.dartnest,
    ).constInstance(const [], {
      for (final MapEntry(:key, :value) in lists.entries)
        if (value.isNotEmpty) key: literalList(value.map(_use)),
    });
  }

  static Expression _use(ComponentReference component) => TypeReference(
    (b) => b
      ..symbol = 'Use'
      ..url = ImportAllocator.dartnest
      ..types.add(TypeEmitter.reference(component.type)),
  ).newInstance(const []);
}
```

`packages/dartnest_generator/lib/src/emit/route_emitter.dart`:

```dart
import 'package:code_builder/code_builder.dart';

import '../model/route_model.dart';
import '../model/type_kind.dart';
import 'argument_emitter.dart';
import 'constant_emitter.dart';
import 'dart_string.dart';
import 'enhancers_emitter.dart';
import 'import_allocator.dart';

/// Writes a [RouteModel] as `Route.get(path, (c, ctx) => ..., name: ...)`.
abstract final class RouteEmitter {
  /// The route of [route].
  static Expression route(RouteModel route) {
    final enhancers = EnhancersEmitter.enhancers(route.enhancers);
    return refer('Route', ImportAllocator.dartnest)
        .property(route.method.toLowerCase())
        .call(
          [
            CodeExpression(Code(DartString.literal(route.path))),
            _handler(route),
          ],
          {
            'name': CodeExpression(Code(DartString.literal(route.handlerName))),
            'enhancers': ?enhancers,
            if (route.metadata.isNotEmpty)
              'metadata': ConstantEmitter.list(route.metadata),
          },
        );
  }

  /// `(c, ctx) async => c.find(await ctx.param<int>('id'))`; a `void`
  /// handler gets a block that returns `null` (204).
  static Expression _handler(RouteModel route) {
    final positional = <Expression>[];
    final named = <String, Expression>{};
    for (final parameter in route.parameters) {
      final argument = ArgumentEmitter.argument(parameter);
      if (parameter.isNamed) {
        named[parameter.name] = argument;
      } else {
        positional.add(argument);
      }
    }
    final call = refer('c').property(route.handlerName).call(positional, named);
    final returnsVoid = route.returnType.kind == TypeKind.voidType;
    final returnsFutureVoid = _isFutureOfVoid(route);
    final isAsync =
        returnsFutureVoid || route.parameters.any(ArgumentEmitter.awaits);
    return Method(
      (b) => b
        ..requiredParameters.addAll([
          Parameter((p) => p..name = 'c'),
          Parameter((p) => p..name = route.parameters.isEmpty ? '_' : 'ctx'),
        ])
        ..modifier = isAsync ? MethodModifier.async : null
        ..lambda = !(returnsVoid || returnsFutureVoid)
        ..body = returnsVoid || returnsFutureVoid
            ? Block.of([
                (returnsFutureVoid ? call.awaited : call).statement,
                literalNull.returned.statement,
              ])
            : call.code,
    ).closure;
  }

  static bool _isFutureOfVoid(RouteModel route) {
    final type = route.returnType;
    return (type.name == 'Future' || type.name == 'FutureOr') &&
        type.libraryUri == 'dart:async' &&
        type.typeArguments.singleOrNull?.kind == TypeKind.voidType;
  }
}
```

`packages/dartnest_generator/lib/src/emit/controller_emitter.dart`:

```dart
import 'package:code_builder/code_builder.dart';

import '../model/controller_model.dart';
import '../model/generated_names.dart';
import 'constant_emitter.dart';
import 'dart_string.dart';
import 'enhancers_emitter.dart';
import 'import_allocator.dart';
import 'injection_emitter.dart';
import 'route_emitter.dart';
import 'type_emitter.dart';

/// Writes a [ControllerModel] as a function returning the core
/// `Controller<T>`.
abstract final class ControllerEmitter {
  /// `Controller<UsersController> usersController() => Controller(...)`.
  static Method function(ControllerModel controller) {
    final type = TypeReference(
      (b) => b
        ..symbol = 'Controller'
        ..url = ImportAllocator.dartnest
        ..types.add(TypeEmitter.reference(controller.type)),
    );
    final enhancers = EnhancersEmitter.enhancers(controller.enhancers);
    return Method(
      (b) => b
        ..docs.add('/// The controller of `${controller.type.name}`.')
        ..name = GeneratedNames.controller(controller.type.name)
        ..returns = type
        ..lambda = true
        ..body = type.newInstance(const [], {
          if (controller.path.isNotEmpty)
            'path': CodeExpression(Code(DartString.literal(controller.path))),
          'create': _create(controller),
          'enhancers': ?enhancers,
          if (controller.metadata.isNotEmpty)
            'metadata': ConstantEmitter.list(controller.metadata),
          'routes': literalList(controller.routes.map(RouteEmitter.route)),
        }).code,
    );
  }

  static Expression _create(ControllerModel controller) => Method(
    (b) => b
      ..requiredParameters.add(
        Parameter(
          (p) =>
              p..name = controller.constructor.dependencies.isEmpty ? '_' : 'i',
        ),
      )
      ..lambda = true
      ..body = InjectionEmitter.create(
        controller.type,
        controller.constructor,
      ).code,
  ).closure;
}
```

- [ ] **Step 4: Write the check and the construct**

`packages/dartnest_generator/lib/src/constructs/controller_check.dart`:

```dart
import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../diagnostic/source_location.dart';
import '../model/body_kind.dart';
import '../model/constant_value.dart';
import '../model/controller_model.dart';
import '../model/enhancers_model.dart';
import '../model/handler_parameter.dart';
import '../model/parameter_binding.dart';
import '../model/route_model.dart';
import 'constructor_check.dart';

/// The checks of one controller: its constructor, components, metadata,
/// handlers and their parameters.
abstract final class ControllerCheck {
  /// The problems of [controller].
  static Iterable<Diagnostic> check(ControllerModel controller) sync* {
    final name = controller.type.name;
    yield* ConstructorCheck.check(
      controller.type,
      controller.constructor,
      controller.location,
    );
    yield* _components(controller.enhancers, name, controller.location);
    yield* _metadata(controller.metadata, name, controller.location);
    for (final route in controller.routes) {
      final handler = '$name.${route.handlerName}';
      if (route.problem case final problem?) {
        yield Diagnostic(
          DiagnosticCode.invalidRouteHandler,
          route.location,
          problem,
        );
        continue;
      }
      yield* _components(route.enhancers, handler, route.location);
      yield* _metadata(route.metadata, handler, route.location);
      final declared = fullPath(controller, route).pathParameters;
      for (final parameter in route.parameters) {
        yield* _parameter(parameter, handler, declared);
      }
    }
  }

  /// [route] with the controller path in front.
  static RouteModel fullPath(
    ControllerModel controller,
    RouteModel route,
  ) => RouteModel(
    method: route.method,
    path:
        '/${[for (final segment in '${controller.path}/${route.path}'.split('/'))
          if (segment.isNotEmpty) segment].join('/')}',
    handlerName: route.handlerName,
    returnType: route.returnType,
    location: route.location,
  );

  static Iterable<Diagnostic> _components(
    EnhancersModel enhancers,
    String owner,
    SourceLocation location,
  ) {
    final kinds = {
      'UseGuards': (enhancers.guards, 'Guard'),
      'UseInterceptors': (enhancers.interceptors, 'Interceptor'),
      'UsePipes': (enhancers.pipes, 'Pipe'),
      'UseFilters': (enhancers.filters, 'ExceptionFilter'),
    };
    return [
      for (final MapEntry(key: annotation, value: (list, kind))
          in kinds.entries)
        for (final component in list)
          if (!component.isValid)
            Diagnostic(
              DiagnosticCode.invalidComponent,
              location,
              '${component.type.name} in @$annotation of $owner is not a '
              '$kind.',
            ),
    ];
  }

  static Iterable<Diagnostic> _metadata(
    List<ConstantValue> metadata,
    String owner,
    SourceLocation location,
  ) => [
    for (final value in metadata)
      if (value.unsupported case final unsupported?)
        Diagnostic(
          DiagnosticCode.unsupportedConstant,
          location,
          'Metadata of $owner cannot be written in generated code: '
          '${unsupported.reason}. Use public constants and const constructors '
          'of public classes.',
        ),
  ];

  static Iterable<Diagnostic> _parameter(
    HandlerParameter parameter,
    String handler,
    List<String> declared,
  ) sync* {
    switch (parameter.binding) {
      case InvalidBinding(:final problem):
        yield Diagnostic(
          DiagnosticCode.invalidHandlerParameter,
          parameter.location,
          '$handler: $problem',
        );
      case BodyBinding(kind: BodyKind.unsupported):
        yield Diagnostic(
          DiagnosticCode.missingFromJson,
          parameter.location,
          '@Body parameter ${parameter.name} of $handler has type '
          '${parameter.type}; @Body needs a class with a '
          'fromJson(Map<String, Object?>) constructor or static method, '
          'Map<String, Object?>, String or List<int>.',
        );
      case PathBinding(:final name) when !declared.contains(name):
        yield Diagnostic(
          DiagnosticCode.unknownPathParameter,
          parameter.location,
          "@Param('$name') of $handler is not in the route path; it declares "
          '${declared.isEmpty ? 'no parameters' : declared.join(', ')}.',
        );
      default:
        break;
    }
  }
}
```

`packages/dartnest_generator/lib/src/constructs/controller_construct.dart`:

```dart
import '../construct/construct.dart';
import '../construct/generated_unit.dart';
import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../emit/controller_emitter.dart';
import '../model/generated_names.dart';
import '../model/package_model.dart';
import 'controller_check.dart';

/// Checks controllers and their handlers and generates one function per
/// `@Controller` class.
final class ControllerConstruct implements Construct {
  /// Creates the construct.
  const ControllerConstruct();

  @override
  Iterable<Diagnostic> validate(PackageModel package) => [
    for (final controller in package.controllers)
      ...ControllerCheck.check(controller),
    ..._duplicateRoutes(package),
  ];

  @override
  Iterable<GeneratedUnit> generate(PackageModel package) => [
    for (final controller in package.controllers)
      DartUnit(
        name: GeneratedNames.controller(controller.type.name),
        spec: ControllerEmitter.function(controller),
        origin: controller.location,
      ),
  ];

  /// Routes with the same method and path shape across the package; path
  /// parameter names do not distinguish routes.
  static Iterable<Diagnostic> _duplicateRoutes(PackageModel package) sync* {
    final first = <String, String>{};
    for (final controller in package.controllers) {
      for (final route in controller.routes) {
        if (route.problem != null) continue;
        final full = ControllerCheck.fullPath(controller, route);
        final shape = full.path.replaceAll(RegExp(r':[^/]*'), ':');
        final handler = '${controller.type.name}.${route.handlerName}';
        final existing = first.putIfAbsent(
          '${route.method} $shape',
          () => handler,
        );
        if (existing != handler) {
          yield Diagnostic(
            DiagnosticCode.duplicateRoute,
            route.location,
            'Route ${route.method} ${full.path} is declared twice: by '
            '$existing and by $handler. Parameter names do not distinguish '
            'routes.',
          );
        }
      }
    }
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd packages/dartnest_generator && dart test test/constructs/controller_construct_test.dart`
Expected: `+2: All tests passed!`

Run: `cd packages/dartnest_generator && dart test`
Expected: `+50: All tests passed!`

- [ ] **Step 6: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 7: Commit**

```bash
git add \
  packages/dartnest_generator/test/constructs/controller_construct_test.dart \
  packages/dartnest_generator/lib/src/emit/argument_emitter.dart \
  packages/dartnest_generator/lib/src/emit/enhancers_emitter.dart \
  packages/dartnest_generator/lib/src/emit/route_emitter.dart \
  packages/dartnest_generator/lib/src/emit/controller_emitter.dart \
  packages/dartnest_generator/lib/src/constructs/controller_check.dart \
  packages/dartnest_generator/lib/src/constructs/controller_construct.dart
git commit -m "feat(generator): generate controllers and routes"
```

### Task 10: `DartnestGenerator.core()`, golden `users_app` і e2e на обох графах

Фікстура `users_app` — невеликий застосунок користувачів (у дусі e2e ядра етапу 2), написаний анотаціями: глобальний `ConfigModule` (токен `greetingWord` через `Value`, `Bind<Clock, EpochClock>`, `Greeter` з `@Inject`), `UsersModule` (контролер `/users` з `@Query int?`, `@Param int`, `@Body CreateUserDto`, `ExecutionContext`, guards `AuthGuard`/`RolesGuard` на роуті, `@UseFilters([UserMissingFilter])`, метадані `Roles(['admin'])`), `GreetingModule` (`@Header String?`, enum-параметр шляху, `void`-хендлер) і `AppModule`. `explicit.dart` — той самий граф явним API (`explicitAppModule`), написаний вручну.

`users_app.dartnest.dart` — golden: його текст нижче є очікуваним виводом генератора, і він закомічений, тож e2e-тест імпортує згенерований `appModule` як звичайну бібліотеку. `golden_test.dart` порівнює вихід з файлом (`DARTNEST_UPDATE_GOLDENS=1` перезаписує його після свідомої зміни виводу), перевіряє детермінізм (Review Focus 2) і що модель несе doc-коментарі та `DtoModel`. `users_app_e2e_test.dart` запускає один набір із 8 тестів двічі: `group('explicit', …)` на `explicitAppModule` і `group('generated', …)` на `appModule`.

`DartnestGenerator.core()` = `[ModuleConstruct(), ControllerConstruct(), ProviderConstruct()]`; barrel експортує три конструкти й показує використання драйвером.

**Files:**
- Create: `packages/dartnest_generator/test/fixtures/users_app/pubspec.yaml`
- Create: `packages/dartnest_generator/test/fixtures/users_app/analysis_options.yaml`
- Create: `packages/dartnest_generator/test/fixtures/users_app/lib/src/auth.dart`
- Create: `packages/dartnest_generator/test/fixtures/users_app/lib/src/users.dart`
- Create: `packages/dartnest_generator/test/fixtures/users_app/lib/src/greeting.dart`
- Create: `packages/dartnest_generator/test/fixtures/users_app/lib/src/modules.dart`
- Create: `packages/dartnest_generator/test/fixtures/users_app/lib/users_app.dart`
- Create: `packages/dartnest_generator/test/fixtures/users_app/lib/explicit.dart`
- Create: `packages/dartnest_generator/test/fixtures/users_app/lib/users_app.dartnest.dart`
- Modify: `pubspec.yaml`
- Modify: `packages/dartnest_generator/pubspec.yaml`
- Modify: `packages/dartnest_generator/lib/src/construct/dartnest_generator.dart`
- Modify: `packages/dartnest_generator/lib/dartnest_generator.dart`
- Test: `packages/dartnest_generator/test/golden/golden_test.dart`
- Test: `packages/dartnest_generator/test/e2e/users_app_e2e_test.dart`

**Interfaces:**
- Consumes: усе з Tasks 2–9; з ядра — `Application.create`, `TestClient`, `Module`, `Controller`, `Route`, `Provider`, `Use`, `Enhancers`, `EnumPipe`, `Token`, `Guard`, `ExceptionFilter`, `HttpException`/`NotFoundException`/`BadRequestException`, `ExecutionContext`.
- Produces:
  - `const DartnestGenerator.core()` (для CLI етапу 5 і build_runner етапу 6)
  - `package:dartnest_generator/dartnest_generator.dart` експортує `PackageCollector`, `Construct`, `GeneratedUnit`/`DartUnit`/`FileUnit`/`ContentType`, `GenerationResult`, `DartnestGenerator`, `ModuleConstruct`, `ProviderConstruct`, `ControllerConstruct`, `Diagnostic`, `DiagnosticCode`, `SourceLocation`, `LibraryWriter`, усю модель
  - golden `packages/dartnest_generator/test/fixtures/users_app/lib/users_app.dartnest.dart`

- [ ] **Step 1: Add the users_app fixture**

Новий член workspace і dev-залежності генератора (`dartnest` для e2e, `users_app` для golden):

`pubspec.yaml`:

```yaml
name: dartnest_workspace
publish_to: none
environment:
  sdk: ^3.8.0
workspace:
  - packages/dartnest
  - packages/dartnest_annotations
  - packages/dartnest_conformance
  - packages/dartnest_generator
  - packages/dartnest_generator/test/fixtures/cases_app
  - packages/dartnest_generator/test/fixtures/users_app
  - packages/dartnest_io
  - packages/dartnest_shelf
```

`packages/dartnest_generator/pubspec.yaml`:

```yaml
name: dartnest_generator
description: >-
  Turns dartnest annotations into ordinary code on the explicit dartnest API,
  with static validation of the module graph.
version: 0.1.0-dev
publish_to: none
environment:
  sdk: ^3.8.0
resolution: workspace
dependencies:
  analyzer: '>=8.1.1 <15.0.0'
  code_builder: ^4.11.1
  dart_style: ^3.1.2
  path: ^1.9.0
  pub_semver: ^2.1.4
dev_dependencies:
  cases_app: ^0.1.0-dev
  dartnest: ^0.1.0-dev
  lints: ^5.1.0
  test: ^1.25.0
  users_app: ^0.1.0-dev
```

`packages/dartnest_generator/test/fixtures/users_app/pubspec.yaml`:

```yaml
name: users_app
description: >-
  The core e2e users application written with annotations; its generated
  library is the golden file of dartnest_generator.
version: 0.1.0-dev
publish_to: none

environment:
  sdk: ^3.8.0

resolution: workspace

dependencies:
  dartnest: ^0.1.0-dev
  dartnest_annotations: ^0.1.0-dev
```

`packages/dartnest_generator/test/fixtures/users_app/analysis_options.yaml`:

```yaml
include: ../../../../../analysis_options.yaml
```

`packages/dartnest_generator/test/fixtures/users_app/lib/src/auth.dart`:

```dart
// Authentication: a bearer guard, a roles guard and their metadata.
import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

/// Route metadata: roles allowed to call a handler.
final class Roles extends RouteMetadata {
  /// Creates the metadata.
  const Roles(this.names);

  /// The role names.
  final List<String> names;
}

/// Accepts `authorization: Bearer <role>`; stores the role in `items`.
@Injectable()
final class AuthGuard implements Guard {
  @override
  bool canActivate(ExecutionContext context) {
    final header = context.header('authorization');
    if (header == null || !header.startsWith('Bearer ')) {
      throw const UnauthorizedException(
        headers: {'www-authenticate': 'Bearer'},
      );
    }
    context.items[#role] = header.substring('Bearer '.length);
    return true;
  }
}

/// Allows a handler only for the roles in its [Roles] metadata.
@Injectable()
final class RolesGuard implements Guard {
  @override
  bool canActivate(ExecutionContext context) {
    final roles = context.metadata<Roles>();
    return roles == null || roles.names.contains(context.items[#role]);
  }
}
```

`packages/dartnest_generator/test/fixtures/users_app/lib/src/users.dart`:

```dart
// Users: the service, the DTOs and the controller.
import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'auth.dart';

/// Thrown by [UsersService] for an unknown id.
final class UserMissing implements Exception {
  /// Creates the error.
  UserMissing(this.id);

  /// The unknown id.
  final int id;
}

/// A user.
final class User {
  /// Creates a user.
  User(this.id, this.name);

  /// The id.
  final int id;

  /// The name.
  final String name;

  /// The JSON form.
  Map<String, Object?> toJson() => {'id': id, 'name': name};
}

/// Body of `POST /users`.
final class CreateUserDto {
  /// Creates the body.
  CreateUserDto(this.name);

  /// Reads the body; an empty name is a 400.
  factory CreateUserDto.fromJson(Map<String, Object?> json) => switch (json) {
    {'name': final String name} when name.isNotEmpty => CreateUserDto(name),
    _ => throw const FormatException('"name" must be a non-empty string'),
  };

  /// The name.
  final String name;
}

/// In-memory users.
@Injectable()
final class UsersService {
  final Map<int, User> _users = {1: User(1, 'ann'), 2: User(2, 'bob')};

  /// The first [limit] users.
  List<User> list({required int limit}) => _users.values.take(limit).toList();

  /// The user [id].
  User find(int id) => _users[id] ?? (throw UserMissing(id));

  /// Adds a user.
  User create(String name) {
    final user = User(_users.length + 1, name);
    _users[user.id] = user;
    return user;
  }
}

/// Maps [UserMissing] to 404.
@Injectable()
final class UserMissingFilter extends ExceptionFilter<UserMissing> {
  @override
  Object? handle(UserMissing error, ExecutionContext context) =>
      throw NotFoundException(message: 'No user ${error.id}');
}

/// Reads are public, writes need an admin.
@Controller('/users')
@UseFilters([UserMissingFilter])
final class UsersController {
  /// Creates the controller.
  UsersController(this.service);

  /// The users.
  final UsersService service;

  /// Lists users, 10 unless `?limit=` says otherwise.
  @Get()
  List<User> list(@Query('limit') int? limit) =>
      service.list(limit: limit ?? 10);

  /// Finds one user.
  @Get('/:id')
  User findOne(@Param('id') int id) => service.find(id);

  /// Creates a user: 201 with its location.
  @Post()
  @UseGuards([AuthGuard, RolesGuard])
  @Roles(['admin'])
  User create(@Body() CreateUserDto dto, ExecutionContext context) {
    final user = service.create(dto.name);
    context.switchToHttp().response
      ..status = StatusCode.created
      ..headers.set('location', '/users/${user.id}');
    return user;
  }
}
```

`packages/dartnest_generator/test/fixtures/users_app/lib/src/greeting.dart`:

```dart
// A global configuration module: a token value, a bound interface and a
// service other modules use without importing it.
import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

/// The greeting word.
const greetingWord = Token<String>('greeting.word');

/// User status.
enum Status { active, banned }

/// Tells the time.
abstract interface class Clock {
  /// The current time.
  DateTime now();
}

/// A clock stuck at the epoch, so responses are stable.
@Injectable()
final class EpochClock implements Clock {
  @override
  DateTime now() => DateTime.utc(1970);
}

/// Builds greetings.
@Injectable()
final class Greeter {
  /// Creates the greeter.
  Greeter(@Inject(greetingWord) this.word, this.clock);

  /// The greeting word.
  final String word;

  /// The clock.
  final Clock clock;

  /// A greeting for [name].
  Map<String, Object?> greet(String name) => {
    'greeting': '$word, $name!',
    'at': clock.now().toIso8601String(),
  };
}

/// Greets callers and echoes statuses.
@Controller()
final class GreetingController {
  /// Creates the controller.
  GreetingController(this.greeter);

  /// The greeter.
  final Greeter greeter;

  /// `GET /hello`, with an optional `x-name` header.
  @Get('/hello')
  Map<String, Object?> hello(@Header('x-name') String? name) =>
      greeter.greet(name ?? 'world');

  /// `GET /status/:status` echoes an enum path parameter.
  @Get('/status/:status')
  Map<String, String> status(@Param('status') Status status) => {
    'status': status.name,
  };

  /// `DELETE /hello` does nothing: 204.
  @Delete('/hello')
  void forget() {}
}
```

`packages/dartnest_generator/test/fixtures/users_app/lib/src/modules.dart`:

```dart
// The module graph, in annotations.
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'auth.dart';
import 'greeting.dart';
import 'users.dart';

/// Configuration every module sees.
@Module(
  id: 'config',
  providers: [
    Value('Hello', token: greetingWord),
    Bind<Clock, EpochClock>(),
    Greeter,
  ],
  exports: [Greeter],
  global: true,
)
class ConfigModule {}

/// Users and their guards.
@Module(
  id: 'users',
  providers: [UsersService, AuthGuard, RolesGuard, UserMissingFilter],
  controllers: [UsersController],
)
class UsersModule {}

/// Greetings; [Greeter] comes from the global [ConfigModule].
@Module(id: 'greeting', controllers: [GreetingController])
class GreetingModule {}

/// The application root.
@Module(id: 'app', imports: [ConfigModule, UsersModule, GreetingModule])
class AppModule {}
```

`packages/dartnest_generator/test/fixtures/users_app/lib/users_app.dart`:

```dart
/// The users application: classes shared by the annotated and the explicit
/// modules.
library;

export 'src/auth.dart';
export 'src/greeting.dart';
export 'src/modules.dart';
export 'src/users.dart';
```

`packages/dartnest_generator/test/fixtures/users_app/lib/explicit.dart`:

```dart
// The users application written by hand with the explicit API: the
// reference the generated modules must behave like.
import 'package:dartnest/dartnest.dart';

import 'users_app.dart';

/// The application root, written by hand.
Module explicitAppModule() => Module(
  id: 'app',
  imports: [_configModule(), _usersModule(), _greetingModule()],
);

Module _configModule() => Module(
  id: 'config',
  providers: [
    Provider<String>.value('Hello', token: greetingWord),
    Provider<Clock>((i) => EpochClock()),
    Provider((i) => Greeter(i.get(greetingWord), i.get())),
  ],
  exports: [Greeter],
  global: true,
);

Module _usersModule() => Module(
  id: 'users',
  providers: [
    Provider((i) => UsersService()),
    Provider((i) => AuthGuard()),
    Provider((i) => RolesGuard()),
    Provider((i) => UserMissingFilter()),
  ],
  controllers: [
    Controller<UsersController>(
      path: '/users',
      create: (i) => UsersController(i.get()),
      enhancers: const Enhancers(filters: [Use<UserMissingFilter>()]),
      routes: [
        Route.get(
          '',
          (c, ctx) async => c.list(await ctx.query<int?>('limit')),
          name: 'list',
        ),
        Route.get(
          '/:id',
          (c, ctx) async => c.findOne(await ctx.param<int>('id')),
          name: 'findOne',
        ),
        Route.post(
          '',
          (c, ctx) async =>
              c.create(await ctx.bodyAs(CreateUserDto.fromJson), ctx),
          name: 'create',
          enhancers: const Enhancers(
            guards: [Use<AuthGuard>(), Use<RolesGuard>()],
          ),
          metadata: const [
            Roles(['admin']),
          ],
        ),
      ],
    ),
  ],
);

Module _greetingModule() => Module(
  id: 'greeting',
  controllers: [
    Controller<GreetingController>(
      create: (i) => GreetingController(i.get()),
      routes: [
        Route.get(
          '/hello',
          (c, ctx) => c.hello(ctx.header('x-name')),
          name: 'hello',
        ),
        Route.get(
          '/status/:status',
          (c, ctx) async => c.status(
            await ctx.param<Status>(
              'status',
              pipes: const [EnumPipe(Status.values)],
            ),
          ),
          name: 'status',
        ),
        Route.delete('/hello', (c, _) {
          c.forget();
          return null;
        }, name: 'forget'),
      ],
    ),
  ],
);
```

Run: `dart pub get`
Expected: `Got dependencies!` (з кореня репозиторію)

- [ ] **Step 2: Write the golden file and the failing tests**

Очікуваний вивід генератора (байт-у-байт; файл форматований і проходить lint'и репозиторію):

`packages/dartnest_generator/test/fixtures/users_app/lib/users_app.dartnest.dart`:

```dart
// GENERATED BY dartnest_generator. DO NOT EDIT.

/// Generated from the annotations of package:users_app.
library;

import 'package:dartnest/dartnest.dart' as dartnest;
import 'package:users_app/src/auth.dart' as i3;
import 'package:users_app/src/greeting.dart' as i1;
import 'package:users_app/src/users.dart' as i2;

/// The module of `ConfigModule`.
dartnest.Module configModule() => dartnest.Module(
  id: 'config',
  providers: [
    dartnest.Provider<String>.value('Hello', token: i1.greetingWord),
    dartnest.Provider<i1.Clock>(_createEpochClock),
    dartnest.Provider<i1.Greeter>(_createGreeter),
  ],
  exports: [i1.Greeter],
  global: true,
);

/// The module of `UsersModule`.
dartnest.Module usersModule() => dartnest.Module(
  id: 'users',
  providers: [
    dartnest.Provider<i2.UsersService>(_createUsersService),
    dartnest.Provider<i3.AuthGuard>(_createAuthGuard),
    dartnest.Provider<i3.RolesGuard>(_createRolesGuard),
    dartnest.Provider<i2.UserMissingFilter>(_createUserMissingFilter),
  ],
  controllers: [usersController()],
);

/// The module of `GreetingModule`.
dartnest.Module greetingModule() =>
    dartnest.Module(id: 'greeting', controllers: [greetingController()]);

/// The module of `AppModule`.
dartnest.Module appModule() => dartnest.Module(
  id: 'app',
  imports: [configModule(), usersModule(), greetingModule()],
);

/// The controller of `GreetingController`.
dartnest.Controller<i1.GreetingController> greetingController() =>
    dartnest.Controller<i1.GreetingController>(
      create: (i) => i1.GreetingController(i.get<i1.Greeter>()),
      routes: [
        dartnest.Route.get(
          '/hello',
          (c, ctx) => c.hello(ctx.header('x-name')),
          name: 'hello',
        ),
        dartnest.Route.get(
          '/status/:status',
          (c, ctx) async => c.status(
            await ctx.param<i1.Status>(
              'status',
              pipes: const [dartnest.EnumPipe(i1.Status.values)],
            ),
          ),
          name: 'status',
        ),
        dartnest.Route.delete('/hello', (c, _) {
          c.forget();
          return null;
        }, name: 'forget'),
      ],
    );

/// The controller of `UsersController`.
dartnest.Controller<i2.UsersController> usersController() =>
    dartnest.Controller<i2.UsersController>(
      path: '/users',
      create: (i) => i2.UsersController(i.get<i2.UsersService>()),
      enhancers: const dartnest.Enhancers(
        filters: [dartnest.Use<i2.UserMissingFilter>()],
      ),
      routes: [
        dartnest.Route.get(
          '',
          (c, ctx) async => c.list(await ctx.query<int?>('limit')),
          name: 'list',
        ),
        dartnest.Route.get(
          '/:id',
          (c, ctx) async => c.findOne(await ctx.param<int>('id')),
          name: 'findOne',
        ),
        dartnest.Route.post(
          '',
          (c, ctx) async =>
              c.create(await ctx.bodyAs(i2.CreateUserDto.fromJson), ctx),
          name: 'create',
          enhancers: const dartnest.Enhancers(
            guards: [
              dartnest.Use<i3.AuthGuard>(),
              dartnest.Use<i3.RolesGuard>(),
            ],
          ),
          metadata: const [
            i3.Roles(<String>['admin']),
          ],
        ),
      ],
    );

i1.EpochClock _createEpochClock(dartnest.Injector i) => i1.EpochClock();

i1.Greeter _createGreeter(dartnest.Injector i) =>
    i1.Greeter(i.get(i1.greetingWord), i.get<i1.Clock>());

i2.UsersService _createUsersService(dartnest.Injector i) => i2.UsersService();

i3.AuthGuard _createAuthGuard(dartnest.Injector i) => i3.AuthGuard();

i3.RolesGuard _createRolesGuard(dartnest.Injector i) => i3.RolesGuard();

i2.UserMissingFilter _createUserMissingFilter(dartnest.Injector i) =>
    i2.UserMissingFilter();
```

`packages/dartnest_generator/test/golden/golden_test.dart`:

```dart
// The generated library of users_app, compared with the committed one.
// Regenerate it with: DARTNEST_UPDATE_GOLDENS=1 dart test test/golden
import 'dart:io';

import 'package:dartnest_generator/dartnest_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

const _golden = 'lib/users_app.dartnest.dart';

void main() {
  late FixturePackage fixture; // Set in setUpAll.

  setUpAll(() => fixture = FixturePackage.open('users_app'));

  test('users_app generates its committed library', () async {
    final result = const DartnestGenerator.core().generate(
      await fixture.collect(),
    );

    expect(result.diagnostics, isEmpty);
    final library = result.library ?? fail('no library');
    if (Platform.environment['DARTNEST_UPDATE_GOLDENS'] == '1') {
      File(p.join(fixture.root, _golden)).writeAsStringSync(library);
    }
    expect(library, fixture.read(_golden));
  });

  // Review Focus 2: drivers pass libraries in any order.
  test('the output does not depend on the order of libraries', () async {
    final libraries = await fixture.libraries();
    final collector = PackageCollector('users_app', fixture.root);

    final forward = const DartnestGenerator.core().generate(
      collector.collect(libraries),
    );
    final backward = const DartnestGenerator.core().generate(
      collector.collect(libraries.reversed),
    );

    expect(backward.library, forward.library);
  });

  test('the model carries documentation and data classes', () async {
    final package = await fixture.collect();

    expect(
      package.modules.firstWhere((m) => m.id == 'config').documentation,
      '/// Configuration every module sees.',
    );
    expect(
      [for (final dto in package.dtos) dto.type.name],
      ['CreateUserDto', 'User'],
    );
  });
}
```

`packages/dartnest_generator/test/e2e/users_app_e2e_test.dart`:

```dart
// One suite, two module graphs: written by hand with the explicit API and
// generated from annotations. The generated graph must behave the same.
import 'package:dartnest/dartnest.dart';
import 'package:dartnest/testing.dart';
import 'package:test/test.dart';
import 'package:users_app/explicit.dart';
import 'package:users_app/users_app.dartnest.dart';

void main() {
  group('explicit', () => _suite(explicitAppModule));
  group('generated', () => _suite(appModule));
}

void _suite(Module Function() root) {
  late Application app; // Set in setUp before every test.
  late TestClient client; // Set in setUp before every test.
  final errors = <Object>[];

  setUp(() async {
    errors.clear();
    app = await Application.create(
      root,
      onError: (error, _) => errors.add(error),
    );
    client = TestClient(app);
  });

  tearDown(() => app.close());

  test('lists users with a query limit', () async {
    final response = await client.get('/users?limit=1');

    expect(response.status, 200);
    expect(response.json, [
      {'id': 1, 'name': 'ann'},
    ]);
    expect((await client.get('/users')).json, hasLength(2));
  });

  test('finds one user; a filter maps a domain error to 404', () async {
    expect((await client.get('/users/2')).json, {'id': 2, 'name': 'bob'});

    final missing = await client.get('/users/9');
    expect(missing.status, 404);
    expect((missing.json as Map)['message'], 'No user 9');
  });

  test('POST by an admin creates a user: 201 with location', () async {
    final response = await client.post(
      '/users',
      json: {'name': 'cid'},
      headers: {'authorization': 'Bearer admin'},
    );

    expect(response.status, 201);
    expect(response.headers['location'], '/users/3');
    expect(response.json, {'id': 3, 'name': 'cid'});
  });

  test('guards: 401 without a token, 403 for a non-admin', () async {
    final anonymous = await client.post('/users', json: {'name': 'cid'});
    final guest = await client.post(
      '/users',
      json: {'name': 'cid'},
      headers: {'authorization': 'Bearer guest'},
    );

    expect(anonymous.status, 401);
    expect(anonymous.headers['www-authenticate'], 'Bearer');
    expect(guest.status, 403);
  });

  test('malformed JSON, an invalid DTO and a bad int query are 400', () async {
    const admin = {'authorization': 'Bearer admin'};

    final malformed = await client.request(
      'POST',
      '/users',
      body: '{"name":',
      headers: admin,
    );
    final invalid = await client.post(
      '/users',
      json: {'name': ''},
      headers: admin,
    );
    final query = await client.get('/users?limit=ten');

    expect(malformed.status, 400);
    expect(invalid.status, 400);
    expect((invalid.json as Map)['message'], contains('"name"'));
    expect(query.status, 400);
  });

  test('a token value, a bound interface and a global module', () async {
    final named = await client.get('/hello', headers: {'x-name': 'ann'});

    expect(named.json, {
      'greeting': 'Hello, ann!',
      'at': '1970-01-01T00:00:00.000Z',
    });
    expect(
      (await client.get('/hello')).json,
      containsPair('greeting', 'Hello, world!'),
    );
  });

  test('an enum path parameter, and a void handler is 204', () async {
    expect((await client.get('/status/banned')).json, {'status': 'banned'});
    expect((await client.get('/status/gone')).status, 400);
    expect((await client.delete('/hello')).status, 204);
  });

  test('405 with allow, 404 for an unknown path, no errors', () async {
    final wrongMethod = await client.delete('/users');

    expect(wrongMethod.status, 405);
    expect(wrongMethod.headers['allow'], 'GET, HEAD, POST');
    expect((await client.get('/nope')).status, 404);
    expect(errors, isEmpty);
  });
}
```

- [ ] **Step 3: Run the golden test to verify it fails**

Run: `cd packages/dartnest_generator && dart test test/golden`
Expected: FAIL: компіляція — `DartnestGenerator.core` не визначено

Явний і закомічений згенерований графи вже поводяться однаково — це перевіряє golden-файл, а не генератор:

Run: `cd packages/dartnest_generator && dart test test/e2e`
Expected: `+16: All tests passed!`

- [ ] **Step 4: Add the core constructs and export them**

Повна заміна `dartnest_generator.dart` і barrel:

`packages/dartnest_generator/lib/src/construct/dartnest_generator.dart`:

```dart
import 'package:code_builder/code_builder.dart';

import '../constructs/controller_construct.dart';
import '../constructs/module_construct.dart';
import '../constructs/provider_construct.dart';
import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../emit/library_writer.dart';
import '../model/package_model.dart';
import 'construct.dart';
import 'generated_unit.dart';
import 'generation_result.dart';

/// Runs a set of [Construct]s over a [PackageModel].
///
/// Every construct validates first; any diagnostic stops generation, so a
/// package with an error never gets a half-generated library.
final class DartnestGenerator {
  /// Creates the generator; [constructs] run in order.
  const DartnestGenerator(this.constructs);

  /// The v1 constructs: modules, then controllers, then the provider
  /// factories they use.
  const DartnestGenerator.core()
    : constructs = const [
        ModuleConstruct(),
        ControllerConstruct(),
        ProviderConstruct(),
      ];

  /// The constructs.
  final List<Construct> constructs;

  /// Validates and generates [package].
  GenerationResult generate(PackageModel package) {
    final diagnostics = {
      for (final construct in constructs) ...construct.validate(package),
    }.toList()..sort();
    if (diagnostics.isNotEmpty) return GenerationResult.failed(diagnostics);
    final units = [
      for (final construct in constructs) ...construct.generate(package),
    ];
    final dartUnits = units.whereType<DartUnit>().toList();
    final duplicates = _duplicateNames(dartUnits);
    if (duplicates.isNotEmpty) return GenerationResult.failed(duplicates);
    return GenerationResult.generated(
      library: LibraryWriter.write(
        packageName: package.packageName,
        languageVersion: package.languageVersion,
        declarations: <Spec>[for (final unit in dartUnits) unit.spec],
      ),
      files: units.whereType<FileUnit>().toList(),
    );
  }

  static List<Diagnostic> _duplicateNames(List<DartUnit> units) {
    final first = <String, DartUnit>{};
    return [
      for (final unit in units)
        if (first.putIfAbsent(unit.name, () => unit) case final other
            when other != unit)
          Diagnostic(
            DiagnosticCode.duplicateGeneratedName,
            unit.origin,
            'Generated name ${unit.name} is used twice: for the declaration '
            'at ${other.origin} and for this one. Rename one of them.',
          ),
    ]..sort();
  }
}
```

`packages/dartnest_generator/lib/dartnest_generator.dart`:

```dart
/// Turns dartnest annotations into ordinary code on the explicit dartnest
/// API, and checks the module graph before the application starts.
///
/// A driver (the CLI, build_runner) resolves the libraries of a package,
/// builds its model with [PackageCollector] and runs a [DartnestGenerator]:
///
/// ```dart
/// final package = PackageCollector('shop', root).collect(libraries);
/// final result = const DartnestGenerator.core().generate(package);
/// if (!result.isSuccess) result.diagnostics.forEach(print);
/// ```
///
/// The model and [Construct] are public so later packages (OpenAPI,
/// GraphQL) can add constructs of their own.
library;

export 'src/collector/package_collector.dart';
export 'src/construct/construct.dart';
export 'src/construct/dartnest_generator.dart';
export 'src/construct/generated_unit.dart';
export 'src/construct/generation_result.dart';
export 'src/constructs/controller_construct.dart';
export 'src/constructs/module_construct.dart';
export 'src/constructs/provider_construct.dart';
export 'src/diagnostic/diagnostic.dart';
export 'src/diagnostic/diagnostic_code.dart';
export 'src/diagnostic/source_location.dart';
export 'src/emit/library_writer.dart';
export 'src/model/body_kind.dart';
export 'src/model/component_reference.dart';
export 'src/model/constant_value.dart';
export 'src/model/constructor_model.dart';
export 'src/model/controller_model.dart';
export 'src/model/dependency_model.dart';
export 'src/model/dto_field.dart';
export 'src/model/dto_model.dart';
export 'src/model/enhancers_model.dart';
export 'src/model/generated_names.dart';
export 'src/model/handler_parameter.dart';
export 'src/model/injectable_model.dart';
export 'src/model/module_export.dart';
export 'src/model/module_model.dart';
export 'src/model/module_reference.dart';
export 'src/model/package_model.dart';
export 'src/model/parameter_binding.dart';
export 'src/model/provider_key.dart';
export 'src/model/provider_model.dart';
export 'src/model/route_model.dart';
export 'src/model/type_kind.dart';
export 'src/model/type_model.dart';
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd packages/dartnest_generator && dart test test/golden`
Expected: `+3: All tests passed!`

Run: `cd packages/dartnest_generator && dart test`
Expected: `+69: All tests passed!`

- [ ] **Step 6: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 7: Commit**

```bash
git add \
  pubspec.yaml \
  packages/dartnest_generator/pubspec.yaml \
  packages/dartnest_generator/test/fixtures/users_app/pubspec.yaml \
  packages/dartnest_generator/test/fixtures/users_app/analysis_options.yaml \
  packages/dartnest_generator/test/fixtures/users_app/lib/src/auth.dart \
  packages/dartnest_generator/test/fixtures/users_app/lib/src/users.dart \
  packages/dartnest_generator/test/fixtures/users_app/lib/src/greeting.dart \
  packages/dartnest_generator/test/fixtures/users_app/lib/src/modules.dart \
  packages/dartnest_generator/test/fixtures/users_app/lib/users_app.dart \
  packages/dartnest_generator/test/fixtures/users_app/lib/explicit.dart \
  packages/dartnest_generator/test/fixtures/users_app/lib/users_app.dartnest.dart \
  packages/dartnest_generator/test/golden/golden_test.dart \
  packages/dartnest_generator/test/e2e/users_app_e2e_test.dart \
  packages/dartnest_generator/lib/src/construct/dartnest_generator.dart \
  packages/dartnest_generator/lib/dartnest_generator.dart
git commit -m "feat(generator): add DartnestGenerator.core with golden and e2e tests"
```

### Task 11: Документація: README пакетів, `CLAUDE.md`, роадмап

README обох пакетів англійською (рішення `CLAUDE.md` про мову): `dartnest_annotations` — приклад анотаційного стилю й правила (OP2, OP4, OP5, OP7–OP9); `dartnest_generator` — використання драйвером, вивід, таблиця кодів діагностик, OP3, OP1. `CLAUDE.md` отримує команду оновлення golden, виняток модельних значень з правила параметрів (рішення 11), правило `hide` і примітку про фікстури. Рядок етапу 4 у роадмапі посилається на цей план. Код не змінюється.

**Files:**
- Create: `packages/dartnest_annotations/README.md`
- Create: `packages/dartnest_generator/README.md`
- Modify: `CLAUDE.md`
- Modify: `docs/superpowers/ROADMAP.md`

**Interfaces:**
- Consumes: публічний API Tasks 1–10 (`PackageCollector`, `DartnestGenerator.core`, `GenerationResult`, коди `DiagnosticCode`).
- Produces: `packages/dartnest_annotations/README.md`, `packages/dartnest_generator/README.md`; правки `CLAUDE.md`, `docs/superpowers/ROADMAP.md`.

- [ ] **Step 1: Write the READMEs**

`packages/dartnest_annotations/README.md`:

````markdown
# dartnest_annotations

Annotations for the declarative style of dartnest. They have no behavior and
no dependencies: `dartnest_generator` reads them and writes ordinary code on
the explicit `package:dartnest` API into `lib/<package>.dartnest.dart`.

```dart
import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

const dbUrl = Token<String>('db.url');

@Injectable()
final class UsersService {
  UsersService(@Inject(dbUrl) this.url);
  final String url;
}

@Controller('/users')
@UseGuards([AuthGuard])
final class UsersController {
  UsersController(this.service);
  final UsersService service;

  @Get('/:id')
  Future<User> findOne(@Param('id') int id) => service.find(id);

  @Post()
  @Roles(['admin']) // final class Roles extends RouteMetadata
  Future<User> create(@Body() CreateUserDto dto) => service.create(dto);
}

@Module(
  id: 'users',
  providers: [UsersService, AuthGuard, Value('postgres://db', token: dbUrl)],
  controllers: [UsersController],
  exports: [UsersService],
)
final class UsersModule {}
```

The generated library exports `Module usersModule()` and
`Controller<UsersController> usersController()`; pass the root module
function to `Application.create(appModule)`.

Rules:

- `Module` and `Controller` share their names with the explicit API. A
  library that uses both imports `package:dartnest/dartnest.dart` with
  `hide Controller, Module`; a module written with the explicit API lives in
  a file without that `hide`.
- `@Module(id:)` defaults to the class name; set it explicitly, because
  renaming the class then changes the id.
- `providers` takes classes annotated with `@Injectable()`, `Bind<K, I>()`
  (`I` is created and provided as `K`) and `Value(value, token: ...)`.
  `imports` takes `@Module` classes (also from other packages generated by
  dartnest) and tear-offs of public functions without required parameters
  that return an explicit `Module` (`imports: [metricsModule]`,
  `imports: [DbModule.forRoot]`). `exports` takes provider classes, `Token`
  constants and imported modules.
- Dependency injection calls the unnamed public constructor. Every
  parameter is required (positional or `required` named) and is either a
  non-nullable class type or `@Inject(token)`.
- `@UseGuards`, `@UseInterceptors`, `@UsePipes` and `@UseFilters` take
  types; each becomes `Use<T>()`, so the type must be a provider visible to
  the controller's module.
- Handler parameters: `@Param` and `@Query` take `String`, `int`, `double`,
  `num`, `bool`, `DateTime` or an enum (a nullable `@Query` is optional);
  `@Header` takes `String` or `String?` (a missing required header is a
  400); `@Body()` takes a class with `fromJson(Map<String, Object?>)`,
  `Map<String, Object?>`, `String` or `List<int>`; a parameter of type
  `ExecutionContext` or `HttpRequest` gets that object.
- Metadata are `const` subclasses of `RouteMetadata`; a private constant is
  allowed, a private class is not (the generated library cannot name it).
````

`packages/dartnest_generator/README.md`:

````markdown
# dartnest_generator

Turns `dartnest_annotations` into ordinary code on the explicit dartnest
API and checks the module graph before the application starts. This
package is the library the drivers (the `dartnest_cli` command line tool,
a build_runner builder) run; it does not read or write files itself.

```dart
import 'package:dartnest_generator/dartnest_generator.dart';

// libraries: the resolved LibraryElements of the package's lib/.
final package = PackageCollector('shop', packageRoot).collect(libraries);
final result = const DartnestGenerator.core().generate(package);
if (result.isSuccess) {
  // Write result.library to lib/shop.dartnest.dart.
} else {
  result.diagnostics.forEach(print);
  // lib/users.dart:12:3: error: No provider for Clock in module "users"
  // (resolving: UsersService). [missing_provider]
}
```

Output (`lib/<package>.dartnest.dart`, one library per package):

- `@Module class UsersModule` → `Module usersModule()`, `@Controller class
  UsersController` → `Controller<UsersController> usersController()`, a
  private factory per provided class. Functions, not top-level `final`s, so
  a hot reload rebuilds the graph.
- It imports `package:dartnest/dartnest.dart` as `dartnest` and the user's
  libraries as `i1`, `i2`, …; it is formatted with `dart_style` for the
  package's language version.
- The same sources give byte-identical output, whatever the order of the
  libraries; a change of output is a breaking change of the generator.

Diagnostics stop generation; each has a stable code:

| Construct | Codes |
| --- | --- |
| `ModuleConstruct` | `duplicate_module_id`, `circular_module_import`, `duplicate_provider`, `invalid_export`, `invalid_module_entry`, `unsupported_constant`, `missing_provider`, `circular_dependency` |
| `ProviderConstruct` | `not_injectable`, `invalid_constructor`, `invalid_dependency` |
| `ControllerConstruct` | `invalid_component`, `invalid_route_handler`, `invalid_handler_parameter`, `missing_from_json`, `unknown_path_parameter`, `duplicate_route` |
| `DartnestGenerator` | `duplicate_generated_name` |

`missing_provider` and `circular_dependency` need the whole graph: when a
module is built by a function or comes from another package, the generator
cannot see its providers and leaves these two checks to
`Application.create`.

`Construct` and the model (`PackageModel`, `ModuleModel`, `RouteModel`,
`DtoModel`, …) are public, so other packages can add constructs.

`analyzer` is accepted from 8.1.1 to 14.x, so the generator runs on Dart
3.8 and on current SDKs.
````

- [ ] **Step 2: Update `CLAUDE.md`**

У `CLAUDE.md` замінити:

```text
dart format packages                  # a second run must change 0 files
```

на:

```text
dart format packages                  # a second run must change 0 files
# packages/dartnest_generator, after a deliberate change of generated output:
DARTNEST_UPDATE_GOLDENS=1 dart test test/golden
```

У `CLAUDE.md` замінити:

```text
| Parameters | 5 | past that, take a parameter object; `Module` has 6 named fields by spec: it is a declarative value, no parameter object |
```

на:

```text
| Parameters | 5 | past that, take a parameter object; `Module` has 6 named fields by spec: it is a declarative value, no parameter object; so are the generator's model classes (`ModuleModel`, `RouteModel`, ...) |
```

У `CLAUDE.md` замінити:

```text
- Escape every string taken from user sources at every interpolation site of
  generated code.
```

на:

```text
- Escape every string taken from user sources at every interpolation site of
  generated code (`DartString.literal` in `dartnest_generator`).
- **Annotations share names with the explicit API** (`Module`,
  `Controller`): a library that uses both imports
  `package:dartnest/dartnest.dart` with `hide Controller, Module`, and a
  module written with the explicit API lives in a file without that `hide`.
```

У `CLAUDE.md` замінити:

```text
`package:test`, and the `register` methods of its test groups are held to the
test-file limits, not to the 40-line method limit.
```

на:

```text
`package:test`, and the `register` methods of its test groups are held to the
test-file limits, not to the 40-line method limit.
The generator's fixture packages (`packages/dartnest_generator/test/fixtures/*`)
are unpublished workspace members; `users_app.dartnest.dart` there is the
golden file: generated, committed, never edited by hand.
```

- [ ] **Step 3: Link the plan from the roadmap**

У `docs/superpowers/ROADMAP.md` замінити:

```text
| 4 | **Анотації та генератор** |
```

на:

```text
| 4 | **Анотації та генератор** (план `2026-10-13-dartnest-annotations-generator.md`) |
```

- [ ] **Step 4: Analyze and format**

Run: `dart analyze`
Expected: `No issues found!`

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: `(0 changed)`, exit code 0

- [ ] **Step 5: Commit**

```bash
git add \
  packages/dartnest_annotations/README.md \
  packages/dartnest_generator/README.md \
  CLAUDE.md \
  docs/superpowers/ROADMAP.md
git commit -m "docs: document annotations and the generator"
```

## Самоперевірка

**Покриття специфікації.**

| Вимога | Задача |
|---|---|
| 3: `@Module(imports, providers: [клас, Bind<K, I>(), Value(v)], controllers, exports)`, `@Injectable()`, `@Inject(token)`; фабрика з неіменованого конструктора, параметр → `i.get<T>()` або `i.get(token)` | 1, 4, 7 |
| 3: динамічні модулі (`forRoot`) підставляються як є, валідація графа для них часткова | 4, 7, 8 (OP3, OP5) |
| 4: `@Controller`, `@UseGuards`, `@Get/@Post/...`, метадані-нащадки `RouteMetadata`; прив'язки `@Param/@Query/@Header/@Body`, `ExecutionContext`, `HttpRequest`; nullable → необов'язковий; невідома анотація або неможлива прив'язка — помилка генерації | 1, 5, 9 (OP6, OP9) |
| 6 «Вихід»: один файл `lib/<package>.dartnest.dart`, звичайна бібліотека, імпортує бібліотеки користувача, `UsersModule` → `usersModule`, `UsersController` → `usersController`, `dart_style` | 6, 7, 9, 10 |
| 6 «Вихід»: запис лише якщо вміст змінився | драйвер, етап 5 (рішення 1) |
| 6: модуль з пакета A імпортується в B як звичайне значення | 4, 7 (OP12) |
| 6 «Архітектура»: `Collector` → `PackageModel` з `documentationComment`, типами, `DtoModel` (поля, nullable, значення за замовчуванням, `@JsonKey(name:)`) | 2, 4, 5 (OP11) |
| 6: `Construct.validate/generate`, `GeneratedUnit` = Dart `Spec` або файл з `contentType`; `ModuleConstruct`, `ProviderConstruct`, `ControllerConstruct` | 6, 7, 9, 10 |
| 6 «Статична валідація»: відсутній провайдер, цикл, експорт, дублікат `id` | 7, 8 |
| 6: конструктор публічний і неіменований, параметри інжектовані за типом/токеном, іменовані — лише `required` | 4, 7 |
| 6: повнота анотацій параметрів хендлера, наявність `fromJson`, дублікати роутів | 5, 9 |
| 6: `path:line:col: error: message` | 2, 6 |
| 6: ненульовий код виходу | CLI, етап 5 |
| 6 «Заділ під документацію»: doc-коментарі й `DtoModel` у моделі, `FileUnit` для довільних файлів | 2, 5, 6 |
| 7: генератор повертає діагностики, а не винятки | 6 (`GenerationResult.failed`) |
| 8: golden-тести на фікстурних пакетах, тести діагностик з позиціями, згенерований код компілюється й проходить ті самі e2e, що явний | 3–9 (діагностики), 10 (golden, e2e) |
| 10.1 п. 1: генератор емітить функції, а не top-level `final` | 7, 9 (рішення 2) |
| Роадмап, етап 4 «Готово, коли» | 2–10; посилання на план — 11 |

Поза планом (рішення 12): драйвери, запис файлів, hot reload, `OpenApiConstruct`.

**Плейсхолдери.** Пошук `TBD`, `TODO`, «similar to Task», «add error handling», «implement later» — нічого. Кожен крок з кодом містить повний файл. Файли, які змінюються кількома задачами, наведено повністю в кожній: кореневий `pubspec.yaml` (Tasks 1, 2, 3, 10), `packages/dartnest_generator/pubspec.yaml` (2, 3, 10), `lib/dartnest_generator.dart` (2, 6, 10), `test/helpers/fixture_package.dart` (3, 4), `lib/src/collector/package_collector.dart` (4, 5), `lib/src/constructs/module_construct.dart` (7, 8), `lib/src/construct/dartnest_generator.dart` (6, 10). Зміни `CLAUDE.md` і роадмапу (Task 11) дано точним «було → стало».

**Узгодженість типів.** Імена між задачами взято з того самого коду, що пройшов перевірку нижче: `PackageCollector(packageName, packageRoot).collect`, `PackageModel({packageName, languageVersion, modules, injectables, controllers, dtos})`, `ModuleModel.invalidEntries`, `ConstructorModel.invalid`, `DependencyModel.injected/invalid`, `RouteModel.pathParameters/problem`, `EntryRead.values/problems`, `Annotations.find/all/field/routeMetadata/describe`, `TypeReader.read/isDartnest/hasSupertype`, `ConstantReader.read`, `TokenReader.read`, `SourceLocations.of`, `Construct.validate/generate`, `DartUnit({name, spec, origin})`, `FileUnit({path, contentType, content})`, `GenerationResult.failed/generated/isSuccess`, `DartnestGenerator(constructs)`/`.core()`, `LibraryWriter.write({packageName, languageVersion, declarations})`, `ImportAllocator.dartnest`, `TypeEmitter.reference`, `ConstantEmitter.expression/list`, `DartString.literal`, `InjectionEmitter.injector/create/get`, `ModuleEmitter.function/reference`, `ConstructorCheck.check`, `ModuleStructureCheck.check`, `ModuleScope.visibleIn/declaring`, `DependencyCheck.check`, `ControllerCheck.check/fullPath`, `ArgumentEmitter.argument/awaits`, `EnhancersEmitter.enhancers`, `RouteEmitter.route`, `ControllerEmitter.function`, `GeneratedNames.module/controller/factory/library`, `FixturePackage.open/libraries/collect/read/root`. З ядра використано лише наявний публічний API етапів 1–2 (`Module`, `Provider`, `Provider.value`, `Injector.get`, `Token`, `Controller`, `Route.get/post/put/patch/delete`, `Enhancers`, `Use`, `EnumPipe`, `BadRequestException`, `ExecutionContext.param/query/header/bodyAs/body/switchToHttp`, `Application.create`, `TestClient`); ядро не змінюється.

**Перевірка.** План перевірено скриптом, який читає цей markdown і застосовує його задачу за задачею до чистого клону `master` (`f500260`) у `/tmp`: записує кожен файл з блоку коду, застосовує «було → стало», виконує кожен рядок `Run:` і порівнює з `Expected:` (кроки «verify it fails» мусять завершитися з помилкою, кроки з `+N` — дати рівно `+N: All tests passed!`), виконує блок коміту як є й перевіряє, що після нього `git status` чистий (тобто `git add` кожної задачі охоплює всі її файли). Результат: усі 11 задач, усі кількості (`+6` анотації; `+6`, `+13`, `+21`, `+29`, `+38`, `+44`, `+48`, `+50`, `+69` генератор), `dart analyze` — «No issues found!» і `dart format` — 0 змінених файлів після кожної задачі; підсумкове дерево `packages/` збігається з еталонною реалізацією. SDK: Dart 3.13.5 (fvm Flutter 3.47.6) з мовною версією 3.8 у всіх нових пакетах (`sdk: ^3.8.0`), тож dot shorthands і новіші можливості не компілюються; окремого Dart 3.8 SDK на машині немає. Залежності на верхньому краї: `analyzer` 14.5.0, `code_builder` 4.12.0, `dart_style` 3.1.13, `test` 1.33.0. Нижній край — окрема копія з `dependency_overrides`: `analyzer` 8.1.1, `code_builder` 4.11.1, `dart_style` 3.1.2, `test` 1.26.3 (`test` ≥ 1.27 вимагає analyzer ≥ 13): `+69` і `+6`, golden байт-у-байт той самий. Ця перевірка знайшла дефект `code_builder` 4.11.1 (`declareFinal(name, type:)` губить аргументи типу), тож тест Task 6 будує тип через `Method.returns`. Розміри: найбільший файл у `lib/` — `model/constant_value.dart` (164 рядки), у `test/` — `controller_collector_test.dart` (178); жоден метод не довший за 40 рядків; 78 файлів у `lib/` двох пакетів.

**Review Focus.** Кожен пункт закріплено тестом з коментарем `// Review Focus N`: 1 → Task 6 (`emit_test.dart`); 2 → Task 10 (`golden_test.dart`); 3 → Task 3 (`constant_reader_test.dart`, два тести); 4 → Task 8 (`dependency_check_test.dart`); 5 → Task 9 (`controller_construct_test.dart`).

## Відкриті питання для автора

Усі рішення, які варто переглянути до виконання, винесено в розділ «Open points» на початку плану (OP1–OP12) з таблицями компромісів і рекомендаціями; план написано за рекомендованими варіантами. Найбільше на подальші етапи впливають:

1. **OP3** — чи достатньо вимикати `missing_provider`/`circular_dependency` для всього пакета, щойно в ньому є непрозорий модуль, чи CLI етапу 5 має читати `@Module` залежних пакетів (варіант C).
2. **OP1** — чи тримати широкий діапазон `analyzer` (Dart 3.8+) ціною двох перевірених країв, чи підняти SDK-підлогу генератора до 3.11.
3. **OP2** — чи лишати імена `Module`/`Controller` зі специфікації з `hide`, чи перейменувати анотації.
