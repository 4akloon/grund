# grund_jaspr: гідратація клієнтських компонентів — план реалізації

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Мета:** серверно відрендерений компонент Jaspr стає інтерактивним у браузері через явний типізований реєстр, `grund bundle` і інтеграцію в `grund dev`, без інструментів Jaspr.

**Архітектура:** нейтральна бібліотека `client_components.dart` (лише дані: імена, типи, `encode`/`decode`) спільна для сервера й клієнта; сервер (`JasprSetup`) і клієнт (`GrundClient.run`) самі перетворюють записи на типи Jaspr; CLI збирає `lib/main.client.dart` звичайним `dart compile js`. Нових пакетів і генератора немає.

**Стек:** Dart `^3.13.0`, `jaspr >=0.23.5 <0.24.0`, `package:test`, `args` (CommandRunner), `logging`.

**Spec:** `docs/superpowers/specs/2026-10-17-grund-jaspr-hydration-design.md` (далі «spec»; §N — його розділи).

**Правки 2026-10-17 (після етапу фрагментів, див. spec §11):** `bundle` завжди `-O2 -Djaspr.flags.release=true` без `.map` і без `--release`, `-O1` з мапами лише в `dev`; клієнтський скрипт лише на сторінках з маркерами острова (вилучення в `PageRenderer`); статика з `ETag`/`304`/`.br`/`.gz` уже злита в `master` разом з `Fragments.respond` і `ClientScriptRemoval`; документація каже про острів у фрагменті й правило вибору. План виконується від поточного `master` (з фрагментами).

## Глобальні обмеження

