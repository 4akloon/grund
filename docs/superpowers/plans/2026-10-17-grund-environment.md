# grund і grund_http: конфігурація із середовища — план реалізації

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Мета:**
- ядро `grund` дає `Environment` (строге читання змінних) і глобальний `EnvironmentModule`;
- `grund_http` дає `HttpConfig.fromEnvironment` і `HttpModule.fromEnvironment` (`HOST`, `PORT`);
- шаблони `grund init` і приклад читають адресу й порт із середовища;
- `docs/configuration.md` описує це разом із «даними старту як перевіреним `Singleton`».

**Архітектура:**
- `Environment` — незмінне значення над `Map<String, String>` у новому каталозі `lib/src/config/` ядра; помилки — нова sealed-родина `EnvironmentError`;
- `HttpModule.fromEnvironment` прив'язує `HttpConfig` через `i<Environment>()`, тож відсутній `EnvironmentModule` — помилка графа до старту;
- `grund_http` лишається без `dart:io`.

**Стек:** Dart `^3.13.0`, `package:test`.

**Spec:** `docs/superpowers/specs/2026-10-17-grund-environment-design.md` (далі «spec»; §N — його розділи).

## Глобальні обмеження

- **Мова й коміти.**
  - Код, doc-коментарі, README, `docs/*.md` і коміти — англійською; `docs/superpowers/**` — українською.
  - Коміти: Conventional Commits, закінчуються `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- **Нічого не пушити, не тегувати, не публікувати; жодних змін `version:` і обмежень між пакетами в pubspec.**
  - Обмеження піднімає мейнтейнер, spec §7.
  - Секції CHANGELOG `grund` 0.2.0, `grund_http` 0.3.0 і `grund_cli` 0.2.0 уже є.
  - Константи версій у шаблонах `grund_cli` — не pubspec, їх міняє Задача 3.
- **Робоче місце.** Worktree `/home/genius/projects/grund-environment`, гілка `environment-config` (від master).
- **Середовище й перевірки.** `export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"`. Після кожної задачі:
  - `dart analyze` (корінь) — `No issues found!`;
  - `dart test` змінених пакетів;
  - `dart format packages example` змінює 0 файлів.
- **Ліміти CLAUDE.md:**
  - файл у `lib/` ≤ 300 рядків (`wc -l`), тест ≤ 500;
  - метод ≤ 40 рядків, параметрів ≤ 5, вкладеність ≤ 3;
  - один публічний клас (або sealed-родина) на файл;
  - `///` на кожному публічному члені; без `// ignore:`;
  - функції верхнього рівня — ні;
  - можливості Dart 3.13, де коротше й зрозуміліше;
  - `catch` лише з `on` і без `Error`.
- **Залежності.** Нових залежностей немає; `grund_http/lib` не імпортує `dart:io`. Тести не ходять у мережу й не залежать від середовища машини: усюди `Environment(<мапа>)` або override.
- **Точні значення зі spec:**
  - **Формат цілого.** `^-?[0-9]+$`; переповнення (`int.tryParse` == `null`) дає `InvalidVariableError`.
  - **Задане й незадане.** Порожнє значення задане; `fallback` лише для незаданої змінної, і `min`/`max` його не перевіряють.
  - **Повідомлення.** Без значення змінної, з текстом «Its value is not shown, as it may be a secret.».
  - **Очікування `expected`:**
    - `'an integer'`;
    - `'an integer from <min> to <max>'`;
    - `'an integer of at least <min>'`;
    - `'an integer of at most <max>'`;
    - `'a host name or an IP address'`.
  - **`HOST`/`PORT`.** Змінні `HOST`, `PORT`; `PORT` 0–65535. `HOST` порожній або з пробілом (`\s`) — помилка.
  - **Модуль.** `EnvironmentModule` глобальний.
  - **Версії шаблонів:**
    - `grundVersion` = `'^0.2.0'`;
    - `grundHttpVersion` = `'^0.3.0'`;
    - `_grundJaspr` = `'^0.3.0'`;
    - `grund_cli` у `fullstack` = `$_grund`.

## Огляд файлів

| Файл | Дія | Відповідальність |
| --- | --- | --- |
| `grund/lib/src/config/environment.dart` | нов. | `Environment` |
| `grund/lib/src/config/environment_module.dart` | нов. | `EnvironmentModule` |
| `grund/lib/src/errors/environment_errors.dart` | нов. | `EnvironmentError`, `MissingVariableError`, `InvalidVariableError` |
| `grund/lib/grund.dart` | змін. | експорти |
| `grund/test/config/{environment,environment_module}_test.dart` | нов. | тести |
| `grund_http/lib/src/server/{http_config,http_module}.dart` | змін. | `fromEnvironment` |
| `grund_http/test/server/http_config_environment_test.dart` | нов. | тести |
| `grund_cli/lib/src/init/{project_template,fullstack_template}.dart`, `test/init_command_test.dart` | змін. | шаблони й версії |
| `example/lib/src/server/{server_options,tasks_app}.dart`, `example/bin/main.dart`, `example/test/{server_options,main_process}_test.dart` | змін. | приклад |
| `docs/configuration.md` | нов. | документація |
| `docs/adapters.md`, `README.md`, CHANGELOG `grund`/`grund_http`/`grund_cli`, `CLAUDE.md` | змін. | документація |

