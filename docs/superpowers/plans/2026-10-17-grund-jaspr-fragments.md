# grund_jaspr: HTML-фрагменти та кеш/стиснення статики — план реалізації

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Мета:** обробник `grund_http` повертає HTML-фрагмент компонента Jaspr (`Fragments.respond`), `/static` віддає `ETag`/`Last-Modified`/`304` і готові `.br`/`.gz`, приклад показує цикл «додати / перевірити / видалити» на htmx.

**Архітектура:** спільне ядро рендеру виокремлюється з `PageRenderer` (рефакторинг), `Fragments` — його друга обгортка (без оболонки документа, без live reload, без скрипта `clientId`); `StaticFiles.respond` отримує заголовки запиту й делегує двом малим колабораторам (валідатори, вибір кодування). htmx не є залежністю пакета: приклад завендорює файл у `example/web/vendor/`.

**Стек:** Dart `^3.13.0`, `jaspr >=0.23.5 <0.24.0`, `package:test`, `dart:io` (`HttpDate`).

**Spec:** `docs/superpowers/specs/2026-10-17-grund-jaspr-fragments-design.md` (далі «spec»; §N — його розділи).

## Глобальні обмеження

- Код, doc-коментарі, README, `docs/*.md` і коміти — англійською; `docs/superpowers/**` — українською. Коміти: Conventional Commits, закінчуються `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Нічого не пушити, не тегувати, не публікувати; жодних змін `version:` у pubspec (`grund_jaspr` лишається 0.2.0, `example` залежить від `grund_jaspr: ^0.2.0` — не чіпати; секція 0.3.0 у CHANGELOG уже є). Працювати у worktree `/home/genius/projects/grund-fragments`, гілка `jaspr-fragments` (від master).
- `export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"`. Після кожної задачі: `dart analyze` (корінь) — `No issues found!`, `dart test` змінених пакетів, `dart format packages example` змінює 0 файлів.
- Ліміти CLAUDE.md: файл у `lib/` ≤ 300 рядків (`wc -l`), тест ≤ 500, метод ≤ 40, параметрів ≤ 5, вкладеність ≤ 3, один публічний клас на файл; `///` на кожному публічному члені; без `// ignore:`; функції верхнього рівня — ні (статичні члени `abstract final class`); можливості Dart 3.13 де коротше й зрозуміліше; `catch` лише з `on` і без `Error`.
- `grund_jaspr` не отримує нових залежностей. Тести не ходять у мережу.
- Точні значення зі spec: ознака відсутнього модуля `c.maybe<PageRenderer>() == null` → `JasprSetupError`; фрагмент не має live reload і скрипта `clientId`; слабкий `ETag`; пріоритет кодувань `br` > `gzip` > оригінал, `q=0` забороняє; сусід приймається, лише якщо він звичайний файл у корені (після розвʼязання симлінків) і не старший за оригінал; `vary: accept-encoding` на кожній відповіді статики; `cache-control: no-cache` лишається; htmx **2.0.11**; фрагментні маршрути вимагають сесії (гість `401`); помилка валідації — `422`.
- Задачу 4 не віддавати виконавцю, доки контролер не поклав у worktree `example/web/vendor/htmx.min.js`, `LICENSE` htmx і `README.md` (завантаження з реєстру npm потребує дозволу користувача; виконавці мережею не користуються).

## Огляд файлів