- Код, doc-коментарі, повідомлення CLI, README, `docs/*.md` і коміти — англійською; `docs/superpowers/**` — українською. Коміти: Conventional Commits, закінчуються `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Нічого не пушити, не тегувати, не публікувати; жодних змін `version:` у pubspec (бампи робить мейнтейнер при релізі). Працювати у worktree `/home/genius/projects/grund-hydration`, гілка `jaspr-hydration` (від master).
- `export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"`. Після кожної задачі: `dart analyze` (корінь) без проблем, `dart test` змінених пакетів, `dart format packages example` змінює 0 файлів.
- Ліміти CLAUDE.md: файл у `lib/` ≤ 300 рядків, тест ≤ 500, метод ≤ 40, параметрів ≤ 5, вкладеність ≤ 3, один публічний клас на файл; `///` на кожному публічному члені; без `// ignore:`; нові й змінені місця використовують можливості Dart 3.13 (primary constructors, dot shorthands, private named parameters) де це коротше й зрозуміліше.
- Точні значення зі spec: ім'я компонента `[a-z0-9_-]+`; `clientId` = `static/client/main.client.dart.js` (відносний, без початкового `/`; береться зі `staticPath` без `/`); `grund bundle` завжди `dart compile js -O2 -Djaspr.flags.release=true` без `.map`, лише `grund dev` збирає `-O1` з мапами, `-O0` ніколи; прапорця `--release` немає; каталог виводу за замовчуванням `web/client`, вхід `lib/main.client.dart`.
- Клієнтський скрипт (`clientId`) стоїть лише на сторінці, де є маркер острова (`<!--@` + ім'я за `[a-z0-9_-]+`, далі пробіл чи `-->`); у фрагменті його немає ніколи (`ClientScriptRemoval` вже в `master`).
- `client_components.dart` імпортує лише `package:jaspr/jaspr.dart`: ні `grund`, ні `dart:io`, ні `jaspr/server.dart`, ні `jaspr/client.dart`.

## Огляд файлів

| Файл | Дія | Відповідальність |
| --- | --- | --- |
| `grund_jaspr/lib/client_components.dart` | нов. | публічна бібліотека: реекспорт трьох класів нижче |
| `grund_jaspr/lib/src/client/client_entry.dart` | нов. | `ClientEntry<T>`: ім'я, `decode`, `encode` з відомим `T` |
| `grund_jaspr/lib/src/client/client_component.dart` | нов. | `ClientComponent<T>`: один запис реєстру |
| `grund_jaspr/lib/src/client/client_components.dart` | нов. | `ClientComponents`: список і `problems` |
| `grund_jaspr/lib/src/client/server_client_options.dart` | нов. | `ClientComponents` → `ServerOptions` |
| `grund_jaspr/lib/src/client/client_bundle_check.dart` | нов. | `WARNING` про відсутній бандл |
| `grund_jaspr/lib/src/client/client_options_lease.dart` | нов. | токен установлених опцій у контейнері застосунку |
| `grund_jaspr/lib/src/client_script_removal.dart`, `lib/src/page/page_renderer.dart` | змін. | скрипт `clientId` лише на сторінці з маркером острова |
| `grund_jaspr/lib/client.dart` + `src/client/grund_client.dart` | нов. | веб-вхід `GrundClient.run` |
| `grund_jaspr/lib/src/{jaspr_config,jaspr_setup,jaspr_module}.dart`, `lib/grund_jaspr.dart` | змін. | `clients`, володіння станом Jaspr, життєвий цикл |
| `grund_cli/lib/src/bundle/{client_bundler,compile_runner,bundle_result}.dart` | нов. | збірка бандла |
| `grund_cli/lib/src/cli/bundle_command.dart`, `grund_cli.dart` | нов./змін. | команда `bundle` |
| `grund_cli/lib/src/dev/dev_bundle.dart`, `cli/dev_command.dart` | нов./змін. | збірка в `dev` |
| `grund_cli/lib/src/init/fullstack_client_files.dart`, `fullstack_template.dart`, `project_kind.dart` | нов./змін. | шаблон з лічильником |
| `example/lib/{clients,main.client}.dart`, `src/web/counter.dart`, `home_page.dart`, `web_module.dart`, `.gitignore`, `integration/` | нов./змін. | приклад і доказ збірки |
| `CLAUDE.md`, `docs/jaspr.md`, `docs/faq.md`, READMEs, CHANGELOG, `ROADMAP.md` | змін. | документація |

## Review Focus

Те, що spec мало явно перевіряє, а помилка вдарить користувача найпершою (кожен пункт має тест у задачі-власниці):

1. Параметр із `"`, `<`, `&`, `-->`, переносом рядка й не-ASCII: розмітка маркера не ламається, `decode` бачить те саме (Задача 4; ручна перевірка в Задачі 6).
2. Послідовні `TestApp` одного файла: застосунок без `clients` після застосунку з ними не має скрипта й маркерів (Задачі 3, 4).
3. Hot reload: новий `onInit` іде раніше за старий `onShutdown` і не втрачає нові опції; користувач, який прибрав `clients`, отримує типові опції (Задача 3).
4. `grund bundle`/`dev`: збірка, що впала, лишає старий бандл недоторканим; повторна збірка не лишає застарілих файлів; відсутній `main.client.dart` — вихід 0 (Задачі 7, 8).
5. Незареєстрований клас або підклас зареєстрованого рендериться без маркерів мовчки (так працює Jaspr): тест фіксує поведінку, `docs/jaspr.md` її описує (Задача 4, 10). Сторінка без маркера острова не має скрипта, сторінка з маркером (також без `data=`) має, фрагмент не має ніколи (Задача 4). Перша збірка в `dev`, що впала, не зупиняє сервер (Задача 8).

---

### Задача 1: Нейтральний реєстр `client_components.dart`

**Files:** Create `packages/grund_jaspr/lib/client_components.dart`, `lib/src/client/{client_entry,client_component,client_components}.dart`, `test/client_components_test.dart`.

**Interfaces:**
- Produces (усе `package:jaspr/jaspr.dart` `Component`):
  - `final class ClientEntry<T extends Component> { const ClientEntry(this.name, this.decode, this.encode); final String name; final T Function(Map<String, Object?> params) decode; final Map<String, Object?> Function(T component)? encode; }`
  - `final class ClientComponent<T extends Component> { const ClientComponent(String name, {required T Function(Map<String, Object?>) decode, Map<String, Object?> Function(T)? encode}); String get name; Type get type; R withType<R>(R Function<C extends Component>(ClientEntry<C> entry) body); }` — поля `decode`/`encode` приватні; `withType` передає `ClientEntry<T>` зі справжнім `T`.
  - `final class ClientComponents { const ClientComponents(this.components); final List<ClientComponent<Component>> components; List<String> get problems; }`

- [ ] **Крок 1: тести** (`test/client_components_test.dart`, плюс допоміжні компоненти `Counter(start,label)` і `Plain` у `test/helpers/client_samples.dart`):
  - `const ClientComponents([ClientComponent<Counter>('counter', encode: Counter.toParams, decode: Counter.fromParams)])` компілюється як `const`; `problems` порожній.
  - `problems` називає: дубль імені (`'counter'` двічі), два записи для одного типу, `T` виведений як `Component` (запис без явного типу), непридатне ім'я (`'Bad Name'`, `''`, `'a/b'`); кожна проблема — окремий рядок із іменем.
  - Пастка коваріантності: `components.first.withType((entry) => entry.encode!(...))` через `ClientComponent<Component>` не падає й повертає параметри; `entry.decode({...})` будує `Counter`.
  - Допустимі імена `'a'`, `'my-counter_2'`.
- [ ] **Крок 2:** `dart test test/client_components_test.dart` падає (бібліотеки немає).
- [ ] **Крок 3: реалізація.** `problems` збирає рядки без кидання; `type` повертає `T`. Бібліотека-вхід `client_components.dart` реекспортує три файли й має library-doc із прикладом `lib/clients.dart` зі spec §4.1. Якщо `const` із tear-off'ами не компілюється — зупинитися й повідомити (spec §9.1).
- [ ] **Крок 4:** тест проходить; `dart analyze` чисто.
- [ ] **Крок 5: коміт** `feat(jaspr): add the shared client component registry`.

### Задача 2: `JasprConfig.clients` і `clientId`

**Files:** Modify `lib/src/jaspr_config.dart` (105 рядків), `test/jaspr_config_test.dart`.

**Interfaces:**
- Consumes: `ClientComponents` (Задача 1).
- Produces: параметр `this.clients` конструктора `const JasprConfig(...)`, `final ClientComponents? clients`; `String? get clientId` (`null`, коли `clients` `null` чи порожній, інакше `'${staticPath без початкового /}/client/main.client.dart.js'`); `static const String clientDirectory = 'client'` і `clientScript = 'main.client.dart.js'`; `withLiveReloadUrl` переносить `clients`.

- [ ] **Крок 1: тести:** `clientId` за замовчуванням `static/client/main.client.dart.js`; для `staticPath: '/assets'` — `assets/client/main.client.dart.js`; `null` без `clients` і з порожнім списком; `withLiveReloadUrl(uri).clients` — той самий об'єкт; `validate()` кидає `JasprSetupError`, чий `reason` містить кожну проблему списку (дубль імені); коректний список проходить.
- [ ] **Крок 2:** падає. **Крок 3:** реалізувати (`validate` додає перевірку `clients.problems`). **Крок 4:** `dart test` пакета проходить.
- [ ] **Крок 5: коміт** `feat(jaspr): add JasprConfig.clients and the derived client script path`.

### Задача 3: Володіння станом Jaspr і `ServerOptions`

**Files:** Create `lib/src/client/server_client_options.dart`, `test/jaspr_setup_clients_test.dart`; Modify `lib/src/jaspr_setup.dart` (24 рядки).

**Interfaces:**
- Consumes: `JasprConfig.clients`, `clientId`; `ClientComponent.withType`.
- Produces: `abstract final class ServerClientOptions { static ServerOptions of(JasprConfig config); }` (кожен запис → `MapEntry(T, ClientTarget<T>(name, params: encode))`); у `JasprSetup` — `static ServerOptions? initialize(JasprConfig config)` (повертає установлені опції, `null` коли `clients` немає) і `static void release(ServerOptions? installed)`; `ensureInitialized()` лишається (його викликає `page_renderer_test.dart`). Статичний стан `JasprSetup` — одне поле `ServerOptions? _latest`: останні опції, установлені `initialize`; ідентичність з ним і є «наше».

Правила `initialize` (spec §4.2):
- немає `clients` → `ensureInitialized()`, нічого не перезаписує, повертає `null`;
- є `clients`: спершу перевірка `useIsolates` як у `ensureInitialized`; Jaspr не ініціалізований, або ініціалізований без `clients` і без `clientId`, або `identical(Jaspr.options, _latest)` → `Jaspr.initializeApp(options: ServerClientOptions.of(config), allowedPathSuffixes: Jaspr.allowedPathSuffixes)`, `_latest =` нові опції, повернути їх; інакше `JasprSetupError`, що пояснює: `main` не має сам викликати `Jaspr.initializeApp(options: ServerOptions(...))`.
- `release(installed)`: коли `installed != null` і `identical(Jaspr.options, installed)` — `Jaspr.initializeApp(allowedPathSuffixes: Jaspr.allowedPathSuffixes)` з типовими опціями й `_latest = null`; інакше нічого. Токен `installed` потрібен, бо під час hot reload новий `onInit` іде раніше за `onShutdown` старого модуля: старий несе свої опції й не чіпає нові.

- [ ] **Крок 1: тести** (`setUp`/`tearDown`: `Jaspr.initializeApp()`; перевіряти `Jaspr.options.clientId`/`.clients`): встановлює `clientId` і запис для типу `Counter`; замінює типові опції; замінює опції попереднього `initialize`; чужі опції з `clients` → `JasprSetupError` (текст містить `Jaspr.initializeApp`); чужі з `clientId` → теж; без `clients` не чіпає наші опції; `release(token)` повертає типові опції, коли `Jaspr.options` ще той самий об'єкт, і не чіпає чужих/новіших (порядок hot reload: `a = initialize(c1)`, `b = initialize(c2)`, `release(a)` → опції `b` лишаються; `release(b)` → типові); `allowedPathSuffixes` не втрачаються; `useIsolates: true` → `JasprSetupError` як раніше; `release(null)` нічого не робить.
- [ ] **Крок 2:** падає. **Крок 3:** реалізувати за правилами вище. **Крок 4:** проходить, включно з наявним `jaspr_setup_test.dart`.
- [ ] **Крок 5: коміт** `feat(jaspr): install client options with an ownership rule`.

### Задача 4: Модуль, `WARNING` про бандл і розмітка на сторінці

**Files:** Create `lib/src/client/{client_bundle_check,client_options_lease}.dart`, `test/hydration_markup_test.dart`, `test/client_script_pages_test.dart`; Modify `lib/src/jaspr_module.dart` (154), `lib/src/client_script_removal.dart` (35), `lib/src/page/page_renderer.dart` (40), `lib/grund_jaspr.dart` (реекспорт `client_component.dart`, `client_components.dart`).

**Interfaces:**
- Consumes: `JasprSetup.initialize/release` (Задача 3), `StaticFiles.find(List<String>)`; наявні `ClientScriptRemoval.from(HttpResponse)` (фрагмент) і `PageRenderer.render` (злито з етапом фрагментів).
- Produces: `abstract final class ClientBundleCheck { static void warnIfMissing(JasprConfig config, StaticFiles files); }` (логер `Logger('grund.jaspr')`, `Level.WARNING`, повідомлення має ім'я файла й `grund bundle`); `final class ClientOptionsLease { ServerOptions? installed; }` — змінний носій токена, що живе в контейнері застосунку (бо `JasprModule` — `const` без стану): модуль реєструє його як `Singleton<ClientOptionsLease>`. `ClientScriptRemoval.unlessIslands(HttpResponse response) → HttpResponse`: вилучає тег скрипта `Jaspr.options.clientId` зі сторінки, у тілі якої немає маркера острова (`<!--@` + ім'я за `[a-z0-9_-]+`, далі пробіл чи `-->`); відповідь без `clientId`, не з байтів або з маркером лишається як є; вилучається лише сам тег (spec §4.2, §9.6), решта `<head>` не змінюється, порожній `<head>` не лишається. `PageRenderer.render` викликає його після `ComponentRendering.render` і до `LiveReloadScript.addTo`; спільне з `from` (регулярний вираз тега) виноситься в приватний член, а не дублюється. `JasprModule.onInit`: `config.validate()`, `injector<ClientOptionsLease>().installed = JasprSetup.initialize(config)`, `ClientBundleCheck.warnIfMissing(config, injector<StaticFiles>())` (лише коли `clients` задано); `onShutdown`: `JasprSetup.release(injector<ClientOptionsLease>().installed)`.

- [ ] **Крок 1: тести** (`startPublic([...], config: JasprConfig(clients: …))` із `Counter`, `LoudCounter extends Counter`, `Plain` із `client_samples.dart`):
  - Сторінка з `Counter`: HTML містить `<!--@counter data=`, `<!--/@counter-->` і `<script src="/static/client/main.client.dart.js" defer></script>`.
  - Параметри з `"`, `<`, `&`, `-->`, `\n`, `ü` у рядку: текст між `data=` і першим `-->` розекранований дорівнює JSON параметрів, і `-->` не з'являється раніше кінця маркера. Якщо Jaspr не екранує `>` — зупинитися й повідомити (це дефект Jaspr, потрібне рішення).
  - Без `clients`: немає `<script`, немає маркерів (як 0.2.0).
  - `test/client_script_pages_test.dart` (з `clients`): сторінка з `Plain` (без острова) не має жодного `<script` з `clientId`, а решта її `<head>` (наприклад, `<title>`) на місці; сторінка з компонентом без `encode` (маркер без `data=`, `<!--@name-->`) скрипт має; сторінка без острова з живим `liveReloadUrl` має скрипт live reload і не має скрипта бандла; `Fragments.respond` з компонентом-островом не має скрипта; відповідь не з байтів (`StreamBody`) лишається як є; без `clientId` відповідь повертається тією самою.
  - `LoudCounter` (підклас) і `Plain` (незареєстрований) рендеряться без маркерів.
  - `encode`, що повертає непридатне для JSON (`DateTime`), → відповідь 500 `problem+json`.
  - Дубль імені у списку → `PagesApp.start` кидає `JasprSetupError`.
  - Відсутній бандл → запис `WARNING` на `grund.jaspr` з `grund bundle`; з файлом `client/main.client.dart.js` у `TempDir` (`staticDirectory`) — запису немає; запуск не падає в обох випадках.
  - Послідовно два застосунки: перший із `clients`, другий без — у другому немає скрипта.
  - Порядок hot reload на рівні модуля (за шаблоном `hot_reload_test.dart`): нові опції переживають `onShutdown` старого модуля; якщо новий `JasprConfig` без `clients`, після `onShutdown` старого сторінки без скрипта.
- [ ] **Крок 2:** падає. **Крок 3:** реалізувати. **Крок 4:** `dart test` пакета проходить; `wc -l` змінених файлів у межах.
- [ ] **Крок 5: коміт** `feat(jaspr): render hydration markers and warn about a missing bundle`.

### Задача 5: Веб-вхід `GrundClient.run` і лічильник у прикладі

**Files:** Create `packages/grund_jaspr/lib/client.dart`, `lib/src/client/grund_client.dart`; `example/lib/clients.dart`, `example/lib/main.client.dart`, `example/lib/src/web/counter.dart`, `example/.gitignore` (`web/client/`); Modify `example/lib/src/web/{home_page,web_module}.dart`, `example/test/web_e2e_test.dart`.

**Interfaces:**
- Consumes: `ClientComponents.components/problems`, `ClientComponent.withType`.
- Produces: `abstract final class GrundClient { static void run(ClientComponents clients); }` — непорожні `problems` → `StateError` з текстом; інакше `Jaspr.initializeApp(options: ClientOptions(clients: {name: ClientLoader((params) => decode(params))}))` і `runApp(const ClientApp())` (без відкладеного завантаження; якщо `ClientLoader` вимагає `loader`, передати негайний `Future`).
- Example: `const clients = ClientComponents([ClientComponent<Counter>('counter', encode: Counter.toParams, decode: Counter.fromParams)])`; `Counter` — `StatefulComponent` (`start`, `label`; кнопки `+`/`−`), що компілюється для вебу (імпорти лише `jaspr/jaspr.dart` і `jaspr/dom.dart`); `main.client.dart` — три рядки зі spec §4.3; `WebModule` передає `JasprConfig(clients: clients)`; `HomePage` показує `Counter(start: 5, label: 'Tasks')` поруч зі списком справ на фрагментах (`#tasks`, `TaskPanel`; його розмітка й маршрути `/fragments/tasks` не змінюються). Якщо веб-модулів два (анотації й явний), змінити обидва; якщо змінився файл з анотаціями, виконати `cd example && dart run grund_cli gen` і закомітити результат (тест перевіряє свіжість `.g.dart`).

- [ ] **Крок 1: тест** у `web_e2e_test.dart` (обидва адаптери й стилі): `GET /` містить `<!--@counter data=`, тег скрипта з `static/client/main.client.dart.js` і `<section id="tasks">`; наявна сторінка прикладу без острова (404 чи інша) не має `<script` з `main.client.dart.js`; відповідь `POST /fragments/tasks` скрипта не має; наявні перевірки `GET /` не зламані.
- [ ] **Крок 2:** падає. **Крок 3:** реалізувати; бібліотеку `client.dart` задокументувати (3-рядковий приклад).
- [ ] **Крок 4:** `cd example && dart test` проходить. Разова перевірка (не комітиться): `dart compile js -O2 -Djaspr.flags.release=true -o <scratchpad>/main.client.dart.js example/lib/main.client.dart` завершується з кодом 0 — це доказ, що `GrundClient`, `const`-реєстр і `Counter` компілюються для вебу (spec §9.1).
- [ ] **Крок 5: коміт** `feat(jaspr): add GrundClient.run and a hydrated counter in the example`.

### Задача 6: Інтеграційний доказ збірки (приклад) і виняток у CLAUDE.md

**Files:** Create `example/integration/client_bundle_test.dart`; Modify `CLAUDE.md` (тестові правила).

- [ ] **Крок 1: тест** (запуск `cd example && dart test integration`, не входить у `dart test`): виконати `Process.run(Platform.resolvedExecutable, ['compile','js','-O2','-Djaspr.flags.release=true','-o','web/client/main.client.dart.js','lib/main.client.dart'])` у каталозі `example` (ті самі прапорці, що в `grund bundle`, spec §4.4); підняти `LoopbackServer` (явний стиль, `io`); `GET /static/client/main.client.dart.js` → 200 і `content-type` JavaScript; `GET /` містить тег скрипта; видалити `web/client` у `tearDown`.
- [ ] **Крок 2:** тест проходить (бандл збирається). **Крок 3:** у `CLAUDE.md` (розділ тестів) додати виняток: «`integration/` of `grund_cli` and `example` run `dart compile js` as a child process» і те, що збірка бандла в `grund bundle` — єдиний продакшн-спавн компілятора.
- [ ] **Крок 4: приймання гідратації вручну (виконує контролер, не імплементер):** `cd example && dart compile js -O2 -Djaspr.flags.release=true -o web/client/main.client.dart.js lib/main.client.dart` (виробничі прапорці: мінімізація може зламати те, що `-O1` не ламав, spec §9.8), запустити приклад (`dart run bin/main.dart`, порт — з його опцій), у вбудованому браузері натиснути `+` кілька разів — число зростає, `label` без спотворень, у консолі немає помилок; увійти в сесію, додати справу через htmx — список оновився, лічильник не скинувся; відкрити сторінку без острова — у мережевій вкладці немає запиту `main.client.dart.js`; другий запит бандла дає `304`. Результат записати в журнал. Без цього Задачі 7–10 не стартують.
- [ ] **Крок 5: коміт** `test(example): prove the client bundle compiles and is served`.

### Задача 7: `ClientBundler` і `grund bundle`

**Files:** Create `packages/grund_cli/lib/src/bundle/{client_bundler,compile_runner,bundle_result}.dart`, `lib/src/cli/bundle_command.dart`, `test/bundle/client_bundler_test.dart`, `test/bundle_command_test.dart`, `integration/bundle_test.dart`; Modify `lib/src/cli/grund_cli.dart` (реєстрація), `lib/grund_cli.dart` за потреби.

**Interfaces:**
- Produces:
  - `abstract interface class CompileRunner { Future<CompileOutcome> compileJs({required String entry, required String output, required bool release, required String workingDirectory}); }`; `final class CompileOutcome { const CompileOutcome(this.exitCode, this.output); }`; `final class ProcessCompileRunner implements CompileRunner { const ProcessCompileRunner({String? executable}); }` — типово `Platform.resolvedExecutable`; коли ім'я виконуваного файла не `dart`/`dart.exe` — `CliFailure(CliExitCode.software, …)` з поясненням (AOT-скомпільований `grund`).
  - `sealed class BundleResult` → `BundleBuilt(Duration elapsed)`, `BundleSkipped()`, `BundleFailed(String output)`.
  - `final class ClientBundler { ClientBundler(this.package, {this.entry = defaultEntry, this.outputDirectory = 'web/client', this.runner = const ProcessCompileRunner()}); static const String defaultEntry = 'lib/main.client.dart'; final String entry; String get outputName; bool get hasEntry; Future<BundleResult> build({required bool release}); }` — компілює у `.dart_tool/grund_bundle/`, і лише при успіху видаляє з `outputDirectory` файли `<outputName>*` (`outputName` = ім'я входу + `.js`, для типового `main.client.dart.js`; разом із застарілими `.br`/`.gz`) та переносить нові (з `release` без `*.map` і `.deps`); при невдачі `outputDirectory` не чіпається. `release: true` — `-O2 -Djaspr.flags.release=true`, `release: false` — `-O1` з мапами (spec §4.4, §4.5); `-O0` не існує.
  - `BundleCommand`: `grund bundle [--entry <file>] [--output <dir>] [-C <dir>]` (прапорця `--release` немає: команда завжди викликає `build(release: true)`); успіх друкує `Bundled <output>/<outputName> in <N> ms.`; `BundleSkipped` — `No <entry>: nothing to bundle.` і код 0; `BundleFailed` → `CliFailure(CliExitCode.problems, 'bundle failed:\n<вивід компілятора>')`.

- [ ] **Крок 1: тести.** Юніт із фейковим `CompileRunner` (пише файли у вказаний `output`): успішна збірка кладе файл і видаляє застарілі `main.client.dart.js_1.part.js`, `main.client.dart.js.gz` і `.br`; невдала лишає старий бандл недоторканим; `release: true` передає виробничий режим (`-O2`, `-Djaspr.flags.release=true`) і не залишає `.map`/`.deps`, `release: false` передає `-O1` і лишає `.map`; без входу — `BundleSkipped`; `ProcessCompileRunner(executable: '/x/grund')` кидає `CliFailure`. Команда через `CliRun`: без входу — вихід 0 і повідомлення; `--help` перелічує `--entry`, `--output` і не перелічує `--release`; `--entry lib/enhance/site.client.dart` дає `site.client.dart.js` і прибирає лише файли з цим іменем; фейковий runner бачить виробничі прапорці. Інтеграція (`integration/bundle_test.dart`, `TempPackage` із `void main() {}`): `grund bundle` справді створює `web/client/main.client.dart.js` без `.map` і `.deps`; друга збірка після зміни виходу оновлює файл; `--entry` на іншому файлі (`TempPackage` з `lib/other.client.dart`) створює `other.client.dart.js`, а `.deps` у виході немає.
- [ ] **Крок 2:** падає. **Крок 3:** реалізувати. **Крок 4:** `dart test` і `dart test integration` у `grund_cli` проходять (відомий флейк `watch_loop_runs_test.dart` — один перезапуск). Ручна перевірка (виконує контролер, у копії): `grund bundle --entry lib/enhance/site.client.dart --output web/enhance` у копії пакета портфоліо дає `web/enhance/site.client.dart.js` без `.deps`, який відповідає `tool/build_client.dart` за вмістом з точністю до `-O2` проти `-O4`.
- [ ] **Крок 5: коміт** `feat(cli): add the bundle command for the client entry`.

### Задача 8: Збірка бандла в `grund dev`

**Files:** Create `packages/grund_cli/lib/src/dev/dev_bundle.dart`, `test/dev_bundle_test.dart`, `integration/dev_client_test.dart`; Modify `lib/src/cli/dev_command.dart` (231), `lib/src/dev/dev_printer.dart` (85) за потреби; `integration/helpers/site_sources.dart`.

**Interfaces:**
- Consumes: `ClientBundler`, `BundleResult`; наявні `WatchLoop.afterRun`, `DevSession.onServing`, `LiveReloadHub.broadcastReload`. `dev` викликає `bundler.build(release: false)` (`-O1` з мапами), `bundle` — `release: true`.
- Produces: `final class DevBundle { DevBundle(this.bundler, {required StringSink out}); Future<void> initial(); void request(); Future<void> get settled; }` — `initial` будує бандл, друкує помилку й не кидає; `request` стартує збірку або, коли одна вже йде, ставить одну відкладену (зміни зливаються); `settled` завершується, коли немає ні збірки, ні відкладеної. `dev` приймає `--output` і `--entry` (ті самі значення за замовчуванням).
- Поведінка `dev` (spec §4.5): якщо `bundler.hasEntry` — `await bundle.initial()` до першого «serving»; у `afterRun` `bundle.request()` лише коли `!report.hasProblems`, паралельно з `dev.apply`; `onServing` чекає `bundle.settled` і лише тоді шле `broadcastReload` (також коли збірка впала).
- Якщо зміни роблять `dev_command.dart` чи `dev_session.dart` довшими за 300 рядків — спершу винести наявний код у колаборатор окремим рефакторинг-комітом без зміни поведінки.

- [ ] **Крок 1: тести.** `dev_bundle_test.dart` (фейковий `CompileRunner`): три `request()` під час однієї збірки дають рівно дві збірки; `initial` із помилкою компіляції друкує текст і не кидає; `settled` чекає відкладеної; `request()` без входу бандла не викликається (`hasEntry == false`). Інтеграція `dev_client_test.dart` (за шаблоном `dev_jaspr_test.dart`; пакет із `lib/main.client.dart`): після зміни `.dart` файл бандла містить нове значення, а подія `reload` приходить лише після його появи; зміна з помилкою компіляції лишає старий бандл, друкує помилку, і `reload` усе одно приходить; пакет, чия перша збірка падає, все одно стартує й віддає сторінку.
- [ ] **Крок 2:** падає. **Крок 3:** реалізувати. **Крок 4:** `dart test` та `dart test integration` проходять.
- [ ] **Крок 5: коміт** `feat(cli): rebuild the client bundle in dev` (рефакторинг, якщо був, — окремим комітом перед ним).
- [ ] **Крок 6: приймання вручну (контролер):** `cd example && dart run grund_cli dev` (з відкритим `lib/src/web/counter.dart`), у браузері змінити підпис кнопки в `Counter` і побачити оновлення сторінки після live reload та працюючий лічильник.

### Задача 9: Шаблон `init --template fullstack`

**Files:** Create `packages/grund_cli/lib/src/init/fullstack_client_files.dart`; Modify `lib/src/init/fullstack_template.dart` (323, плоский каталог: додати лише об'єднання), `project_kind.dart` (`nextSteps`), `test/init_fullstack_test.dart`, `integration/init_fullstack_test.dart`.

**Interfaces:** `abstract final class FullstackClientFiles { static Map<String, String> files(String name); }` повертає `lib/clients.dart`, `lib/main.client.dart`, `lib/src/pages/counter.dart` (вміст за зразком прикладу); `FullstackTemplate.files` розгортає їх (каталог уже понад 300 рядків і задокументований як плоский виняток; його вміст росте лише на потрібні рядки в `home_page`/`app_module`); `.gitignore` шаблону отримує `web/client/`; `home_page`/`app_module` шаблону використовують `Counter` і `JasprConfig(clients: clients)`; константи залежностей шаблону — `grund_jaspr: ^0.3.0`, `grund_cli: ^0.2.0` (версії цього циклу, `version:` пакетів бампає мейнтейнер). README шаблон не створює (spec §4.6 згадував його, але його немає): `nextSteps` отримує рядок `dart run grund_cli bundle  # production bundle (-O2) for /static/client/`.

- [ ] **Крок 1: тести:** `init_fullstack_test` перевіряє наявність нових файлів, рядок `web/client/` у `.gitignore`, нові константи залежностей і `nextSteps`; пакет без діагностик `DartDiagnostics`. Інтеграційний `init_fullstack_test` (тести свіжого пакета на VM) проходить, включно зі сторінкою з маркерами.
- [ ] **Крок 2:** падає. **Крок 3:** реалізувати. **Крок 4:** `dart test`, `dart test integration` проходять.
- [ ] **Крок 5: коміт** `feat(cli): add the hydrated counter to the fullstack template`.

### Задача 10: Документація й прийом

**Files:** Modify `docs/jaspr.md` (рядки 16–17 та новий розділ «Client components» після «Static files»; «Things to know»), `docs/faq.md:14-15`, `packages/grund_jaspr/README.md:162-171`, `packages/grund_cli/README.md`, `packages/grund_jaspr/CHANGELOG.md` (секція 0.3.0), `packages/grund_cli/CHANGELOG.md` (секція 0.2.0), `docs/superpowers/ROADMAP.md`, `CLAUDE.md` (список пакетів, правило про політику генераторів зі spec §7, `grund_cli (gen, dev, init, bundle)`).

- [ ] **Крок 1:** `docs/jaspr.md` описує: реєстр і `lib/clients.dart`, `lib/main.client.dart`, вимоги до компонента (компілюється для вебу, параметри JSON-сумісні, точний `runtimeType`), `grund bundle` (завжди виробнича збірка `-O2`, без `.map`) і `--output`, `dev` (`-O1` з мапами), стискання після `bundle` (`gzip -9k`, `brotli -k`; `/static` віддає готові `.br`/`.gz`, сиблінг не має бути старшим за бандл), скрипт бандла лише на сторінках з островами, `<base>` відсутній або `/`, один стан Jaspr на процес (два одночасні застосунки з різними списками не виявляються), відсутній бандл = `WARNING`, процедуру ручної перевірки в браузері, **правило вибору** (серверний фрагмент для істини на сервері, локальний стан для суто UI-стану, острів Jaspr для типізованої або нетривіальної клієнтської логіки) і **обмеження: острів усередині фрагмента, який htmx підставив після завантаження сторінки, не гідратується** — острови стоять на сторінці, фрагмент оновлює серверний вміст довкола них. Уже зроблені етапом фрагментів рядки `docs/jaspr.md`/`docs/faq.md` («Fragments and htmx») не дублюються, а доповнюються посиланням.
- [ ] **Крок 2:** CHANGELOG-рядки під версіями цього циклу; `ROADMAP.md`: G7b — гідратація здано (дата), лишається `grund_ws` і шаблони; `CLAUDE.md` оновлено.
- [ ] **Крок 3: повні ворота:** `dart pub get`; `dart format --output=none --set-exit-if-changed packages example`; `dart analyze --fatal-infos`; `dart test` у кожному `packages/*/` та `example/`; `dart test integration` у `grund_cli`, `grund_build`, `example`; `dart pub publish --dry-run` у `grund_jaspr` і `grund_cli` («0 warnings»); `git status --short` чисто.
- [ ] **Крок 4: коміт** `docs: document client components, bundle and dev`.

---

## Самоперевірка плану (виконана)

- **Покриття spec:** §4.1 → Задача 1; §4.2 → Задачі 2–4 (скрипт лише на сторінках з островами — Задача 4); §4.3 → Задача 5; §4.4 → Задача 7; §4.5 → Задача 8; §4.6 → Задачі 5, 9, 10; §6 → тести у задачах та ручні приймання (6, 8); §8 (виняток CLAUDE.md) → Задача 6; §7 (політика генераторів) → Задача 10; §9 → Задачі 1, 5, 6 (перевірки 1–4, 8), Задача 4 (перевірка 6), 7 (мапи й `.deps`); §11 → шапка плану, Задачі 4–10.
- **Узгодженість типів:** `ClientEntry`/`ClientComponent.withType` (Задача 1) використовують `ServerClientOptions` (3) і `GrundClient` (5); `JasprConfig.clientId` (2) — `ServerClientOptions` (3) і `ClientBundleCheck` (4); `ClientBundler`/`BundleResult` (7) — `DevBundle` (8).
- **Ruling плану:** токен володіння — значення, яке `initialize` повертає й модуль зберігає в `ClientOptionsLease` у контейнері (модуль `const`, стану не має), плюс один статичний `_latest` для розпізнавання «наших» опцій; шаблон без README замість рядка зі spec §4.6; `GrundCli` не отримує нового параметра (шов `CompileRunner` лише в `ClientBundler`/`ProcessCompileRunner`, бо в конструкторі вже 5 іменованих).
- **Ruling правок 2026-10-17:** `ClientBundler.build(release:)` лишає булевий параметр, бо вибір — «виробнича збірка чи `dev`», а не довільний рівень оптимізації; `bundle` не має прапорця `release`, тож `release: true` захардкоджено в команді (spec §11.1). Вилучення скрипта на сторінці живе в `ClientScriptRemoval` поряд із фрагментним (спільний регулярний вираз тега), а не в `PageRenderer`, щоб файл рендерера не ріс.
- **Ruling (прохання користувача про `tool/` у портфоліо):** `--entry` додано в `bundle` і `dev` (spec §4.4, §11.6); рівня оптимізації й постійної конфігурації немає. Перевірка на зворотному споживачі: бандл портфоліо (`lib/enhance/site.client.dart`, `package:web` без Jaspr) має збиратися `grund bundle --entry lib/enhance/site.client.dart --output web/enhance` до того самого файла, що й `tool/build_client.dart`, — це ручна перевірка Задачі 7, виконується в копії, не в репозиторії портфоліо.