## Review Focus

Те, що spec майже не перевіряє, а помилка вдарить користувача першою (кожен пункт має тест у задачі-власниці):

1. **Строгий розбір цілого** (Задача 1): `' 80'`, `'+80'`, `'0x50'`, `'1e3'`, `''` і 20-значне число дають `InvalidVariableError`, а не відкат до `fallback`. `'007'` дає 7.
2. **Секрети** (Задача 1): `message` і `toString()` обох помилок не містять значення. Тест із `SECRET=hunter2` шукає `hunter2` у `message`, `toString()` і в `ProviderCreationError.message` вручну зібраної обгортки (контейнер `GrundError` не обгортає, Задача 1).
3. **Порядок збою** (Задача 2): зіпсований `PORT` з `HttpModule.fromEnvironment` кидає `InvalidVariableError` (не обгорнуту: контейнер пропускає `GrundError`) з `App.start`. Адаптер не викликав `bind`: лічильник у фейковому адаптері `test/helpers/fake_adapter.dart` дорівнює 0.
4. **Явне ввімкнення** (Задача 2): `HttpModule()` без `fromEnvironment` ігнорує `PORT` у підміненому `Environment`. `HttpModule.fromEnvironment()` без `EnvironmentModule` дає `MissingProviderError` для `Environment` до будь-якої фабрики.
5. **Шаблони розвʼязуються й стартують** (Задача 3): згенерований `default` компілюється з `HttpModule.fromEnvironment()` в анотації, а `dart test integration` для `fullstack` зелений.

---

### Задача 1: `grund` — `Environment`, помилки, `EnvironmentModule`

**Files:**
- Create `packages/grund/lib/src/config/environment.dart`, `lib/src/config/environment_module.dart`, `lib/src/errors/environment_errors.dart`, `test/config/environment_test.dart`, `test/config/environment_module_test.dart`.
- Modify `lib/grund.dart`.

**Interfaces:**
- Produces:
  - `final class Environment { const Environment(Map<String, String> values); bool has(String name); String string(String name, {String? fallback}); int integer(String name, {int? fallback, int? min, int? max}); }`;
  - `sealed class EnvironmentError extends GrundError { String get name; }`;
  - `final class MissingVariableError extends EnvironmentError { const MissingVariableError(this.name); }`;
  - `final class InvalidVariableError extends EnvironmentError { const InvalidVariableError({required this.name, required this.expected}); final String expected; }`;
  - `final class EnvironmentModule extends Module { const EnvironmentModule(); }` (`global => true`, експортує `Key<Environment>()`).
  - Барель: `export 'src/config/environment.dart' show Environment;`, `export 'src/config/environment_module.dart' show EnvironmentModule;`, `export 'src/errors/environment_errors.dart';`.

**Кроки:**
- [ ] **Крок 1: тести** spec §6 («`grund`») і Review Focus 1–2. Модулі для тесту модуля — у `test/helpers/module_fixtures.dart`, якщо там є місце (≤ 500), інакше в новому `test/helpers/environment_fixtures.dart`.
- [ ] **Крок 2:** тести падають.
- [ ] **Крок 3: реалізація** за spec §4.1–4.3. `integer` ділиться на приватні статики `_parse` і `_expectation(min, max)`. `EnvironmentModule` імпортує `dart:io` лише заради `Platform`.
- [ ] **Крок 4.** `cd packages/grund && dart test`; `dart analyze`; `wc -l`. Коміт `feat(core): Environment, EnvironmentModule and environment errors`.

### Задача 2: `grund_http` — `HttpConfig.fromEnvironment` і `HttpModule.fromEnvironment`

**Files:**
- Create `packages/grund_http/test/server/http_config_environment_test.dart`.
- Modify `lib/src/server/http_config.dart`, `lib/src/server/http_module.dart`.