| Файл | Дія | Відповідальність |
| --- | --- | --- |
| `grund_jaspr/lib/src/page/component_rendering.dart` | нов. | `ComponentRendering.render`: `renderComponent` → `HttpResponse` (спільне для сторінок і фрагментів) |
| `grund_jaspr/lib/src/page/page_renderer.dart` | змін. | делегує `ComponentRendering`, додає live reload |
| `grund_jaspr/lib/src/fragments.dart`, `lib/src/client_script_removal.dart`, `lib/grund_jaspr.dart` | нов./змін. | публічний `Fragments.respond`; вилучення скрипта `clientId` |
| `grund_jaspr/lib/src/site/static_validators.dart` | нов. | `ETag`, `Last-Modified`, перевірка умовних заголовків |
| `grund_jaspr/lib/src/site/static_encodings.dart` | нов. | вибір `.br`/`.gz` за `Accept-Encoding` |
| `grund_jaspr/lib/src/site/{static_files,static_api}.dart` | змін. | `respond` приймає заголовки запиту й складає відповідь |
| `grund_jaspr/test/{fragments,fragments_client_script,static_conditional,static_encodings}_test.dart` | нов. | тести |
| `example/lib/src/web/{task_panel,task_fragments}.dart`, `home_page.dart`, `public_site.dart`, `web_module.dart` | нов./змін. | компонент панелі, API фрагментів, htmx у shell |
| `example/web/vendor/*`, `example/test/web_fragments_test.dart`, `example/test/helpers/web_session.dart` | нов. | завендорений htmx; тести; спільний помічник входу |
| `docs/jaspr.md`, `docs/faq.md`, `packages/grund_jaspr/{README,CHANGELOG}.md`, `CLAUDE.md`, `docs/superpowers/ROADMAP.md` | змін. | документація |

## Review Focus

Те, що spec майже не перевіряє, а помилка вдарить користувача першою (кожен пункт має тест у задачі-власниці):

1. Фрагмент, відрендерений при `ServerOptions(clientId: …)`: у тілі немає ні `<script>`, ні порожнього `<head>`, а сторінка при тих самих опціях скрипт зберігає (Задача 1).
2. Умовні запити: `If-None-Match: *`, список тегів, слабкий і сильний тег, зіпсований `If-Modified-Since` (→ повний `200`), `If-None-Match` без збігу разом із свіжим `If-Modified-Since` (→ `200`: тег виграє) (Задача 2).
3. Готові файли: застарілий сусід, сусід-симлінк за межі кореня, прямий запит `x.js.br`, `q=0`; `ETag` і `304` окремі для кожного варіанта; `vary` і на `304` (Задача 3).
4. Фрагментні маршрути: чужий `Origin` або `Sec-Fetch-Site: cross-site` → `403 cross_site_request`; гість → `401`; після входу з same-origin заголовками → успіх (Задача 4).
5. Назва з `<b>x</b>&"`, лише пробіли, 201 символ: у фрагменті екранується (також у `value` повернутої форми при `422`), `422` не дублює список (Задача 4).

---

### Задача 1: `ComponentRendering` і `Fragments.respond`

**Files:** Create `packages/grund_jaspr/lib/src/page/component_rendering.dart`, `lib/src/fragments.dart`, `lib/src/client_script_removal.dart`, `test/fragments_test.dart`, `test/fragments_client_script_test.dart`. Modify `lib/src/page/page_renderer.dart`, `lib/grund_jaspr.dart` (додати експорт `src/fragments.dart`).

**Interfaces:**
- Produces:
  - `abstract final class ComponentRendering { static Future<HttpResponse> render(HttpCtx c, Component component, {int status = 200, PageMatch? match, bool standalone = false}); }` — рівно те, що сьогодні робить `PageRenderer.render` до live reload (`renderComponent(GrundScope(...), request: JasprRequest.from(c.request))`, `PageRenderError` при 500, `JasprResponse.from`, правило статусу), із `standalone` передано в `renderComponent`.
  - `abstract final class Fragments { static Future<HttpResponse> respond(HttpCtx c, Component fragment, {int status = 200}); }` — публічний, з `///`.
  - `abstract final class ClientScriptRemoval { static HttpResponse from(HttpResponse response); }` — внутрішній.

