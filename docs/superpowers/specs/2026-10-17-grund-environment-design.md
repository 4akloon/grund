# grund і grund_http: конфігурація із середовища — дизайн

Дата: 2026-10-17. Стан: чернетка на перегляд. Джерело: знахідки першого
споживача, портфоліо (`/home/genius/projects/portfolio`, лише читання), №3
(PORT/HOST із середовища) і №9 (статичний `SiteContent.current`, лише
документація). Решта знахідок — у
`2026-10-17-grund-jaspr-page-addresses-design.md`. Цей spec від нього не
залежить: спільні лише CHANGELOG `grund_http` 0.3.0 і `docs/adapters.md`.

## 1. Мета й межі

**Мета.** Застосунок grund читає порт і адресу з середовища без власного коду,
а будь-яку іншу змінну — через один перевірений тип у DI. Помилка
конфігурації — типізована `GrundError` на старті, до прослуховування, і в
повідомленні ніколи немає значення змінної.

**Цілі.**
- `grund`:
  - `Environment` (читання з перевіркою);
  - родина `EnvironmentError`;
  - `EnvironmentModule` (глобальний; прив'язує `Environment` процесу).
- `grund_http`:
  - `HttpConfig.fromEnvironment` (`HOST`, `PORT`);
  - `HttpModule.fromEnvironment`.
- Шаблони `grund init` (`default` і `fullstack`) читають `HOST`/`PORT`.
- Приклад: `ServerOptions` переходить на `HttpConfig.fromEnvironment`.
- Документація:
  - новий `docs/configuration.md`, де є і «дані старту як перевірений
    `Singleton`» (№9);
  - `docs/adapters.md`.

**Не цілі.**
- Файли `.env`, профілі, ієрархічна конфігурація, секрет-менеджери.
- Типи читання, яких ще ніхто не потребує: `flag`, `uri`, `duration`, списки.
- `debug`, `maxBodyBytes`, `accessLog` із середовища: `debug` — питання
  безпеки, решту можна задати в коді.
- Читання `GRUND_LIVE_RELOAD_URL` у `JasprModule` (`jaspr_module.dart:152`)
  лишається як є: цю змінну передає `grund dev`, а не користувач.
- Зміна типової адреси `localhost` (Для автора, п. 3).
- Функція верхнього рівня `env(...)` зі старого spec
  (`2026-10-13-dartnest-design.md:96`). Її так і не реалізували; клас із
  методами відповідає правилам CLAUDE.md.

**Анти-цілі.**
- Неявне читання середовища: `HttpModule()` без `fromEnvironment` поводиться
  так само, як у 0.2.0.
- Значення змінних у повідомленнях помилок і в логах (там бувають секрети).
- Мовчазний відкат до типового значення, коли змінна задана, але зіпсована
  (`PORT=80a`, `PORT=`).
- `dart:io` у `grund_http`.

## 2. Вхідні факти

**Портфоліо** (перевірено читанням):
- `bin/main.dart:7-15` читає `PORT` і `HOST` з `Platform.environment` і
  передає `HttpConfig(address:, port:)` у `HttpModule(config:)`, тобто
  повторює те, що мав би дати фреймворк.
- `CLAUDE.md:172-173` портфоліо називає це обхідним рішенням.
- `lib/content/site_content.dart`: `static final SiteContent current =
  SiteContent.placeholder();` — дані сайту в статичному полі. Їх не можна
  підмінити в тесті, і їх перевірка не біжить на старті (№9).

**`grund`** (перевірено читанням):
- `lib/src/errors/grund_error.dart`: `abstract base class GrundError
  implements Exception`, де ім'я класу — стабільний код. Родини `GraphError`,
  `ResolutionError` і `AppError` — `sealed`.
- `lib/src/errors/resolution_errors.dart:36-48`: `ProviderCreationError`
  обгортає збій фабрики разом із причиною й стеком.
- `lib/src/di/module.dart:30-36`: `bool get global`. За
  `docs/modules-and-di.md:118-120` глобальні модулі — рекомендований спосіб
  для конфігурації й адаптерів.
- `lib/src/di/module_shape.dart`: два екземпляри одного класу модуля
  порівнюються лише за ключами; фабрики не порівнюються («may carry different
  configuration»). Наявне правило: `HttpModule()` і
  `HttpModule.fromEnvironment()` в одному графі не будуть помилкою, як і два
  `HttpModule(config: …)` зараз.
- `dart:io` у ядрі вже є (`app/stop_signals.dart`, `log/log_output.dart`).
  CLAUDE.md забороняє ядру лише сервер. `Platform.environment` допустимий.
- Барель `lib/grund.dart` експортує через `show`.
- `lib/src/testing/test_app.dart:11-16`: `TestApp.start(root:, overrides:)`.
- CHANGELOG уже має секцію 0.2.0 (Dart 3.13).

**Генератор** (перевірено читанням):
- `grund_generator/lib/src/collector/provides_reader.dart:53-54`: параметри
  методу `@Provides` — залежності, тож `static DbConfig db(Environment env)`
  працює.
- `collector/constant_reader.dart:81-119`: імпорт модуля в `@Module(imports:)`
  відтворюється через `constructorInvocation` разом з іменованим
  конструктором. Тож `HttpModule.fromEnvironment()` в анотації перейде в
  згенерований код.

**`grund_http`** (перевірено читанням):
- `lib/src/server/http_config.dart` (33 рядки): `const HttpConfig({address =
  'localhost', port = 8080, maxBodyBytes = 1048576, debug = false, accessLog =
  true})`, `Object address`. `///` класу радить override, щоб читати порт із
  середовища.
- `lib/src/server/http_module.dart`:
  - `:41` `this.config = const HttpConfig()`;
  - `:58` `Singleton<HttpConfig>((i) => config, dependsOn: const [])`;
  - `:73` експортує `Key<HttpServer>()` і `Key<HttpConfig>()`.
- У `lib/` немає імпорту `dart:io` (grep).
- `docs/adapters.md:77-84`: рецепт з override; адреса `localhost` за
  замовчуванням; у контейнері — `InternetAddress.anyIPv4`.

**`grund_cli`** (перевірено читанням):
- `lib/src/init/project_template.dart`:
  - `:7` `grundVersion = '^0.1.0'`, `:11` `grundHttpVersion = '^0.2.0'`;
  - pubspec шаблону `:20-25` бере `grundVersion` і для `grund_io` та
    `grund_cli`;
  - модуль (анотації) — `imports: [HttpModule(), IoAdapterModule()]`.
- `lib/src/init/fullstack_template.dart` (323 рядки; library-doc називає його
  пласким каталогом):
  - `:32-37` версії, `_grundJaspr = '^0.2.0'`;
  - `grund_cli: ^0.1.2` у `dev_dependencies`;
  - модуль явним API — `HttpModule(use: [...])`.
- `test/init_command_test.dart:31-32` перевіряє рядки версій.
- Неопубліковані секції CHANGELOG (крок Dart 3.13): `grund` 0.2.0,
  `grund_http` 0.3.0, `grund_io`/`grund_shelf`/`grund_auth` 0.2.0,
  `grund_cli` 0.2.0, `grund_jaspr` 0.3.0.
  - `grund_jaspr` 0.2.0 вимагає `grund_http: ^0.2.0`, тож шаблон із
    `grund_http: ^0.3.0` і `grund_jaspr: ^0.2.0` не розвʼяжеться.
  - Те саме з `grund_cli: ^0.1.2` проти `grund: ^0.2.0`.

**Приклад** (перевірено читанням):
- `example/lib/src/server/server_options.dart`: власний розбір `PORT`
  (1–65535, `int.tryParse`), без `HOST`.
- `example/lib/src/server/tasks_app.dart:19-25` передає `port:` у
  `ServingModule`, а той уже має `address`.
- `example/bin/main.dart` ловить `FormatException` і завершується з кодом 64.
- `example/test/main_process_test.dart:26-30` запускає `bin/main.dart` з
  `environment: {'PORT': …}`. Батьківське середовище успадковується, тож
  експортований `HOST` змінив би адресу дочірнього процесу.

**Проба Dart:** `int.tryParse` приймає `' 80'`, `'+80'` і `'0x50'`. Отже,
потрібен власний строгий формат.

## 3. Рішення

1. **`Environment` — значення в DI, а не глобальна функція.**
   - `EnvironmentModule` (глобальний) прив'язує `Environment` процесу.
   - Фабрики й методи `@Provides` беруть `Environment` параметром.
   - Тест підміняє його через override (Для автора, п. 2).
2. **Строгі значення.** Задана змінна має бути коректною; порожнє значення
   теж задане. Типове значення діє лише для незаданої змінної.
3. **Без значень у повідомленнях.** Помилка називає змінну й очікувану
   форму.
4. **`HOST` і `PORT` без префікса** (Для автора, п. 1). Хостинги (Heroku,
   Cloud Run, Render) задають `PORT`, а `HOST` — поширена пара до нього.
5. **Явне ввімкнення.** `HttpModule.fromEnvironment(...)` залежить від
   `Environment`, тож без `EnvironmentModule` граф падає з
   `MissingProviderError` до старту.
6. **Шаблони показують цей шлях**, приклад — шлях без DI: `main` лише
   передає `Environment(Platform.environment)` у `ServerOptions.parse`, а той
   викликає `HttpConfig.fromEnvironment` (§4.6).
7. **№9 — документація.** Дані, що завантажуються й перевіряються на
   старті, — це `Singleton` або `@Provides`, а не статичне поле. Помилка
   тоді виникає до прослуховування (як `GrundError`, без обгортки), а тест підміняє дані
   override-ом.

**Відхилені альтернативи.**
- *`HttpModule` завжди читає середовище.* Неявно, і тести залежали б від
  оточення машини.
- *`HttpModule.fromEnvironment` читає `Platform.environment` сам.* Це тягне
  `dart:io` у `grund_http`, і підмінити середовище в тесті без DI неможливо.
- *Префікс `GRUND_HOST`/`GRUND_PORT`.* Безпечніше від чужих змінних, але
  розходиться з конвенцією хостингів і вимагає перейменування в кожному
  деплої.
- *Типова адреса `0.0.0.0`.* Відкриває dev-сервер у мережу.
- *Функція `env('X')`.* Глобальний стан і жодної підміни в тесті.

## 4. Дизайн

### 4.1 `grund`: `Environment`

Новий файл `lib/src/config/environment.dart`, експорт `show Environment`:

```dart
/// Environment variables read with checks: a variable that is set must be
/// valid, and only an unset one falls back.
final class Environment {
  /// Wraps the variables, usually `Platform.environment`; tests pass a
  /// map. The map is not copied.
  const Environment(this._values);

  final Map<String, String> _values;

  /// Whether [name] is set; an empty value counts as set.
  bool has(String name);

  /// The value of [name]; [fallback] when it is unset; throws
  /// [MissingVariableError] when it is unset and there is no [fallback].
  String string(String name, {String? fallback});

  /// The value of [name] as a decimal integer (`-?[0-9]+`) within [min] and
  /// [max]; [fallback] when it is unset. Throws [MissingVariableError] or
  /// [InvalidVariableError].
  int integer(String name, {int? fallback, int? min, int? max});
}
```

- Звичайний конструктор, бо `///` про `Platform.environment` варто зберегти
  (CLAUDE.md, «Code rules»).
- `integer` розбирає `^-?[0-9]+$` через `int.tryParse`. `null` (переповнення)
  або вихід за `min`/`max` дає `InvalidVariableError`. Очікування формулюється
  як `'an integer'`, `'an integer from 0 to 65535'`, `'an integer of at least
  1'` чи `'an integer of at most 9'`.
- `fallback` не перевіряється на `min`/`max`: його пише програміст.

### 4.2 `grund`: помилки

Новий файл `lib/src/errors/environment_errors.dart`, експорт цілим файлом, як
інші родини:

```dart
/// A failure to read an environment variable.
sealed class EnvironmentError extends GrundError {
  const EnvironmentError();

  /// The name of the variable.
  String get name;
}

/// A required variable is not set.
final class MissingVariableError extends EnvironmentError { ... }
// message: 'The environment variable PORT is not set. Set it, or read it
// with a fallback.'

/// A variable is set to a value of the wrong form; the value is not shown.
final class InvalidVariableError extends EnvironmentError {
  const InvalidVariableError({required this.name, required this.expected});
  /// What the value must be, such as "an integer from 0 to 65535".
  final String expected;
}
// message: 'The environment variable PORT must be an integer from 0 to
// 65535. Its value is not shown, as it may be a secret.'
```

### 4.3 `grund`: `EnvironmentModule`

Новий файл `lib/src/config/environment_module.dart`, експорт `show
EnvironmentModule`:

```dart
/// Binds the [Environment] of the process, visible to every module.
final class EnvironmentModule extends Module {
  const EnvironmentModule();
  @override bool get global => true;
  @override List<Binding<Object>> get bindings => [
    Singleton<Environment>(
      (_) => Environment(Platform.environment),
      dependsOn: const [],
    ),
  ];
  @override List<Object> get exports => const [Key<Environment>()];
}
```

Тест підміняє середовище override-ом:

```dart
TestApp.start(
  root: const AppModule(),
  overrides: [
    Singleton<Environment>(
      (_) => const Environment({'PORT': '0'}),
      dependsOn: const [],
    ),
  ],
);
```

### 4.4 `grund_http`: `HttpConfig.fromEnvironment` і `HttpModule.fromEnvironment`

```dart
/// The configuration with the address from `HOST` and the port from `PORT`
/// (0 to 65535) when they are set, and everything else from [defaults].
/// Throws [InvalidVariableError] for an empty `HOST`, one with white space,
/// or a bad `PORT`.
factory HttpConfig.fromEnvironment(
  Environment environment, {
  HttpConfig defaults = const HttpConfig(),
});

/// The variable [HttpConfig.fromEnvironment] reads the address from.
static const hostVariable = 'HOST';

/// The variable [HttpConfig.fromEnvironment] reads the port from.
static const portVariable = 'PORT';
```

- `HOST` задано, але він порожній або має пробіли — `InvalidVariableError(name:
  'HOST', expected: 'a host name or an IP address')`. Інших перевірок немає:
  адресу перевіряє адаптер під час `bind`, і це, як і зараз, `RunnerError`.
- `PORT` дозволяє 0, як і `HttpConfig.port` («0 asks the adapter for an
  ephemeral port»).

```dart
/// The HTTP module whose `HttpConfig` is [HttpConfig.fromEnvironment] of
/// the [Environment] in the graph, with [defaults] for what is unset;
/// import `EnvironmentModule` too.
const HttpModule.fromEnvironment({
  this.use = const [],
  this.middleware = const [],
  this.codecs = const [],
  HttpConfig defaults = const HttpConfig(),
}) : config = defaults, _readsEnvironment = true;
```

- Наявний конструктор отримує `_readsEnvironment = false`.
- `bindings`:
  - з `_readsEnvironment`: `Singleton<HttpConfig>((i) =>
    HttpConfig.fromEnvironment(i<Environment>(), defaults: config), dependsOn:
    const [Key<Environment>()])`;
  - інакше як зараз.
- Без `EnvironmentModule` граф дає `MissingProviderError` для `Environment`
  до будь-якої фабрики.
- `///` поля `config` уточнюється: «з `fromEnvironment` — типові значення».
- `///` класу `HttpConfig` замість рецепта з override посилається на
  `fromEnvironment`.

Зіпсований `PORT` на старті: фабрика `HttpConfig` кидає `InvalidVariableError`.
`InjectionRuntime` пропускає `GrundError` без обгортки (наявна поведінка
`_wrap`), тож `App.start` кидає саме `InvalidVariableError`, відкочується,
порт не відкривається.

### 4.5 Шаблони `grund init`

- **`default`** (`project_template.dart`, анотації): `imports:
  [grund.EnvironmentModule(), HttpModule.fromEnvironment(),
  IoAdapterModule()]` (`app_module.dart` імпортує `package:grund/grund.dart as
  grund`, а `HttpModule` і `IoAdapterModule` без префікса). Коментар у `main`
  про `HOST`/`PORT`.
- **`fullstack`** (`fullstack_template.dart`, явний API):
  - `EnvironmentModule()` (за префіксом імпорту файла) і
    `HttpModule.fromEnvironment(use: [...])` в `imports`;
  - коментар про `HOST=0.0.0.0` у контейнері.
- **Версії шаблонів** — хвиля випуску, без якої шаблон не розвʼяжеться (§2):
  - `grundVersion` = `'^0.2.0'` (`grund`, `grund_io`, `grund_auth`,
    `grund_cli` у `default`);
  - `grundHttpVersion` = `'^0.3.0'`;
  - `_grundJaspr` = `'^0.3.0'`;
  - `grund_cli` у `fullstack` = `$_grund`.
  - `///` констант називають причину («the release with `Environment`»).
- **Тест шаблону** (`_helloTest`) не змінюється. Він не стартує раннер, а
  `PORT`/`HOST` машини розробника читаються, але не відкривають порт.
  Зіпсований `PORT` у середовищі розробника дасть зрозумілу
  `InvalidVariableError`; рецепт override — у документації.
- **`main` шаблонів помилку конфігурації не ловить** (моє рішення, §10.11):
  `App.run` перекидає `InvalidVariableError`, і користувач бачить виняток з
  повідомленням про змінну (без значення) та код виходу 255, а не один рядок
  з кодом 64, як у прикладі. Приклад ловить помилку, бо це його власна
  `main`-логіка парсингу аргументів; шаблон лишається мінімальним, а
  документація (`configuration.md`) показує, як піймати помилку й вийти з
  кодом 64, якщо хочеться.

### 4.6 Приклад

- `ServerOptions`:
  - поле `address` (`Object`, типово `'localhost'`);
  - `parse(List<String> arguments, Environment environment)`: `final http =
    HttpConfig.fromEnvironment(environment)`, далі `address: http.address`,
    `port: http.port`;
  - власний розбір `PORT` і `defaultPort` вилучаються;
  - `usage` згадує `HOST` і `PORT`.
- `TasksApp.create` передає `address:` у `ServingModule`.
- `bin/main.dart`:
  - `ServerOptions.parse(arguments, Environment(Platform.environment))`;
  - `on EnvironmentError catch (error)` → `stderr.writeln(error.message)`,
    `exitCode = 64`, поруч із `FormatException`;
  - рядок старту друкує `http://${options.address}:${options.port}`.
- `test/server_options_test.dart`:
  - `HOST` і `PORT` з мапи;
  - `PORT=0` тепер приймається (як у `HttpConfig`);
  - `65536`, `http`, `+80`, ` 80`, `''` дають `InvalidVariableError`;
  - порожній `HOST` дає `InvalidVariableError`.
- `test/main_process_test.dart` передає `'HOST': 'localhost'` разом із
  `PORT`, щоб експортований `HOST` оболонки не змінив адресу.

Модулі прикладу (`AppModule`, `ExplicitAppModule`) не змінюються. Шлях DI
показують шаблони, приклад — шлях без DI.

### 4.7 Документація (англійською)

- **Новий `docs/configuration.md`:**
  - `Environment` і його правила (задане має бути коректним, порожнє —
    задане);
  - `EnvironmentModule`;
  - `HttpModule.fromEnvironment`, `HOST`/`PORT`, `HOST=0.0.0.0` у
    контейнері;
  - `@Provides` з параметром `Environment` і явний `Singleton` з `dependsOn:
    const [Key<Environment>()]`; **обмеження:** `DependencyCheck`
    (`grund_generator`, `constructs/dependency_check.dart`) називає
    `missing_provider` залежність, якої не оголошує жоден модуль пакета, якщо
    у пакеті немає імпорту з іншого пакета; `Environment` приходить з
    `EnvironmentModule` пакета `grund`, тож модуль, чий `@Provides` приймає
    `Environment`, сам імпортує `EnvironmentModule()` (це «чужий» імпорт, і
    перевірка стає частковою; повторний імпорт того самого глобального модуля
    безпечний, перевіряється тестом задачі генератора);
  - тести через override;
  - розділ «Startup data» (№9): дані, які застосунок вантажить і перевіряє
    один раз, — `Singleton`/`@Provides` з перевіркою у фабриці, а не
    статичне поле. Помилка на старті, підміна в тесті, доступ зі сторінки
    через `context.call<T>()`.
- **`docs/adapters.md:77-84`:** рецепт override замінюється посиланням на
  `fromEnvironment`.
- **README:** лінк на `configuration.md` в індексі документації (якщо він
  там є).
- **`docs/getting-started.md`:** рядок про `PORT` у розділі запуску, якщо
  він описує порт.
- **CHANGELOG:**
  - `grund` 0.2.0: `Environment`, `EnvironmentModule`, `EnvironmentError`;
  - `grund_http` 0.3.0: `HttpConfig.fromEnvironment`,
    `HttpModule.fromEnvironment`;
  - `grund_cli` 0.2.0: шаблони читають `HOST`/`PORT`, нові версії.
- **`CLAUDE.md`:** у винятках «Prefer classes…» прибрати `env(...)`; у
  «Project» `grund` описується як «modules, DI, runners, logging,
  environment».

## 5. Помилки

| Клас (стабільний код) | Родина | Коли |
| --- | --- | --- |
| `MissingVariableError(name)` | `EnvironmentError` | незадана змінна без `fallback` |
| `InvalidVariableError(name, expected)` | `EnvironmentError` | задана змінна не тієї форми; `HOST` порожній або з пробілами |
| `MissingProviderError` (наявна) | `GraphError` | `HttpModule.fromEnvironment` без `EnvironmentModule` |

## 6. Тестування

- **`grund`:**
  - `test/config/environment_test.dart`:
    - `has` (порожнє задане);
    - `string` з `fallback` і без;
    - `integer`: `'42'`, `'-3'`, `'007'` проходять; `' 80'`, `'+80'`,
      `'0x50'`, `'1e3'`, `''`, `'99999999999999999999'` дають
      `InvalidVariableError`;
    - `min`/`max` і тексти `expected`;
    - повідомлення не містить значення: змінна `SECRET=abc` + `integer` →
      `message` без `abc`.
  - `test/config/environment_module_test.dart`:
    - `TestApp` з `EnvironmentModule` віддає `Environment` у модуль, що його
      не імпортує (глобальний);
    - override підміняє;
    - фабрика, що кидає `InvalidVariableError`, доходить до виклику старту як
      є (`GrundError` не обгортається), і застосунок не стартує.
- **`grund_http`** (`test/server/http_config_environment_test.dart`):
  - без змінних — `defaults`;
  - `HOST`/`PORT` задані;
  - `PORT=0`;
  - `HOST=''` і `HOST='a b'` дають помилку;
  - `defaults` з `debug: true` зберігається;
  - `HttpModule.fromEnvironment` + `EnvironmentModule` + override
    `Environment({'PORT': '0', 'HOST': '127.0.0.1'})` → `i<HttpConfig>()` має
    ці значення;
  - без `EnvironmentModule` — `MissingProviderError`;
  - зіпсований `PORT` — `InvalidVariableError` (не обгорнута).
- **`grund_cli`:**
  - `init_command_test.dart`: нові рядки версій, `EnvironmentModule()` і
    `HttpModule.fromEnvironment()` у модулі шаблону;
  - `dart test integration` (`init_fullstack_test.dart`) зелений.
- **Приклад:** §4.6.
- **Прийом:**
  - `dart analyze` чистий;
  - тести `grund`, `grund_http`, `grund_cli`, прикладу;
  - `publish --dry-run` без попереджень для `grund`, `grund_http` і
    `grund_cli`.

## 7. Відхилення від CLAUDE.md і релізи

- **Відхилень немає.** `dart:io` у ядрі — лише `Platform.environment` в
  `EnvironmentModule` (сервер лишається поза ядром). `grund_http` не отримує
  `dart:io`. Нових залежностей немає.
- **`CLAUDE.md` оновлюється:** зник приклад `env(...)` (§4.7).
- **Версії** (секції CHANGELOG уже є, `version:` не змінюється):
  - `grund` 0.2.0;
  - `grund_http` 0.3.0;
  - `grund_cli` 0.2.0.
- **Обмеження під час випуску (мейнтейнер):**
  - `grund_http` → `grund: ^0.2.0`, бо використовує `Environment`;
  - `grund_cli` випускається після `grund`, `grund_http`, `grund_io`,
    `grund_auth` і `grund_jaspr` цієї хвилі, бо його шаблони посилаються на
    них.
  - План не змінює обмежень у pubspec.

## 8. Не перевірено (перші перевірки плану)

1. Чи `HOST` експортується в типових оболонках і CI. zsh має параметр `HOST`
   і, наскільки відомо, не експортує його. Debian розвʼязує ім'я машини в
   `127.0.1.1`, тож експортований `HOST=<машина>` прив'язав би сервер туди.
   Перевірка в плані: `env | grep '^HOST='` у середовищі виконавця. Захист —
   `main_process_test` задає `HOST` явно, а документація попереджає.
2. Конвенції хостингів (Heroku/Cloud Run/Render задають `PORT`; SvelteKit
   adapter-node читає `HOST`/`PORT`) взято з пам'яті, не з джерел.
3. Чи генерований `$AppModule` шаблону з `HttpModule.fromEnvironment()` в
   `imports` компілюється (читання `constant_reader.dart` каже так). Перевіряє
   `init_command_test`/інтеграційний тест шаблону.
4. Чи `public_member_api_docs` вимагає `///` на `const
   HttpModule.fromEnvironment` з ініціалізатором приватного поля.
   Очікувано — лише на конструкторі.
5. Чи пакет з `@Provides(Environment)` і власним `imports: [EnvironmentModule()]`
   проходить `DependencyCheck` без `missing_provider`, і чи повторний імпорт
   глобального модуля не дублює вузол графа (перший тест плану для
   генератора; якщо ні, обмеження стає зміною `grund_generator`).

## 9. Узгодження з іншими spec

- Spec адрес сторінок також змінює CHANGELOG `grund_http` 0.3.0 (свої рядки)
  і не чіпає `http_config.dart`/`http_module.dart`. Конфліктів у коді немає.
- План гідратації змінює шаблон `fullstack` (`grund bundle`). Хто
  зливається другим, той робить rebase. Версії шаблону — з цього spec.

## 10. Рішення, прийняті без користувача

1. Порожнє значення — задане, і для `HOST`/`PORT` воно помилкове. Тож
   деплой із `PORT=` падає, а не слухає 8080.
2. `PORT=0` дозволено, як у `HttpConfig.port`. Приклад раніше забороняв 0.
3. Строгий десятковий формат замість `int.tryParse`.
4. Повідомлення ніколи не містить значення змінної, навіть для `PORT`.
5. `HOST` перевіряється лише на порожнечу й пробіли; решту перевіряє адаптер.
6. `debug`/`maxBodyBytes`/`accessLog` із середовища не читаються.
7. Тест шаблону не підміняє `Environment`; рецепт підміни — у документації.
8. Приклад показує шлях без DI, шаблони — шлях DI.
9. Версії шаблонів піднімаються на всю хвилю випуску (§4.5), бо інакше шаблон
   не розвʼяжеться.
10. Звичайний конструктор `Environment`, а не первинний (§4.1).
11. Шаблонна `main` не ловить помилку конфігурації (§4.5);
    `@Provides(Environment)` у пакеті без чужого імпорту вимагає імпорту
    `EnvironmentModule()` у самому модулі, генератор не змінюється (§4.7).
    Ціна помилки: гірший вивід при зіпсованому `PORT` у шаблоні; зміна
    генератора знадобиться, якщо обмеження виявиться нестерпним.
12. Виправлення під час виконання (Задача 1): перша редакція казала, що
    `ProviderCreationError` обгортає помилку фабрики, але `_wrap` у
    `InjectionRuntime` пропускає `GrundError` як є (`ScopedOutsideCallError`,
    `CircularDependencyError` теж). Код — істина: зіпсований `PORT` доходить
    до `App.start` як `InvalidVariableError`. Ціна: у повідомленні немає ключа
    й ланцюга залежностей, але є імʼя змінної й очікувана форма. Змінювати
    `_wrap` або робити `EnvironmentError` не-`GrundError` не став.

## 11. Для автора

1. **`HOST` і `PORT` без префікса.** Рекомендую так: так роблять хостинги, і
   деплой не потребує перейменувань. Альтернатива — `GRUND_HOST`/`GRUND_PORT`:
   безпечніше від чужого `HOST`, але кожен деплой мусить перейменувати
   `PORT`. Зміна торкається лише двох констант.
2. **`Environment` у DI через `EnvironmentModule`.** Рекомендую так: його
   беруть фабрики й `@Provides`, а тест підміняє override-ом.
   Альтернатива — лише статичний `Environment.process` без модуля: менше
   коду, але тест не підмінить те, що прочитала фабрика.
3. **Типова адреса лишається `localhost`, а шаблони читають `HOST`.**
   Рекомендую так: dev-сервер не відкривається в мережу. У контейнері
   задається `HOST=0.0.0.0`, і документація це каже. Альтернатива —
   `0.0.0.0` за замовчуванням у `fromEnvironment`: зручніше в контейнері,
   але небезпечно на ноутбуці.

**Рішення автора (2026-10-17, відповідь «Все»):** усі рекомендації цього
розділу прийнято, spec і його план схвалено до виконання.