**Interfaces:**
- Consumes: `Environment`, `InvalidVariableError`, `EnvironmentModule` (Задача 1; workspace розвʼязує локальний `grund` без зміни обмеження `^0.1.0`). Якщо `dart pub get` відмовляє через обмеження, зупинитися й повідомити — обмеження не міняти.
- Produces:
  - `factory HttpConfig.fromEnvironment(Environment environment, {HttpConfig defaults = const HttpConfig()})`;
  - `static const hostVariable = 'HOST'`, `static const portVariable = 'PORT'`;
  - `const HttpModule.fromEnvironment({List<HookRef<HttpHook>> use, List<Middleware> middleware, List<ResponseCodec<Object>> codecs, HttpConfig defaults})`;
  - приватне поле `_readsEnvironment`.

**Кроки:**
- [ ] **Крок 1: тести** spec §6 («`grund_http`») і Review Focus 3–4. Застосунок — через `App(root:, overrides:)`/`TestApp` з `test/helpers/adapter_module.dart` або `fake_adapter.dart`. Подивитися, як `http_server_test.dart:32-40` будує модулі, і повторити.
- [ ] **Крок 2:** тести падають.
- [ ] **Крок 3: реалізація** за spec §4.4.
  - `///` класу `HttpConfig`: замість рецепта override — посилання на `fromEnvironment`;
  - `///` поля `HttpModule.config`: «the configuration, or the defaults with `fromEnvironment`»;
  - doc-приклад класу `HttpModule` лишається, а нижче додається рядок про `fromEnvironment`.
- [ ] **Крок 4.** `dart test` у `grund_http`, `grund_io`, `grund_shelf`; `dart analyze`; `wc -l` (`http_module.dart` 74 → ≤ 110, `http_config.dart` 33 → ≤ 80). Коміт `feat(http): HttpConfig and HttpModule from the environment (HOST, PORT)`.

### Задача 3: шаблони `grund init`

**Files:** Modify `packages/grund_cli/lib/src/init/project_template.dart`, `lib/src/init/fullstack_template.dart`, `test/init_command_test.dart`.

**Interfaces:**
- Consumes: `EnvironmentModule`, `HttpModule.fromEnvironment` (Задачі 1–2).
- Produces:
  - нові значення констант версій (Глобальні обмеження);
  - `imports` шаблонів за spec §4.5.

**Кроки:**
- [ ] **Крок 1: перевірка** spec §8.1: `env | grep -c '^HOST='` у середовищі виконавця; записати у звіт.
- [ ] **Крок 2: тести.**
  - `init_command_test.dart` очікує `grund: ^0.2.0`, `grund_http: ^0.3.0`, `grund_cli: ^0.2.0`;
  - модуль `default` містить `EnvironmentModule()` і `HttpModule.fromEnvironment()`;
  - для `fullstack` — `grund_jaspr: ^0.3.0`, `grund_cli: ^0.2.0` і обидва модулі.
- [ ] **Крок 3:** тести падають.
- [ ] **Крок 4: реалізація.**
  - **`default`:** імпорт `package:grund/grund.dart as grund` уже є, а `EnvironmentModule` в анотації пишеться як `grund.EnvironmentModule()`. Перевірити, що генератор приймає префіксований const у `imports` (як у прикладі з `grund.`), інакше імпортувати `show EnvironmentModule` без префікса.
  - **Коментарі** в `main` шаблонів: `HOST`/`PORT`, `HOST=0.0.0.0` у контейнері.
  - **`///` констант версій** називають причину.
  - **`fullstack_template.dart`** — плаский каталог; ліміт файла на нього не діє (library-doc).
- [ ] **Крок 5.**
  - `cd packages/grund_cli && dart test` і `dart test integration` (Review Focus 5; `init_fullstack_test.dart` проганяє тести свіжого пакета проти workspace);
  - `dart analyze`.
  - Коміт `feat(cli): templates read HOST and PORT through EnvironmentModule`.

### Задача 4: приклад

**Files:** Modify `example/lib/src/server/server_options.dart`, `example/lib/src/server/tasks_app.dart`, `example/bin/main.dart`, `example/test/server_options_test.dart`, `example/test/main_process_test.dart`.

**Interfaces:**
- Consumes: `HttpConfig.fromEnvironment`, `Environment`, `EnvironmentError`.
- Produces:
  - `ServerOptions({ModuleStyle style, AdapterKind adapter, Object address = 'localhost', int port = 8080})`;
  - `factory ServerOptions.parse(List<String> arguments, Environment environment)`;
  - `defaultPort` вилучено (перевірити `grep -rn defaultPort example`).

**Кроки:**
- [ ] **Крок 1: тести** spec §4.6 у `server_options_test.dart` (тексти помилок через `isA<InvalidVariableError>().having((e) => e.name, …)`). `main_process_test.dart` передає `'HOST': 'localhost'`.
- [ ] **Крок 2:** тести падають.
- [ ] **Крок 3: реалізація** за spec §4.6. `main` ловить `on EnvironmentError` поруч із `FormatException` (обидва → `stderr`, `exitCode = 64`). `usage` згадує `HOST` і `PORT`.
- [ ] **Крок 4.** `cd example && dart test`; `dart analyze`; `dart format packages example` — 0 змін. Коміт `refactor(example): read HOST and PORT with HttpConfig.fromEnvironment`.