- [ ] **Крок 1 (рефакторинг, окремий коміт):** виокремити `ComponentRendering` із `PageRenderer.render`; `PageRenderer.render` = `ComponentRendering.render(...)` + `LiveReloadScript.addTo`. Сигнатура `PageRenderer` не змінюється. `dart test` пакета зелений без змін у тестах. Коміт `refactor(jaspr): extract the component rendering shared by pages and fragments`.
- [ ] **Крок 2: перевірка.** Переконатися, що `renderComponent` Jaspr 0.23.5 має параметр `standalone`; якщо ні — зупинитися й повідомити. Надрукувати сире тіло фрагмента при `ServerOptions(clientId: 'static/client/main.client.dart.js')`, щоб побачити точну форму `<head><script …></script></head>`; з'ясувати, звідки взяти `clientId` у виконанні (`Jaspr.options` чи інший відкритий доступ); якщо недоступний, правилом вилучення є «єдиний скрипт `defer` у `<head>`, що є єдиним вмістом `<head>`».
- [ ] **Крок 3: тести** `test/fragments_test.dart` (за зразком `page_renderer_test.dart`: `setUpAll(JasprSetup.ensureInitialized)`, `PagesApp.start`, маршрут `Route.get('/x', (c) => Fragments.respond(c, const Comp(), status: …))` у модулі, що імпортує `JasprModule`):
  - тіло містить `<p>` компонента й не містить `<html`, `<head`, `<body`, `<!DOCTYPE`;
  - компонент читає `context.call<Service>()` і виводить значення;
  - заголовки: `content-type: text/html; charset=utf-8`, `cache-control: private, no-cache`; `set-cookie` компонента (через `context.setCookie`) збережено;
  - статус за замовчуванням 200; `status: 201` дає 201; не-200 статус, виставлений самим компонентом, виграє;
  - зламаний компонент (кидає при `build`) → `PageRenderError`;
  - з `JasprConfig(liveReloadUrl: <абсолютний http URL>)` тіло не містить `<script`;
  - графа без `JasprModule` в модулі обробника: обробник ловить `JasprSetupError` і віддає `e.reason` у тілі; тест перевіряє, що причина називає `JasprModule`. Спершу перевірити, що `c.maybe<PageRenderer>()` з `HttpApi` модуля, який імпортує `JasprModule`, не `null` (як у прикладі); якщо ні — зупинитися й повідомити.
  `test/fragments_client_script_test.dart` (окремий файл: стан Jaspr глобальний для ізоляту тест-файла): `setUpAll` викликає `Jaspr.initializeApp(options: ServerOptions(clientId: 'static/client/main.client.dart.js'))` до `ensureInitialized`; сторінка (через `startPublic`) містить `main.client.dart.js`, фрагмент — ні, і не містить `<head`.
- [ ] **Крок 4:** тести падають; `dart test test/fragments_test.dart test/fragments_client_script_test.dart`.
- [ ] **Крок 5: реалізація.** `Fragments.respond`: гвард `c.maybe<PageRenderer>() == null` → `JasprSetupError` з поясненням «import `JasprModule` into the module that declares this API»; далі `ComponentRendering.render(c, fragment, status: status, standalone: true)` → `ClientScriptRemoval.from`. `ClientScriptRemoval` декодує UTF-8, вилучає лише скрипт `clientId` за правилом з Кроку 2, кодує назад; без скрипта повертає відповідь як є. Library-doc `Fragments` має приклад хендлера з spec §4.1.
- [ ] **Крок 6:** `dart test` пакета, `dart analyze`, `wc -l` змінених файлів. Коміт `feat(jaspr): add Fragments.respond for HTML fragments`.

### Задача 2: умовні запити статики (`ETag`, `Last-Modified`, `304`)

**Files:** Create `packages/grund_jaspr/lib/src/site/static_validators.dart`, `test/static_conditional_test.dart`. Modify `lib/src/site/static_files.dart`, `lib/src/site/static_api.dart`, `test/static_files_test.dart:151` (виклик `respond`).

**Interfaces:**
- Consumes: `startWithStatic(staticDirectory())`, `TestClient` (перевірити, як передати заголовки запиту в `get`), `TempDir` з `test/helpers`.
- Produces:
  - `Future<HttpResponse> StaticFiles.respond(String file, {required HeaderMap requestHeaders})`; `StaticApi` передає `c.request.headers`. `StaticFiles` не експортовано з `grund_jaspr.dart`, тож зміна не публічна.
  - `abstract final class StaticValidators { static String etag(FileStat stat, {String variant = ''}); static String lastModified(DateTime modified); static bool isNotModified(HeaderMap request, {required String etag, required DateTime modified}); }`