### Задача 5: документація і підсумкові перевірки

**Files:**
- Create `docs/configuration.md`.
- Modify:
  - `docs/adapters.md` (77–84);
  - `README.md` (індекс документації, 213–223: рядок «Configuration and the environment» після «Modules and dependency injection»);
  - CHANGELOG `packages/grund` (0.2.0), `packages/grund_http` (0.3.0), `packages/grund_cli` (0.2.0);
  - `CLAUDE.md`: виняток «Prefer classes…» без `env(...)`; «Project», опис `grund`;
  - `docs/modules-and-di.md`: одне посилання на `configuration.md` у «Visibility» поруч зі словами про конфігурацію.

**Кроки:**
- [ ] **Крок 0: перевірка spec §8.5 до текстів.** Тест у `packages/grund_generator/test/` (за зразком наявних тестів `DependencyCheck`; fixture-пакет у `TempDir`, вихід з `WorkspacePackageConfig`): модуль із `@Provides static X f(Environment e)` і власним `imports: [EnvironmentModule()]` проходить без діагностик, а без цього імпорту дає `missing_provider`. Якщо повторний імпорт глобального модуля дублює вузол або падає — зупинитися й повідомити контролера (обмеження §4.7 стає зміною генератора, потрібне рішення). Імена `Environment`/`EnvironmentModule` у `lib/` генератора не з'являються (`boundary_test`).
- [ ] **Крок 1: тексти** англійською за spec §4.7. Обмеження `DependencyCheck` і рецепт «модуль сам імпортує `EnvironmentModule()`» входять у `configuration.md`.
  - У `configuration.md` чотири приклади коду:
    - `@Provides` з `Environment`;
    - явний `Singleton` з `dependsOn`;
    - override у тесті;
    - «Startup data»: `Singleton<SiteContent>` з перевіркою у фабриці й доступом через `context.call<SiteContent>()` у компоненті Jaspr.
  - Кожен приклад звірити з наявним API (`Singleton`, `Key`, `TestApp.start(overrides:)`).
  - CHANGELOG:
    - `grund` 0.2.0: `Environment`, `EnvironmentModule`, `EnvironmentError`;
    - `grund_http` 0.3.0: `HttpConfig.fromEnvironment`, `HttpModule.fromEnvironment`;
    - `grund_cli` 0.2.0: шаблони читають `HOST`/`PORT`, версії залежностей.
- [ ] **Крок 2: підсумкові перевірки** з кореня worktree:
  - `dart pub get`; `dart analyze` (`No issues found!`);
  - `dart test` у `grund`, `grund_http`, `grund_io`, `grund_shelf`, `grund_cli`; `cd example && dart test`;
  - `dart format packages example` — 0 змін (двічі);
  - `dart pub publish --dry-run` — `0 warnings` для `grund`, `grund_http`, `grund_cli`;
  - `wc -l` змінених файлів у межах.
- [ ] **Крок 3 (контролер):** `HOST=127.0.0.1 PORT=9099 dart run bin/main.dart` у `example/` друкує `http://127.0.0.1:9099` і відповідає на `curl`, а `PORT=abc` дає один рядок на stderr і код 64. Результат записати у звіт.
- [ ] **Крок 4: коміт** `docs: configuration from the environment`.

---

## Самоперевірка плану

**Покриття spec:**

| Розділ spec | Задача |
| --- | --- |
| §4.1–4.3 | 1 |
| §4.4 | 2 |
| §4.5 | 3 |
| §4.6 | 4 |
| §4.7 | 5 |
| §5 | тести задач 1–2 |
| §6 | тести задач 1–4 |
| §7 (версії й обмеження не чіпати) | Глобальні обмеження |
| §8.1 | Крок 1 Задачі 3 і `main_process_test` у Задачі 4 |
| §8.3 | Задача 3, Review Focus 5 |
| §8.4 | `dart analyze` Задачі 2 |
| §9 | rebase за потреби |

**Узгодженість типів:**
- `Environment`/`InvalidVariableError` визначено в 1 і використано в 2–4.
- `HttpConfig.fromEnvironment` — у 2, потім у 4.
- `HttpModule.fromEnvironment` — у 2, потім у 3.

**Ризики лімітів:** нових великих файлів немає. `http_module.dart` 74 → ~105; `fullstack_template.dart` (323) — плаский каталог.

**Рефакторинг першою задачею не потрібен:** жоден файл `lib/` не підходить до 300 рядків.