- [ ] **Крок 1: тести** `test/static_conditional_test.dart` (через `startWithStatic`, `GET /static/styles.css`):
  - `200` має `etag` (починається з `W/"`), `last-modified` (формат HTTP-date), `cache-control: no-cache`, `x-content-type-options: nosniff`;
  - повторний запит із `if-none-match: <etag>` → `304`, порожнє тіло, ті самі `etag`, `last-modified`, `cache-control`;
  - збіг із префіксом `W/` і без нього; `*`; список `"other", <etag>`; тег без збігу → `200`;
  - `if-modified-since: <last-modified>` → `304`; дата на годину раніше → `200`;
  - `if-none-match` без збігу + свіжий `if-modified-since` → `200`;
  - зіпсований `if-modified-since: yesterday` → `200`;
  - після перезапису файла з іншим розміром `etag` інший.
  Оновити виклик у `static_files_test.dart:151`: `requestHeaders: HeaderMap()`.
- [ ] **Крок 2:** тести падають.
- [ ] **Крок 3: реалізація.** `etag` = `W/"<розмір hex>-<mtime у мілісекундах hex>"` (+ `-<variant>` для варіанта); `lastModified` = `HttpDate.format(modified.toUtc())`; `isNotModified`: за наявності `if-none-match` рішення лише за ним (слабке порівняння, `*`, список через кому, пробіли), інакше за `if-modified-since` (`HttpDate.parse`, порівняння з точністю до секунди, збій розбору → `false`). Імпорт `dart:io` з префіксом (`HttpException` `dart:io` конфліктує з `grund_http`). `respond`: `File(file).stat()`; при збігу умови — `304` без читання файла; інакше `200` як сьогодні плюс валідатори.
- [ ] **Крок 4:** `dart test` пакета зелений; `dart analyze`; `wc -l`. Коміт `feat(jaspr): answer 304 for conditional static requests`.

### Задача 3: готові `.br`/`.gz` і `Vary`

**Files:** Create `packages/grund_jaspr/lib/src/site/static_encodings.dart`, `test/static_encodings_test.dart`. Modify `lib/src/site/static_files.dart`.

**Interfaces:**
- Consumes: Задача 2 (`respond(file, requestHeaders:)`, `StaticValidators.etag(stat, variant:)`).
- Produces: `typedef StaticVariant = ({String path, String? encoding});` та `abstract final class StaticEncodings { static StaticVariant choose(String file, {required String root, String? acceptEncoding}); }` — `encoding` це `'br'`, `'gzip'` або `null` (оригінал).

- [ ] **Крок 1: тести** `test/static_encodings_test.dart` (власний каталог: `TempDir`, файли `app.js`, `app.js.br`, `app.js.gz` з довільними байтами; `StaticFiles` + `startPublic` за зразком `static_site.dart`):
  - `accept-encoding: br, gzip` → тіло з `app.js.br`, `content-encoding: br`, `content-type` оригіналу (`javascript`);
  - `gzip` → `.gz`; `br;q=0, gzip` → `.gz`; `gzip;q=1, br;q=0.5` → `.gz`; `identity` або без заголовка → оригінал без `content-encoding`;
  - `br` прийнятний, але `.br` немає, є `.gz` і `gzip` прийнятний → `.gz`; жодного сусіда → оригінал;
  - застарілий сусід (`File.setLastModifiedSync` на годину раніше за оригінал) ігнорується;
  - `app.js.br` — симлінк на файл поза коренем → ігнорується;
  - прямий `GET /static/app.js.br` → звичайний файл, без `content-encoding`;
  - `vary: accept-encoding` на `200` оригіналу, на `200` варіанта і на `304`;
  - `etag` оригіналу, `br` і `gzip` різні; `if-none-match` з тегом варіанта + `accept-encoding: br` → `304`.
- [ ] **Крок 2:** тести падають.
- [ ] **Крок 3: реалізація.** `choose`: розібрати `Accept-Encoding` (елементи через кому, `;q=`, явний запис важливіший за `*`, `q=0` забороняє), серед прийнятних `br`/`gzip` узяти найбільше `q` (рівні — `br`); пропустити кандидата, чий сусід не звичайний файл, не в корені після розвʼязання симлінків чи старший за оригінал; файл із суфіксом `.br`/`.gz` варіантів не шукає. `respond` додає `vary: accept-encoding` до кожної відповіді (і `304`), `content-encoding` для варіанта, `content-type` за оригіналом, `etag` з `variant`. `content-length` не виставляти: його виставляє адаптер.
- [ ] **Крок 4:** `dart test` пакета; `dart analyze`; `wc -l` (`static_files.dart` ≤ 300). Коміт `feat(jaspr): serve precompressed static siblings by Accept-Encoding`.

### Задача 4: приклад — список справ на фрагментах

**Передумова:** `example/web/vendor/htmx.min.js` (htmx.org 2.0.11, `dist/htmx.min.js`), `LICENSE` і `README.md` (джерело, версія, `dist.integrity`) покладено контролером окремим комітом `chore(example): vendor htmx 2.0.11`.

**Files:** Create `example/lib/src/web/task_panel.dart` (`TaskPanel`: `<section id="tasks">` зі списком, формою, помилкою), `example/lib/src/web/task_fragments.dart` (`TaskFragments extends HttpApi`), `example/test/web_fragments_test.dart`, `example/test/helpers/web_session.dart`. Modify `example/lib/src/web/{home_page,public_site,web_module}.dart`, `example/test/web_e2e_test.dart` (`_cookieHeader`/вхід → `web_session.dart`).

**Interfaces:**
- Consumes: `TasksService.list()`, `create(CreateTask)`, `delete(int)`; `CreateTask.fromJson` (`FormatException` на порожню/задовгу назву, `CreateTask.maxTitleLength` = 200); `grund_auth` `CurrentUser`; `UnauthorizedException`; `LoopbackServer.send`; `ApiResponse`.
- Produces: `final class TaskPanel extends StatelessComponent { const TaskPanel({required this.tasks, required this.editable, this.draft = '', this.error}); }`; маршрути `POST /fragments/tasks` (форма `title`, відповідь `201` або `422`, тіло — `TaskPanel`) і `DELETE /fragments/tasks/:id` (`200`, `TaskPanel`; невідомий id — `TaskNotFound` як у JSON-API); `Future<String> WebSession.signIn(LoopbackServer server, String name)` повертає значення `cookie`.

- [ ] **Крок 1: тести** `web_fragments_test.dart` (цикл `ModuleStyle` × `AdapterKind` як у `web_e2e_test.dart`; same-origin заголовки `{'origin': 'http://127.0.0.1:${port}', 'sec-fetch-site': 'same-origin'}`):
  - гість: `GET /` містить `<li>Read the grund README</li>`, не містить `hx-post`; `POST /fragments/tasks` без сесії → `401`;
  - після входу `GET /` містить `hx-post="/fragments/tasks"`, `hx-delete=`, скрипт `/static/vendor/htmx.min.js` і `htmx-config` із `422`;
  - `POST` із `title=Buy+milk` → `201`, тіло починається з `<section id="tasks"`, містить `Buy milk`, не містить `<html`, `content-type` html;
  - `POST` із порожньою назвою, лише пробілами і 201 символом → `422`, у тілі повідомлення про 1–200 символів і форма; кількість `<li>` та сама, що в `GET /`;
  - назва `<b>x</b>&"` → у відповіді `&lt;b&gt;`, без сирого `<b>x`; при `422` значення `draft` екрановано в `value=`;
  - `DELETE /fragments/tasks/<id існуючої>` → `200`, назви немає; `DELETE` невідомого → `404`;
  - після входу `sec-fetch-site: cross-site` і `origin: http://evil.test` → `403`, `json['code'] == 'cross_site_request'`; same-origin → `201`;
  - `GET /static/vendor/htmx.min.js` → `200`, `content-type` JavaScript, є `etag`; повтор із `if-none-match` → `304`.
- [ ] **Крок 2:** винести вхід у `web_session.dart`, `web_e2e_test.dart` лишається зеленим. Окремий коміт `test(example): share the sign-in helper`.
- [ ] **Крок 3:** нові тести падають.
- [ ] **Крок 4: реалізація.** `TaskFragments` застосовує `SessionHook` так само, як сторінки сайту (подивитися `public_site.dart` і `SessionModule`): без нього немає ні `CurrentUser`, ні `SameOriginHook`; гість → `UnauthorizedException`. Назву читати з `(await c.form())`, перевіряти через `CreateTask.fromJson({'title': raw})`, `on FormatException` → `Fragments.respond(c, TaskPanel(…, error: e.message, draft: raw), status: 422)`. `HomePage`: гостю `TaskPanel(editable: false)` (розмітка `<li>назва</li>` без змін), користувачу з сесією `editable: true` (форма з `hx-post`, `hx-target="#tasks"`, `hx-swap="outerHTML"`; кнопка з `hx-delete`). `PublicSite.shell`: `<script src="/static/vendor/htmx.min.js" defer>` та `<meta name="htmx-config" content='{"responseHandling":[{"code":"204","swap":false},{"code":"[23]..","swap":true},{"code":"422","swap":true},{"code":"[45]..","swap":false,"error":true}]}'>`; перевірити в `htmx.min.js`, що ключ `responseHandling` існує в 2.0.11. `web_module.dart` привʼязує `TaskFragments`. Якщо наявні перевірки `web_e2e_test.dart` для користувача з сесією ламаються через нову розмітку — оновити їх і назвати це в звіті.
- [ ] **Крок 5:** `cd example && dart test` зелений (4 сервери); `dart analyze`; `dart format packages example` — 0 змін; `grund_cli gen` не потрібен (файли з анотаціями не змінено); `wc -l`. Коміти: `feat(example): task list on HTML fragments with htmx`.

### Задача 5: документація і підсумкові перевірки

**Files:** Modify `docs/jaspr.md` (новий розділ «Fragments and htmx» перед «Static files»; доповнити «Static files»; рядки 16–17), `docs/faq.md` (14–15), `packages/grund_jaspr/README.md` (162–171), `packages/grund_jaspr/CHANGELOG.md` (секція 0.3.0), `CLAUDE.md` (опис `grund_jaspr` у «Project»), `docs/superpowers/ROADMAP.md` (рядок G7b: фрагменти здано окремим кроком).

- [ ] **Крок 1: тексти** (англійською; spec §4.5): як віддати фрагмент (приклад хендлера з `Fragments.respond`), як підключити htmx і `responseHandling` для `422`, що CSRF-захист `SameOriginHook` пропускає same-origin XHR і запит без браузерних заголовків, токена немає; правило вибору (серверні фрагменти / локальний стан / острів Jaspr; острів у підставленому фрагменті не гідратується); у «Static files»: `ETag`/`304`, готові `.br`/`.gz` (`gzip -k -9`, `brotli -k`) і правила сусіда. Про стиль анотацій — нічого (spec §8.2). Рядки про відсутність інтерактивності оновити: фрагменти є, гідратація — окремо. CHANGELOG 0.3.0: `Fragments.respond`; статика отримує `ETag`, `Last-Modified`, `304`, `Vary`, готові `.br`/`.gz`.
- [ ] **Крок 2: підсумкові перевірки** з кореня worktree: `dart pub get`; `dart analyze` (`No issues found!`); `cd packages/grund_jaspr && dart test`; `cd example && dart test`; `dart format packages example` — 0 змін (двічі); `cd packages/grund_jaspr && dart pub publish --dry-run` — `0 warnings`; `wc -l` усіх змінених файлів у межах лімітів.
- [ ] **Крок 3 (контролер):** запустити приклад, у вбудованому браузері увійти, додати назву, отримати помилку валідації на місці, видалити; результат записати у звіт (відповідає критерію приймання spec §6).
- [ ] **Крок 4: коміт** `docs: fragments and htmx, static caching and precompressed files`.

---

## Самоперевірка плану

Покриття spec: §4.1 → Задача 1; §4.2 → 2; §4.3 → 3; §4.4 → 4; §4.5 → 5; §6 → тести задач 1–4 і ручна перевірка в 5; §7 (версії не чіпати) → Глобальні обмеження; §8.1 → Крок 2 Задачі 1; §8.2 (анотації) → свідомо поза планом (документація мовчить); §8.3 → тест 403/201 у Задачі 4. Типи: `StaticFiles.respond(file, {requestHeaders})` однаково в Задачах 2–3; `StaticVariant`/`StaticEncodings.choose` визначено лише в Задачі 3; `TaskPanel` та маршрути — в Задачі 4. Файли `lib/` нові малі; найбільший ризик ліміту — `static_files.dart` (66 → до ~130 рядків).
