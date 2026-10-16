# grund G7a: Jaspr SSR і сесії — план реалізації

> **Для виконавців-агентів:** ОБОВ'ЯЗКОВИЙ піднавик: `superpowers:subagent-driven-development` (рекомендовано) або `superpowers:executing-plans`. Кроки мають чекбокси (`- [ ]`) для відстеження.

**Мета:** Один процес grund віддає REST API і HTML-сторінки, відрендерені на сервері Jaspr, з одним DI, одним життєвим циклом і спільною cookie-сесією; `grund init --template fullstack` створює такий проєкт, а `grund dev` сам оновлює відкриті сторінки після reload.

**Архітектура:** Новий пакет `grund_jaspr` дає `JasprModule`: `HttpApi` з порожнім шляхом і маршрутами `GET /` і `GET /*` (нижче за API-маршрути), який на кожен запит віддає файл із `web/` або рендерить `app()` через `renderComponent` під `GrundScope` (що тримає `HttpCtx`) і перетворює відповідь Jaspr на `HttpResponse`. Новий пакет `grund_auth` дає сесії: непрозорий токен у `HttpOnly`-cookie, `Sessions.start` з ротацією токена, глобальний `SessionHook`, що кладе `CurrentUser` у call-скоуп, і перевірку same-origin. `grund_http` отримує злиття `set-cookie`, `c.form()` і `StatusCode.seeOther`; `grund_cli` — шаблон `fullstack` і loopback-точку SSE, адресу якої `grund_jaspr` вставляє скриптом у сторінки в dev.

**Стек:** Dart `^3.8.0` (pub workspace), Jaspr `>=0.23.5 <0.24.0` (лише `package:jaspr/server.dart` і `package:jaspr/dom.dart`, без `jaspr_builder`), `package:path`, `dart:io` `HttpServer` для точки SSE у `grund_cli`.

**Spec:** `docs/superpowers/specs/2026-10-16-grund-jaspr-design.md` (етап G7a; розділ 4.6 «Автооновлення браузера в dev» — доповнення, коміт `fbf37cb`). Рамка: `docs/superpowers/specs/2026-10-15-grund-platform-design.md` §6.7; ядро й HTTP: `2026-10-15-grund-core-design.md`.

**Як цей план перевірено.** Код у задачах не вигаданий. Кожен коміт плану зібрано як окремий коміт у копії репозиторію від `HEAD` `1a8755e` (окремий git-репозиторій у scratch, не цей), і на кожному коміті пройдено: `dart pub get --offline`, `dart analyze --fatal-infos` з кореня («No issues found!»), `dart format --set-exit-if-changed packages example` (0 змін) і `dart test` пакетів задачі; інтеграційні тести `grund_cli` — після задач 11, 12b і 12d; `dart pub publish --dry-run` усіх десяти пакетів — після задачі 13 (0 попереджень). Блоки «файл цілком» і диффи вставлені скриптом із цих комітів, тому порядок і проміжні версії файлів узгоджені. Перевірено на Dart 3.13.5 (fvm Flutter 3.47.6) на Linux. **Не перевірено**: Dart 3.8.0 (локального SDK немає: це підтвердить CI, задача 14), CI GitHub Actions, macOS/Windows, бали pana, справжній браузер (EventSource, перепідключення, mixed content). Повний перелік — «Що не перевірено» в кінці.

---

## Глобальні обмеження

Кожна задача неявно містить цей розділ. Значення скопійовано з `CLAUDE.md` репозиторію та зі spec.

- Мова: код, `///`-коментарі, діагностики, README, CHANGELOG, повідомлення комітів — **англійською**. Документи в `docs/superpowers/` (цей план, роадмап) — українською.
- SDK `^3.8.0`; фічі Dart 3.8 (patterns, switch-вирази, records, модифікатори класів). Без dot shorthands і null-aware elements (3.10), без primary constructors.
- Залежності: `grund_jaspr` → `grund`, `grund_http`, `jaspr: '>=0.23.5 <0.24.0'`, `path`; dev: `grund_io`, `lints`, `test`. `grund_auth` → `grund`, `grund_http`; dev: `grund_io`, `lints`, `test`. `jaspr` — лише в `grund_jaspr` і `example`. `grund_jaspr` не залежить від `grund_auth`, `grund_auth` — від `jaspr`; `grund_cli` не залежить від жодного з них (шаблон fullstack — рядки). Ядро `grund` не змінюється.
- Імпорти Jaspr: `package:jaspr/server.dart` (вона реекспортує `package:jaspr/jaspr.dart`: не імпортувати обидві, інакше `unnecessary_import`) і `package:jaspr/dom.dart` для елементів (`div`, `p`, `ul`, …). `package:jaspr/server.dart` і `package:grund/grund.dart` обидві оголошують `Key`: **у файлі, що імпортує обидві**, писати `import 'package:jaspr/server.dart' hide Key;`; в інших файлах `hide` не потрібен.
- Версії (модель `docs/RELEASING.md`: пакети версіонуються незалежно). Нові пакети мають `version: 0.1.0` і розділ `## 0.1.0` у CHANGELOG. **Поле `version:` наявних пакетів не змінюється**, обмеження між членами workspace лишаються `^0.1.0`. Записи CHANGELOG ідуть під версію, з якою зміна вийде: `grund_http` — `## 0.1.1`, `grund_cli` — `## 0.1.2` (зараз 0.1.1). Підняти `version:` і обмеження (`grund_http: ^0.1.1` у `grund_auth`/`grund_jaspr`) — крок релізу мейнтейнера, не цього плану (див. «Що не перевірено»).
- Ліміти: файл у `lib/` ≤ 300 рядків (`wc -l`; плаский каталог без логіки може перевищити, з поміткою в doc бібліотеки), тестовий файл ≤ 500, метод ≤ 40, параметрів ≤ 5, вкладеність ≤ 3, ~15 членів і одна відповідальність на клас, один публічний клас (або sealed-родина) на файл. Перед розширенням файла — `wc -l`; файл понад ліміт не росте.
- Класи зі статичними членами замість top-level функцій у `lib/src`; константи в класі, якому належать. Публічні члени мають `///` (перше речення — підсумок; булеві — «Whether»; `[ідентифікатори]`). Без `dynamic`, без `!` там, де допомагає патерн, `late` лише з коментарем, без позиційних `bool`.
- Помилки — типізовані `GrundError` (`JasprError`, `AuthError`) або RFC 9457-відповіді; жодного `catch` без `on`; `Error` ловиться лише за точним підтипом. Нова межа виняткова: `BodyReader` перетворює `FormatException` тіла форми на 400 (записати в `CLAUDE.md`, задача 13).
- Тести — в тому ж коміті, що й код; нова гілка логіки має тест, що без неї падає. Без мережі; HTTP — ефемерні порти на loopback; тимчасові файли — `TempDir`. `grund_cli`: тести in-process (`CliRun`), винятки — `dev` (дочірній процес) і `integration/` (`dart test integration`, не частина `dart test`).
- Коміти — Conventional Commits, англійською, останній рядок повідомлення: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (або рядок атрибуції, який дає харнес виконавця). **Додавати лише названі файли** (`git add <файли>`); ніколи `git add -A`, `git stash`, `git checkout -- .`, `git reset --hard`: у робочому дереві можуть бути чужі зміни. Не пушити, не тегувати, не публікувати.
- Перевірка кожної задачі перед комітом: `dart analyze` з кореня — `No issues found!`; `dart test` пакетів задачі зелений; `dart format packages example` — `(0 changed)`; `wc -l` змінених файлів у межах.
- Dart не завжди в `PATH`: кожна команда `Bash` починається з `export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"`. Нижче команди наведено без цього рядка.
- Робоча гілка: `g7a-jaspr` від `master` (`git switch -c g7a-jaspr`); злиття в `master` вирішує користувач.

## Рішення плану і відхилення від spec

Spec — опис наміру; там, де він неповний або розходиться з кодом, план фіксує таке (перевірено в комітах-стадіях).

1. **`JasprModule` не імпортує `HttpModule`** (spec 4.1: «модуль, що імпортує `HttpModule`»). `HttpModule` має конфігурацію й глобальні хуки застосунку; другий екземпляр у графі або дублює сервер, або губить `use:`/`middleware:`. Застосунок імпортує `HttpModule` сам, а `JasprModule(app:, imports:, config:)` бере `imports:` — модулі, експорти яких бачать компоненти (`context.call<T>()`).
2. **Відповідь Jaspr зі статусом 500 — `PageRenderError`** (`JasprError`), тобто 500 `application/problem+json` через `ProblemResponder`, як решта збоїв (spec §5). Jaspr сам друкує виняток компонента в stderr.
3. **Charset додається лише HTML без charset** (spec: «якщо `content-type` відсутній або без charset»): `application/xml` сторінки (RSS) не чіпається; явний `charset=iso-8859-1` зберігається. `content-length` Jaspr відкидається (його ставить адаптер).
4. **Нове API `grund_http`, якого spec не називає, але без якого потік входу 4.4 неможливий**: `HttpCtx.form()` (поля `application/x-www-form-urlencoded` як `Params`, `ParamLocation.form`, вказівник `/body/<name>`), `FormDecoder`, `StatusCode.seeOther` (303 після `POST`). Додавання значення enum `ParamLocation.form` вважаємо несумісністю лише для вичерпного `switch` користувача: `grund_http` — патч `0.1.1` з приміткою в CHANGELOG (альтернатива — `0.2.0`, яка тягне релізи `grund_io`/`grund_shelf`; рішення мейнтейнера при релізі).
5. **Перевірку same-origin виконує `SessionHook`** (за `SessionConfig.sameOrigin`, за замовчуванням увімкнено), а `SameOriginHook` — та сама перевірка окремо для застосунку без сесій. Spec 4.2 каже «вмикається в `SessionConfig`», але не каже, як хук потрапляє в `HttpModule(use:)`; одна реєстрація `SessionHook` закриває обидва.
6. **Статика**: сегмент, що починається з `.`, містить `/`, `\`, `:` або керівні символи, ніколи не файл (spec: «шлях після нормалізації лишається всередині каталогу»; правило сегментів суворіше й закриває `.env`, `C:` і закодовані `%2F`/`%5C`); символьні посилання розв'язуються. Статика має пріоритет над сторінкою. Шлях із розширенням, якого немає в `JasprConfig.pageSuffixes` (spec: `allowedPathSuffixes` Jaspr), і не файл — 404 `file_not_found`.
7. **`CookieAttributes` без `Expires` і `Domain`**: `Max-Age` досить для всіх сучасних браузерів, а cookie без `Domain` лишається з хостом. `SetCookie` відхиляє `SameSite=None` без `Secure` (`CookieFormatError`), `SessionConfig` — те саме плюс `__Host-`/`__Secure-` без `Secure` і `maxAge` < 1 с (`SessionConfigError` у `onInit`, до старту сервера). `Path` сесійної cookie завжди `/`.
8. **`Sessions.start` також кладе `CurrentUser` у call-скоуп** поточного запиту (обробник після входу бачить користувача). `InMemorySessionStore` видаляє прострочені сесії при кожному `create` і при читанні простроченої.
9. **`Jaspr.initializeApp()` у `onInit` через `JasprSetup.ensureInitialized`**: повторна ініціалізація пропускається; якщо Jaspr уже ініціалізовано з `useIsolates: true`, це `JasprSetupError` (сторінка читає call-скоуп, недосяжний з іншого ізолята).
10. **`context.cookies` Jaspr кидає на зіпсованому заголовку `cookie`** (spec цього не знає). Компоненти читають cookie через `GrundScope.of(context).cookies` (`Params` grund); це в документації і в прикладі.
11. **`HEAD` для сторінок**: router grund обслуговує `HEAD` через `GET`; тіло відкидає адаптер, тож в in-process `TestClient` тіло `HEAD` присутнє — тест перевіряє лише статус і заголовки. Скрипт live reload вставляється і для `HEAD` (той самий рендер).
12. **Приклад**: `TasksModule`/`ExplicitTasksModule` експортують `TasksService` (сторінки його читають); `WebModule` написаний явним API в обох графах (`JasprModule(app:)` бере функцію, якої анотація не втримає); вхід — лише ім'я (облікові дані поза зрізом, spec 4.4). Наявний e2e-тест `GET /nowhere → 404 route_not_found` став `DELETE /nowhere → 405`: тепер `GET /*` — сторінки (їхній 404 — сторінка сайту).
13. **Шаблон fullstack**: `Secure` cookie вмикається лише в product-збірці (`bool.fromEnvironment('dart.vm.product')`), бо `grund dev`/`dart run` віддають plain `http` (spec 4.2: «шаблон `init` вимикає у dev»). Шаблон називає `grund_http: ^0.1.1` (`c.form()` і злиття `set-cookie`).
14. **Перевірка шаблону без `pub get`** (spec §6: «`pub get` у робочому просторі»): тести `grund_cli` не ходять у мережу, тож інтеграційний тест розв'язує новий пакет через `WorkspacePackageConfig` і запускає `test/app_test.dart` самою VM.
15. **Spec §7 застарів щодо версій**: «lockstep» і «0.2.0…» суперечать чинному `docs/RELEASING.md` (незалежні версії, реліз тегом `<package>-vX.Y.Z`). Роадмап переписується на віхи без номерів версій; нові пакети починають з `0.1.0`.
16. **Автооновлення (4.6)**: `ReloadClient.waitUntilServing` чекає реєстрації `ext.grund.reassemble` (до `ReloadTimeouts.serving`, 30 с) — так `dev` знає, що перезапущений процес обслуговує; процес без grund ніколи не «обслуговує», і подія для нього не надсилається.

## Review Focus

Класи входів і відмов, які spec припускає, але функціональні тести легко пропускають. Кожен рядок має тест у задачі-власнику (позначено `(RF…)` у назві тесту або вказано тут).

1. **RF1 · Фіксація сесії.** Токен, відомий до входу (живий у сховищі або вигаданий нападником), ніколи не стає дійсним: вхід видаляє стару сесію і видає новий токен. — `sessions_test.dart`: «signing in replaces the token the request came with (RF1)», «a token the attacker made up is not adopted on sign-in (RF1)» (задача 5).
2. **RF2 · Ін'єкція заголовків через назву, значення чи шлях cookie.** `;`, `,`, пробіл, лапки, CR/LF, керівні символи — `CookieFormatError`, а не додатковий атрибут чи заголовок. — `set_cookie_test.dart`: «a value cannot add a header or a cookie (RF2)», «a path with ; or a line break is refused (RF2)», цикли за назвами/значеннями (задача 3); `session_config_test.dart` (задача 5).
3. **RF3 · Обхід шляху в статиці.** `..`, `%2e%2e`, `%2F`, `%5C`, `.env`, `C:`, порожній сегмент, NUL, символьне посилання назовні — не файл. — `static_files_test.dart` (задача 8), «$target never leaves the static directory» і «a symlink out of the static directory is not served» у `jaspr_pages_test.dart` (задача 9, через справжній router).
4. **RF4 · Кілька `set-cookie` доходять до клієнта на обох адаптерах.** — `http_response_test.dart` (задача 2), `jaspr_response_test.dart` «the status, the body and every set-cookie are kept» (задача 7), `jaspr_pages_test.dart` «cookies and headers a page sets reach the client» (задача 9), `web_e2e_test.dart` «signing in sets the session and the flash cookie (RF4, RF5)» на `dart:io` і shelf (задача 10).
5. **RF5 · Cookie сесії і власна cookie обробника (у поверненому `HttpResponse`) обидві доходять.** — `sessions_test.dart` (задача 5, тест із `flash`), `web_e2e_test.dart` (задача 10).
6. **RF6 · Скрипт live reload — лише в HTML-сторінках у dev, адреса екранована.** Не в product, не без змінної, не в XML, не в статичному `.html`; `</script>` в адресі не закриває елемент. — `live_reload_script_test.dart`, `live_reload_pages_test.dart` (задача 12d).
7. **RF7 · Точка SSE не тримає `dev` і закривається з ним.** — `live_reload_hub_test.dart` «close ends every stream and frees the port (RF7)», `dev_live_reload_test.dart` (exit 0, потік закінчився), наявний `integration/dev_test.dart` «a failing run ends the dev process with 70, not a hang» уже з точкою (задача 12c); `integration/dev_jaspr_test.dart` (подія `null` після зупинки, задача 12d).

## Структура файлів

```text
packages/grund_http/lib/src/
  http/http_response.dart       mergeHeaders додає set-cookie                    (2)
  http/status_code.dart         seeOther                                         (2)
  ctx/form_decoder.dart         FormDecoder (новий)                               (2)
  ctx/body_reader.dart          form()                                           (2)
  ctx/http_ctx.dart             form()                                           (2)
  ctx/param_location.dart       form                                             (2)
packages/grund_auth/            (новий пакет)                                    (3–6)
  lib/grund_auth.dart           barrel
  lib/src/auth_error.dart       AuthError, CookieFormatError, SessionConfigError
  lib/src/current_user.dart     CurrentUser
  lib/src/cookie/               SetCookie, CookieAttributes, SameSitePolicy, CookieSyntax
  lib/src/session/              Session, SessionStore, InMemorySessionStore, SessionTokens,
                                SessionConfig, Sessions, SessionModule
  lib/src/hook/                 SessionHook, SameOriginHook
  example/grund_auth_example.dart
packages/grund_jaspr/           (новий пакет)                                    (1, 7–9, 12d)
  lib/grund_jaspr.dart          barrel
  lib/src/jaspr_request.dart    JasprRequest: HttpRequest → shelf Request
  lib/src/jaspr_response.dart   JasprResponse: ResponseLike → HttpResponse
  lib/src/content_types.dart    ContentTypes (таблиця)
  lib/src/static_files.dart     StaticFiles
  lib/src/jaspr_config.dart     JasprConfig
  lib/src/grund_scope.dart      GrundScope (InheritedComponent)
  lib/src/grund_context.dart    extension GrundContext on BuildContext
  lib/src/jaspr_error.dart      JasprError, PageRenderError, JasprSetupError, MissingGrundScopeError
  lib/src/jaspr_setup.dart      JasprSetup.ensureInitialized
  lib/src/page_renderer.dart    PageRenderer
  lib/src/jaspr_pages.dart      JasprPages (HttpApi: GET /, GET /*)
  lib/src/jaspr_module.dart     JasprModule
  lib/src/live_reload_script.dart LiveReloadScript                                (12d)
  example/grund_jaspr_example.dart
packages/grund_cli/lib/src/
  init/project_kind.dart        ProjectKind (api, fullstack)                     (11)
  init/fullstack_template.dart  FullstackTemplate (каталог файлів)               (11)
  init/project_scaffold.dart, init/reserved_names.dart, cli/init_command.dart   (11)
  dev/app_command.dart          AppCommand                                       (12a, 12c)
  dev/live_reload_hub.dart      LiveReloadHub                                    (12c)
  dev/app_process.dart, app_launcher.dart, dev_target.dart, dev_session.dart,
  dev/reload_client.dart, reload_timeouts.dart, cli/dev_command.dart          (12a, 12c)
packages/grund_cli/integration/
  helpers/dev_run.dart, helpers/site_sources.dart, dev_jaspr_test.dart,
  init_fullstack_test.dart                                                       (11, 12b, 12d)
example/lib/src/web/            WebModule, LoginApi, TasksSite, HomePage, LoginPage (10)
example/web/styles.css                                                           (10)
docs/jaspr.md (новий), docs/*.md, README.md, CLAUDE.md, ROADMAP, RELEASING,
.github/workflows/{ci,publish}.yaml                                              (1, 3, 13)
```

## Нумерація задач і комітів

| № | Задача | Коміти |
|---|---|---|
| 1 | Каркас `grund_jaspr` і спайк: контракт Jaspr, workspace, CI | 1 |
| 2 | `grund_http`: злиття `set-cookie`; `c.form()`, `StatusCode.seeOther` | 2 (2a, 2b) |
| 3 | `grund_auth`: каркас і `SetCookie` | 1 |
| 4 | `CurrentUser`, `Session`, `SessionStore`, `InMemorySessionStore` | 1 |
| 5 | `SessionConfig`, `Sessions` з ротацією, токени `Random.secure`, `SessionModule` | 1 |
| 6 | `SessionHook`, `SameOriginHook`, приклад пакета | 1 |
| 7 | `grund_jaspr`: відображення запиту й відповіді | 1 |
| 8 | Статичні файли і `JasprConfig` | 1 |
| 9 | `GrundScope`, розширення `BuildContext`, `JasprPages`, `JasprModule`, ідемпотентна ініціалізація | 1 |
| 10 | `example/`: SSR-сторінки і вхід через сесію на обох адаптерах | 1 |
| 11 | `grund_cli init --template fullstack` | 2 (11a refactor, 11b feat) |
| 12 | Автооновлення сторінок у `dev` | 4 (12a refactor, 12b test, 12c feat cli, 12d feat jaspr) |
| 13 | Документація і супровід: `docs/jaspr.md`, README, CHANGELOG, роадмап, RELEASING, `CLAUDE.md`, publish.yaml | 1 |
| 14 | Фінальна перевірка і реєстр неперевіреного | 0 |

---
### Задача 1: Каркас `grund_jaspr` і спайк — контракт Jaspr, workspace, CI

**Мета:** порожній пакет `grund_jaspr` у workspace і в циклі `publish --dry-run` CI, плюс тест-контракт, що фіксує поведінку Jaspr 0.23.5, на яку спираються задачі 7–9 і 12d: `renderComponent` з вручну створеним `Request` (шлях, query, кілька `set-cookie`, HTML `content-type`) і повторний `Jaspr.initializeApp()`. Спайк уже пройдено (Jaspr 0.23.5, Dart 3.13.5, `grund dev`): правка компонента — звичайний reload (новий маршрут підхоплює reassemble, нове поле — перезапуск процесу); `JasprModule(app:)` викликається на кожен запит і ніде не кешується. Якщо тест-контракт падає на новій версії Jaspr — зупинитися й повідомити: план на неї не розрахований.

**Files:**
- Create: `packages/grund_jaspr/{pubspec.yaml,LICENSE,analysis_options.yaml,CHANGELOG.md,README.md,lib/grund_jaspr.dart}`
- Modify: `pubspec.yaml` (workspace), `.github/workflows/ci.yaml` (цикл dry-run)
- Test: `packages/grund_jaspr/test/jaspr_contract_test.dart`

**Interfaces:**
- Consumes: `package:jaspr/server.dart` (`renderComponent(Component, {Request? request}) → Future<ResponseLike>`, `Request(method, Uri, {handlerPath})`, `Jaspr.initializeApp({useIsolates})`, `Jaspr.isInitialized`, `Jaspr.useIsolates`, `BuildContext.url`, `BuildContext.setCookie`), `package:jaspr/dom.dart` (`p`, `div`, …), `Document`.
- Produces: пакет `grund_jaspr` 0.1.0 (залежності: `grund ^0.1.0`, `grund_http ^0.1.0`, `jaspr '>=0.23.5 <0.24.0'`, `path ^1.9.0`); бібліотека `package:grund_jaspr/grund_jaspr.dart` поки без експортів.

- [ ] **Крок 1: Каркас пакета**

`packages/grund_jaspr/pubspec.yaml` (файл цілком, 20 рядків):

```yaml
name: grund_jaspr
description: >-
  Server-side rendered Jaspr pages in a grund application: one process serves
  the API and the pages, with one dependency injection and one lifecycle.
version: 0.1.0
repository: https://github.com/4akLoon/grund/tree/master/packages/grund_jaspr
issue_tracker: https://github.com/4akLoon/grund/issues
topics: [server, http, framework, jaspr, ssr]
environment:
  sdk: ^3.8.0
resolution: workspace
dependencies:
  grund: ^0.1.0
  grund_http: ^0.1.0
  jaspr: '>=0.23.5 <0.24.0'
  path: ^1.9.0
dev_dependencies:
  grund_io: ^0.1.0
  lints: ^5.1.0
  test: ^1.25.0
```

`LICENSE` і `analysis_options.yaml` — копії (опції опублікованого пакета: кореневі плюс `public_member_api_docs`):

```bash
cp LICENSE packages/grund_jaspr/LICENSE
cp packages/grund_http/analysis_options.yaml packages/grund_jaspr/analysis_options.yaml
```

`packages/grund_jaspr/CHANGELOG.md` (файл цілком, 3 рядків):

```markdown
## 0.1.0

Initial release.
```

`packages/grund_jaspr/README.md` (файл цілком, 5 рядків):

```markdown
# grund_jaspr

Server-side rendered [Jaspr](https://pub.dev/packages/jaspr) pages in a
grund application: one process serves the API and the pages, with one
dependency injection and one lifecycle.
```

(README і CHANGELOG доповнює задача 13.)

`packages/grund_jaspr/lib/grund_jaspr.dart` (файл цілком, 4 рядків):

```dart
/// Server-side rendered Jaspr pages in a grund application: one process
/// serves the API and the pages, with one dependency injection and one
/// lifecycle.
library;
```

- [ ] **Крок 2: Workspace і CI**

`pubspec.yaml` (зміни):

```diff
--- a/pubspec.yaml
+++ b/pubspec.yaml
@@ -16,4 +16,5 @@ workspace:
   - packages/grund_http_generator/test/fixtures/http_cases_app
   - packages/grund_http_generator/test/fixtures/users_app
   - packages/grund_io
+  - packages/grund_jaspr
   - packages/grund_shelf
```

`.github/workflows/ci.yaml` (зміни):

```diff
--- a/.github/workflows/ci.yaml
+++ b/.github/workflows/ci.yaml
@@ -75,7 +75,7 @@ jobs:
       # Every published package (the list of docs/RELEASING.md); any warning fails the job.
       - name: dart pub publish --dry-run
         run: |
-          for package in grund grund_http grund_io grund_shelf \
+          for package in grund grund_http grund_io grund_shelf grund_jaspr \
               grund_generator grund_http_generator grund_cli grund_build; do
             echo "::group::$package"
             (cd "packages/$package" && dart pub publish --dry-run) || exit 1
```

- [ ] **Крок 3: Залежності**

Run: `dart pub get` (з кореня)
Expected: `Got dependencies!`; `grep -A7 '^  jaspr:' pubspec.lock | grep version` — `version: "0.23.5"`.

- [ ] **Крок 4: Тест-контракт Jaspr**

`packages/grund_jaspr/test/jaspr_contract_test.dart` (файл цілком, 51 рядків):

```dart
import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:test/test.dart';

/// Sets two cookies and shows the URL Jaspr saw.
final class _ContractPage extends StatelessComponent {
  const _ContractPage();

  @override
  Component build(BuildContext context) {
    context
      ..setCookie('a', '1')
      ..setCookie('b', '2');
    return Document(body: p([Component.text('url ${context.url}')]));
  }
}

/// The values of [name] in [headers], whatever the spelling of the name.
List<String> _values(Map<String, List<String>> headers, String name) => [
  for (final MapEntry(:key, :value) in headers.entries)
    if (key.toLowerCase() == name) ...value,
];

// What grund_jaspr relies on in Jaspr; a Jaspr upgrade that breaks one of
// these breaks the package.
void main() {
  setUpAll(Jaspr.initializeApp);

  test('a hand-made request renders a document with its URL', () async {
    final rendered = await renderComponent(
      const _ContractPage(),
      request: Request(
        'GET',
        Uri.parse('http://localhost/a/b?x=1'),
        handlerPath: '/',
      ),
    );

    expect(rendered.statusCode, 200);
    expect(String.fromCharCodes(rendered.body), contains('url /a/b?x=1'));
    expect(_values(rendered.headers, 'set-cookie'), hasLength(2));
    expect(_values(rendered.headers, 'content-type').single, contains('html'));
  });

  test('initializing Jaspr again keeps it initialized', () {
    Jaspr.initializeApp();

    expect(Jaspr.isInitialized, isTrue);
    expect(Jaspr.useIsolates, isFalse);
  });
}
```

- [ ] **Крок 5: Запустити**

Run: `cd packages/grund_jaspr && dart test`
Expected: `+2: All tests passed!`. Перший рендер друкує в stdout `[WARNING] ...` про `.client.dart`: це очікувано (клієнтських компонентів немає), не приглушувати; задача 13 описує це в «Things to know».

- [ ] **Крок 6: Перевірки**

Run: `dart analyze` (з кореня) → `No issues found!`; `dart format packages example` → `(0 changed)`.

- [ ] **Крок 7: Коміт**

```bash
git add \
  .github/workflows/ci.yaml \
  packages/grund_jaspr/CHANGELOG.md \
  packages/grund_jaspr/LICENSE \
  packages/grund_jaspr/README.md \
  packages/grund_jaspr/analysis_options.yaml \
  packages/grund_jaspr/lib/grund_jaspr.dart \
  packages/grund_jaspr/pubspec.yaml \
  packages/grund_jaspr/test/jaspr_contract_test.dart \
  pubspec.yaml
git commit -m "build(jaspr): add grund_jaspr with the Jaspr contract it relies on" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git show --stat --format=%s HEAD   # 9 файлів, лише ці
```

---

### Задача 2: `grund_http` — злиття `set-cookie`; `c.form()` і `StatusCode.seeOther`

**Мета:** дві зміни `grund_http`, без яких сесії не працюють, кожна окремим комітом. (2a, RF4/RF5) `HttpResponse.mergeHeaders` додає **кожен** `set-cookie` з `c.response.headers` перед власними `set-cookie` відповіді, а не відкидає їх, коли відповідь має свій: cookie сесії, поставлена хуком чи `Sessions.start`, і cookie поверненої `HttpResponse` обидві доходять до клієнта. Для інших назв власні значення відповіді, як і раніше, виграють. (2b) `await c.form()` читає тіло `application/x-www-form-urlencoded` у `Params` (ті самі читачі, що `c.query`; проблема вказує на `/body/<name>`), `FormDecoder` — декодер, `ParamLocation.form` — нове місце параметра, `StatusCode.seeOther` — 303 після `POST` форми.

**Files:**
- Modify: `packages/grund_http/lib/src/http/http_response.dart`, `packages/grund_http/CHANGELOG.md` (2a); `packages/grund_http/lib/src/{http/status_code.dart,ctx/param_location.dart,ctx/body_reader.dart,ctx/http_ctx.dart}`, `packages/grund_http/CHANGELOG.md` (2b)
- Create: `packages/grund_http/lib/src/ctx/form_decoder.dart` (2b)
- Test: `packages/grund_http/test/http/http_response_test.dart` (2a), `packages/grund_http/test/ctx/{form_decoder_test.dart,http_ctx_test.dart}` (2b)

**Interfaces:**
- Consumes: наявні `HttpResponse`, `HeaderMap` (`names`, `all`, `add`, `remove`, `HeaderMap.copy`), `BodyReader`, `Params(ParamLocation, List<String> Function(String))`, `ParamLocation(label, pointerSegment)`.
- Produces:

```dart
// http/http_response.dart (поведінка змінилася, сигнатура та сама)
HttpResponse mergeHeaders(HeaderMap extra); // set-cookie: extra, потім власні
// http/status_code.dart
static const seeOther = 303;
// ctx/param_location.dart
enum ParamLocation { path, query, header, cookie, form /* ('form field', 'body') */ }
// ctx/form_decoder.dart
abstract final class FormDecoder {
  static Map<String, List<String>> decode(String text); // FormatException на поганому %
}
// ctx/body_reader.dart
Future<Map<String, List<String>>> form(); // 400 body_invalid, 413 понад ліміт
// ctx/http_ctx.dart
Future<Params> form();
```

> Додане значення `ParamLocation.form` ламає лише вичерпний `switch` користувача по `ParamLocation`; у репозиторії такого `switch` немає (`grund_http_generator` зіставляє лише `ParamLocation.path`; його тести — у кроці 9). CHANGELOG каже про це прямо; версія `grund_http` — рішення релізу (див. «Рішення плану», п. 4).

#### 2a. Злиття `set-cookie`

- [ ] **Крок 1: Падаючий тест**

`packages/grund_http/test/http/http_response_test.dart` (зміни):

```diff
--- a/packages/grund_http/test/http/http_response_test.dart
+++ b/packages/grund_http/test/http/http_response_test.dart
@@ -86,6 +86,24 @@ void main() {
       expect(response.headers['x-trace'], '7');
     });
 
+    test('adds every set-cookie of extra before the response\'s own', () {
+      final own = HttpResponse(
+        303,
+        headers: HeaderMap()..add('set-cookie', 'flash=1'),
+      );
+      final extra = HeaderMap()
+        ..add('set-cookie', 'sid=a')
+        ..add('set-cookie', 'theme=b');
+
+      final response = own.mergeHeaders(extra);
+
+      expect(response.headers.all('set-cookie'), [
+        'sid=a',
+        'theme=b',
+        'flash=1',
+      ]);
+    });
+
     test('returns the same response when nothing is missing', () {
       final response = HttpResponse.text('x');
 
```

- [ ] **Крок 2: Переконатися, що падає**

Run: `cd packages/grund_http && dart test test/http/http_response_test.dart`
Expected: FAIL у `adds every set-cookie of extra before the response's own` — у відповіді лише її власна `set-cookie`.

- [ ] **Крок 3: Реалізація**

`packages/grund_http/lib/src/http/http_response.dart` (зміни):

```diff
--- a/packages/grund_http/lib/src/http/http_response.dart
+++ b/packages/grund_http/lib/src/http/http_response.dart
@@ -80,23 +80,30 @@ final class HttpResponse {
   /// The body.
   final ResponseBody body;
 
-  /// A copy that also carries every header of [extra] whose name this
-  /// response does not set; the response's own values win.
+  /// A copy that also carries the headers of [extra]: a name this response
+  /// does not set is added with all its values, and every `set-cookie` of
+  /// [extra] is added before the response's own, so both reach the client
+  /// and the response's own cookie wins where both set the same one. For
+  /// any other name the response's own values win.
   HttpResponse mergeHeaders(HeaderMap extra) {
-    final missing = [
+    final added = [
       for (final name in extra.names)
-        if (!headers.contains(name)) name,
+        if (!headers.contains(name) || name == _setCookie) name,
     ];
-    if (missing.isEmpty) return this;
+    if (added.isEmpty) return this;
     final merged = HeaderMap.copy(headers);
-    for (final name in missing) {
-      for (final value in extra.all(name)) {
+    for (final name in added) {
+      final own = merged.all(name);
+      merged.remove(name);
+      for (final value in [...extra.all(name), ...own]) {
         merged.add(name, value);
       }
     }
     return HttpResponse(status, headers: merged, body: body);
   }
 
+  static const _setCookie = 'set-cookie';
+
   static HttpResponse _typed(
     int status,
     HeaderMap? headers,
```

`packages/grund_http/CHANGELOG.md` (зміни):

```diff
--- a/packages/grund_http/CHANGELOG.md
+++ b/packages/grund_http/CHANGELOG.md
@@ -1,3 +1,10 @@
+## 0.1.1
+
+- `HttpResponse.mergeHeaders` adds every `set-cookie` of the merged headers
+  before the response's own instead of dropping them when the response has
+  one: a cookie a hook or `Sessions.start` set on `c.response` and the
+  cookie of a returned `HttpResponse` both reach the client.
+
 ## 0.1.0
 
 Initial release.
```

- [ ] **Крок 4: Тести**

Run: `cd packages/grund_http && dart test` → `+241: All tests passed!`; `cd example && dart test` → `+58: All tests passed!` (поведінка решти заголовків не змінилася).

- [ ] **Крок 5: Перевірки і коміт**

Run: `dart analyze` → `No issues found!`; `dart format packages example` → `(0 changed)`.

```bash
git add \
  packages/grund_http/CHANGELOG.md \
  packages/grund_http/lib/src/http/http_response.dart \
  packages/grund_http/test/http/http_response_test.dart
git commit -m "fix(http): keep every set-cookie when merging headers" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git show --stat --format=%s HEAD   # 3 файлів, лише ці
```

#### 2b. `c.form()` і `StatusCode.seeOther`

- [ ] **Крок 6: Падаючі тести**

`packages/grund_http/test/ctx/form_decoder_test.dart` (файл цілком, 36 рядків):

```dart
import 'package:grund_http/src/ctx/form_decoder.dart';
import 'package:test/test.dart';

void main() {
  test('decodes names and values, + as a space and UTF-8 escapes', () {
    expect(FormDecoder.decode('name=ann+lee&city=K%C3%B6ln'), {
      'name': ['ann lee'],
      'city': ['Köln'],
    });
  });

  test('keeps repeated names in order', () {
    expect(FormDecoder.decode('tag=a&tag=b'), {
      'tag': ['a', 'b'],
    });
  });

  test('a field without = has an empty value; empty fields are skipped', () {
    expect(FormDecoder.decode('flag&&x='), {
      'flag': [''],
      'x': [''],
    });
  });

  test('splits a field at the first =', () {
    expect(FormDecoder.decode('q=a=b'), {
      'q': ['a=b'],
    });
  });

  for (final text in ['a=%zz', 'a=%', 'a=%4', '%C3=x', 'a=%C3']) {
    test('"$text" is a FormatException', () {
      expect(() => FormDecoder.decode(text), throwsFormatException);
    });
  }
}
```

`packages/grund_http/test/ctx/http_ctx_test.dart` (зміни):

```diff
--- a/packages/grund_http/test/ctx/http_ctx_test.dart
+++ b/packages/grund_http/test/ctx/http_ctx_test.dart
@@ -270,4 +270,55 @@ void main() {
       expect((await c.body(NewUser.fromJson)).name, 'ann');
     });
   });
+
+  group('HttpCtx form', () {
+    test(
+      'reads the fields of a form body with the parameter readers',
+      () async {
+        final c = contexts(requestFor('POST', '/', body: 'name=ann&age=7'));
+
+        final form = await c.form();
+
+        expect(form.string('name'), 'ann');
+        expect(form.integer('age'), 7);
+      },
+    );
+
+    test('a missing field points at /body/<name>', () async {
+      final c = contexts(requestFor('POST', '/', body: 'name=ann'));
+      final form = await c.form();
+
+      expect(
+        () => form.string('password'),
+        throwsA(problem('parameter_missing', '/body/password')),
+      );
+    });
+
+    test('a bad escape is a 400 body_invalid', () async {
+      final c = contexts(requestFor('POST', '/', body: 'name=%zz'));
+
+      await expectLater(c.form(), throwsA(problem('body_invalid', '/body')));
+    });
+
+    test('a body that is not UTF-8 is a 400 body_invalid', () async {
+      final c = contexts(
+        HttpRequest(
+          method: 'POST',
+          uri: Uri.parse('/'),
+          body: RequestBody.bytes([0x6e, 0x3d, 0xff]),
+        ),
+      );
+
+      await expectLater(c.form(), throwsA(problem('body_invalid', '/body')));
+    });
+
+    test('a form over the limit is a 413', () async {
+      final c = contexts(
+        requestFor('POST', '/', body: 'name=${'x' * 20}'),
+        maxBodyBytes: 10,
+      );
+
+      await expectLater(c.form(), throwsA(isA<PayloadTooLargeException>()));
+    });
+  });
 }
```

- [ ] **Крок 7: Переконатися, що падають**

Run: `cd packages/grund_http && dart test test/ctx`
Expected: FAIL — помилка компіляції: `form_decoder.dart` не існує, `HttpCtx` не має методу `form`.

- [ ] **Крок 8: Реалізація**

`packages/grund_http/lib/src/ctx/form_decoder.dart` (файл цілком, 31 рядків):

```dart
/// Decodes an `application/x-www-form-urlencoded` body (what a browser
/// sends for a `<form method="post">`).
///
/// Fields are separated by `&`, a name from its value by the first `=`; `+`
/// is a space and `%XX` a byte of UTF-8. A field without `=` has the value
/// `''`; empty fields (`a=1&&b=2`) are skipped.
abstract final class FormDecoder {
  static final _badEscape = RegExp('%(?![0-9A-Fa-f]{2})');

  /// The values of every field of [text], by name, in order; throws a
  /// [FormatException] for a `%` that is not followed by two hex digits or
  /// escapes that are not UTF-8.
  static Map<String, List<String>> decode(String text) {
    final fields = <String, List<String>>{};
    for (final field in text.split('&')) {
      if (field.isEmpty) continue;
      final split = field.indexOf('=');
      final name = _component(split < 0 ? field : field.substring(0, split));
      final value = split < 0 ? '' : _component(field.substring(split + 1));
      (fields[name] ??= []).add(value);
    }
    return fields;
  }

  static String _component(String raw) {
    if (_badEscape.hasMatch(raw)) {
      throw const FormatException('A "%" is not followed by two hex digits.');
    }
    return Uri.decodeQueryComponent(raw);
  }
}
```

`packages/grund_http/lib/src/ctx/body_reader.dart` (зміни):

```diff
--- a/packages/grund_http/lib/src/ctx/body_reader.dart
+++ b/packages/grund_http/lib/src/ctx/body_reader.dart
@@ -1,9 +1,11 @@
+import 'dart:convert';
 import 'dart:typed_data';
 
 import '../http/http_exception.dart';
 import '../http/http_request.dart';
 import '../http/problem_code.dart';
 import '../http/request_body.dart';
+import 'form_decoder.dart';
 
 /// Reads the body of one request once, within a size limit, and decodes it.
 final class BodyReader {
@@ -15,6 +17,7 @@ final class BodyReader {
   final int? _maxBytes;
   Future<Uint8List>? _bytes;
   Future<Object?>? _json;
+  Future<Map<String, List<String>>>? _form;
 
   /// The raw body; throws [PayloadTooLargeException] (413) as soon as the
   /// declared or the received size exceeds the limit.
@@ -52,6 +55,11 @@ final class BodyReader {
     ];
   }
 
+  /// The body decoded as form fields; a body that is not UTF-8 or has a
+  /// bad escape is a 400 `body_invalid`.
+  Future<Map<String, List<String>>> form() =>
+      _form ??= bytes().then(_decodeForm);
+
   Future<Object?> _decoded() =>
       _json ??= bytes().then((data) => RequestBody.bytes(data).json());
 
@@ -79,6 +87,14 @@ final class BodyReader {
     }
   }
 
+  static Map<String, List<String>> _decodeForm(Uint8List data) {
+    try {
+      return FormDecoder.decode(utf8.decode(data));
+    } on FormatException catch (error) {
+      throw _invalid('Invalid form body: ${error.message}');
+    }
+  }
+
   Future<Uint8List> _read() async {
     final limit = _maxBytes;
     if (limit == null) return _request.body.bytes();
```

`BodyReader._decodeForm` ловить `FormatException` (поганий `%` чи не-UTF-8) і перетворює на 400 `body_invalid` — нова виняткова межа, задача 13 запише її в `CLAUDE.md`.

`packages/grund_http/lib/src/ctx/http_ctx.dart` (зміни):

```diff
--- a/packages/grund_http/lib/src/ctx/http_ctx.dart
+++ b/packages/grund_http/lib/src/ctx/http_ctx.dart
@@ -76,6 +76,17 @@ final class HttpCtx extends CallContext {
     T Function(Map<String, Object?> json) fromJson,
   ) => _body.list(fromJson);
 
+  /// The fields of an `application/x-www-form-urlencoded` body, read with
+  /// the same readers as [query] (a problem points at `/body/<name>`).
+  ///
+  /// A body that is not UTF-8 or has a bad `%` escape is a 400 with the
+  /// code `body_invalid`; a body over the limit is a 413. The content type
+  /// is not checked, as for [body].
+  Future<Params> form() async {
+    final fields = await _body.form();
+    return Params(ParamLocation.form, (name) => fields[name] ?? const []);
+  }
+
   /// The raw body; a body over the limit is a 413.
   Future<Uint8List> bytes() => _body.bytes();
 
```

`packages/grund_http/lib/src/ctx/param_location.dart` (зміни):

```diff
--- a/packages/grund_http/lib/src/ctx/param_location.dart
+++ b/packages/grund_http/lib/src/ctx/param_location.dart
@@ -10,7 +10,10 @@ enum ParamLocation {
   header('header', 'header'),
 
   /// A cookie of the `Cookie` header.
-  cookie('cookie', 'cookie');
+  cookie('cookie', 'cookie'),
+
+  /// A field of an `application/x-www-form-urlencoded` body.
+  form('form field', 'body');
 
   const ParamLocation(this.label, this.pointerSegment);
 
```

`packages/grund_http/lib/src/http/status_code.dart` (зміни):

```diff
--- a/packages/grund_http/lib/src/http/status_code.dart
+++ b/packages/grund_http/lib/src/http/status_code.dart
@@ -13,6 +13,9 @@ abstract final class StatusCode {
   /// 302 Found.
   static const found = 302;
 
+  /// 303 See Other: the redirect after a form `POST`, followed with `GET`.
+  static const seeOther = 303;
+
   /// 400 Bad Request.
   static const badRequest = 400;
 
```

`packages/grund_http/CHANGELOG.md` (зміни):

```diff
--- a/packages/grund_http/CHANGELOG.md
+++ b/packages/grund_http/CHANGELOG.md
@@ -4,6 +4,12 @@
   before the response's own instead of dropping them when the response has
   one: a cookie a hook or `Sessions.start` set on `c.response` and the
   cookie of a returned `HttpResponse` both reach the client.
+- `await c.form()` reads an `application/x-www-form-urlencoded` body into
+  `Params` (`ParamLocation.form`, pointer `/body/<name>`); a bad escape or
+  UTF-8 sequence is a 400 `body_invalid`, a body over the limit a 413.
+  `ParamLocation` gained the value `form`: an exhaustive `switch` over it
+  needs a case for it.
+- `StatusCode.seeOther` (303), the redirect after a form `POST`.
 
 ## 0.1.0
 
```

- [ ] **Крок 9: Тести**

Run: `cd packages/grund_http && dart test test/ctx/form_decoder_test.dart` → `+9: All tests passed!`; `dart test test/ctx/http_ctx_test.dart` → `+25: All tests passed!`; увесь пакет `dart test` → `+255: All tests passed!`.
Run: `cd packages/grund_http_generator && dart test` → `+100: All tests passed!` (генератор не має вичерпного `switch` по `ParamLocation`); `cd example && dart test` → `+58: All tests passed!`.

- [ ] **Крок 10: Перевірки і коміт**

Run: `dart analyze` → `No issues found!`; `dart format packages example` → `(0 changed)`; `wc -l packages/grund_http/lib/src/ctx/{body_reader,http_ctx}.dart` — обидва < 300.

```bash
git add \
  packages/grund_http/CHANGELOG.md \
  packages/grund_http/lib/src/ctx/body_reader.dart \
  packages/grund_http/lib/src/ctx/form_decoder.dart \
  packages/grund_http/lib/src/ctx/http_ctx.dart \
  packages/grund_http/lib/src/ctx/param_location.dart \
  packages/grund_http/lib/src/http/status_code.dart \
  packages/grund_http/test/ctx/form_decoder_test.dart \
  packages/grund_http/test/ctx/http_ctx_test.dart
git commit -m "feat(http): read form bodies with c.form(), add StatusCode.seeOther" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git show --stat --format=%s HEAD   # 8 файлів, лише ці
```

---
### Задача 3: `grund_auth` — каркас пакета і `SetCookie`

**Мета:** новий пакет `grund_auth` у workspace і CI та перевірений запис `set-cookie`: `SetCookie(name, value, attributes:)` відмовляє (`CookieFormatError`) назві, що не є токеном RFC 6265, значенню з пробілом, лапкою, комою, `;`, `\` чи керівним символом, шляху з `;` чи керівним символом, від'ємному `maxAge` і `SameSite=None` без `Secure` (RF2). Атрибути пишуться у фіксованому порядку: `Max-Age`, `Path`, `Secure`, `HttpOnly`, `SameSite`. `Expires` і `Domain` свідомо немає («Рішення плану», п. 7).

**Files:**
- Create: `packages/grund_auth/{pubspec.yaml,LICENSE,analysis_options.yaml,CHANGELOG.md,README.md,lib/grund_auth.dart}`, `packages/grund_auth/lib/src/auth_error.dart`, `packages/grund_auth/lib/src/cookie/{same_site_policy,cookie_attributes,cookie_syntax,set_cookie}.dart`
- Modify: `pubspec.yaml` (workspace), `.github/workflows/ci.yaml` (цикл dry-run)
- Test: `packages/grund_auth/test/set_cookie_test.dart`

**Interfaces:**
- Consumes: `GrundError` (`package:grund/grund.dart`).
- Produces:

```dart
sealed class AuthError extends GrundError { const AuthError(this.reason); final String reason; }
final class CookieFormatError extends AuthError { const CookieFormatError(super.reason); } // 'Invalid cookie: $reason'
enum SameSitePolicy { lax('Lax'), strict('Strict'), none('None'); final String attribute; }
final class CookieAttributes {
  const CookieAttributes({Duration? maxAge, String path = '/', bool secure = true,
      bool httpOnly = true, SameSitePolicy sameSite = SameSitePolicy.lax});
}
abstract final class CookieSyntax { // поза barrel
  static bool isName(String name); static bool isValue(String value); static bool isAttributeValue(String value);
}
final class SetCookie {
  SetCookie(String name, String value, {CookieAttributes attributes = const CookieAttributes()});
  final String name; final String value; final CookieAttributes attributes;
  String toHeader(); // 'sid=abc; Max-Age=604800; Path=/; Secure; HttpOnly; SameSite=Lax'
}
```

- [ ] **Крок 1: Каркас пакета**

`packages/grund_auth/pubspec.yaml` (файл цілком, 18 рядків):

```yaml
name: grund_auth
description: >-
  Cookie sessions for grund: an opaque token in an HttpOnly cookie, a hook
  that puts the CurrentUser in the call scope, and a same-origin check.
version: 0.1.0
repository: https://github.com/4akLoon/grund/tree/master/packages/grund_auth
issue_tracker: https://github.com/4akLoon/grund/issues
topics: [server, http, framework, authentication]
environment:
  sdk: ^3.8.0
resolution: workspace
dependencies:
  grund: ^0.1.0
  grund_http: ^0.1.0
dev_dependencies:
  grund_io: ^0.1.0
  lints: ^5.1.0
  test: ^1.25.0
```

```bash
cp LICENSE packages/grund_auth/LICENSE
cp packages/grund_http/analysis_options.yaml packages/grund_auth/analysis_options.yaml
```

`packages/grund_auth/CHANGELOG.md` (файл цілком, 3 рядків):

```markdown
## 0.1.0

Initial release.
```

`packages/grund_auth/README.md` (файл цілком, 5 рядків):

```markdown
# grund_auth

Cookie sessions for grund applications: an opaque session token in an
`HttpOnly` cookie, a global hook that puts the `CurrentUser` of a request in
its call scope, and a same-origin check for unsafe requests.
```

(README і CHANGELOG доповнює задача 13.)

`pubspec.yaml` (зміни):

```diff
--- a/pubspec.yaml
+++ b/pubspec.yaml
@@ -5,6 +5,7 @@ environment:
 workspace:
   - example
   - packages/grund
+  - packages/grund_auth
   - packages/grund_build
   - packages/grund_cli
   - packages/grund_conformance
```

`.github/workflows/ci.yaml` (зміни):

```diff
--- a/.github/workflows/ci.yaml
+++ b/.github/workflows/ci.yaml
@@ -75,8 +75,9 @@ jobs:
       # Every published package (the list of docs/RELEASING.md); any warning fails the job.
       - name: dart pub publish --dry-run
         run: |
-          for package in grund grund_http grund_io grund_shelf grund_jaspr \
-              grund_generator grund_http_generator grund_cli grund_build; do
+          for package in grund grund_http grund_io grund_shelf grund_auth \
+              grund_jaspr grund_generator grund_http_generator grund_cli \
+              grund_build; do
             echo "::group::$package"
             (cd "packages/$package" && dart pub publish --dry-run) || exit 1
             echo "::endgroup::"
```

Run: `dart pub get` → `Got dependencies!`.

- [ ] **Крок 2: Падаючий тест**

`packages/grund_auth/test/set_cookie_test.dart` (файл цілком, 95 рядків):

```dart
import 'package:grund_auth/grund_auth.dart';
import 'package:test/test.dart';

void main() {
  test('writes the attributes in a fixed order', () {
    final cookie = SetCookie(
      'sid',
      'abc',
      attributes: const CookieAttributes(maxAge: Duration(days: 7)),
    );

    expect(
      cookie.toHeader(),
      'sid=abc; Max-Age=604800; Path=/; Secure; HttpOnly; SameSite=Lax',
    );
  });

  test('leaves out Max-Age, Secure and HttpOnly when they are off', () {
    final cookie = SetCookie(
      'theme',
      'dark',
      attributes: const CookieAttributes(
        path: '/app',
        secure: false,
        httpOnly: false,
        sameSite: SameSitePolicy.strict,
      ),
    );

    expect(cookie.toHeader(), 'theme=dark; Path=/app; SameSite=Strict');
  });

  test('an empty value with Max-Age=0 deletes a cookie', () {
    final cookie = SetCookie(
      'sid',
      '',
      attributes: const CookieAttributes(maxAge: Duration.zero),
    );

    expect(cookie.toHeader(), startsWith('sid=; Max-Age=0; '));
  });

  for (final name in ['', 'a b', 'a;b', 'a=b', 'a,b', 'a\r\nb', 'ä', '"a"']) {
    test('the name ${Uri.encodeFull(name)} is refused', () {
      expect(() => SetCookie(name, 'v'), throwsA(isA<CookieFormatError>()));
    });
  }

  for (final value in [' ', '"', ',', ';', r'\', '\t', '\x7f', 'ä']) {
    test('the value ${Uri.encodeFull(value)} is refused', () {
      expect(() => SetCookie('n', value), throwsA(isA<CookieFormatError>()));
    });
  }

  test('a value cannot add a header or a cookie (RF2)', () {
    expect(
      () => SetCookie('sid', 'x\r\nSet-Cookie: admin=1'),
      throwsA(isA<CookieFormatError>()),
    );
  });

  test('a path with ; or a line break is refused (RF2)', () {
    for (final path in ['/; Domain=evil.test', '/\r\nx: y']) {
      expect(
        () => SetCookie('n', 'v', attributes: CookieAttributes(path: path)),
        throwsA(isA<CookieFormatError>()),
      );
    }
  });

  test('a negative maxAge is refused', () {
    expect(
      () => SetCookie(
        'n',
        'v',
        attributes: const CookieAttributes(maxAge: Duration(seconds: -1)),
      ),
      throwsA(isA<CookieFormatError>()),
    );
  });

  test('SameSite=None without Secure is refused', () {
    expect(
      () => SetCookie(
        'n',
        'v',
        attributes: const CookieAttributes(
          secure: false,
          sameSite: SameSitePolicy.none,
        ),
      ),
      throwsA(isA<CookieFormatError>()),
    );
  });
}
```

Run: `cd packages/grund_auth && dart test`
Expected: FAIL — помилка компіляції: `package:grund_auth/grund_auth.dart` не знайдено.

- [ ] **Крок 3: Реалізація**

`packages/grund_auth/lib/grund_auth.dart` (файл цілком, 9 рядків):

```dart
/// Cookie sessions for grund applications: `SessionModule`, `Sessions`
/// (start and end a session), `SessionHook` (the `CurrentUser` of a
/// request), `SameOriginHook` and `SetCookie`.
library;

export 'src/auth_error.dart';
export 'src/cookie/cookie_attributes.dart';
export 'src/cookie/same_site_policy.dart';
export 'src/cookie/set_cookie.dart';
```

`packages/grund_auth/lib/src/auth_error.dart` (файл цілком, 20 рядків):

```dart
import 'package:grund/grund.dart';

/// A failure of `grund_auth`: a cookie that cannot be written.
sealed class AuthError extends GrundError {
  /// Creates the error.
  const AuthError(this.reason);

  /// What is wrong and what to do.
  final String reason;
}

/// A `SetCookie` with a name, value or path that would break the
/// `set-cookie` header (RFC 6265), or with attributes a browser drops.
final class CookieFormatError extends AuthError {
  /// Creates the error; [reason] says what is wrong.
  const CookieFormatError(super.reason);

  @override
  String get message => 'Invalid cookie: $reason';
}
```

`packages/grund_auth/lib/src/cookie/same_site_policy.dart` (файл цілком, 18 рядків):

```dart
/// The `SameSite` attribute of a cookie: when a browser sends it with a
/// request that another site started.
enum SameSitePolicy {
  /// Sent with top-level navigations from other sites, not with their
  /// subrequests or form posts.
  lax('Lax'),

  /// Never sent with a request another site started.
  strict('Strict'),

  /// Always sent; browsers require `Secure` with it.
  none('None');

  const SameSitePolicy(this.attribute);

  /// The value written after `SameSite=`.
  final String attribute;
}
```

`packages/grund_auth/lib/src/cookie/cookie_attributes.dart` (файл цілком, 32 рядків):

```dart
import 'same_site_policy.dart';

/// The attributes of a `SetCookie`; the defaults suit a session cookie.
///
/// There is no `Domain` (the cookie stays with the host that set it) and
/// no `Expires` (`Max-Age` says the same to every current browser).
final class CookieAttributes {
  /// Creates the attributes.
  const CookieAttributes({
    this.maxAge,
    this.path = '/',
    this.secure = true,
    this.httpOnly = true,
    this.sameSite = SameSitePolicy.lax,
  });

  /// How long the browser keeps the cookie, in whole seconds; `null` keeps
  /// it until the browser closes, [Duration.zero] deletes it.
  final Duration? maxAge;

  /// The path prefix the browser sends the cookie for.
  final String path;

  /// Whether the browser sends the cookie over HTTPS only.
  final bool secure;

  /// Whether scripts of the page cannot read the cookie.
  final bool httpOnly;

  /// When the browser sends the cookie with a request another site started.
  final SameSitePolicy sameSite;
}
```

`packages/grund_auth/lib/src/cookie/cookie_syntax.dart` (файл цілком, 20 рядків):

```dart
/// The characters RFC 6265 allows in a cookie name, value and attribute.
abstract final class CookieSyntax {
  static final _token = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");
  static final _value = RegExp(
    r'^[\x21\x23-\x2B\x2D-\x3A\x3C-\x5B\x5D-\x7E]*$',
  );
  static final _attribute = RegExp(r'^[\x20-\x3A\x3C-\x7E]*$');

  /// Whether [name] is a token: not empty, no separators, no spaces, no
  /// control characters.
  static bool isName(String name) => _token.hasMatch(name);

  /// Whether [value] has only cookie octets: no spaces, quotes, commas,
  /// semicolons, backslashes or control characters (empty is allowed).
  static bool isValue(String value) => _value.hasMatch(value);

  /// Whether [value] can follow an attribute name: no `;` and no control
  /// characters.
  static bool isAttributeValue(String value) => _attribute.hasMatch(value);
}
```

`packages/grund_auth/lib/src/cookie/set_cookie.dart` (файл цілком, 72 рядків):

````dart
import 'dart:convert';

import '../auth_error.dart';
import 'cookie_attributes.dart';
import 'cookie_syntax.dart';
import 'same_site_policy.dart';

/// One `set-cookie` header value, checked when it is created.
///
/// ```dart
/// c.response.headers.add('set-cookie', SetCookie('theme', 'dark').toHeader());
/// ```
///
/// The attributes are written in a fixed order: `Max-Age`, `Path`,
/// `Secure`, `HttpOnly`, `SameSite`.
final class SetCookie {
  /// The cookie [name] with [value]; throws [CookieFormatError] for a name
  /// that is not a token, a value with characters outside the cookie
  /// octets, a path with `;` or control characters, a negative `maxAge`, or
  /// `SameSite=None` without `Secure`.
  SetCookie(
    this.name,
    this.value, {
    this.attributes = const CookieAttributes(),
  }) {
    if (!CookieSyntax.isName(name)) {
      throw CookieFormatError('the name ${jsonEncode(name)} is not a token.');
    }
    if (!CookieSyntax.isValue(value)) {
      throw CookieFormatError(
        'the value of $name has a character a cookie cannot carry.',
      );
    }
    _checkAttributes();
  }

  /// The cookie name.
  final String name;

  /// The cookie value.
  final String value;

  /// `Max-Age`, `Path`, `Secure`, `HttpOnly` and `SameSite`.
  final CookieAttributes attributes;

  /// The header value: `name=value; Max-Age=...; Path=/; ...`.
  String toHeader() => [
    '$name=$value',
    if (attributes.maxAge case final maxAge?) 'Max-Age=${maxAge.inSeconds}',
    'Path=${attributes.path}',
    if (attributes.secure) 'Secure',
    if (attributes.httpOnly) 'HttpOnly',
    'SameSite=${attributes.sameSite.attribute}',
  ].join('; ');

  void _checkAttributes() {
    if (!CookieSyntax.isAttributeValue(attributes.path)) {
      throw CookieFormatError(
        'the path of $name has ";" or a control '
        'character.',
      );
    }
    if (attributes.maxAge case final maxAge? when maxAge.isNegative) {
      throw CookieFormatError('the maxAge of $name is negative.');
    }
    if (attributes.sameSite == SameSitePolicy.none && !attributes.secure) {
      throw CookieFormatError(
        '$name has SameSite=None without Secure; browsers drop it.',
      );
    }
  }
}
````

- [ ] **Крок 4: Тести**

Run: `cd packages/grund_auth && dart test` → `+23: All tests passed!` (серед них «a value cannot add a header or a cookie (RF2)» і «a path with ; or a line break is refused (RF2)»).

- [ ] **Крок 5: Перевірки і коміт**

Run: `dart analyze` → `No issues found!`; `dart format packages example` → `(0 changed)`.

```bash
git add \
  .github/workflows/ci.yaml \
  packages/grund_auth/CHANGELOG.md \
  packages/grund_auth/LICENSE \
  packages/grund_auth/README.md \
  packages/grund_auth/analysis_options.yaml \
  packages/grund_auth/lib/grund_auth.dart \
  packages/grund_auth/lib/src/auth_error.dart \
  packages/grund_auth/lib/src/cookie/cookie_attributes.dart \
  packages/grund_auth/lib/src/cookie/cookie_syntax.dart \
  packages/grund_auth/lib/src/cookie/same_site_policy.dart \
  packages/grund_auth/lib/src/cookie/set_cookie.dart \
  packages/grund_auth/pubspec.yaml \
  packages/grund_auth/test/set_cookie_test.dart \
  pubspec.yaml
git commit -m "feat(auth): add grund_auth with a checked SetCookie" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git show --stat --format=%s HEAD   # 14 файлів, лише ці
```

---

### Задача 4: `CurrentUser`, `Session`, `SessionStore`, `InMemorySessionStore`

**Мета:** значення й сховище сесій. `CurrentUser(id, claims:)` — те, що бачать обробники й сторінки. `Session` — запис сховища (непрозорий `id`-токен, `userId`, `createdAt`, `expiresAt`, `isLiveAt`). `SessionStore` — інтерфейс (`create`, `read`, `delete`) для довговічних сховищ користувача. `InMemorySessionStore` за замовчуванням: прострочена сесія читається як `null` і видаляється, а кожен `create` прибирає всі прострочені (пам'ять не росте від покинутих сесій).

**Files:**
- Create: `packages/grund_auth/lib/src/current_user.dart`, `packages/grund_auth/lib/src/session/{session,session_store,in_memory_session_store}.dart`
- Modify: `packages/grund_auth/lib/grund_auth.dart`
- Test: `packages/grund_auth/test/in_memory_session_store_test.dart`

**Interfaces:**
- Consumes: нічого з попередніх задач.
- Produces:

```dart
final class CurrentUser { const CurrentUser(this.id, {this.claims = const {}}); final String id; final Map<String, Object?> claims; }
final class Session {
  const Session({required String id, required String userId, required DateTime createdAt, required DateTime expiresAt});
  bool isLiveAt(DateTime time); // time < expiresAt
}
abstract interface class SessionStore {
  Future<void> create(Session session); Future<Session?> read(String id); Future<void> delete(String id);
}
final class InMemorySessionStore implements SessionStore { InMemorySessionStore({DateTime Function() now = DateTime.now}); }
```

- [ ] **Крок 1: Падаючий тест**

`packages/grund_auth/test/in_memory_session_store_test.dart` (файл цілком, 58 рядків):

```dart
import 'package:grund_auth/grund_auth.dart';
import 'package:test/test.dart';

final _start = DateTime.utc(2026, 10, 16, 12);

Session _session(String id, {Duration lasts = const Duration(hours: 1)}) =>
    Session(
      id: id,
      userId: 'ann',
      createdAt: _start,
      expiresAt: _start.add(lasts),
    );

void main() {
  late DateTime now;
  late InMemorySessionStore store;

  setUp(() {
    now = _start;
    store = InMemorySessionStore(now: () => now);
  });

  test('reads a created session back', () async {
    final session = _session('a');
    await store.create(session);

    expect(await store.read('a'), same(session));
  });

  test('an unknown id reads as null', () async {
    expect(await store.read('nope'), isNull);
  });

  test('an expired session reads as null and is gone', () async {
    await store.create(_session('a'));
    now = _start.add(const Duration(hours: 1));

    expect(await store.read('a'), isNull);
    now = _start;
    expect(await store.read('a'), isNull);
  });

  test('a deleted session reads as null', () async {
    await store.create(_session('a'));
    await store.delete('a');

    expect(await store.read('a'), isNull);
  });

  test('create removes the expired sessions', () async {
    await store.create(_session('old', lasts: const Duration(minutes: 1)));
    now = _start.add(const Duration(minutes: 2));
    await store.create(_session('new', lasts: const Duration(hours: 2)));
    now = _start;

    expect(await store.read('old'), isNull);
  });
}
```

Run: `cd packages/grund_auth && dart test test/in_memory_session_store_test.dart`
Expected: FAIL — помилка компіляції: `Session`, `InMemorySessionStore` не визначено.

- [ ] **Крок 2: Реалізація**

`packages/grund_auth/lib/grund_auth.dart` (зміни):

```diff
--- a/packages/grund_auth/lib/grund_auth.dart
+++ b/packages/grund_auth/lib/grund_auth.dart
@@ -7,3 +7,7 @@ export 'src/auth_error.dart';
 export 'src/cookie/cookie_attributes.dart';
 export 'src/cookie/same_site_policy.dart';
 export 'src/cookie/set_cookie.dart';
+export 'src/current_user.dart';
+export 'src/session/in_memory_session_store.dart';
+export 'src/session/session.dart';
+export 'src/session/session_store.dart';
```

`packages/grund_auth/lib/src/current_user.dart` (файл цілком, 19 рядків):

```dart
/// The signed-in user of a request, in its call scope.
///
/// `SessionHook` sets it for a request with a live session; read it with
/// `c.maybe<CurrentUser>()` in a handler or hook, and with
/// `context.maybe<CurrentUser>()` in a `grund_jaspr` page.
final class CurrentUser {
  /// The user [id], with optional [claims].
  const CurrentUser(this.id, {this.claims = const {}});

  /// The id the application passed to `Sessions.start`.
  final String id;

  /// What else the application knows about the user; empty for a user of a
  /// session.
  final Map<String, Object?> claims;

  @override
  String toString() => 'CurrentUser($id)';
}
```

`packages/grund_auth/lib/src/session/session.dart` (файл цілком, 28 рядків):

```dart
/// A signed-in session: who it belongs to and until when it is valid.
///
/// The [id] is the opaque token in the session cookie; nothing else about
/// the session leaves the server.
final class Session {
  /// Creates the session.
  const Session({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.expiresAt,
  });

  /// The token of the session cookie.
  final String id;

  /// The user the session signs in.
  final String userId;

  /// When `Sessions.start` created it.
  final DateTime createdAt;

  /// When it ends; it is not extended by use.
  final DateTime expiresAt;

  /// Whether the session is still valid at [time].
  bool isLiveAt(DateTime time) => time.isBefore(expiresAt);
}
```

`packages/grund_auth/lib/src/session/session_store.dart` (файл цілком, 17 рядків):

```dart
import 'session.dart';

/// Where sessions live between requests.
///
/// `InMemorySessionStore` is the one this package has: sessions end when
/// the process does. A durable store implements this interface.
abstract interface class SessionStore {
  /// Saves the new [session].
  Future<void> create(Session session);

  /// The session [id], or `null` when there is none (or it expired, for a
  /// store that tracks expiry).
  Future<Session?> read(String id);

  /// Removes the session [id]; nothing happens when there is none.
  Future<void> delete(String id);
}
```

`packages/grund_auth/lib/src/session/in_memory_session_store.dart` (файл цілком, 37 рядків):

```dart
import 'session.dart';
import 'session_store.dart';

/// Sessions in a map of this process: lost on restart, not shared between
/// processes.
///
/// An expired session is removed when it is read, and every [create]
/// removes all expired ones, so the map does not grow with sessions nobody
/// reads again.
final class InMemorySessionStore implements SessionStore {
  /// Creates an empty store; [now] is the clock (tests pass their own).
  InMemorySessionStore({DateTime Function() now = DateTime.now}) : _now = now;

  final DateTime Function() _now;
  final Map<String, Session> _sessions = {};

  @override
  Future<void> create(Session session) async {
    final now = _now();
    _sessions
      ..removeWhere((_, stored) => !stored.isLiveAt(now))
      ..[session.id] = session;
  }

  @override
  Future<Session?> read(String id) async {
    final session = _sessions[id];
    if (session == null || session.isLiveAt(_now())) return session;
    _sessions.remove(id);
    return null;
  }

  @override
  Future<void> delete(String id) async {
    _sessions.remove(id);
  }
}
```

- [ ] **Крок 3: Тести**

Run: `cd packages/grund_auth && dart test test/in_memory_session_store_test.dart` → `+5: All tests passed!`; `dart test` → `+28: All tests passed!`.

- [ ] **Крок 4: Перевірки і коміт**

Run: `dart analyze` → `No issues found!`; `dart format packages example` → `(0 changed)`.

```bash
git add \
  packages/grund_auth/lib/grund_auth.dart \
  packages/grund_auth/lib/src/current_user.dart \
  packages/grund_auth/lib/src/session/in_memory_session_store.dart \
  packages/grund_auth/lib/src/session/session.dart \
  packages/grund_auth/lib/src/session/session_store.dart \
  packages/grund_auth/test/in_memory_session_store_test.dart
git commit -m "feat(auth): add CurrentUser, Session and the in-memory SessionStore" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git show --stat --format=%s HEAD   # 6 файлів, лише ці
```

---

### Задача 5: `SessionConfig`, `Sessions` з ротацією, токени `Random.secure`, `SessionModule`

**Мета:** почати й завершити сесію. `SessionTokens.next()` — 32 байти `Random.secure()` у base64url без доповнення (43 символи); `isWellFormed` відсіює все інше ще до звернення до сховища. `SessionConfig` (назва cookie `grund_sid`, `secure: true`, `maxAge` 7 днів, `SameSite=Lax`, `sameOrigin: true`) перевіряє себе в `validate()`: назва-не-токен, `maxAge` < 1 с, `SameSite=None` без `Secure`, `__Host-`/`__Secure-` без `Secure` — `SessionConfigError`. `Sessions.start(c, userId)` видаляє сесію, з якою прийшов запит, створює нову під свіжим токеном, ставить cookie на `c.response` і кладе `CurrentUser` у call-скоуп (RF1: токен, відомий до входу, ніколи не стає дійсним). `Sessions.end(c)` видаляє сесію й надсилає порожню cookie з `Max-Age=0`. `Sessions.current(c)` — жива сесія або `null`. `SessionModule` — глобальний модуль, що прив'язує `SessionConfig`, `SessionStore` (з фабрики `store:`), `Sessions` і перевіряє конфіг в `onInit` (до старту сервера). `SessionHook` до модуля додає задача 6.

**Files:**
- Create: `packages/grund_auth/lib/src/session/{session_config,session_tokens,sessions,session_module}.dart`
- Modify: `packages/grund_auth/lib/src/auth_error.dart` (`SessionConfigError`), `packages/grund_auth/lib/grund_auth.dart`
- Test: `packages/grund_auth/test/{session_tokens_test,session_config_test,sessions_test}.dart`, helpers `packages/grund_auth/test/helpers/{frozen_store,account_api,session_app}.dart`

**Interfaces:**
- Consumes: задача 2 (`mergeHeaders` додає `set-cookie`, `c.form()` не потрібен тут), задача 3 (`SetCookie`, `CookieAttributes`, `SameSitePolicy`, `CookieSyntax`), задача 4 (`Session`, `SessionStore`, `InMemorySessionStore`, `CurrentUser`); `HttpCtx` (`cookies.stringOrNull`, `response.headers.add`, `set<T>`), `Module`, `Singleton`, `Key`.
- Produces:

```dart
final class SessionConfigError extends AuthError { const SessionConfigError(super.reason); } // 'Invalid SessionConfig: $reason'
final class SessionTokens {
  SessionTokens([Random? random]); // Random.secure() за замовчуванням
  static const byteCount = 32;
  String next();
  static bool isWellFormed(String token);
}
final class SessionConfig {
  const SessionConfig({String cookieName = 'grund_sid', bool secure = true,
      Duration maxAge = const Duration(days: 7), SameSitePolicy sameSite = SameSitePolicy.lax,
      bool sameOrigin = true});
  CookieAttributes attributes({required Duration maxAge}); // Path=/, HttpOnly завжди
  void validate(); // throws SessionConfigError
}
final class Sessions {
  Sessions(SessionStore store, SessionConfig config, {SessionTokens? tokens, DateTime Function() now = DateTime.now});
  Future<Session> start(HttpCtx c, String userId);
  Future<void> end(HttpCtx c);
  Future<Session?> current(HttpCtx c);
}
final class SessionModule extends Module { // global; exports Key<SessionConfig>, Key<SessionStore>, Key<Sessions>
  const SessionModule({SessionConfig config = const SessionConfig(),
      SessionStore Function() store = InMemorySessionStore.new});
}
```

- [ ] **Крок 1: Тестові помічники**

`AccountApi` — маленький API з `/login`, `/logout`, `/me`, `SessionApp` — застосунок із сесіями в процесі (`TestApp` + `TestClient`, без сокета), `FrozenStore` — сховище, що не стежить за терміном і рахує читання (тест RF1 бачить, що підкинутого токена немає у сховищі; тести задачі 6 — що `Sessions` сам відкидає прострочену сесію і не читає підроблений токен).

`packages/grund_auth/test/helpers/frozen_store.dart` (файл цілком, 27 рядків):

```dart
import 'package:grund_auth/grund_auth.dart';

/// A store that keeps what it is given, expired or not, and counts reads:
/// a store that does not track expiry.
final class FrozenStore implements SessionStore {
  /// The sessions, by id.
  final Map<String, Session> sessions = {};

  /// How often [read] was called.
  int reads = 0;

  @override
  Future<void> create(Session session) async {
    sessions[session.id] = session;
  }

  @override
  Future<Session?> read(String id) async {
    reads++;
    return sessions[id];
  }

  @override
  Future<void> delete(String id) async {
    sessions.remove(id);
  }
}
```

`packages/grund_auth/test/helpers/account_api.dart` (файл цілком, 31 рядків):

```dart
import 'package:grund_auth/grund_auth.dart';
import 'package:grund_http/grund_http.dart';

/// Signs in whoever names themselves, signs out, and says who is signed in.
final class AccountApi extends HttpApi {
  /// Creates the API.
  AccountApi(super.injector, this._sessions);

  final Sessions _sessions;

  @override
  List<Route> get routes => [
    Route.post('/login', _login),
    Route.post('/logout', (c) => _sessions.end(c)),
    Route.get(
      '/me',
      (c) async => (await _sessions.current(c))?.userId ?? 'nobody',
    ),
  ];

  Future<HttpResponse> _login(HttpCtx c) async {
    final name = (await c.form()).string('name');
    await _sessions.start(c, name);
    // The handler's own cookie, next to the session cookie of `start`.
    final flash = SetCookie('flash', 'signed-in').toHeader();
    return HttpResponse(
      StatusCode.seeOther,
      headers: HeaderMap.of({'location': '/', 'set-cookie': flash}),
    );
  }
}
```

`packages/grund_auth/test/helpers/session_app.dart` (файл цілком, 62 рядків):

```dart
import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:grund_auth/grund_auth.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:grund_io/grund_io.dart';
import 'package:test/test.dart';

import 'account_api.dart';

/// [AccountApi] with sessions, started in process (no socket); closed after
/// the test.
abstract final class SessionApp {
  /// The client of the application with [config] and the store [store]
  /// creates.
  static Future<TestClient> start({
    SessionConfig config = const SessionConfig(),
    SessionStore Function() store = InMemorySessionStore.new,
  }) async {
    final app = await TestApp.start(
      root: _Root(SessionModule(config: config, store: store)),
    );
    addTearDown(app.close);
    return TestClient.of(app);
  }

  /// The value of the cookie [name] that [response] sets, or `null`.
  static String? cookie(TestResponse response, String name) {
    for (final header in response.headers.all('set-cookie')) {
      final pair = header.split(';').first;
      if (pair.startsWith('$name=')) return pair.substring(name.length + 1);
    }
    return null;
  }

  /// The `set-cookie` header of [response] for [name], or `null`.
  static String? header(TestResponse response, String name) => response.headers
      .all('set-cookie')
      .where((header) => header.startsWith('$name='))
      .firstOrNull;
}

final class _Root extends Module {
  const _Root(this._sessions);

  final SessionModule _sessions;

  @override
  List<Module> get imports => [
    const HttpModule(),
    const IoAdapterModule(),
    _sessions,
  ];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<AccountApi>(
      (i) => AccountApi(i, i<Sessions>()),
      dependsOn: const [Key<Sessions>()],
    ),
  ];
}
```

- [ ] **Крок 2: Падаючі тести**

`packages/grund_auth/test/session_tokens_test.dart` (файл цілком, 31 рядків):

```dart
import 'dart:math';

import 'package:grund_auth/src/session/session_tokens.dart';
import 'package:test/test.dart';

void main() {
  test('a token is 43 base64url characters without padding', () {
    final token = SessionTokens().next();

    expect(token, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
  });

  test('two tokens differ', () {
    final tokens = SessionTokens();

    expect(tokens.next(), isNot(tokens.next()));
  });

  test('draws from the given random source', () {
    expect(SessionTokens(Random(1)).next(), SessionTokens(Random(1)).next());
  });

  test('isWellFormed accepts a token and refuses other shapes', () {
    final token = SessionTokens().next();

    expect(SessionTokens.isWellFormed(token), isTrue);
    expect(SessionTokens.isWellFormed('$token='), isFalse);
    expect(SessionTokens.isWellFormed(token.substring(1)), isFalse);
    expect(SessionTokens.isWellFormed('${token.substring(1)}+'), isFalse);
  });
}
```

`packages/grund_auth/test/session_config_test.dart` (файл цілком, 68 рядків):

```dart
import 'package:grund/testing.dart';
import 'package:grund_auth/grund_auth.dart';
import 'package:test/test.dart';

Matcher _refused(String part) => throwsA(
  isA<SessionConfigError>().having((e) => e.message, 'message', contains(part)),
);

void main() {
  test('the defaults are valid', () {
    expect(const SessionConfig().validate, returnsNormally);
  });

  test('a cookie name that is not a token is refused', () {
    expect(
      const SessionConfig(cookieName: 'my sid').validate,
      _refused('cookieName'),
    );
    expect(
      const SessionConfig(cookieName: '').validate,
      _refused('cookieName'),
    );
  });

  test('a maxAge under one second is refused', () {
    const config = SessionConfig(maxAge: Duration(milliseconds: 999));

    expect(config.validate, _refused('maxAge'));
  });

  test('SameSite=None without secure is refused', () {
    const config = SessionConfig(secure: false, sameSite: SameSitePolicy.none);

    expect(config.validate, _refused('SameSite=None'));
  });

  test('a __Host- or __Secure- name without secure is refused', () {
    for (final name in ['__Host-sid', '__secure-sid']) {
      final config = SessionConfig(cookieName: name, secure: false);

      expect(config.validate, _refused('prefix'));
    }
  });

  test('the cookie attributes carry secure and sameSite', () {
    const config = SessionConfig(
      secure: false,
      sameSite: SameSitePolicy.strict,
    );

    final attributes = config.attributes(maxAge: const Duration(hours: 1));

    expect(attributes.secure, isFalse);
    expect(attributes.sameSite, SameSitePolicy.strict);
    expect(attributes.httpOnly, isTrue);
    expect(attributes.path, '/');
    expect(attributes.maxAge, const Duration(hours: 1));
  });

  test('SessionModule refuses an invalid config when the app starts', () {
    expect(
      TestApp.start(
        root: const SessionModule(config: SessionConfig(cookieName: 'a b')),
      ),
      throwsA(isA<SessionConfigError>()),
    );
  });
}
```

`packages/grund_auth/test/sessions_test.dart` (файл цілком, 130 рядків):

```dart
import 'package:test/test.dart';

import 'helpers/frozen_store.dart';
import 'helpers/session_app.dart';

const _form = {'content-type': 'application/x-www-form-urlencoded'};

void main() {
  test(
    'start sets an HttpOnly session cookie with the configured attributes',
    () async {
      final client = await SessionApp.start();

      final response = await client.request(
        'POST',
        '/login',
        body: 'name=ann',
        headers: _form,
      );

      expect(response.status, 303);
      expect(
        SessionApp.header(response, 'grund_sid'),
        matches(
          RegExp(
            r'^grund_sid=[A-Za-z0-9_-]{43}; Max-Age=604800; Path=/; Secure; HttpOnly; SameSite=Lax$',
          ),
        ),
      );
    },
  );

  test('the session cookie signs the next request in', () async {
    final client = await SessionApp.start();
    final login = await client.request(
      'POST',
      '/login',
      body: 'name=ann',
      headers: _form,
    );
    final token = SessionApp.cookie(login, 'grund_sid');

    final me = await client.get('/me', headers: {'cookie': 'grund_sid=$token'});

    expect(me.text, 'ann');
  });

  test(
    'the session cookie and the handler\'s own cookie both reach the client (RF5)',
    () async {
      final client = await SessionApp.start();

      final response = await client.request(
        'POST',
        '/login',
        body: 'name=ann',
        headers: _form,
      );

      expect(SessionApp.cookie(response, 'grund_sid'), isNotNull);
      expect(SessionApp.cookie(response, 'flash'), 'signed-in');
    },
  );

  test('signing in replaces the token the request came with (RF1)', () async {
    final client = await SessionApp.start();
    final mallory = await client.request(
      'POST',
      '/login',
      body: 'name=mallory',
      headers: _form,
    );
    final planted = SessionApp.cookie(mallory, 'grund_sid');

    final ann = await client.request(
      'POST',
      '/login',
      body: 'name=ann',
      headers: {..._form, 'cookie': 'grund_sid=$planted'},
    );
    final withPlanted = await client.get(
      '/me',
      headers: {'cookie': 'grund_sid=$planted'},
    );

    expect(SessionApp.cookie(ann, 'grund_sid'), isNot(planted));
    expect(withPlanted.text, 'nobody');
  });

  test(
    'a token the attacker made up is not adopted on sign-in (RF1)',
    () async {
      final store = FrozenStore();
      final client = await SessionApp.start(store: () => store);
      const planted = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

      final ann = await client.request(
        'POST',
        '/login',
        body: 'name=ann',
        headers: {..._form, 'cookie': 'grund_sid=$planted'},
      );

      expect(SessionApp.cookie(ann, 'grund_sid'), isNot(planted));
      expect(store.sessions.keys, isNot(contains(planted)));
    },
  );

  test('end deletes the session and expires the cookie', () async {
    final client = await SessionApp.start();
    final login = await client.request(
      'POST',
      '/login',
      body: 'name=ann',
      headers: _form,
    );
    final cookie = {
      'cookie': 'grund_sid=${SessionApp.cookie(login, 'grund_sid')}',
    };

    final logout = await client.post('/logout', headers: cookie);
    final me = await client.get('/me', headers: cookie);

    expect(
      SessionApp.header(logout, 'grund_sid'),
      startsWith('grund_sid=; Max-Age=0; Path=/;'),
    );
    expect(me.text, 'nobody');
  });
}
```

Run: `cd packages/grund_auth && dart test`
Expected: FAIL — помилка компіляції: `SessionTokens`, `SessionConfig`, `Sessions`, `SessionModule` не визначено.

- [ ] **Крок 3: Реалізація**

`packages/grund_auth/lib/src/auth_error.dart` (зміни):

```diff
--- a/packages/grund_auth/lib/src/auth_error.dart
+++ b/packages/grund_auth/lib/src/auth_error.dart
@@ -1,6 +1,7 @@
 import 'package:grund/grund.dart';
 
-/// A failure of `grund_auth`: a cookie that cannot be written.
+/// A failure of `grund_auth`: a cookie that cannot be written, or a session
+/// configuration a browser would not honour.
 sealed class AuthError extends GrundError {
   /// Creates the error.
   const AuthError(this.reason);
@@ -18,3 +19,13 @@ final class CookieFormatError extends AuthError {
   @override
   String get message => 'Invalid cookie: $reason';
 }
+
+/// A `SessionConfig` that cannot work; thrown when `SessionModule` starts,
+/// before the server serves.
+final class SessionConfigError extends AuthError {
+  /// Creates the error; [reason] says what is wrong.
+  const SessionConfigError(super.reason);
+
+  @override
+  String get message => 'Invalid SessionConfig: $reason';
+}
```

`packages/grund_auth/lib/src/session/session_tokens.dart` (файл цілком, 26 рядків):

```dart
import 'dart:convert';
import 'dart:math';

/// Creates and recognises session tokens: 32 random bytes from a
/// cryptographically secure source, base64url without padding (43
/// characters).
final class SessionTokens {
  /// Draws from [random]; `Random.secure()` unless a test passes its own.
  SessionTokens([Random? random]) : _random = random ?? Random.secure();

  /// The number of random bytes of a token.
  static const byteCount = 32;

  static final _shape = RegExp(r'^[A-Za-z0-9_-]{43}$');

  final Random _random;

  /// A new token.
  String next() => base64Url
      .encode([for (var i = 0; i < byteCount; i++) _random.nextInt(256)])
      .replaceAll('=', '');

  /// Whether [token] has the shape of a token; anything else is not looked
  /// up in the store.
  static bool isWellFormed(String token) => _shape.hasMatch(token);
}
```

`packages/grund_auth/lib/src/session/session_config.dart` (файл цілком, 68 рядків):

```dart
import 'dart:convert';

import '../auth_error.dart';
import '../cookie/cookie_attributes.dart';
import '../cookie/cookie_syntax.dart';
import '../cookie/same_site_policy.dart';

/// The session cookie and the same-origin check of `SessionModule`.
///
/// The cookie is always `HttpOnly` with `Path=/` and no `Domain`; its
/// lifetime is absolute ([maxAge] from the sign-in, not extended by use).
final class SessionConfig {
  /// Creates the configuration; [validate] checks it when `SessionModule`
  /// starts.
  const SessionConfig({
    this.cookieName = 'grund_sid',
    this.secure = true,
    this.maxAge = const Duration(days: 7),
    this.sameSite = SameSitePolicy.lax,
    this.sameOrigin = true,
  });

  /// The name of the session cookie.
  final String cookieName;

  /// Whether the cookie is `Secure` (sent over HTTPS only). Turn it off
  /// only for development over plain `http`.
  final bool secure;

  /// How long a session lasts, from the sign-in; at least one second.
  final Duration maxAge;

  /// The `SameSite` attribute of the cookie.
  final SameSitePolicy sameSite;

  /// Whether `SessionHook` refuses unsafe cross-site requests, as
  /// `SameOriginHook` does.
  final bool sameOrigin;

  /// The attributes of the session cookie, with [maxAge] as `Max-Age`.
  CookieAttributes attributes({required Duration maxAge}) =>
      CookieAttributes(maxAge: maxAge, secure: secure, sameSite: sameSite);

  /// Throws [SessionConfigError] when a browser would not keep the cookie
  /// or the header could not carry it.
  void validate() {
    final problem = _problem();
    if (problem != null) throw SessionConfigError(problem);
  }

  String? _problem() {
    if (!CookieSyntax.isName(cookieName)) {
      return 'cookieName ${jsonEncode(cookieName)} is not a cookie name.';
    }
    if (maxAge.inSeconds < 1) {
      return 'maxAge must be at least one second; it is $maxAge.';
    }
    if (sameSite == SameSitePolicy.none && !secure) {
      return 'SameSite=None needs secure: true; browsers drop the cookie.';
    }
    final prefixed = cookieName.toLowerCase();
    if (!secure &&
        (prefixed.startsWith('__host-') || prefixed.startsWith('__secure-'))) {
      return 'the prefix of $cookieName needs secure: true.';
    }
    return null;
  }
}
```

`packages/grund_auth/lib/src/session/sessions.dart` (файл цілком, 87 рядків):

````dart
import 'package:grund_http/grund_http.dart';

import '../cookie/set_cookie.dart';
import '../current_user.dart';
import 'session.dart';
import 'session_config.dart';
import 'session_store.dart';
import 'session_tokens.dart';

/// Starts, ends and finds the session of a request.
///
/// ```dart
/// Route.post('/login', (c) async {
///   final user = await accounts.verify(await c.form()); // yours
///   await sessions.start(c, user.id);
///   return HttpResponse.redirect(Uri.parse('/'), status: StatusCode.seeOther);
/// });
/// ```
final class Sessions {
  /// Keeps sessions in [store] with the cookie of [config]; [tokens] and
  /// [now] are for tests.
  Sessions(
    this._store,
    this._config, {
    SessionTokens? tokens,
    DateTime Function() now = DateTime.now,
  }) : _tokens = tokens ?? SessionTokens(),
       _now = now;

  final SessionStore _store;
  final SessionConfig _config;
  final SessionTokens _tokens;
  final DateTime Function() _now;

  /// Signs [userId] in: deletes the session the request came with, creates
  /// a new one under a fresh token (a token known before the sign-in never
  /// becomes valid: no session fixation), sets its cookie on [c]'s response
  /// and puts the [CurrentUser] in [c]'s call scope.
  Future<Session> start(HttpCtx c, String userId) async {
    await _forget(c);
    final now = _now();
    final session = Session(
      id: _tokens.next(),
      userId: userId,
      createdAt: now,
      expiresAt: now.add(_config.maxAge),
    );
    await _store.create(session);
    _setCookie(c, session.id, _config.maxAge);
    c.set<CurrentUser>(CurrentUser(userId));
    return session;
  }

  /// Signs out: deletes the session of the request and tells the browser
  /// to delete the cookie (an empty value with `Max-Age=0`).
  Future<void> end(HttpCtx c) async {
    await _forget(c);
    _setCookie(c, '', Duration.zero);
  }

  /// The live session of [c]'s cookie, or `null`: no cookie, a value that
  /// is not a token, an unknown or an expired session.
  Future<Session?> current(HttpCtx c) async {
    final token = _token(c);
    if (token == null) return null;
    final session = await _store.read(token);
    return session != null && session.isLiveAt(_now()) ? session : null;
  }

  Future<void> _forget(HttpCtx c) async {
    if (_token(c) case final token?) await _store.delete(token);
  }

  String? _token(HttpCtx c) {
    final token = c.cookies.stringOrNull(_config.cookieName);
    return token != null && SessionTokens.isWellFormed(token) ? token : null;
  }

  void _setCookie(HttpCtx c, String value, Duration maxAge) {
    final cookie = SetCookie(
      _config.cookieName,
      value,
      attributes: _config.attributes(maxAge: maxAge),
    );
    c.response.headers.add('set-cookie', cookie.toHeader());
  }
}
````

`packages/grund_auth/lib/src/session/session_module.dart` (файл цілком, 55 рядків):

````dart
import 'package:grund/grund.dart';

import 'in_memory_session_store.dart';
import 'session_config.dart';
import 'session_store.dart';
import 'sessions.dart';

/// Cookie sessions: binds [SessionConfig], [SessionStore] and [Sessions],
/// globally, so every API sees them.
///
/// ```dart
/// imports: [
///   const HttpModule(),
///   const SessionModule(config: SessionConfig(secure: false)), // dev only
/// ]
/// ```
///
/// [config] is validated when the application starts; an invalid one
/// throws [SessionConfigError] before the server serves.
final class SessionModule extends Module {
  /// Sessions with [config], kept in the store [store] creates.
  const SessionModule({
    this.config = const SessionConfig(),
    this.store = InMemorySessionStore.new,
  });

  /// The cookie and the same-origin check.
  final SessionConfig config;

  /// Creates the store, once per application.
  final SessionStore Function() store;

  @override
  bool get global => true;

  @override
  List<Binding<Object>> get bindings => [
    Singleton<SessionConfig>((_) => config, dependsOn: const []),
    Singleton<SessionStore>((_) => store(), dependsOn: const []),
    Singleton<Sessions>(
      (i) => Sessions(i<SessionStore>(), i<SessionConfig>()),
      dependsOn: const [Key<SessionStore>(), Key<SessionConfig>()],
    ),
  ];

  @override
  List<Object> get exports => const [
    Key<SessionConfig>(),
    Key<SessionStore>(),
    Key<Sessions>(),
  ];

  @override
  void onInit(Injector injector) => config.validate();
}
````

`packages/grund_auth/lib/grund_auth.dart` (зміни):

```diff
--- a/packages/grund_auth/lib/grund_auth.dart
+++ b/packages/grund_auth/lib/grund_auth.dart
@@ -10,4 +10,7 @@ export 'src/cookie/set_cookie.dart';
 export 'src/current_user.dart';
 export 'src/session/in_memory_session_store.dart';
 export 'src/session/session.dart';
+export 'src/session/session_config.dart';
+export 'src/session/session_module.dart';
 export 'src/session/session_store.dart';
+export 'src/session/sessions.dart';
```

- [ ] **Крок 4: Тести**

Run: `cd packages/grund_auth && dart test` → `+45: All tests passed!` (`session_tokens_test` 4, `session_config_test` 7, `sessions_test` 6 — серед них обидва тести RF1 і тест RF5 «the session cookie and the handler's own cookie both reach the client (RF5)»).

- [ ] **Крок 5: Перевірки і коміт**

Run: `dart analyze` → `No issues found!`; `dart format packages example` → `(0 changed)`; `wc -l packages/grund_auth/lib/src/session/*.dart` — найбільший `sessions.dart` (87).

```bash
git add \
  packages/grund_auth/lib/grund_auth.dart \
  packages/grund_auth/lib/src/auth_error.dart \
  packages/grund_auth/lib/src/session/session_config.dart \
  packages/grund_auth/lib/src/session/session_module.dart \
  packages/grund_auth/lib/src/session/session_tokens.dart \
  packages/grund_auth/lib/src/session/sessions.dart \
  packages/grund_auth/test/helpers/account_api.dart \
  packages/grund_auth/test/helpers/frozen_store.dart \
  packages/grund_auth/test/helpers/session_app.dart \
  packages/grund_auth/test/session_config_test.dart \
  packages/grund_auth/test/session_tokens_test.dart \
  packages/grund_auth/test/sessions_test.dart
git commit -m "feat(auth): start and end sessions with rotating tokens" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git show --stat --format=%s HEAD   # 12 файлів, лише ці
```

---

### Задача 6: `SessionHook`, `SameOriginHook`, приклад пакета

**Мета:** `SessionHook` — глобальний хук (реєструється один раз: `HttpModule(use: [HookRef<SessionHook>.type()])`), що кладе `CurrentUser(session.userId)` у call-скоуп запиту з живою сесією; без cookie, з невідомим, простроченим або підробленим токеном — просто без `CurrentUser`, не помилка. З `SessionConfig.sameOrigin` (за замовчуванням) він спершу робить перевірку `SameOriginHook`: небезпечний запит (не `GET`/`HEAD`/`OPTIONS`) з `sec-fetch-site`, що не `same-origin`/`none`, або з `origin`, що не називає `host`, — 403 `cross_site_request`; запит без цих заголовків (curl, інший сервер) проходить. `SessionModule` тепер прив'язує й експортує `SessionHook`. Приклад пакета (`example/grund_auth_example.dart`) потрібен для балів pub.dev і перевіряється тестом.

**Files:**
- Create: `packages/grund_auth/lib/src/hook/{same_origin_hook,session_hook}.dart`, `packages/grund_auth/example/grund_auth_example.dart`
- Modify: `packages/grund_auth/lib/src/session/session_module.dart`, `packages/grund_auth/lib/grund_auth.dart`, `packages/grund_auth/test/helpers/{account_api,session_app}.dart`
- Test: `packages/grund_auth/test/{same_origin_hook_test,session_hook_test,example_test}.dart`

**Interfaces:**
- Consumes: задача 5 (`Sessions.current`, `SessionConfig.sameOrigin`, `SessionModule`), задача 4 (`CurrentUser`); `HttpHook.before`, `ForbiddenException`, `HookRef<T>.type()`.
- Produces:

```dart
final class SameOriginHook extends HttpHook { const SameOriginHook(); void before(HttpCtx c); } // 403 cross_site_request
final class SessionHook extends HttpHook { SessionHook(Sessions sessions, SessionConfig config); Future<void> before(HttpCtx c); }
// SessionModule: + Singleton<SessionHook>, exports + Key<SessionHook>
```

- [ ] **Крок 1: Тестові помічники**

`SessionApp` реєструє `SessionHook` глобально, `AccountApi` отримує `/echo` (POST для перевірки same-origin), а `/me` читає `CurrentUser`, який поставив хук.

`packages/grund_auth/test/helpers/session_app.dart` (зміни):

```diff
--- a/packages/grund_auth/test/helpers/session_app.dart
+++ b/packages/grund_auth/test/helpers/session_app.dart
@@ -8,8 +8,8 @@ import 'package:test/test.dart';
 
 import 'account_api.dart';
 
-/// [AccountApi] with sessions, started in process (no socket); closed after
-/// the test.
+/// [AccountApi] behind the global [SessionHook], started in process (no
+/// socket); closed after the test.
 abstract final class SessionApp {
   /// The client of the application with [config] and the store [store]
   /// creates.
@@ -47,7 +47,7 @@ final class _Root extends Module {
 
   @override
   List<Module> get imports => [
-    const HttpModule(),
+    const HttpModule(use: [HookRef<SessionHook>.type()]),
     const IoAdapterModule(),
     _sessions,
   ];
```

`packages/grund_auth/test/helpers/account_api.dart` (зміни):

```diff
--- a/packages/grund_auth/test/helpers/account_api.dart
+++ b/packages/grund_auth/test/helpers/account_api.dart
@@ -12,10 +12,8 @@ final class AccountApi extends HttpApi {
   List<Route> get routes => [
     Route.post('/login', _login),
     Route.post('/logout', (c) => _sessions.end(c)),
-    Route.get(
-      '/me',
-      (c) async => (await _sessions.current(c))?.userId ?? 'nobody',
-    ),
+    Route.get('/me', (c) => c.maybe<CurrentUser>()?.id ?? 'nobody'),
+    Route.post('/echo', (_) => 'ok'),
   ];
 
   Future<HttpResponse> _login(HttpCtx c) async {
```

- [ ] **Крок 2: Падаючі тести**

`packages/grund_auth/test/same_origin_hook_test.dart` (файл цілком, 131 рядків):

```dart
import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:grund_auth/grund_auth.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:grund_io/grund_io.dart';
import 'package:test/test.dart';

final class EchoApi extends HttpApi {
  EchoApi(super.injector);

  @override
  List<Route> get routes => [
    Route.get('/echo', (_) => 'ok'),
    Route.post('/echo', (_) => 'ok'),
    Route.delete('/echo', (_) => 'ok'),
  ];
}

final class EchoModule extends Module {
  const EchoModule();

  @override
  List<Module> get imports => const [
    HttpModule(use: [HookRef<SameOriginHook>.instance(SameOriginHook())]),
    IoAdapterModule(),
  ];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<EchoApi>(EchoApi.new, dependsOn: const []),
  ];
}

void main() {
  late TestClient client;

  setUp(() async {
    final app = await TestApp.start(root: const EchoModule());
    addTearDown(app.close);
    client = TestClient.of(app);
  });

  Future<int> post(Map<String, String> headers) async =>
      (await client.post('/echo', headers: headers)).status;

  test('a POST without browser headers passes', () async {
    expect(await post({}), 200);
  });

  test('a GET from another site passes', () async {
    final response = await client.get(
      '/echo',
      headers: {'sec-fetch-site': 'cross-site'},
    );

    expect(response.status, 200);
  });

  for (final site in ['same-origin', 'none']) {
    test('a POST with sec-fetch-site $site passes', () async {
      expect(await post({'sec-fetch-site': site}), 200);
    });
  }

  for (final site in ['same-site', 'cross-site']) {
    test('a POST with sec-fetch-site $site is a 403', () async {
      expect(await post({'sec-fetch-site': site}), 403);
    });
  }

  test('a DELETE from another site is a 403', () async {
    final response = await client.delete(
      '/echo',
      headers: {'sec-fetch-site': 'cross-site'},
    );

    expect(response.status, 403);
  });

  test('an origin that names the host passes, in any case', () async {
    expect(
      await post({
        'origin': 'http://Example.test:8080',
        'host': 'example.test:8080',
      }),
      200,
    );
    expect(
      await post({'origin': 'https://example.test', 'host': 'example.test'}),
      200,
    );
    expect(
      await post({'origin': 'http://[::1]:8080', 'host': '[::1]:8080'}),
      200,
    );
  });

  test('an origin of another host or port is a 403', () async {
    expect(
      await post({'origin': 'http://evil.test', 'host': 'example.test'}),
      403,
    );
    expect(
      await post({
        'origin': 'http://example.test:9',
        'host': 'example.test:8080',
      }),
      403,
    );
  });

  test('origin null or an origin without a host header is a 403', () async {
    expect(await post({'origin': 'null', 'host': 'example.test'}), 403);
    expect(await post({'origin': 'http://example.test'}), 403);
  });

  test(
    'a matching origin does not excuse a cross-site sec-fetch-site',
    () async {
      expect(
        await post({
          'origin': 'http://example.test',
          'host': 'example.test',
          'sec-fetch-site': 'cross-site',
        }),
        403,
      );
    },
  );
}
```

`packages/grund_auth/test/session_hook_test.dart` (файл цілком, 100 рядків):

```dart
import 'package:grund_auth/grund_auth.dart';
import 'package:test/test.dart';

import 'helpers/frozen_store.dart';
import 'helpers/session_app.dart';

const _token = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

Session _session({required Duration endsIn}) => Session(
  id: _token,
  userId: 'ann',
  createdAt: DateTime.now().subtract(const Duration(days: 1)),
  expiresAt: DateTime.now().add(endsIn),
);

void main() {
  test('a live session puts the CurrentUser in the call scope', () async {
    final store = FrozenStore();
    store.sessions[_token] = _session(endsIn: const Duration(hours: 1));
    final client = await SessionApp.start(store: () => store);

    final me = await client.get(
      '/me',
      headers: {'cookie': 'grund_sid=$_token'},
    );

    expect(me.text, 'ann');
  });

  test('no cookie means no CurrentUser and no error', () async {
    final client = await SessionApp.start();

    final me = await client.get('/me');

    expect(me.status, 200);
    expect(me.text, 'nobody');
  });

  test('an unknown token means no CurrentUser', () async {
    final client = await SessionApp.start();

    final me = await client.get(
      '/me',
      headers: {'cookie': 'grund_sid=$_token'},
    );

    expect(me.text, 'nobody');
  });

  test(
    'an expired session means no CurrentUser, also from a store that keeps it',
    () async {
      final store = FrozenStore();
      store.sessions[_token] = _session(endsIn: const Duration(seconds: -1));
      final client = await SessionApp.start(store: () => store);

      final me = await client.get(
        '/me',
        headers: {'cookie': 'grund_sid=$_token'},
      );

      expect(me.text, 'nobody');
    },
  );

  test('a forged value that is not a token is not looked up', () async {
    final store = FrozenStore();
    final client = await SessionApp.start(store: () => store);

    final me = await client.get('/me', headers: {'cookie': 'grund_sid=admin'});

    expect(me.text, 'nobody');
    expect(store.reads, 0);
  });

  test('refuses a cross-site POST by default', () async {
    final client = await SessionApp.start();

    final response = await client.post(
      '/echo',
      headers: {'sec-fetch-site': 'cross-site'},
    );

    expect(response.status, 403);
    expect(response.json, containsPair('code', 'cross_site_request'));
  });

  test('lets a cross-site POST through with sameOrigin off', () async {
    final client = await SessionApp.start(
      config: const SessionConfig(sameOrigin: false),
    );

    final response = await client.post(
      '/echo',
      headers: {'sec-fetch-site': 'cross-site'},
    );

    expect(response.status, 200);
  });
}
```

`packages/grund_auth/test/example_test.dart` (файл цілком, 9 рядків):

```dart
import 'package:test/test.dart';

import '../example/grund_auth_example.dart' as example;

void main() {
  test('the example signs in with a form and finds the user', () {
    expect(example.signIn(), completion(['303', '{"user":"ann"}']));
  });
}
```

Run: `cd packages/grund_auth && dart test`
Expected: FAIL — помилка компіляції: `SameOriginHook`, `SessionHook` не визначено; `example/grund_auth_example.dart` не існує.

- [ ] **Крок 3: Реалізація**

`packages/grund_auth/lib/src/hook/same_origin_hook.dart` (файл цілком, 47 рядків):

```dart
import 'package:grund_http/grund_http.dart';

/// Refuses an unsafe request (not `GET`, `HEAD` or `OPTIONS`) that a
/// browser sent from another site: a 403 `cross_site_request`.
///
/// A request is cross-site when its `sec-fetch-site` is neither
/// `same-origin` nor `none`, or when its `origin` does not name the `host`
/// it was sent to. A request without these headers (not from a browser:
/// curl, another server) passes. `SessionHook` does the same check when
/// `SessionConfig.sameOrigin` is on; use this hook alone for an
/// application without sessions.
///
/// Behind a proxy that rewrites `host`, `origin` no longer matches; forward
/// the original `host`.
final class SameOriginHook extends HttpHook {
  /// Creates the hook.
  const SameOriginHook();

  static const _safeMethods = {'GET', 'HEAD', 'OPTIONS'};

  @override
  void before(HttpCtx c) {
    final request = c.request;
    if (_safeMethods.contains(request.method)) return;
    final site = request.headers['sec-fetch-site'];
    if (site != null && site != 'same-origin' && site != 'none') {
      throw _refused('sec-fetch-site is $site');
    }
    final origin = request.headers['origin'];
    if (origin != null && !_namesHost(origin, request.headers['host'])) {
      throw _refused('origin $origin is not the host');
    }
  }

  static bool _namesHost(String origin, String? host) {
    final uri = Uri.tryParse(origin);
    if (host == null || uri == null || !uri.hasAuthority) return false;
    final name = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    final authority = uri.hasPort ? '$name:${uri.port}' : name;
    return authority.toLowerCase() == host.toLowerCase();
  }

  static ForbiddenException _refused(String why) => ForbiddenException(
    message: 'Cross-site request refused: $why.',
    code: 'cross_site_request',
  );
}
```

`packages/grund_auth/lib/src/hook/session_hook.dart` (файл цілком, 33 рядків):

````dart
import 'package:grund_http/grund_http.dart';

import '../current_user.dart';
import '../session/session_config.dart';
import '../session/sessions.dart';
import 'same_origin_hook.dart';

/// Puts the [CurrentUser] of a live session into the call scope; register
/// it once, globally:
///
/// ```dart
/// HttpModule(use: const [HookRef<SessionHook>.type()])
/// ```
///
/// A request without a session, or with an unknown, expired or forged
/// token, simply has no [CurrentUser]. With `SessionConfig.sameOrigin`
/// (the default) it first refuses unsafe cross-site requests the way
/// [SameOriginHook] does.
final class SessionHook extends HttpHook {
  /// Reads sessions through [sessions]; [config] says whether to check the
  /// origin.
  SessionHook(this._sessions, this._config);

  final Sessions _sessions;
  final SessionConfig _config;

  @override
  Future<void> before(HttpCtx c) async {
    if (_config.sameOrigin) const SameOriginHook().before(c);
    final session = await _sessions.current(c);
    if (session != null) c.set<CurrentUser>(CurrentUser(session.userId));
  }
}
````

`packages/grund_auth/lib/src/session/session_module.dart` (зміни):

````diff
--- a/packages/grund_auth/lib/src/session/session_module.dart
+++ b/packages/grund_auth/lib/src/session/session_module.dart
@@ -1,16 +1,18 @@
 import 'package:grund/grund.dart';
 
+import '../hook/session_hook.dart';
 import 'in_memory_session_store.dart';
 import 'session_config.dart';
 import 'session_store.dart';
 import 'sessions.dart';
 
-/// Cookie sessions: binds [SessionConfig], [SessionStore] and [Sessions],
-/// globally, so every API sees them.
+/// Cookie sessions: binds [SessionConfig], [SessionStore], [Sessions] and
+/// [SessionHook], globally, so every API and the hook list of `HttpModule`
+/// see them.
 ///
 /// ```dart
 /// imports: [
-///   const HttpModule(),
+///   HttpModule(use: const [HookRef<SessionHook>.type()]),
 ///   const SessionModule(config: SessionConfig(secure: false)), // dev only
 /// ]
 /// ```
@@ -41,6 +43,10 @@ final class SessionModule extends Module {
       (i) => Sessions(i<SessionStore>(), i<SessionConfig>()),
       dependsOn: const [Key<SessionStore>(), Key<SessionConfig>()],
     ),
+    Singleton<SessionHook>(
+      (i) => SessionHook(i<Sessions>(), i<SessionConfig>()),
+      dependsOn: const [Key<Sessions>(), Key<SessionConfig>()],
+    ),
   ];
 
   @override
@@ -48,6 +54,7 @@ final class SessionModule extends Module {
     Key<SessionConfig>(),
     Key<SessionStore>(),
     Key<Sessions>(),
+    Key<SessionHook>(),
   ];
 
   @override
````

`packages/grund_auth/lib/grund_auth.dart` (зміни):

```diff
--- a/packages/grund_auth/lib/grund_auth.dart
+++ b/packages/grund_auth/lib/grund_auth.dart
@@ -8,6 +8,8 @@ export 'src/cookie/cookie_attributes.dart';
 export 'src/cookie/same_site_policy.dart';
 export 'src/cookie/set_cookie.dart';
 export 'src/current_user.dart';
+export 'src/hook/same_origin_hook.dart';
+export 'src/hook/session_hook.dart';
 export 'src/session/in_memory_session_store.dart';
 export 'src/session/session.dart';
 export 'src/session/session_config.dart';
```

`packages/grund_auth/example/grund_auth_example.dart` (файл цілком, 72 рядків):

```dart
import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:grund_auth/grund_auth.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:grund_io/grund_io.dart';

/// Signs a name in with a form post and says who is signed in.
final class AccountApi extends HttpApi {
  /// Starts sessions through [_sessions].
  AccountApi(super.injector, this._sessions);

  final Sessions _sessions;

  @override
  List<Route> get routes => [
    Route.post('/login', _login),
    Route.get('/me', (c) => {'user': c.maybe<CurrentUser>()?.id}),
  ];

  Future<HttpResponse> _login(HttpCtx c) async {
    final name = (await c.form()).string('name', minLength: 1);
    // Check a password or another credential here before signing in.
    await _sessions.start(c, name);
    return HttpResponse.redirect(Uri.parse('/me'), status: StatusCode.seeOther);
  }
}

/// The root module: the server, sessions with their hook, and the API.
final class AppModule extends Module {
  /// Creates the module.
  const AppModule();

  @override
  List<Module> get imports => const [
    HttpModule(use: [HookRef<SessionHook>.type()]),
    IoAdapterModule(),
    // Plain http here; keep the default `secure: true` behind HTTPS.
    SessionModule(config: SessionConfig(secure: false)),
  ];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<AccountApi>(
      (i) => AccountApi(i, i<Sessions>()),
      dependsOn: const [Key<Sessions>()],
    ),
  ];
}

/// Signs `ann` in, in process, and returns the status of the sign-in and
/// what `GET /me` answers with the session cookie.
Future<List<String>> signIn() async {
  final app = await TestApp.start(root: const AppModule());
  try {
    final client = TestClient.of(app);
    final login = await client.request(
      'POST',
      '/login',
      body: 'name=ann',
      headers: {'content-type': 'application/x-www-form-urlencoded'},
    );
    final cookie = (login.headers['set-cookie'] ?? '').split(';').first;
    final me = await client.get('/me', headers: {'cookie': cookie});
    return ['${login.status}', me.text];
  } finally {
    await app.close();
  }
}

/// Serves the API on port 8080 until Ctrl+C.
Future<void> main() => App(root: const AppModule()).run();
```

- [ ] **Крок 4: Тести**

Run: `cd packages/grund_auth && dart test` → `+64: All tests passed!` (`same_origin_hook_test` 11, `session_hook_test` 7, `example_test` 1).

- [ ] **Крок 5: Перевірки і коміт**

Run: `dart analyze` → `No issues found!`; `dart format packages example` → `(0 changed)`. (`publish --dry-run` нових пакетів — у задачі 13, коли README і CHANGELOG повні.)

```bash
git add \
  packages/grund_auth/example/grund_auth_example.dart \
  packages/grund_auth/lib/grund_auth.dart \
  packages/grund_auth/lib/src/hook/same_origin_hook.dart \
  packages/grund_auth/lib/src/hook/session_hook.dart \
  packages/grund_auth/lib/src/session/session_module.dart \
  packages/grund_auth/test/example_test.dart \
  packages/grund_auth/test/helpers/account_api.dart \
  packages/grund_auth/test/helpers/session_app.dart \
  packages/grund_auth/test/same_origin_hook_test.dart \
  packages/grund_auth/test/session_hook_test.dart
git commit -m "feat(auth): add SessionHook and SameOriginHook" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git show --stat --format=%s HEAD   # 10 файлів, лише ці
```

---
### Задача 7: `grund_jaspr` — відображення запиту й відповіді

**Мета:** два чисті перетворення між grund і Jaspr. `JasprRequest.from(HttpRequest)` будує shelf-`Request`, з якого рендерить Jaspr: метод, шлях (порожній — `/`), query без змін і **кожне** значення кожного заголовка; тіло не передається (Jaspr його не читає), хост URL — заглушка (справжній у заголовку `host`). `JasprResponse.from(ResponseLike)` повертає `HttpResponse`: статус, тіло і всі заголовки Jaspr зі збереженням кожного `set-cookie` (RF4); HTML без charset стає `text/html; charset=utf-8` (інший тип або явний charset не чіпається, «Рішення плану», п. 3); `content-length` відкидається (його ставить адаптер); без `cache-control` від сторінки — `private, no-cache` (сторінка може залежати від сесії).

**Files:**
- Create: `packages/grund_jaspr/lib/src/{jaspr_request,jaspr_response}.dart`
- Test: `packages/grund_jaspr/test/{jaspr_request_test,jaspr_response_test}.dart`

**Interfaces:**
- Consumes: задача 1 (`package:jaspr/server.dart`: `Request`, `ResponseLike` з `statusCode`, `body` (`Uint8List`), `headers` (`Map<String, List<String>>`)); `HttpRequest`, `HttpResponse`, `HeaderMap`, `ResponseBody` з `grund_http`.
- Produces (поза barrel; тести імпортують `package:grund_jaspr/src/…`):

```dart
abstract final class JasprRequest { static Request from(HttpRequest request); }
abstract final class JasprResponse {
  static const htmlType = 'text/html; charset=utf-8';
  static HttpResponse from(ResponseLike rendered);
  static bool isHtml(String contentType); // text/html з будь-якими параметрами
}
```

- [ ] **Крок 1: Падаючі тести**

`packages/grund_jaspr/test/jaspr_request_test.dart` (файл цілком, 40 рядків):

```dart
import 'package:grund_http/grund_http.dart';
import 'package:grund_jaspr/src/jaspr_request.dart';
import 'package:test/test.dart';

HttpRequest _request(String target, {HeaderMap? headers}) => HttpRequest(
  method: 'GET',
  uri: Uri.parse(target),
  headers: headers ?? HeaderMap(),
);

void main() {
  test('the path and the query reach Jaspr as they were sent', () {
    final request = JasprRequest.from(_request('/a/b?x=1&y=%20z'));

    expect(request.method, 'GET');
    expect(request.url.path, 'a/b');
    expect(request.requestedUri.path, '/a/b');
    expect(request.requestedUri.query, 'x=1&y=%20z');
    expect(request.handlerPath, '/');
  });

  test('an empty path is the root', () {
    final request = JasprRequest.from(_request(''));

    expect(request.requestedUri.path, '/');
    expect(request.requestedUri.hasQuery, isFalse);
  });

  test('every value of a header is passed', () {
    final headers = HeaderMap()
      ..add('accept', 'text/html')
      ..add('x-many', 'a')
      ..add('x-many', 'b');

    final request = JasprRequest.from(_request('/', headers: headers));

    expect(request.headersAll['x-many'], ['a', 'b']);
    expect(request.headers['accept'], 'text/html');
  });
}
```

`packages/grund_jaspr/test/jaspr_response_test.dart` (файл цілком, 72 рядків):

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:grund_http/grund_http.dart';
import 'package:grund_jaspr/src/jaspr_response.dart';
import 'package:test/test.dart';

HttpResponse _from(Map<String, List<String>> headers, {int status = 200}) =>
    JasprResponse.from((
      statusCode: status,
      body: Uint8List.fromList(utf8.encode('<p>ü</p>')),
      headers: headers,
    ));

void main() {
  test('the status, the body and every set-cookie are kept', () {
    final response = _from({
      'Set-Cookie': ['a=1', 'b=2'],
      'x-page': ['yes'],
    }, status: 203);

    expect(response.status, 203);
    expect(response.headers.all('set-cookie'), ['a=1', 'b=2']);
    expect(response.headers['x-page'], 'yes');
    expect((response.body as BytesBody).bytes, utf8.encode('<p>ü</p>'));
  });

  test('HTML without a charset becomes UTF-8 HTML', () {
    for (final type in [null, 'text/html', 'TEXT/HTML ; level=1']) {
      final response = _from({
        if (type != null) 'Content-Type': [type],
      });

      expect(response.headers['content-type'], 'text/html; charset=utf-8');
    }
  });

  test('a content type of the page wins over Jaspr default', () {
    final response = _from({
      'Content-Type': ['text/html; charset=utf-8'],
      'content-type': ['application/xml'],
    });

    expect(response.headers.all('content-type'), ['application/xml']);
  });

  test('a charset the page chose is kept', () {
    final response = _from({
      'content-type': ['text/html; charset=iso-8859-1'],
    });

    expect(response.headers['content-type'], 'text/html; charset=iso-8859-1');
  });

  test('a page is not cached unless it says so', () {
    final plain = _from({});
    final cached = _from({
      'Cache-Control': ['max-age=60'],
    });

    expect(plain.headers['cache-control'], 'private, no-cache');
    expect(cached.headers['cache-control'], 'max-age=60');
  });

  test('content-length is left to the adapter', () {
    final response = _from({
      'Content-Length': ['999'],
    });

    expect(response.headers.contains('content-length'), isFalse);
  });
}
```

Run: `cd packages/grund_jaspr && dart test`
Expected: FAIL — помилка компіляції: `src/jaspr_request.dart`, `src/jaspr_response.dart` не існують.

- [ ] **Крок 2: Реалізація**

`packages/grund_jaspr/lib/src/jaspr_request.dart` (файл цілком, 25 рядків):

```dart
import 'package:grund_http/grund_http.dart';
import 'package:jaspr/server.dart';

/// Builds the shelf [Request] Jaspr renders from: the method, the path and
/// query, and every header value of a grund request.
///
/// Jaspr reads only the URL, the handler path and the headers, so the body
/// is not passed. The host of the URL is a placeholder; the real one is in
/// the `host` header.
abstract final class JasprRequest {
  /// The Jaspr request for [request].
  static Request from(HttpRequest request) => Request(
    request.method,
    Uri(
      scheme: 'http',
      host: 'localhost',
      path: request.uri.path.isEmpty ? '/' : request.uri.path,
      query: request.uri.hasQuery ? request.uri.query : null,
    ),
    headers: {
      for (final name in request.headers.names) name: request.headers.all(name),
    },
    handlerPath: '/',
  );
}
```

`packages/grund_jaspr/lib/src/jaspr_response.dart` (файл цілком, 48 рядків):

```dart
import 'package:grund_http/grund_http.dart';
import 'package:jaspr/server.dart';

/// Turns what Jaspr rendered into an [HttpResponse].
///
/// Header names are lower-cased; every `set-cookie` value is kept, for any
/// other name the last spelling Jaspr holds wins (`Content-Type` is Jaspr's
/// default, `content-type` a component's own). `content-length` is dropped:
/// the adapter sets it for the body it sends. A missing `content-type`, or
/// `text/html` without a charset, becomes `text/html; charset=utf-8` (Jaspr
/// writes UTF-8); a page without `cache-control` gets `private, no-cache`,
/// since it may depend on the session.
abstract final class JasprResponse {
  /// The `content-type` of a rendered page.
  static const htmlType = 'text/html; charset=utf-8';

  /// The response for [rendered].
  static HttpResponse from(ResponseLike rendered) => HttpResponse(
    rendered.statusCode,
    headers: _headers(rendered.headers),
    body: BytesBody(rendered.body),
  );

  /// Whether [contentType] is `text/html`, with or without parameters.
  static bool isHtml(String contentType) =>
      contentType.split(';').first.trim().toLowerCase() == 'text/html';

  static HeaderMap _headers(Map<String, List<String>> rendered) {
    final headers = HeaderMap();
    for (final MapEntry(:key, :value) in rendered.entries) {
      final name = key.toLowerCase();
      if (name == 'content-length') continue;
      if (name != 'set-cookie') headers.remove(name);
      for (final item in value) {
        headers.add(name, item);
      }
    }
    final type = headers['content-type'];
    if (type == null ||
        (isHtml(type) && !type.toLowerCase().contains('charset='))) {
      headers.set('content-type', htmlType);
    }
    if (!headers.contains('cache-control')) {
      headers.set('cache-control', 'private, no-cache');
    }
    return headers;
  }
}
```

- [ ] **Крок 3: Тести**

Run: `cd packages/grund_jaspr && dart test` → `+11: All tests passed!` (`jaspr_request_test` 3, `jaspr_response_test` 6 — серед них «the status, the body and every set-cookie are kept», RF4).

- [ ] **Крок 4: Перевірки і коміт**

Run: `dart analyze` → `No issues found!`; `dart format packages example` → `(0 changed)`.

```bash
git add \
  packages/grund_jaspr/lib/src/jaspr_request.dart \
  packages/grund_jaspr/lib/src/jaspr_response.dart \
  packages/grund_jaspr/test/jaspr_request_test.dart \
  packages/grund_jaspr/test/jaspr_response_test.dart
git commit -m "feat(jaspr): map a grund request to Jaspr and its answer back" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git show --stat --format=%s HEAD   # 4 файлів, лише ці
```

---

### Задача 8: Статичні файли і `JasprConfig`

**Мета:** `StaticFiles(directory)` знаходить файл каталогу за сегментами шляху і віддає його байти з типом за розширенням (`ContentTypes`, без урахування регістру) і `cache-control: no-cache`. Сегмент, що порожній, починається з `.`, містить `/`, `\`, `:` або керівний символ (включно з NUL), — ніколи не файл; шлях після `realpath` (символьні посилання розв'язано) мусить лишатися в каталозі (RF3). Каталог, якого немає, нічого не віддає; відносний каталог розв'язується від робочого каталогу. `JasprConfig` поки має `staticDirectory` (`web`) і `pageSuffixes` (`html`, `htm`, `xml` — розширення, з якими шлях ще може бути сторінкою); `liveReloadUrl` додає задача 12d.

**Files:**
- Create: `packages/grund_jaspr/lib/src/{content_types,static_files,jaspr_config}.dart`
- Modify: `packages/grund_jaspr/lib/grund_jaspr.dart`
- Test: `packages/grund_jaspr/test/static_files_test.dart`, helper `packages/grund_jaspr/test/helpers/temp_dir.dart`

**Interfaces:**
- Consumes: `package:path` (`p.normalize`, `p.absolute`, `p.join`, `p.isWithin`, `p.extension`), `dart:io` (`File`, `Directory`, `resolveSymbolicLinksSync`), `HttpResponse.bytes`.
- Produces:

```dart
abstract final class ContentTypes { static String forPath(String path); } // поза barrel; невідоме — application/octet-stream
final class StaticFiles { // поза barrel
  StaticFiles(String directory);
  final String root; // абсолютний нормалізований
  String? find(List<String> segments); // null: не файл або поза root
  Future<HttpResponse> respond(String file);
}
final class JasprConfig { // у barrel
  const JasprConfig({String staticDirectory = 'web', List<String> pageSuffixes = const ['html', 'htm', 'xml']});
}
```

- [ ] **Крок 1: Тестовий помічник і падаючий тест**

`TempDir` — тимчасовий каталог, що видаляється після тесту (правило репозиторію: тимчасові файли лише через `TempDir`).

`packages/grund_jaspr/test/helpers/temp_dir.dart` (файл цілком, 44 рядків):

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A fresh directory under the system temp directory, deleted when the
/// test that created it ends.
final class TempDir {
  TempDir._(this.path);

  /// Creates the directory and registers its deletion with [addTearDown].
  factory TempDir.create() {
    final directory = Directory.systemTemp.createTempSync('grund_jaspr_');
    final temp = TempDir._(directory.resolveSymbolicLinksSync());
    addTearDown(temp._delete);
    return temp;
  }

  /// Absolute path of the directory, symbolic links resolved.
  final String path;

  /// The absolute path of [relative] (with `/` separators) in the directory.
  String resolve(String relative) => p.joinAll([path, ...relative.split('/')]);

  /// Writes [content] to [relative], creating parent directories; returns
  /// the absolute path.
  String write(String relative, String content) {
    final file = File(resolve(relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file.path;
  }

  /// The content of [relative].
  String read(String relative) => File(resolve(relative)).readAsStringSync();

  /// Whether a file exists at [relative].
  bool exists(String relative) => File(resolve(relative)).existsSync();

  void _delete() {
    final directory = Directory(path);
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}
```

`packages/grund_jaspr/test/static_files_test.dart` (файл цілком, 93 рядків):

```dart
import 'dart:io';

import 'package:grund_http/grund_http.dart';
import 'package:grund_jaspr/src/content_types.dart';
import 'package:grund_jaspr/src/static_files.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/temp_dir.dart';

/// A temp directory with `web/app.css`, `web/.env` and, next to `web/`,
/// `secret.txt`; returns the files of `web/`.
StaticFiles _web(TempDir dir) {
  dir
    ..write('web/app.css', 'body{}')
    ..write('web/sub/page.js', 'go()')
    ..write('web/.env', 'secret')
    ..write('secret.txt', 'secret');
  return StaticFiles(dir.resolve('web'));
}

void main() {
  test('a file of the directory is found by its segments', () {
    final dir = TempDir.create();
    final files = _web(dir);

    expect(files.find(['app.css']), dir.resolve('web/app.css'));
    expect(files.find(['sub', 'page.js']), dir.resolve('web/sub/page.js'));
  });

  test('a directory, a missing file and the root are not files', () {
    final files = _web(TempDir.create());

    expect(files.find(['sub']), isNull);
    expect(files.find(['missing.css']), isNull);
    expect(files.find([]), isNull);
  });

  for (final segments in [
    ['..', 'secret.txt'],
    ['sub', '..', '..', 'secret.txt'],
    ['.env'],
    ['../secret.txt'],
    [r'..\secret.txt'],
    ['C:', 'secret.txt'],
    ['', 'app.css'],
    ['app.css\x00'],
  ]) {
    test('$segments never leaves the directory', () {
      final files = _web(TempDir.create());

      expect(files.find(segments), isNull);
    });
  }

  test('a symbolic link out of the directory is not served', () {
    final dir = TempDir.create();
    final files = _web(dir);
    Link(dir.resolve('web/link.txt')).createSync(dir.resolve('secret.txt'));

    expect(files.find(['link.txt']), isNull);
  });

  test('a directory that does not exist serves nothing', () {
    final dir = TempDir.create();

    expect(StaticFiles(dir.resolve('none')).find(['app.css']), isNull);
  });

  test('a relative directory is resolved against the working directory', () {
    expect(StaticFiles('web').root, p.join(Directory.current.path, 'web'));
  });

  test('a file is answered with its bytes, its type and no-cache', () async {
    final dir = TempDir.create();
    final files = _web(dir);

    final response = await files.respond(dir.resolve('web/app.css'));

    expect(response.status, 200);
    expect(response.headers['content-type'], 'text/css; charset=utf-8');
    expect(response.headers['cache-control'], 'no-cache');
    expect(String.fromCharCodes((response.body as BytesBody).bytes), 'body{}');
  });

  test('the type comes from the extension, in any case', () {
    expect(ContentTypes.forPath('a/b.PNG'), 'image/png');
    expect(ContentTypes.forPath('app.js'), 'text/javascript; charset=utf-8');
    expect(ContentTypes.forPath('font.woff2'), 'font/woff2');
    expect(ContentTypes.forPath('data.bin'), 'application/octet-stream');
    expect(ContentTypes.forPath('Makefile'), 'application/octet-stream');
  });
}
```

Run: `cd packages/grund_jaspr && dart test test/static_files_test.dart`
Expected: FAIL — помилка компіляції: `src/static_files.dart` не існує.

- [ ] **Крок 2: Реалізація**

`packages/grund_jaspr/lib/src/content_types.dart` (файл цілком, 39 рядків):

```dart
import 'package:path/path.dart' as p;

/// The `content-type` of a static file, by its extension.
///
/// A small table of the types a web page uses; anything else is
/// `application/octet-stream`.
abstract final class ContentTypes {
  /// The type of the file at [path].
  static String forPath(String path) =>
      _byExtension[p.extension(path).toLowerCase()] ??
      'application/octet-stream';

  static const _byExtension = {
    '.avif': 'image/avif',
    '.css': 'text/css; charset=utf-8',
    '.gif': 'image/gif',
    '.htm': 'text/html; charset=utf-8',
    '.html': 'text/html; charset=utf-8',
    '.ico': 'image/x-icon',
    '.jpeg': 'image/jpeg',
    '.jpg': 'image/jpeg',
    '.js': 'text/javascript; charset=utf-8',
    '.json': 'application/json',
    '.map': 'application/json',
    '.mjs': 'text/javascript; charset=utf-8',
    '.otf': 'font/otf',
    '.pdf': 'application/pdf',
    '.png': 'image/png',
    '.svg': 'image/svg+xml',
    '.ttf': 'font/ttf',
    '.txt': 'text/plain; charset=utf-8',
    '.wasm': 'application/wasm',
    '.webmanifest': 'application/manifest+json',
    '.webp': 'image/webp',
    '.woff': 'font/woff',
    '.woff2': 'font/woff2',
    '.xml': 'application/xml',
  };
}
```

`packages/grund_jaspr/lib/src/static_files.dart` (файл цілком, 63 рядків):

```dart
import 'dart:io';

import 'package:grund_http/grund_http.dart';
import 'package:path/path.dart' as p;

import 'content_types.dart';

/// The files of a directory, served as they are.
///
/// A request path maps to a file only when every segment is a plain name:
/// not empty, not starting with `.` (so no `..`, no `.env`), without `/`,
/// `\`, `:` or control characters (a percent-encoded `%2F` or `%5C` arrives
/// decoded in a segment), and the file, with symbolic links resolved, lies
/// inside the directory.
final class StaticFiles {
  /// Serves [directory]; a relative path is resolved against the working
  /// directory. A directory that does not exist serves nothing.
  StaticFiles(String directory) : root = p.normalize(p.absolute(directory));

  /// The absolute directory.
  final String root;

  /// The file for the decoded path [segments], or `null` when there is no
  /// such regular file in [root].
  String? find(List<String> segments) {
    if (segments.isEmpty || !segments.every(_isPlainName)) return null;
    final candidate = p.joinAll([root, ...segments]);
    if (!p.isWithin(root, candidate)) return null;
    try {
      if (FileSystemEntity.typeSync(candidate) != FileSystemEntityType.file) {
        return null;
      }
      final file = File(candidate).resolveSymbolicLinksSync();
      final directory = Directory(root).resolveSymbolicLinksSync();
      return p.isWithin(directory, file) ? file : null;
    } on FileSystemException {
      // Gone or unreadable between the checks: not a file to serve.
      return null;
    }
  }

  /// The response with the bytes of [file], its type and
  /// `cache-control: no-cache` (the browser revalidates every time).
  Future<HttpResponse> respond(String file) async => HttpResponse.bytes(
    await File(file).readAsBytes(),
    headers: HeaderMap.of({
      'content-type': ContentTypes.forPath(file),
      'cache-control': 'no-cache',
    }),
  );

  static bool _isPlainName(String segment) =>
      segment.isNotEmpty &&
      !segment.startsWith('.') &&
      !segment.codeUnits.any(_isForbidden);

  static bool _isForbidden(int unit) =>
      unit < 0x20 ||
      unit == 0x7f ||
      unit == 0x2f ||
      unit == 0x5c ||
      unit == 0x3a;
}
```

`packages/grund_jaspr/lib/src/jaspr_config.dart` (файл цілком, 18 рядків):

```dart
/// How `JasprModule` serves pages and static files.
final class JasprConfig {
  /// Creates the configuration.
  const JasprConfig({
    this.staticDirectory = 'web',
    this.pageSuffixes = const ['html', 'htm', 'xml'],
  });

  /// The directory of the static files; a relative path is resolved
  /// against the working directory (run the application from its package
  /// root). A directory that does not exist serves nothing.
  final String staticDirectory;

  /// The file extensions a page path may have (`/feed.xml`); a path with
  /// another extension that is not a static file is a 404 instead of a
  /// page, the way Jaspr's own server does it.
  final List<String> pageSuffixes;
}
```

`packages/grund_jaspr/lib/grund_jaspr.dart` (зміни):

```diff
--- a/packages/grund_jaspr/lib/grund_jaspr.dart
+++ b/packages/grund_jaspr/lib/grund_jaspr.dart
@@ -2,3 +2,5 @@
 /// serves the API and the pages, with one dependency injection and one
 /// lifecycle.
 library;
+
+export 'src/jaspr_config.dart';
```

- [ ] **Крок 3: Тести**

Run: `cd packages/grund_jaspr && dart test test/static_files_test.dart` → `+15: All tests passed!` (серед них «$segments never leaves the directory» для `..`, `sub/../..`, `.env`, `../x` в одному сегменті, `..\x`, `C:`, порожнього сегмента, NUL і «a symbolic link out of the directory is not served», RF3); `dart test` → `+26: All tests passed!`.

- [ ] **Крок 4: Перевірки і коміт**

Run: `dart analyze` → `No issues found!`; `dart format packages example` → `(0 changed)`.

```bash
git add \
  packages/grund_jaspr/lib/grund_jaspr.dart \
  packages/grund_jaspr/lib/src/content_types.dart \
  packages/grund_jaspr/lib/src/jaspr_config.dart \
  packages/grund_jaspr/lib/src/static_files.dart \
  packages/grund_jaspr/test/helpers/temp_dir.dart \
  packages/grund_jaspr/test/static_files_test.dart
git commit -m "feat(jaspr): serve static files, add JasprConfig" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git show --stat --format=%s HEAD   # 6 файлів, лише ці
```

---

### Задача 9: `GrundScope`, розширення `BuildContext`, `JasprPages`, `JasprModule`, ідемпотентна ініціалізація

**Мета:** сторінки в застосунку. `JasprModule(app:, imports:, config:)` прив'язує `JasprPages` — `HttpApi` з маршрутами `GET /` і `GET /*`: файл зі `StaticFiles` має пріоритет; шлях з розширенням не з `pageSuffixes` і не файл — 404 `file_not_found`; інакше `PageRenderer` будує **новий** `app()` на кожен запит (так hot reload видно в наступній відповіді), загортає в `GrundScope(httpContext: c)` і рендерить через `renderComponent`. Відповідь Jaspr 500 — `PageRenderError` (500 problem+json через `ProblemResponder`, без деталі). Компоненти читають call-скоуп через `context.call<T>()`, `context.maybe<T>()`, `context.injector` (розширення `GrundContext`), cookie — через `GrundScope.of(context).cookies` (Jaspr-івський `context.cookies` кидає на зіпсованому заголовку). `onInit` модуля викликає `JasprSetup.ensureInitialized()`: друга програма в процесі не ініціалізує Jaspr удруге, а Jaspr, ініціалізований з `useIsolates: true`, — `JasprSetupError` до старту. API-маршрути виграють у `*` сторінок (літерал і `:param` старші), а `HEAD` обслуговується через `GET`. `JasprModule` не імпортує `HttpModule` («Рішення плану», п. 1). Приклад пакета — `example/grund_jaspr_example.dart`.

**Files:**
- Create: `packages/grund_jaspr/lib/src/{grund_scope,grund_context,jaspr_error,jaspr_setup,page_renderer,jaspr_pages,jaspr_module}.dart`, `packages/grund_jaspr/example/grund_jaspr_example.dart`
- Modify: `packages/grund_jaspr/lib/grund_jaspr.dart`
- Test: `packages/grund_jaspr/test/{jaspr_pages_test,jaspr_setup_test,example_test}.dart`, helpers `packages/grund_jaspr/test/helpers/{pages,pages_app}.dart`

**Interfaces:**
- Consumes: задача 7 (`JasprRequest.from`, `JasprResponse.from`), задача 8 (`StaticFiles`, `JasprConfig`); `HttpApi(Injector)`, `Route.get`, `NotFoundException(message:, code:)`, `StatusCode.internalServerError`, `GrundError`, `Module` (`imports`, `bindings`, `onInit`), `InheritedComponent`, `BuildContext.dependOnInheritedComponentOfExactType`, `renderComponent`, `Jaspr.initializeApp/isInitialized/useIsolates`.
- Produces:

```dart
sealed class JasprError extends GrundError { const JasprError(); }
final class PageRenderError extends JasprError { const PageRenderError({required String method, required String path}); }
final class JasprSetupError extends JasprError { const JasprSetupError(String reason); }
final class MissingGrundScopeError extends JasprError { const MissingGrundScopeError(); }
final class GrundScope extends InheritedComponent {
  const GrundScope({required HttpCtx httpContext, required Component child, Key? key});
  static HttpCtx of(BuildContext context); // MissingGrundScopeError поза сторінкою
}
extension GrundContext on BuildContext {
  Injector get injector; T call<T extends Object>([String? name]); T? maybe<T extends Object>([String? name]);
}
abstract final class JasprSetup { static void ensureInitialized(); } // поза barrel
final class PageRenderer { const PageRenderer(Component Function() app); Future<HttpResponse> render(HttpCtx c); } // поза barrel
final class JasprPages extends HttpApi { // поза barrel
  JasprPages(Injector injector, {required Component Function() app, JasprConfig config = const JasprConfig()});
}
final class JasprModule extends Module {
  const JasprModule({required Component Function() app, List<Module> imports = const [], JasprConfig config = const JasprConfig()});
}
```

`Key` у `GrundScope` — Jaspr-івський; файли, що імпортують і `package:grund/grund.dart`, пишуть `import 'package:jaspr/server.dart' hide Key;` (див. «Глобальні обмеження»).

- [ ] **Крок 1: Тестові помічники**

`pages.dart` — компоненти для тестів: `UrlPage` (URL, який побачив Jaspr), `CookiePage` (дві cookie і свій заголовок), `FeedPage` (XML зі своїм статусом), `BrokenPage` (кидає), `ServicePage` (DI і значення `VisitorHook`), `ScopelessPage` (читає контекст поза сторінкою), `FlashPage` (cookie через `GrundScope.of(context).cookies`); `pages_app.dart` — застосунок із `JasprModule` у процесі.

`packages/grund_jaspr/test/helpers/pages.dart` (файл цілком, 125 рядків):

```dart
import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart' hide Key;

/// Shows the URL Jaspr saw.
final class UrlPage extends StatelessComponent {
  const UrlPage();

  @override
  Component build(BuildContext context) =>
      Document(title: 'url', body: p([Component.text('url ${context.url}')]));
}

/// Sets two cookies and a header of its own.
final class CookiePage extends StatelessComponent {
  const CookiePage();

  @override
  Component build(BuildContext context) {
    context
      ..setCookie('a', '1')
      ..setCookie('b', '2')
      ..setHeader('x-page', 'yes');
    return Component.text('cookies');
  }
}

/// Answers XML with a status of its own.
final class FeedPage extends StatelessComponent {
  const FeedPage();

  @override
  Component build(BuildContext context) {
    context
      ..setHeader('content-type', 'application/xml')
      ..setHeader('Cache-Control', 'max-age=60')
      ..setStatusCode(203);
    return Component.text('feed');
  }
}

/// Throws while it is built.
final class BrokenPage extends StatelessComponent {
  const BrokenPage();

  @override
  Component build(BuildContext context) => throw StateError('secret detail');
}

/// A service a page reads from the call scope.
final class Greeter {
  /// The greeting.
  String greet() => 'hello from DI';
}

/// Exports [Greeter].
final class GreeterModule extends Module {
  const GreeterModule();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<Greeter>((_) => Greeter(), dependsOn: const []),
  ];

  @override
  List<Object> get exports => const [Key<Greeter>()];
}

/// A value a hook puts into the call scope.
final class Visitor {
  const Visitor(this.name);

  final String name;
}

/// Sets the [Visitor] named by the `x-visitor` header.
final class VisitorHook extends HttpHook {
  const VisitorHook();

  @override
  void before(HttpCtx c) {
    if (c.headers.stringOrNull('x-visitor') case final name?) {
      c.set<Visitor>(Visitor(name));
    }
  }
}

/// Greets through DI and names the visitor a hook set.
final class ServicePage extends StatelessComponent {
  const ServicePage();

  @override
  Component build(BuildContext context) => Component.text(
    '${context.call<Greeter>().greet()}, '
    '${context.maybe<Visitor>()?.name ?? 'nobody'}',
  );
}

/// Reads the grund context where there is none.
final class ScopelessPage extends StatelessComponent {
  const ScopelessPage();

  @override
  Component build(BuildContext context) {
    try {
      context.injector;
      return Component.text('scope');
    } on MissingGrundScopeError {
      return Component.text('no scope');
    }
  }
}

/// Reads the cookie `flash` through grund, which tolerates a malformed
/// `Cookie` header of another application on the same host.
final class FlashPage extends StatelessComponent {
  const FlashPage();

  @override
  Component build(BuildContext context) => Component.text(
    'flash ${GrundScope.of(context).cookies.stringOrNull('flash')}',
  );
}
```

`packages/grund_jaspr/test/helpers/pages_app.dart` (файл цілком, 34 рядків):

```dart
import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:grund_io/grund_io.dart';
import 'package:test/test.dart';

/// Starts an application of [modules] with the HTTP server ([use] as its
/// global hooks) and returns an in-process client; nothing listens.
abstract final class PagesApp {
  /// The client of the started application, closed after the test.
  static Future<TestClient> start(
    List<Module> modules, {
    List<HookRef<HttpHook>> use = const [],
  }) async {
    final app = await TestApp.start(root: _Root(modules, use));
    addTearDown(app.close);
    return TestClient.of(app);
  }
}

final class _Root extends Module {
  _Root(this._modules, this._use);

  final List<Module> _modules;
  final List<HookRef<HttpHook>> _use;

  @override
  List<Module> get imports => [
    HttpModule(use: _use),
    const IoAdapterModule(),
    ..._modules,
  ];
}
```

- [ ] **Крок 2: Падаючі тести**

`packages/grund_jaspr/test/jaspr_pages_test.dart` (файл цілком, 229 рядків):

```dart
import 'dart:io';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:test/test.dart';

import 'helpers/pages.dart';
import 'helpers/pages_app.dart';
import 'helpers/temp_dir.dart';

final class HelloApi extends HttpApi {
  HelloApi(super.injector);

  @override
  String get path => '/api';

  @override
  List<Route> get routes => [
    Route.get('/hello', (_) => {'hello': 'api'}),
  ];
}

final class ApiModule extends Module {
  const ApiModule();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<HelloApi>(HelloApi.new, dependsOn: const []),
  ];
}

void main() {
  test('GET / renders the page as UTF-8 HTML that is not cached', () async {
    final client = await PagesApp.start([const JasprModule(app: UrlPage.new)]);

    final response = await client.get('/');

    expect(response.status, 200);
    expect(response.headers['content-type'], 'text/html; charset=utf-8');
    expect(response.headers['cache-control'], 'private, no-cache');
    expect(response.text, contains('<html'));
    expect(response.text, contains('url /'));
  });

  test('a deep path and its query reach the page', () async {
    final client = await PagesApp.start([const JasprModule(app: UrlPage.new)]);

    final response = await client.get('/a/b?x=1&y=%20z');

    expect(response.text, contains('url /a/b?x=1&amp;y=%20z'));
  });

  test('cookies and headers a page sets reach the client', () async {
    final client = await PagesApp.start([
      const JasprModule(app: CookiePage.new),
    ]);

    final response = await client.get('/');

    expect(response.headers.all('set-cookie'), hasLength(2));
    expect(response.headers['x-page'], 'yes');
  });

  test(
    'a content type, status and cache header of the page are kept',
    () async {
      final client = await PagesApp.start([
        const JasprModule(app: FeedPage.new),
      ]);

      final response = await client.get('/feed.xml');

      expect(response.status, 203);
      expect(response.headers['content-type'], 'application/xml');
      expect(response.headers['cache-control'], 'max-age=60');
    },
  );

  test('a page that throws answers a 500 problem without the detail', () async {
    final client = await PagesApp.start([
      const JasprModule(app: BrokenPage.new),
    ]);

    final response = await client.get('/');

    expect(response.status, 500);
    expect(response.headers['content-type'], 'application/problem+json');
    expect(response.text, isNot(contains('secret detail')));
  });

  test('HEAD answers with the headers of GET', () async {
    final client = await PagesApp.start([const JasprModule(app: UrlPage.new)]);

    final response = await client.request('HEAD', '/');

    expect(response.status, 200);
    expect(response.headers['content-type'], 'text/html; charset=utf-8');
  });

  test('POST to a page is a 405', () async {
    final client = await PagesApp.start([const JasprModule(app: UrlPage.new)]);

    final response = await client.post('/');

    expect(response.status, 405);
  });

  test('a page reads DI and a value a global hook set', () async {
    final client = await PagesApp.start(
      [
        const JasprModule(app: ServicePage.new, imports: [GreeterModule()]),
      ],
      use: [HookRef.instance(const VisitorHook())],
    );

    final response = await client.get('/', headers: {'x-visitor': 'ann'});

    expect(response.text, contains('hello from DI, ann'));
  });

  test('an API route wins over the page catch-all', () async {
    final client = await PagesApp.start([
      const JasprModule(app: UrlPage.new),
      const ApiModule(),
    ]);

    final response = await client.get('/api/hello');

    expect(response.json, {'hello': 'api'});
  });

  test('a file of the static directory is served with its type', () async {
    final dir = TempDir.create();
    File('${dir.path}/app.css').writeAsStringSync('body{}');
    final client = await PagesApp.start([
      JasprModule(
        app: UrlPage.new,
        config: JasprConfig(staticDirectory: dir.path),
      ),
    ]);

    final response = await client.get('/app.css');

    expect(response.headers['content-type'], 'text/css; charset=utf-8');
    expect(response.text, 'body{}');
  });

  test('a missing non-page file is a 404, not a page', () async {
    final client = await PagesApp.start([const JasprModule(app: UrlPage.new)]);

    final response = await client.get('/missing.png');

    expect(response.status, 404);
    expect(response.json, containsPair('code', 'file_not_found'));
  });

  test('a path with a page suffix of the config is a page', () async {
    final client = await PagesApp.start([
      const JasprModule(
        app: UrlPage.new,
        config: JasprConfig(pageSuffixes: ['rss']),
      ),
    ]);

    final rss = await client.get('/feed.rss');
    final xml = await client.get('/feed.xml');

    expect(rss.status, 200);
    expect(rss.text, contains('url /feed.rss'));
    expect(xml.status, 404);
  });

  test('a malformed Cookie header does not break a page', () async {
    final client = await PagesApp.start([
      const JasprModule(app: FlashPage.new),
    ]);

    final response = await client.get(
      '/',
      headers: {'cookie': 'flash=yes; =; broken; a="b'},
    );

    expect(response.status, 200);
    expect(response.text, contains('flash yes'));
  });

  for (final target in [
    '/../pubspec.yaml',
    '/%2e%2e/pubspec.yaml',
    '/a/%2F..%2F..%2Fpubspec.yaml',
    '/.hidden',
    '/a%5C..%5Cx.css',
  ]) {
    test('$target never leaves the static directory', () async {
      final dir = TempDir.create();
      Directory('${dir.path}/web').createSync();
      File('${dir.path}/pubspec.yaml').writeAsStringSync('secret');
      File('${dir.path}/web/.hidden').writeAsStringSync('secret');
      final client = await PagesApp.start([
        JasprModule(
          app: UrlPage.new,
          config: JasprConfig(staticDirectory: '${dir.path}/web'),
        ),
      ]);

      final response = await client.get(target);

      expect(response.text, isNot(contains('secret')));
    });
  }

  test('a symlink out of the static directory is not served', () async {
    final dir = TempDir.create();
    Directory('${dir.path}/web').createSync();
    File('${dir.path}/secret.txt').writeAsStringSync('secret');
    Link('${dir.path}/web/link.txt').createSync('${dir.path}/secret.txt');
    final client = await PagesApp.start([
      JasprModule(
        app: UrlPage.new,
        config: JasprConfig(staticDirectory: '${dir.path}/web'),
      ),
    ]);

    final response = await client.get('/link.txt');

    expect(response.status, 404);
  });
}
```

`packages/grund_jaspr/test/jaspr_setup_test.dart` (файл цілком, 34 рядків):

```dart
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/server.dart';
import 'package:test/test.dart';

import 'helpers/pages.dart';
import 'helpers/pages_app.dart';

void main() {
  test('two applications in one process both render', () async {
    final first = await PagesApp.start([const JasprModule(app: UrlPage.new)]);
    final second = await PagesApp.start([const JasprModule(app: UrlPage.new)]);

    expect((await first.get('/')).status, 200);
    expect((await second.get('/')).status, 200);
  });

  test('a component outside a page has no grund context', () async {
    await PagesApp.start([const JasprModule(app: UrlPage.new)]);

    final rendered = await renderComponent(const ScopelessPage());

    expect(String.fromCharCodes(rendered.body), contains('no scope'));
  });

  test('Jaspr initialized with useIsolates refuses to start', () async {
    Jaspr.initializeApp(useIsolates: true);
    addTearDown(Jaspr.initializeApp);

    await expectLater(
      PagesApp.start([const JasprModule(app: UrlPage.new)]),
      throwsA(isA<JasprSetupError>()),
    );
  });
}
```

`packages/grund_jaspr/test/example_test.dart` (файл цілком, 12 рядків):

```dart
import 'package:test/test.dart';

import '../example/grund_jaspr_example.dart' as example;

void main() {
  test('the example renders a page with a value from DI', () {
    expect(
      example.renderTwice(),
      completion(['Visit number 1.', 'Visit number 2.']),
    );
  });
}
```

Run: `cd packages/grund_jaspr && dart test`
Expected: FAIL — помилка компіляції: `JasprModule`, `GrundScope`, `JasprSetupError` не визначено.

- [ ] **Крок 3: Помилки, скоуп і розширення**

`packages/grund_jaspr/lib/src/jaspr_error.dart` (файл цілком, 50 рядків):

```dart
import 'package:grund/grund.dart';

/// A failure of `grund_jaspr`: setting Jaspr up or rendering a page.
sealed class JasprError extends GrundError {
  /// Creates the error.
  const JasprError();
}

/// A page answered 500: a component threw while it was built (Jaspr printed
/// the error and its stack trace to stderr), or set the status 500 itself.
final class PageRenderError extends JasprError {
  /// Creates the error for the request [method] [path].
  const PageRenderError({required this.method, required this.path});

  /// The request method.
  final String method;

  /// The request path.
  final String path;

  @override
  String get message =>
      'The page $method $path failed to render: Jaspr answered 500. A '
      'component threw while it was built (Jaspr printed the error to '
      'stderr) or set the status 500.';
}

/// Jaspr is set up in a way `grund_jaspr` cannot render with.
final class JasprSetupError extends JasprError {
  /// Creates the error; [reason] says what is wrong and what to do.
  const JasprSetupError(this.reason);

  /// What is wrong and what to do.
  final String reason;

  @override
  String get message => 'Cannot render Jaspr pages: $reason';
}

/// A component asked for the grund context outside a page that
/// `JasprModule` renders.
final class MissingGrundScopeError extends JasprError {
  /// Creates the error.
  const MissingGrundScopeError();

  @override
  String get message =>
      'No GrundScope above this component: context.injector, context.call '
      'and context.maybe work only in pages that JasprModule renders.';
}
```

`packages/grund_jaspr/lib/src/grund_scope.dart` (файл цілком, 33 рядків):

```dart
import 'package:grund_http/grund_http.dart';
import 'package:jaspr/server.dart';

import 'jaspr_error.dart';

/// Holds the [HttpCtx] of the request a page is rendered for; `JasprModule`
/// puts it above the application's root component.
///
/// Components reach it through the `BuildContext` extension
/// (`context.call<T>()`) or [of].
final class GrundScope extends InheritedComponent {
  /// Makes [httpContext] available to [child] and its descendants.
  const GrundScope({
    required this.httpContext,
    required super.child,
    super.key,
  });

  /// The context of the request being rendered.
  final HttpCtx httpContext;

  /// The request context above [context]; throws [MissingGrundScopeError]
  /// outside a page that `JasprModule` renders.
  static HttpCtx of(BuildContext context) =>
      context
          .dependOnInheritedComponentOfExactType<GrundScope>()
          ?.httpContext ??
      (throw const MissingGrundScopeError());

  @override
  bool updateShouldNotify(GrundScope oldComponent) =>
      !identical(httpContext, oldComponent.httpContext);
}
```

`packages/grund_jaspr/lib/src/grund_context.dart` (файл цілком, 27 рядків):

````dart
import 'package:grund/grund.dart';
import 'package:jaspr/server.dart';

import 'grund_scope.dart';

/// The grund side of a page's [BuildContext]: the call scope of the request
/// it is rendered for, with the semantics of `HttpCtx`.
///
/// ```dart
/// final tasks = context.call<TasksService>().list();
/// final user = context.maybe<CurrentUser>();
/// ```
///
/// Each throws `MissingGrundScopeError` outside a page that `JasprModule`
/// renders.
extension GrundContext on BuildContext {
  /// The call scope: the bindings visible to `JasprModule`, plus the values
  /// hooks set for this request.
  Injector get injector => GrundScope.of(this).scope;

  /// The [T] (named [name]) of the call scope; throws when there is none.
  T call<T extends Object>([String? name]) => GrundScope.of(this).call<T>(name);

  /// The [T] (named [name]) of the call scope, or `null`.
  T? maybe<T extends Object>([String? name]) =>
      GrundScope.of(this).maybe<T>(name);
}
````

`packages/grund_jaspr/lib/src/jaspr_setup.dart` (файл цілком, 24 рядків):

```dart
import 'package:jaspr/server.dart';

import 'jaspr_error.dart';

/// Initializes Jaspr's process-wide state once, for every application of
/// the process.
abstract final class JasprSetup {
  /// Initializes Jaspr unless it is initialized already (by another
  /// application of the process, or by `main` with its own options); throws
  /// [JasprSetupError] when it was initialized to render in other isolates.
  static void ensureInitialized() {
    if (!Jaspr.isInitialized) {
      Jaspr.initializeApp();
      return;
    }
    if (Jaspr.useIsolates) {
      throw const JasprSetupError(
        'Jaspr was initialized with useIsolates: true. A page reads the call '
        'scope of its request, which another isolate cannot reach; call '
        'Jaspr.initializeApp() without useIsolates, or not at all.',
      );
    }
  }
}
```

- [ ] **Крок 4: Рендер, маршрути, модуль**

`packages/grund_jaspr/lib/src/page_renderer.dart` (файл цілком, 30 рядків):

```dart
import 'package:grund_http/grund_http.dart';
import 'package:jaspr/server.dart';

import 'grund_scope.dart';
import 'jaspr_error.dart';
import 'jaspr_request.dart';
import 'jaspr_response.dart';

/// Renders the page of one request: a new root component from [app] under
/// a [GrundScope], through Jaspr, into an [HttpResponse].
final class PageRenderer {
  /// Renders [app].
  const PageRenderer(this.app);

  /// Builds the root component; called for every request, so a hot reload
  /// shows in the next page.
  final Component Function() app;

  /// The page for [c]; throws [PageRenderError] when Jaspr answers 500.
  Future<HttpResponse> render(HttpCtx c) async {
    final rendered = await renderComponent(
      GrundScope(httpContext: c, child: app()),
      request: JasprRequest.from(c.request),
    );
    if (rendered.statusCode == StatusCode.internalServerError) {
      throw PageRenderError(method: c.request.method, path: c.request.uri.path);
    }
    return JasprResponse.from(rendered);
  }
}
```

`packages/grund_jaspr/lib/src/jaspr_pages.dart` (файл цілком, 52 рядків):

```dart
import 'package:grund_http/grund_http.dart';
import 'package:jaspr/server.dart';
import 'package:path/path.dart' as p;

import 'jaspr_config.dart';
import 'page_renderer.dart';
import 'static_files.dart';

/// The routes of the pages: `GET /` and `GET /*` (Jaspr's `HEAD` comes
/// with them), below every API route, since a literal or `:param` segment
/// wins over `*`.
///
/// A path that names a file of the static directory gets the file; a path
/// whose extension is not a page suffix is a 404 `file_not_found`; any
/// other path is a page rendered from [app].
final class JasprPages extends HttpApi {
  /// Serves the pages of [app] and the files of [config] in the module of
  /// [injector].
  JasprPages(
    super.injector, {
    required Component Function() app,
    JasprConfig config = const JasprConfig(),
  }) : _renderer = PageRenderer(app),
       _files = StaticFiles(config.staticDirectory),
       _pageSuffixes = config.pageSuffixes;

  final PageRenderer _renderer;
  final StaticFiles _files;
  final List<String> _pageSuffixes;

  @override
  List<Route> get routes => [Route.get('/', _serve), Route.get('/*', _serve)];

  Future<HttpResponse> _serve(HttpCtx c) async {
    final segments = c.request.uri.pathSegments;
    if (_files.find(segments) case final file?) return _files.respond(file);
    if (!_isPage(segments)) {
      throw NotFoundException(
        message: 'There is no file ${c.request.uri.path}.',
        code: 'file_not_found',
      );
    }
    return _renderer.render(c);
  }

  bool _isPage(List<String> segments) {
    if (segments.isEmpty) return true;
    final extension = p.extension(segments.last);
    return extension.isEmpty ||
        _pageSuffixes.contains(extension.substring(1).toLowerCase());
  }
}
```

`packages/grund_jaspr/lib/src/jaspr_module.dart` (файл цілком, 54 рядків):

````dart
import 'package:grund/grund.dart';
import 'package:jaspr/server.dart';

import 'jaspr_config.dart';
import 'jaspr_pages.dart';
import 'jaspr_setup.dart';

/// Server-side rendered pages of the Jaspr component [app], served by the
/// application's `HttpModule` next to its APIs.
///
/// ```dart
/// final class AppModule extends Module {
///   const AppModule();
///
///   @override
///   List<Module> get imports => const [
///     HttpModule(),
///     IoAdapterModule(),
///     JasprModule(app: HomePage.new, imports: [TasksModule()]),
///   ];
/// }
/// ```
///
/// It does not import `HttpModule`: the application imports it once, with
/// its own hooks and configuration. Pages see the exports of [imports] and
/// of global modules through `context.call<T>()`.
final class JasprModule extends Module {
  /// Serves [app] with [config]; components see the exports of [imports].
  const JasprModule({
    required this.app,
    this.imports = const [],
    this.config = const JasprConfig(),
  });

  /// Builds the root component of a page; called for every request.
  final Component Function() app;

  @override
  final List<Module> imports;

  /// The static directory and the page suffixes.
  final JasprConfig config;

  @override
  List<Binding<Object>> get bindings => [
    Singleton<JasprPages>(
      (i) => JasprPages(i, app: app, config: config),
      dependsOn: const [],
    ),
  ];

  @override
  void onInit(Injector injector) => JasprSetup.ensureInitialized();
}
````

`packages/grund_jaspr/lib/grund_jaspr.dart` (зміни):

```diff
--- a/packages/grund_jaspr/lib/grund_jaspr.dart
+++ b/packages/grund_jaspr/lib/grund_jaspr.dart
@@ -3,4 +3,8 @@
 /// lifecycle.
 library;
 
+export 'src/grund_context.dart';
+export 'src/grund_scope.dart';
 export 'src/jaspr_config.dart';
+export 'src/jaspr_error.dart';
+export 'src/jaspr_module.dart';
```

- [ ] **Крок 5: Приклад пакета**

`packages/grund_jaspr/example/grund_jaspr_example.dart` (файл цілком, 75 рядків):

```dart
import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:grund_io/grund_io.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart' hide Key;

/// Counts the pages served; one instance for the application.
final class VisitCounter {
  int _visits = 0;

  /// Counts one more visit and returns the total.
  int visit() => ++_visits;
}

/// Exports [VisitCounter] to the pages.
final class CounterModule extends Module {
  /// Creates the module.
  const CounterModule();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<VisitCounter>((_) => VisitCounter(), dependsOn: const []),
  ];

  @override
  List<Object> get exports => const [Key<VisitCounter>()];
}

/// The page: the visit count, read from DI.
final class HomePage extends StatelessComponent {
  /// Creates the page.
  const HomePage();

  @override
  Component build(BuildContext context) => Document(
    title: 'grund_jaspr',
    body: p([
      Component.text('Visit number ${context.call<VisitCounter>().visit()}.'),
    ]),
  );
}

/// The root module: the HTTP server over dart:io and the pages.
final class AppModule extends Module {
  /// Creates the module.
  const AppModule();

  @override
  List<Module> get imports => const [
    HttpModule(),
    IoAdapterModule(),
    JasprModule(app: HomePage.new, imports: [CounterModule()]),
  ];
}

/// Renders `GET /` twice in process and returns the two paragraphs.
Future<List<String>> renderTwice() async {
  final app = await TestApp.start(root: const AppModule());
  try {
    final client = TestClient.of(app);
    return [
      for (var visit = 0; visit < 2; visit++)
        RegExp('<p>(.*)</p>').firstMatch((await client.get('/')).text)?[1] ??
            '',
    ];
  } finally {
    await app.close();
  }
}

/// Serves the page on port 8080 until Ctrl+C.
Future<void> main() => App(root: const AppModule()).run();
```

- [ ] **Крок 6: Тести**

Run: `cd packages/grund_jaspr && dart test` → `+49: All tests passed!` (`jaspr_pages_test` 19 — серед них «cookies and headers a page sets reach the client» (RF4), «$target never leaves the static directory» і «a symlink out of the static directory is not served» (RF3 через справжній router), «an API route wins over the page catch-all», «HEAD answers with the headers of GET», «POST to a page is a 405», «a malformed Cookie header does not break a page»; `jaspr_setup_test` 3; `example_test` 1).

- [ ] **Крок 7: Перевірки і коміт**

Run: `dart analyze` → `No issues found!`; `dart format packages example` → `(0 changed)`; `wc -l packages/grund_jaspr/lib/src/*.dart` — усі < 100.

```bash
git add \
  packages/grund_jaspr/example/grund_jaspr_example.dart \
  packages/grund_jaspr/lib/grund_jaspr.dart \
  packages/grund_jaspr/lib/src/grund_context.dart \
  packages/grund_jaspr/lib/src/grund_scope.dart \
  packages/grund_jaspr/lib/src/jaspr_error.dart \
  packages/grund_jaspr/lib/src/jaspr_module.dart \
  packages/grund_jaspr/lib/src/jaspr_pages.dart \
  packages/grund_jaspr/lib/src/jaspr_setup.dart \
  packages/grund_jaspr/lib/src/page_renderer.dart \
  packages/grund_jaspr/test/example_test.dart \
  packages/grund_jaspr/test/helpers/pages.dart \
  packages/grund_jaspr/test/helpers/pages_app.dart \
  packages/grund_jaspr/test/jaspr_pages_test.dart \
  packages/grund_jaspr/test/jaspr_setup_test.dart
git commit -m "feat(jaspr): add JasprModule, GrundScope and the BuildContext extension" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git show --stat --format=%s HEAD   # 14 файлів, лише ці
```

---
### Задача 10: `example/` — SSR-сторінки і вхід через сесію на обох адаптерах

**Мета:** застосунок `tasks_api` отримує сторінки поряд з API в обох графах (анотації і явний API), на `dart:io` і shelf. `WebModule(tasks)` (явний API в обох графах: `JasprModule(app:)` бере функцію) імпортує `SessionModule(config: SessionConfig(secure: false))` (приклад працює через plain `http`) і `JasprModule(app: TasksSite.new, imports: [tasks])`, прив'язує `LoginApi`. `TasksSite` вибирає сторінку за `context.url`: `/` — `HomePage` (задачі з `TasksService`, хто увійшов, форма виходу, одноразова flash-cookie), `/login` — `LoginPage` (форма з ім'ям), інше — 404 сторінки сайту. `LoginApi`: `POST /login` читає `c.form()`, викликає `Sessions.start` і повертає 303 на `/` **з власною** cookie `flash` (RF4/RF5: обидві `set-cookie` доходять); `POST /logout` — `Sessions.end` і 303. `SessionHook` зареєстровано глобально в `ServingModule` поряд з `TimingHook`. `TasksModule` і `ExplicitTasksModule` експортують `TasksService`.

У прикладі вже є свій `CurrentUser` (власник API-ключа), тож `home_page.dart` імпортує `grund_auth` з префіксом: `import 'package:grund_auth/grund_auth.dart' as auth;` і читає `context.maybe<auth.CurrentUser>()`.

Наявний e2e-тест `GET /nowhere → 404 route_not_found` змінюється на `DELETE /nowhere → 405`: `GET` будь-якого шляху тепер сторінка («Рішення плану», п. 12). Тестовий клієнт `LoopbackServer.send` отримує `form:` і не йде за редиректом, `ApiResponse` — список `setCookies`.

**Files:**
- Create: `example/lib/src/web/{web_module,login_api,tasks_site,home_page,login_page}.dart`, `example/web/styles.css`
- Modify: `example/pubspec.yaml`, `example/lib/{tasks_api,explicit}.dart`, `example/lib/src/app_module.dart`, `example/lib/src/tasks/tasks_module.dart`, `example/lib/src/server/serving_module.dart`, згенеровані `example/lib/src/app_module.g.dart`, `example/lib/src/tasks/tasks_module.g.dart` (`grund_cli gen`), `example/README.md`
- Test: `example/test/web_e2e_test.dart`; Modify: `example/test/e2e_test.dart`, `example/test/helpers/{api_response,loopback_server}.dart`

**Interfaces:**
- Consumes: задача 2 (`c.form()`, `StatusCode.seeOther`, злиття `set-cookie`), задачі 3–6 (`SessionModule`, `SessionConfig`, `Sessions.start/end`, `SessionHook`, `SetCookie`, `CookieAttributes`, `CurrentUser`), задача 9 (`JasprModule`, `GrundScope.of`, `context.call/maybe`); у прикладі — `TasksService.list()`, `ServingModule`, `AdapterKind`, `LoopbackServer`.
- Produces (експортує `package:tasks_api/tasks_api.dart`):

```dart
final class WebModule extends Module { const WebModule(Module tasks); }
final class LoginApi extends HttpApi { LoginApi(Injector injector, Sessions sessions); } // POST /login, POST /logout
final class TasksSite extends StatelessComponent { const TasksSite(); }
final class HomePage extends StatelessComponent { const HomePage(); }
final class LoginPage extends StatelessComponent { const LoginPage(); }
```

- [ ] **Крок 1: Залежності прикладу**

`example/pubspec.yaml` (зміни):

```diff
--- a/example/pubspec.yaml
+++ b/example/pubspec.yaml
@@ -10,9 +10,12 @@ resolution: workspace
 
 dependencies:
   grund: ^0.1.0
+  grund_auth: ^0.1.0
   grund_http: ^0.1.0
   grund_io: ^0.1.0
+  grund_jaspr: ^0.1.0
   grund_shelf: ^0.1.0
+  jaspr: '>=0.23.5 <0.24.0'
 
 dev_dependencies:
   dart_style: ^3.1.2
```

Run: `dart pub get` (з кореня) → `Got dependencies!`.

- [ ] **Крок 2: Тестовий клієнт форм і cookie**

`example/test/helpers/api_response.dart` (зміни):

```diff
--- a/example/test/helpers/api_response.dart
+++ b/example/test/helpers/api_response.dart
@@ -3,7 +3,12 @@ import 'dart:convert';
 /// A response read whole by `LoopbackServer.send`.
 final class ApiResponse {
   /// Creates the response.
-  ApiResponse(this.status, this.headers, this.body);
+  ApiResponse(
+    this.status,
+    this.headers,
+    this.body, {
+    this.setCookies = const [],
+  });
 
   /// The status code.
   final int status;
@@ -11,6 +16,9 @@ final class ApiResponse {
   /// The first value of every header, by lowercase name.
   final Map<String, String> headers;
 
+  /// Every `set-cookie` value, in order.
+  final List<String> setCookies;
+
   /// The body as text.
   final String body;
 
```

`example/test/helpers/loopback_server.dart` (зміни):

```diff
--- a/example/test/helpers/loopback_server.dart
+++ b/example/test/helpers/loopback_server.dart
@@ -59,30 +59,40 @@ final class LoopbackServer {
   final LogSubscription _logOutput;
   final HttpClient _client = HttpClient();
 
-  /// Sends [method] to [target] with [headers] and [json] as the body;
-  /// reads the whole response.
+  /// Sends [method] to [target] with [headers] and [json] or the form
+  /// fields [form] (already encoded) as the body; reads the whole response
+  /// and does not follow a redirect.
   Future<ApiResponse> send(
     String method,
     String target, {
     Map<String, String> headers = const {},
     Object? json,
+    String? form,
   }) async {
     final request = await _client.openUrl(
       method,
       Uri.parse('http://127.0.0.1:$port$target'),
     );
+    request.followRedirects = false;
     headers.forEach(request.headers.set);
     if (json != null) {
       request.headers.contentType = ContentType.json;
       request.write(jsonEncode(json));
     }
+    if (form != null) {
+      request.headers.contentType = _formType;
+      request.write(form);
+    }
     final response = await request.close();
     final body = await utf8.decodeStream(response);
     final first = <String, String>{};
     response.headers.forEach((name, values) => first[name] = values.first);
-    return ApiResponse(response.statusCode, first, body);
+    final cookies = response.headers[HttpHeaders.setCookieHeader] ?? const [];
+    return ApiResponse(response.statusCode, first, body, setCookies: cookies);
   }
 
+  static final _formType = ContentType('application', 'x-www-form-urlencoded');
+
   /// Closes the client and the application.
   Future<void> close() async {
     _client.close(force: true);
```

- [ ] **Крок 3: Падаючі тести**

`example/test/web_e2e_test.dart` (файл цілком, 132 рядків):

```dart
// The pages and the session on the same four servers as e2e_test.dart:
// pages rendered with data from DI, a static file, sign-in through a form
// with both cookies over the wire, and sign-out.
import 'package:tasks_api/tasks_api.dart';
import 'package:test/test.dart';

import 'helpers/api_response.dart';
import 'helpers/loopback_server.dart';

void main() {
  for (final style in ModuleStyle.values) {
    for (final kind in AdapterKind.values) {
      group('${style.name} on ${kind.name}', () => _suite(style, kind));
    }
  }
}

void _suite(ModuleStyle style, AdapterKind kind) {
  late LoopbackServer server; // Set in setUp before every test.
  setUp(() async => server = await LoopbackServer.start(style, kind));
  tearDown(() async {
    await server.close();
    expect(server.errors, isEmpty);
  });

  _pages(() => server);
  _session(() => server);
}

/// Pages and files without a session.
void _pages(LoopbackServer Function() server) {
  test('GET / renders the tasks of the service as HTML', () async {
    final page = await server().send('GET', '/');

    expect(page.status, 200);
    expect(page.headers['content-type'], 'text/html; charset=utf-8');
    expect(page.headers['cache-control'], 'private, no-cache');
    expect(page.body, contains('<li>Read the grund README</li>'));
    expect(page.body, contains('href="/login"'));
  });

  test('the stylesheet is served from web/', () async {
    final css = await server().send('GET', '/styles.css');

    expect(css.status, 200);
    expect(css.headers['content-type'], 'text/css; charset=utf-8');
  });

  test('a path without a page is the 404 of the site', () async {
    final page = await server().send('GET', '/nowhere');

    expect(page.status, 404);
    expect(page.body, contains('No page here.'));
  });
}

/// Signing in and out through the forms.
void _session(LoopbackServer Function() server) {
  Future<ApiResponse> signIn(String name) =>
      server().send('POST', '/login', form: 'name=$name');

  test('signing in sets the session and the flash cookie (RF4, RF5)', () async {
    final login = await signIn('ann');

    expect(login.status, 303);
    expect(login.headers['location'], '/');
    expect(login.setCookies, hasLength(2));
    expect(
      login.setCookies,
      contains(
        matches(
          RegExp(
            r'^grund_sid=[A-Za-z0-9_-]{43}; Max-Age=604800; Path=/; '
            r'HttpOnly; SameSite=Lax$',
          ),
        ),
      ),
    );
    expect(login.setCookies, contains(startsWith('flash=signed-in; ')));
  });

  test('the next page sees the user and shows the flash once', () async {
    final cookie = _cookieHeader(await signIn('ann'));

    final home = await server().send('GET', '/', headers: {'cookie': cookie});

    expect(home.body, contains('Signed in as ann.'));
    expect(home.body, contains('class="flash"'));
    expect(home.setCookies, contains(startsWith('flash=; ')));
  });

  test('the name is escaped in the page', () async {
    final login = await signIn('%3Cb%3Eann');

    final home = await server().send(
      'GET',
      '/',
      headers: {'cookie': _cookieHeader(login)},
    );

    expect(home.body, contains('&lt;b&gt;ann'));
    expect(home.body, isNot(contains('<b>ann')));
  });

  test('signing out ends the session', () async {
    final cookie = {'cookie': _cookieHeader(await signIn('ann'))};

    final logout = await server().send('POST', '/logout', headers: cookie);
    final home = await server().send('GET', '/', headers: cookie);

    expect(logout.status, 303);
    expect(logout.setCookies, contains(startsWith('grund_sid=; Max-Age=0; ')));
    expect(home.body, isNot(contains('Signed in as')));
  });

  test('a form posted from another site is refused', () async {
    final login = await server().send(
      'POST',
      '/login',
      form: 'name=ann',
      headers: {'sec-fetch-site': 'cross-site'},
    );

    expect(login.status, 403);
    expect(login.setCookies, isEmpty);
  });
}

/// The `cookie` header a browser sends after [response]: the name and value
/// of every cookie it set.
String _cookieHeader(ApiResponse response) =>
    response.setCookies.map((cookie) => cookie.split(';').first).join('; ');
```

`example/test/e2e_test.dart` (зміни):

```diff
--- a/example/test/e2e_test.dart
+++ b/example/test/e2e_test.dart
@@ -44,10 +44,11 @@ void _public(LoopbackServer Function() server) {
       '/health',
       headers: {'x-request-id': 'abc'},
     );
-    final unrouted = await server().send('GET', '/nowhere');
+    // GET of any path is a page now; no route answers DELETE /nowhere.
+    final unrouted = await server().send('DELETE', '/nowhere');
 
     expect(own.headers['x-request-id'], 'abc');
-    expect(unrouted.status, 404);
+    expect(unrouted.status, 405);
     expect(unrouted.headers['content-type'], contains('problem+json'));
     expect(unrouted.headers['x-request-id'], startsWith('req-'));
   });
```

Run: `cd example && dart test test/web_e2e_test.dart`
Expected: FAIL — `GET /` у прикладі ще 404 (`route_not_found`), `POST /login` — 404.

- [ ] **Крок 4: Сторінки і вхід**

`example/lib/src/web/login_api.dart` (файл цілком, 42 рядків):

```dart
import 'package:grund_auth/grund_auth.dart';
import 'package:grund_http/grund_http.dart';

/// Signs a visitor in and out; the forms of the pages post here.
///
/// The example trusts the name it is given. A real application checks a
/// password or another credential before [Sessions.start].
final class LoginApi extends HttpApi {
  /// Starts and ends sessions through [_sessions].
  LoginApi(super.injector, this._sessions);

  final Sessions _sessions;

  @override
  List<Route> get routes => [
    Route.post('/login', _login),
    Route.post('/logout', _logout),
  ];

  Future<HttpResponse> _login(HttpCtx c) async {
    final name = (await c.form()).string('name', minLength: 1, maxLength: 40);
    await _sessions.start(c, name);
    // The handler's own cookie travels next to the session cookie.
    final flash = SetCookie(
      'flash',
      'signed-in',
      attributes: const CookieAttributes(
        maxAge: Duration(minutes: 1),
        secure: false,
      ),
    );
    return HttpResponse(
      StatusCode.seeOther,
      headers: HeaderMap.of({'location': '/', 'set-cookie': flash.toHeader()}),
    );
  }

  Future<HttpResponse> _logout(HttpCtx c) async {
    await _sessions.end(c);
    return HttpResponse.redirect(Uri.parse('/'), status: StatusCode.seeOther);
  }
}
```

`example/lib/src/web/home_page.dart` (файл цілком, 50 рядків):

```dart
import 'package:grund_auth/grund_auth.dart' as auth;
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import '../tasks/tasks_service.dart';

/// The task list, who is signed in, and the form to sign out.
final class HomePage extends StatelessComponent {
  /// Creates the page.
  const HomePage();

  @override
  Component build(BuildContext context) {
    final tasks = context.call<TasksService>().list();
    // grund_auth's CurrentUser, not the example's own (the API key's).
    final user = context.maybe<auth.CurrentUser>();
    return Document(
      title: 'Tasks',
      head: [link(href: '/styles.css', rel: 'stylesheet')],
      body: main_([
        if (_takeFlash(context))
          p(classes: 'flash', [Component.text('Signed in.')]),
        h1([Component.text('Tasks')]),
        ul([
          for (final task in tasks)
            li([
              Component.text(task.done ? '${task.title} (done)' : task.title),
            ]),
        ]),
        if (user == null)
          a(href: '/login', [Component.text('Sign in')])
        else
          form(action: '/logout', method: FormMethod.post, [
            Component.text('Signed in as ${user.id}. '),
            button(type: ButtonType.submit, [Component.text('Sign out')]),
          ]),
      ]),
    );
  }

  // Read through grund: Jaspr's context.cookies throws on a malformed
  // cookie of another application on the same host.
  static bool _takeFlash(BuildContext context) {
    final flash = GrundScope.of(context).cookies.stringOrNull('flash');
    if (flash == null) return false;
    context.setCookie('flash', '', maxAge: 0, path: '/');
    return flash == 'signed-in';
  }
}
```

`example/lib/src/web/login_page.dart` (файл цілком, 22 рядків):

```dart
import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

/// The sign-in form; it posts the name to `LoginApi`.
final class LoginPage extends StatelessComponent {
  /// Creates the page.
  const LoginPage();

  @override
  Component build(BuildContext context) => Document(
    title: 'Sign in',
    head: [link(href: '/styles.css', rel: 'stylesheet')],
    body: main_([
      h1([Component.text('Sign in')]),
      form(action: '/login', method: FormMethod.post, [
        label(htmlFor: 'name', [Component.text('Name ')]),
        input(id: 'name', name: 'name', type: InputType.text),
        button(type: ButtonType.submit, [Component.text('Sign in')]),
      ]),
    ]),
  );
}
```

`example/lib/src/web/tasks_site.dart` (файл цілком, 24 рядків):

```dart
import 'package:grund_http/grund_http.dart';
import 'package:jaspr/server.dart';

import 'home_page.dart';
import 'login_page.dart';

/// The root component of the pages: picks the page for the path.
final class TasksSite extends StatelessComponent {
  /// Creates the site.
  const TasksSite();

  @override
  Component build(BuildContext context) {
    switch (Uri.parse(context.url).path) {
      case '/':
        return const HomePage();
      case '/login':
        return const LoginPage();
      default:
        context.setStatusCode(StatusCode.notFound);
        return Component.text('No page here.');
    }
  }
}
```

`example/lib/src/web/web_module.dart` (файл цілком, 36 рядків):

```dart
import 'package:grund/grund.dart';
import 'package:grund_auth/grund_auth.dart';
import 'package:grund_jaspr/grund_jaspr.dart';

import 'login_api.dart';
import 'tasks_site.dart';

/// The pages of the tasks application and the session they share with the
/// API: [SessionModule], [LoginApi] and the Jaspr pages of [TasksSite],
/// which read the services [tasks] exports.
///
/// Written with the explicit API in both graphs: `JasprModule(app:)` takes
/// a function, which an annotation cannot hold.
final class WebModule extends Module {
  /// The pages over the tasks module [tasks].
  const WebModule(this.tasks);

  /// `TasksModule` or `ExplicitTasksModule`.
  final Module tasks;

  @override
  List<Module> get imports => [
    // Plain http in the example; keep the default secure: true in an
    // application served over HTTPS.
    const SessionModule(config: SessionConfig(secure: false)),
    JasprModule(app: TasksSite.new, imports: [tasks]),
  ];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<LoginApi>(
      (i) => LoginApi(i, i<Sessions>()),
      dependsOn: const [Key<Sessions>()],
    ),
  ];
}
```

`example/web/styles.css` (файл цілком, 2 рядків):

```css
body { font-family: system-ui, sans-serif; margin: 2rem auto; max-width: 40rem; }
.flash { background: #e6f4ea; padding: 0.5rem 1rem; }
```

- [ ] **Крок 5: Графи, сервер, експорти**

`example/lib/src/app_module.dart` (зміни):

```diff
--- a/example/lib/src/app_module.dart
+++ b/example/lib/src/app_module.dart
@@ -5,10 +5,18 @@ import 'app_module.g.dart';
 import 'config/config_module.dart';
 import 'health/health_module.dart';
 import 'tasks/tasks_module.dart';
+import 'web/web_module.dart';
 
 /// The application: what it does, not how it is served. `ServingModule`
 /// adds the HTTP server and the adapter around it.
-@Module(imports: [ConfigModule(), TasksModule(), HealthModule()])
+@Module(
+  imports: [
+    ConfigModule(),
+    TasksModule(),
+    HealthModule(),
+    WebModule(TasksModule()),
+  ],
+)
 final class AppModule extends grund.Module with $AppModule {
   /// Creates the module.
   const AppModule();
```

`example/lib/src/tasks/tasks_module.dart` (зміни):

```diff
--- a/example/lib/src/tasks/tasks_module.dart
+++ b/example/lib/src/tasks/tasks_module.dart
@@ -9,7 +9,8 @@ import 'tasks_api.dart';
 import 'tasks_module.g.dart';
 import 'tasks_service.dart';
 
-/// Tasks: the store, the service, the API and its error hook.
+/// Tasks: the store, the service, the API and its error hook; the pages
+/// read [TasksService].
 @Module(
   imports: [AuthModule()],
   providers: [
@@ -18,6 +19,7 @@ import 'tasks_service.dart';
     TaskNotFoundHook,
     TasksApi,
   ],
+  exports: [TasksService],
 )
 final class TasksModule extends grund.Module with $TasksModule {
   /// Creates the module.
```

`example/lib/explicit.dart` (зміни):

```diff
--- a/example/lib/explicit.dart
+++ b/example/lib/explicit.dart
@@ -110,6 +110,9 @@ final class ExplicitTasksModule extends Module {
       dependsOn: const [Key<TasksApi>()],
     ),
   ];
+
+  @override
+  List<Object> get exports => const [Key<TasksService>()];
 }
 
 /// The health check, with an inline `HttpApi`.
@@ -152,5 +155,6 @@ final class ExplicitAppModule extends Module {
     ExplicitConfigModule(),
     ExplicitTasksModule(),
     ExplicitHealthModule(),
+    WebModule(ExplicitTasksModule()),
   ];
 }
```

`example/lib/src/server/serving_module.dart` (зміни):

```diff
--- a/example/lib/src/server/serving_module.dart
+++ b/example/lib/src/server/serving_module.dart
@@ -1,4 +1,5 @@
 import 'package:grund/grund.dart';
+import 'package:grund_auth/grund_auth.dart' show SessionHook;
 import 'package:grund_http/grund_http.dart';
 import 'package:grund_io/grund_io.dart';
 import 'package:grund_shelf/grund_shelf.dart';
@@ -43,7 +44,10 @@ final class ServingModule extends Module {
       AdapterKind.shelf => ShelfAdapterModule(onError: onError),
     },
     HttpModule(
-      use: const [HookRef<TimingHook>.instance(TimingHook())],
+      use: const [
+        HookRef<TimingHook>.instance(TimingHook()),
+        HookRef<SessionHook>.type(),
+      ],
       middleware: [RequestIdMiddleware()],
       config: HttpConfig(address: address, port: port),
     ),
```

`example/lib/tasks_api.dart` (зміни):

```diff
--- a/example/lib/tasks_api.dart
+++ b/example/lib/tasks_api.dart
@@ -32,3 +32,8 @@ export 'src/tasks/tasks_api.dart';
 export 'src/tasks/tasks_module.dart';
 export 'src/tasks/tasks_service.dart';
 export 'src/tasks/update_task.dart';
+export 'src/web/home_page.dart';
+export 'src/web/login_api.dart';
+export 'src/web/login_page.dart';
+export 'src/web/tasks_site.dart';
+export 'src/web/web_module.dart';
```

- [ ] **Крок 6: Перегенерувати**

Run: `cd example && dart run grund_cli gen`
Expected: переписано два файли; `git diff --stat example/lib/src/app_module.g.dart example/lib/src/tasks/tasks_module.g.dart` показує рівно ці зміни (не редагувати вручну):

`example/lib/src/app_module.g.dart` (зміни):

```diff
--- a/example/lib/src/app_module.g.dart
+++ b/example/lib/src/app_module.g.dart
@@ -7,6 +7,7 @@ import 'package:grund/grund.dart' as grund;
 import 'package:tasks_api/src/config/config_module.dart' as i1;
 import 'package:tasks_api/src/health/health_module.dart' as i3;
 import 'package:tasks_api/src/tasks/tasks_module.dart' as i2;
+import 'package:tasks_api/src/web/web_module.dart' as i4;
 
 /// The generated declarations of `AppModule`.
 mixin $AppModule on grund.Module {
@@ -15,5 +16,6 @@ mixin $AppModule on grund.Module {
     i1.ConfigModule(),
     i2.TasksModule(),
     i3.HealthModule(),
+    i4.WebModule(i2.TasksModule()),
   ];
 }
```

`example/lib/src/tasks/tasks_module.g.dart` (зміни):

```diff
--- a/example/lib/src/tasks/tasks_module.g.dart
+++ b/example/lib/src/tasks/tasks_module.g.dart
@@ -39,4 +39,7 @@ mixin $TasksModule on grund.Module {
       dependsOn: const [grund.Key<i6.TasksApi>()],
     ),
   ];
+
+  @override
+  List<Object> get exports => const [grund.Key<i4.TasksService>()];
 }
```

- [ ] **Крок 7: README прикладу**

`example/README.md` (зміни):

````diff
--- a/example/README.md
+++ b/example/README.md
@@ -4,7 +4,9 @@ A small tasks API that uses every part of grund: modules with imports,
 exports and a global module, a `@Provides` method, an interface bound to an
 implementation (`Bind`), `HttpApi` classes with typed path, query and body
 readers, `HttpHook`s (by type and by instance, per route, per API and
-global), a middleware, both adapters and hot reload.
+global), a middleware, both adapters and hot reload. Next to the API it
+serves HTML pages rendered on the server by Jaspr (`grund_jaspr`) and a
+cookie session (`grund_auth`) that the pages and the API share.
 
 The same application is wired twice:
 
@@ -47,6 +49,19 @@ curl -X DELETE -H 'x-api-key: editor-key' localhost:8080/tasks/3
 Errors are `application/problem+json` (RFC 9457): a `status`, a `detail`, a
 stable `code` and, for a bad body, `errors` with a JSON `pointer`.
 
+Open `http://localhost:8080/` in a browser: the page lists the tasks of
+`TasksService` (the same singleton the API changes), links to a sign-in
+form, and after signing in shows who is signed in and a sign-out button.
+
+```sh
+curl localhost:8080/                       # the HTML page
+curl -i -d 'name=ann' localhost:8080/login # 303 with the session cookie
+```
+
+The example trusts the name it is given; a real application checks a
+password before `Sessions.start`. The session cookie is not `Secure` here
+(`SessionConfig(secure: false)`): the example serves plain `http`.
+
 | Request | Answer |
 | --- | --- |
 | `GET /health` | `{"status": "ok", "name": "tasks_api"}`, no key needed |
@@ -71,6 +86,11 @@ stable `code` and, for a bad body, `errors` with a JSON `pointer`.
 | Adapter choice | `lib/src/server/serving_module.dart`, `bin/main.dart` |
 | The generated glue | `lib/src/**/*.g.dart` |
 | The explicit-API twin | `lib/explicit.dart` |
+| Jaspr pages reading DI and the session | `lib/src/web/tasks_site.dart`, `home_page.dart`, `login_page.dart` |
+| Sign-in and sign-out with `Sessions`, a cookie of the handler's own | `lib/src/web/login_api.dart` |
+| `JasprModule`, `SessionModule` (explicit in both graphs) | `lib/src/web/web_module.dart` |
+| The `SessionHook`, global | `lib/src/server/serving_module.dart` |
+| Static files | `web/styles.css` |
 
 ## Generated files
 
@@ -120,6 +140,9 @@ dart test
 ```
 
 - `test/e2e_test.dart`: both graphs on both adapters, over loopback.
+- `test/web_e2e_test.dart`: the pages, the stylesheet, sign-in with both
+  cookies, sign-out and a refused cross-site form, on the same four
+  servers.
 - `test/in_process_test.dart`: `TestApp` and `TestClient`, no socket.
 - `test/tasks_service_test.dart`: the service alone, and a test module
   with a fake store.
````

- [ ] **Крок 8: Тести**

Run: `cd example && dart test test/web_e2e_test.dart` → `+32: All tests passed!` (8 тестів × `dart:io`/shelf × анотації/явний API; серед них «signing in sets the session and the flash cookie (RF4, RF5)» через справжній сокет на обох адаптерах, «the name is escaped in the page», «a form posted from another site is refused»).
Run: `cd example && dart test` → `+90: All tests passed!` (золотий тест згенерованих файлів зелений: `.g.dart` збігаються з виводом `gen`).

- [ ] **Крок 9: Перевірки і коміт**

Run: `dart analyze` → `No issues found!`; `dart format packages example` → `(0 changed)`; `wc -l example/lib/src/web/*.dart` — усі < 60.

```bash
git add \
  example/README.md \
  example/lib/explicit.dart \
  example/lib/src/app_module.dart \
  example/lib/src/app_module.g.dart \
  example/lib/src/server/serving_module.dart \
  example/lib/src/tasks/tasks_module.dart \
  example/lib/src/tasks/tasks_module.g.dart \
  example/lib/src/web/home_page.dart \
  example/lib/src/web/login_api.dart \
  example/lib/src/web/login_page.dart \
  example/lib/src/web/tasks_site.dart \
  example/lib/src/web/web_module.dart \
  example/lib/tasks_api.dart \
  example/pubspec.yaml \
  example/test/e2e_test.dart \
  example/test/helpers/api_response.dart \
  example/test/helpers/loopback_server.dart \
  example/test/web_e2e_test.dart \
  example/web/styles.css
git commit -m "feat(example): Jaspr pages and a session next to the tasks API" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git show --stat --format=%s HEAD   # 19 файлів, лише ці
```

---
### Задача 11: `grund_cli init --template fullstack`

**Мета:** `grund init --template fullstack my_site` створює застосунок зі сторінками й сесіями, написаний явним API (без генерації): `AppModule` з `HttpModule(use: [HookRef<SessionHook>.type()])`, `IoAdapterModule`, `SessionModule` (`secure` лише в product-збірці, «Рішення плану», п. 13), `JasprModule(app: Site.new)`; `AccountApi` (`POST /login`, `POST /logout`), `Site`/`HomePage`/`LoginPage`, `web/styles.css`, `test/app_test.dart` (`TestApp` + `TestClient`, без сокета). `--template api` (за замовчуванням) — попередній шаблон без змін. Задача з двох комітів: 11a — рефакторинг без зміни поведінки (шаблон названо `ProjectKind`, список залежностей, які не можна взяти назвою пакета, переїхав з `ReservedNames` у `ProjectKind.dependencies`, аналіз пакета в тестах — у помічник `DartDiagnostics`); 11b — сам шаблон і опція.

Шаблон називає `grund_http: ^0.1.1` (йому потрібні `c.form()` і злиття `set-cookie`), `grund_auth: ^0.1.0`, `grund_jaspr: ^0.1.0`, `jaspr: '>=0.23.5 <0.24.0'`: такий пакет розв'язується з pub.dev лише після релізу цих версій (див. «Що не перевірено»). Тести тому не роблять `pub get`: модульний тест аналізує згенеровані файли проти workspace (`WorkspacePackageConfig`), інтеграційний — запускає `test/app_test.dart` нового пакета самою VM («Рішення плану», п. 14).

**Files:**
- Create: `packages/grund_cli/lib/src/init/project_kind.dart` (11a), `packages/grund_cli/lib/src/init/fullstack_template.dart` (11b), `packages/grund_cli/test/helpers/dart_diagnostics.dart` (11a)
- Modify: `packages/grund_cli/lib/src/init/{project_scaffold,reserved_names}.dart` (11a), `packages/grund_cli/lib/src/cli/init_command.dart`, `packages/grund_cli/CHANGELOG.md` (11b)
- Test: `packages/grund_cli/test/init_command_test.dart` (11a), `packages/grund_cli/test/init_fullstack_test.dart`, `packages/grund_cli/integration/init_fullstack_test.dart` (11b)

**Interfaces:**
- Consumes: наявні `ProjectTemplate.files(name)`, `ProjectTemplate.grundVersion`, `ProjectScaffold`, `ReservedNames`, `InitCommand`, `CliRun`, `TempDir`, `WorkspacePackageConfig.write(root, name)`; задачі 2–9 — API, яке використовує згенерований код.
- Produces:

```dart
enum ProjectKind {
  api('A JSON API written with annotations.'),
  fullstack('Server-rendered Jaspr pages with cookie sessions.'); // 11b
  final String summary;                     // 11b
  Map<String, String> files(String name);
  Set<String> get dependencies;
  List<String> get nextSteps;               // 11b
}
ProjectScaffold(String directory, {ProjectKind kind = ProjectKind.api, void Function(File, String)? writeFile});
static String? ReservedNames.reasonFor(String name, Set<String> dependencies);
abstract final class FullstackTemplate { static Map<String, String> files(String name); } // 11b
abstract final class DartDiagnostics { static Future<List<String>> of(String root); } // test/helpers
// init: --template <api|fullstack>, за замовчуванням api
```

#### 11a. Рефакторинг: `ProjectKind`

- [ ] **Крок 1: Помічник аналізу і тест, що вже є**

Винести `_analyze` з `init_command_test.dart` у `test/helpers/dart_diagnostics.dart` і перевести тест імен на новий `ReservedNames.reasonFor(name, dependencies)` (`jaspr` — ім'я, яке шаблон `api` не використовує):

`packages/grund_cli/test/helpers/dart_diagnostics.dart` (файл цілком, 31 рядків):

```dart
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/error/error.dart';
import 'package:test/test.dart';

/// What the analyzer reports for a package that `init` wrote.
abstract final class DartDiagnostics {
  /// Errors and warnings of the Dart files of [root]'s `lib/`, `bin/` and
  /// `test/`; infos are dropped.
  static Future<List<String>> of(String root) async {
    final collection = AnalysisContextCollection(includedPaths: [root]);
    addTearDown(collection.dispose);
    final files = [
      for (final directory in ['lib', 'bin', 'test'])
        for (final entity in Directory(
          '$root/$directory',
        ).listSync(recursive: true))
          if (entity.path.endsWith('.dart')) entity.path,
    ];
    return [
      for (final file in files)
        if (await collection.contextFor(file).currentSession.getErrors(file)
            case final ErrorsResult result)
          for (final diagnostic in result.diagnostics)
            if (diagnostic.diagnosticCode.severity != DiagnosticSeverity.INFO)
              '$file: ${diagnostic.message}',
    ];
  }
}
```

`packages/grund_cli/test/init_command_test.dart` (зміни):

```diff
--- a/packages/grund_cli/test/init_command_test.dart
+++ b/packages/grund_cli/test/init_command_test.dart
@@ -1,39 +1,17 @@
 import 'dart:io';
 
-import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
-import 'package:analyzer/dart/analysis/results.dart';
-import 'package:analyzer/error/error.dart';
 import 'package:grund_cli/grund_cli.dart';
 import 'package:grund_cli/src/cli/shell_word.dart';
+import 'package:grund_cli/src/init/project_kind.dart';
 import 'package:grund_cli/src/init/project_scaffold.dart';
 import 'package:grund_cli/src/init/reserved_names.dart';
 import 'package:test/test.dart';
 
 import 'helpers/cli_run.dart';
+import 'helpers/dart_diagnostics.dart';
 import 'helpers/temp_dir.dart';
 import 'helpers/workspace_package_config.dart';
 
-/// Errors and warnings of the Dart files of [root]'s `lib/` and `bin/`.
-Future<List<String>> _analyze(String root) async {
-  final collection = AnalysisContextCollection(includedPaths: [root]);
-  addTearDown(collection.dispose);
-  final files = [
-    for (final directory in ['lib', 'bin', 'test'])
-      for (final entity in Directory(
-        '$root/$directory',
-      ).listSync(recursive: true))
-        if (entity.path.endsWith('.dart')) entity.path,
-  ];
-  return [
-    for (final file in files)
-      if (await collection.contextFor(file).currentSession.getErrors(file)
-          case final ErrorsResult result)
-        for (final diagnostic in result.diagnostics)
-          if (diagnostic.diagnosticCode.severity != DiagnosticSeverity.INFO)
-            '$file: ${diagnostic.message}',
-  ];
-}
-
 void main() {
   test('init writes an application that generates and analyzes', () async {
     final dir = TempDir.create();
@@ -58,8 +36,8 @@ void main() {
     expect(gen.out, startsWith('Generated 2 files in '));
     expect(dir.exists('my_app/lib/src/app_module.g.dart'), isTrue);
     expect(dir.exists('my_app/lib/src/hello.g.dart'), isTrue);
-    expect(await _analyze(target), isEmpty);
-    // `_analyze` drops infos, the severity of `implementation_imports`.
+    expect(await DartDiagnostics.of(target), isEmpty);
+    // `DartDiagnostics` drops infos, the severity of `implementation_imports`.
     final generated = dir.read('my_app/lib/src/app_module.g.dart');
     expect(
       RegExp(r"import 'package:(?!my_app/)\w+/src/").hasMatch(generated),
@@ -115,8 +93,11 @@ void main() {
   }
 
   test('init accepts the names of packages the template does not use', () {
-    for (final name in ['grund_conformance', 'grund_generator']) {
-      expect(ReservedNames.reasonFor(name), isNull);
+    for (final name in ['grund_conformance', 'grund_generator', 'jaspr']) {
+      expect(
+        ReservedNames.reasonFor(name, ProjectKind.api.dependencies),
+        isNull,
+      );
     }
   });
 
```

Run: `cd packages/grund_cli && dart test test/init_command_test.dart`
Expected: FAIL — помилка компіляції: `project_kind.dart` не існує, `reasonFor` бере один аргумент.

- [ ] **Крок 2: Рефакторинг**

`packages/grund_cli/lib/src/init/project_kind.dart` (файл цілком, 26 рядків):

```dart
import 'project_template.dart';

/// Which application `init` writes.
enum ProjectKind {
  /// A JSON API written with annotations.
  api;

  /// The files of application [name] (relative path to content), sorted by
  /// path.
  Map<String, String> files(String name) => switch (this) {
    ProjectKind.api => ProjectTemplate.files(name),
  };

  /// The packages the new pubspec names; the new package cannot take one
  /// of these names.
  Set<String> get dependencies => switch (this) {
    ProjectKind.api => const {
      'grund',
      'grund_cli',
      'grund_http',
      'grund_io',
      'lints',
      'test',
    },
  };
}
```

`packages/grund_cli/lib/src/init/project_scaffold.dart` (зміни):

```diff
--- a/packages/grund_cli/lib/src/init/project_scaffold.dart
+++ b/packages/grund_cli/lib/src/init/project_scaffold.dart
@@ -5,20 +5,26 @@ import 'package:path/path.dart' as p;
 import '../cli/cli_exit_code.dart';
 import '../cli/cli_failure.dart';
 import '../package/package_root.dart';
-import 'project_template.dart';
+import 'project_kind.dart';
 import 'reserved_names.dart';
 
-/// Writes a new application from [ProjectTemplate] into an empty or new
+/// Writes a new application of a [ProjectKind] into an empty or new
 /// directory; the directory name is the package name.
 final class ProjectScaffold {
   /// Creates the scaffold of [directory]; [writeFile] replaces the file
   /// write (a seam for failure tests).
-  ProjectScaffold(String directory, {void Function(File, String)? writeFile})
-    : directory = p.normalize(p.absolute(directory)),
-      _writeFile = writeFile ?? _write;
+  ProjectScaffold(
+    String directory, {
+    this.kind = ProjectKind.api,
+    void Function(File, String)? writeFile,
+  }) : directory = p.normalize(p.absolute(directory)),
+       _writeFile = writeFile ?? _write;
 
   final void Function(File, String) _writeFile;
 
+  /// The application this scaffold writes.
+  final ProjectKind kind;
+
   /// Absolute path of the new package.
   final String directory;
 
@@ -38,7 +44,7 @@ final class ProjectScaffold {
         'lowercase_with_underscores.',
       );
     }
-    final reason = ReservedNames.reasonFor(name);
+    final reason = ReservedNames.reasonFor(name, kind.dependencies);
     if (reason != null) {
       throw CliFailure(
         CliExitCode.usage,
@@ -47,7 +53,7 @@ final class ProjectScaffold {
     }
     final existed = _checkEmpty();
     final topmostNew = existed ? null : _topmostMissing();
-    final files = ProjectTemplate.files(name);
+    final files = kind.files(name);
     for (final MapEntry(key: path, value: content) in files.entries) {
       final file = File(p.joinAll([directory, ...path.split('/')]));
       try {
```

`packages/grund_cli/lib/src/init/reserved_names.dart` (зміни):

```diff
--- a/packages/grund_cli/lib/src/init/reserved_names.dart
+++ b/packages/grund_cli/lib/src/init/reserved_names.dart
@@ -1,9 +1,10 @@
 /// Names a new package cannot have.
 abstract final class ReservedNames {
-  /// Why [name] cannot name a new package, or `null` when it can.
-  static String? reasonFor(String name) {
+  /// Why [name] cannot name a new package whose pubspec names
+  /// [dependencies], or `null` when it can.
+  static String? reasonFor(String name, Set<String> dependencies) {
     if (_reservedWords.contains(name)) return 'a Dart reserved word';
-    if (_dependencies.contains(name)) {
+    if (dependencies.contains(name)) {
       return 'a dependency of the new package';
     }
     return null;
@@ -44,13 +45,4 @@ abstract final class ReservedNames {
     'while',
     'with',
   };
-
-  static const _dependencies = {
-    'grund',
-    'grund_http',
-    'grund_cli',
-    'grund_io',
-    'lints',
-    'test',
-  };
 }
```

- [ ] **Крок 3: Тести, перевірки, коміт**

Run: `cd packages/grund_cli && dart test test/init_command_test.dart` → `+14: All tests passed!`; `dart test` → `+155: All tests passed!` (як до рефакторингу).
Run: `dart analyze` → `No issues found!`; `dart format packages example` → `(0 changed)`.

```bash
git add \
  packages/grund_cli/lib/src/init/project_kind.dart \
  packages/grund_cli/lib/src/init/project_scaffold.dart \
  packages/grund_cli/lib/src/init/reserved_names.dart \
  packages/grund_cli/test/helpers/dart_diagnostics.dart \
  packages/grund_cli/test/init_command_test.dart
git commit -m "refactor(cli): name the init scaffold by a ProjectKind" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git show --stat --format=%s HEAD   # 5 файлів, лише ці
```

#### 11b. Шаблон `fullstack`

- [ ] **Крок 4: Падаючі тести**

`packages/grund_cli/test/init_fullstack_test.dart` (файл цілком, 83 рядків):

```dart
import 'package:grund_cli/grund_cli.dart';
import 'package:test/test.dart';

import 'helpers/cli_run.dart';
import 'helpers/dart_diagnostics.dart';
import 'helpers/temp_dir.dart';
import 'helpers/workspace_package_config.dart';

void main() {
  test('init --template fullstack writes pages that analyze', () async {
    final dir = TempDir.create();
    final target = dir.resolve('my_site');

    final init = await CliRun.run(['init', '--template', 'fullstack', target]);
    await WorkspacePackageConfig.write(target, 'my_site');

    expect(init.exitCode, 0, reason: init.err);
    expect(init.out, contains('  lib/src/pages/home_page.dart\n'));
    expect(init.out, contains('  web/styles.css\n'));
    expect(init.out, endsWith('  dart pub get\n  dart run grund_cli dev\n'));
    final pubspec = dir.read('my_site/pubspec.yaml');
    expect(pubspec, contains('  grund_auth: ^0.1.0\n'));
    expect(pubspec, contains('  grund_http: ^0.1.1\n'));
    expect(pubspec, contains('  grund_jaspr: ^0.1.0\n'));
    expect(pubspec, contains("  jaspr: '>=0.23.5 <0.24.0'\n"));
    expect(await DartDiagnostics.of(target), isEmpty);
  });

  test('init without --template still writes the annotated API', () async {
    final dir = TempDir.create();

    final run = await CliRun.run(['init', dir.resolve('my_app')]);

    expect(run.exitCode, 0, reason: run.err);
    expect(dir.exists('my_app/lib/src/hello.dart'), isTrue);
    expect(dir.exists('my_app/web/styles.css'), isFalse);
  });

  test(
    'init --template fullstack rejects the name of a package it adds',
    () async {
      final dir = TempDir.create();

      final run = await CliRun.run([
        'init',
        '--template',
        'fullstack',
        dir.resolve('jaspr'),
      ]);

      expect(run.exitCode, CliExitCode.usage.code);
      expect(run.err, contains('a dependency of the new package'));
      expect(dir.exists('jaspr'), isFalse);
    },
  );

  test('init refuses a template it does not know', () async {
    final dir = TempDir.create();

    final run = await CliRun.run([
      'init',
      '--template',
      'mobile',
      dir.resolve('my_app'),
    ]);

    expect(run.exitCode, CliExitCode.usage.code);
    expect(run.err, contains('"mobile" is not an allowed value'));
    expect(dir.exists('my_app'), isFalse);
  });

  test('the help of init names every template', () async {
    final run = await CliRun.run(['init', '--help']);

    expect(run.out, contains('[api] (default)'));
    expect(run.out, contains('A JSON API written with annotations.'));
    expect(run.out, contains('[fullstack]'));
    expect(
      run.out,
      contains('Server-rendered Jaspr pages with cookie sessions.'),
    );
  });
}
```

`packages/grund_cli/integration/init_fullstack_test.dart` (файл цілком, 29 рядків):

```dart
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:test/test.dart';

import '../test/helpers/cli_run.dart';
import '../test/helpers/temp_dir.dart';
import '../test/helpers/workspace_package_config.dart';

void main() {
  test('the tests of a new fullstack application pass', () async {
    final dir = TempDir.create();
    final target = dir.resolve('my_site');
    final init = await CliRun.run(['init', '--template', 'fullstack', target]);
    expect(init.exitCode, 0, reason: init.err);
    await WorkspacePackageConfig.write(target, 'my_site');

    // The VM runs the test file directly: `dart test` would resolve the
    // new package with `pub get`, and tests do not touch the network.
    final run = await Process.run(Platform.resolvedExecutable, [
      'test/app_test.dart',
    ], workingDirectory: target);

    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
    expect(run.stdout, contains('All tests passed!'));
  });
}
```

Run: `cd packages/grund_cli && dart test test/init_fullstack_test.dart`
Expected: FAIL — `init` не знає опції `--template` (код виходу 64, помилка використання).

- [ ] **Крок 5: Шаблон**

`fullstack_template.dart` — плаский каталог вмісту файлів без логіки (виняток із ліміту довжини методу, як і наявний `project_template.dart`; позначено в doc класу).

`packages/grund_cli/lib/src/init/fullstack_template.dart` (файл цілком, 270 рядків):

```dart
import 'project_template.dart';

/// The files of a new fullstack application (`init --template fullstack`):
/// Jaspr pages rendered on the server, cookie sessions and a sign-in API,
/// written with the explicit API (no code generation).
///
/// A flat catalog of file contents without logic.
abstract final class FullstackTemplate {
  /// The files of application [name] (relative path to content), sorted by
  /// path.
  ///
  /// [name] is interpolated into the files as is: it must be a valid Dart
  /// package name (`[a-z_][a-z0-9_]*`), which `ProjectScaffold` checks.
  static Map<String, String> files(String name) => {
    '.gitignore': '.dart_tool/\n',
    'analysis_options.yaml': 'include: package:lints/recommended.yaml\n',
    'bin/main.dart': _main(name),
    'lib/src/account_api.dart': _accountApi,
    'lib/src/app_module.dart': _appModule,
    'lib/src/pages/home_page.dart': _homePage,
    'lib/src/pages/login_page.dart': _loginPage,
    'lib/src/pages/site.dart': _site,
    'pubspec.yaml': _pubspec(name),
    'test/app_test.dart': _appTest(name),
    'web/styles.css': _styles,
  };

  static const _grund = ProjectTemplate.grundVersion;

  // `HttpCtx.form` and the `set-cookie` merge arrived in grund_http 0.1.1.
  static const _grundHttp = '^0.1.1';

  static String _pubspec(String name) =>
      '''
name: $name
description: A grund application with server-rendered Jaspr pages.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.8.0

dependencies:
  grund: $_grund
  grund_auth: $_grund
  grund_http: $_grundHttp
  grund_io: $_grund
  grund_jaspr: $_grund
  jaspr: '>=0.23.5 <0.24.0'

dev_dependencies:
  grund_cli: $_grund
  lints: ^5.1.0
  test: ^1.25.0
''';

  static String _main(String name) =>
      '''
import 'package:grund/grund.dart';
import 'package:$name/src/app_module.dart';

/// Serves the pages and the API until Ctrl+C. Run it from the package
/// root: the static files are read from `web/`.
Future<void> main(List<String> arguments) async {
  await App(root: const AppModule()).run(only: Runners.fromArgs(arguments));
}
''';

  static const _appModule = '''
import 'package:grund/grund.dart';
import 'package:grund_auth/grund_auth.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_io/grund_io.dart';
import 'package:grund_jaspr/grund_jaspr.dart';

import 'account_api.dart';
import 'pages/site.dart';

/// The root module: the HTTP server over dart:io, cookie sessions, the
/// sign-in API and the pages.
final class AppModule extends Module {
  /// Creates the module.
  const AppModule();

  // A Secure cookie needs HTTPS; `dart run` serves plain http, a product
  // build (`dart compile exe`) is expected behind HTTPS.
  static const _isProduct = bool.fromEnvironment('dart.vm.product');

  @override
  List<Module> get imports => const [
    HttpModule(use: [HookRef<SessionHook>.type()]),
    IoAdapterModule(),
    SessionModule(config: SessionConfig(secure: _isProduct)),
    JasprModule(app: Site.new),
  ];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<AccountApi>(
      (i) => AccountApi(i, i<Sessions>()),
      dependsOn: const [Key<Sessions>()],
    ),
  ];
}
''';

  static const _accountApi = '''
import 'package:grund_auth/grund_auth.dart';
import 'package:grund_http/grund_http.dart';

/// Signs a visitor in and out; the forms of the pages post here.
final class AccountApi extends HttpApi {
  /// Starts and ends sessions through [_sessions].
  AccountApi(super.injector, this._sessions);

  final Sessions _sessions;

  @override
  List<Route> get routes => [
    Route.post('/login', _login),
    Route.post('/logout', _logout),
  ];

  Future<HttpResponse> _login(HttpCtx c) async {
    final name = (await c.form()).string('name', minLength: 1, maxLength: 40);
    // Check a password or another credential here before signing in.
    await _sessions.start(c, name);
    return HttpResponse.redirect(Uri.parse('/'), status: StatusCode.seeOther);
  }

  Future<HttpResponse> _logout(HttpCtx c) async {
    await _sessions.end(c);
    return HttpResponse.redirect(Uri.parse('/'), status: StatusCode.seeOther);
  }
}
''';

  static const _site = '''
import 'package:jaspr/server.dart';

import 'home_page.dart';
import 'login_page.dart';

/// The root component of every page: picks the page for the path.
final class Site extends StatelessComponent {
  /// Creates the site.
  const Site();

  @override
  Component build(BuildContext context) {
    switch (Uri.parse(context.url).path) {
      case '/':
        return const HomePage();
      case '/login':
        return const LoginPage();
      default:
        context.setStatusCode(404);
        return Component.text('No page here.');
    }
  }
}
''';

  static const _homePage = '''
import 'package:grund_auth/grund_auth.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

/// The start page: who is signed in, and how to sign in or out.
final class HomePage extends StatelessComponent {
  /// Creates the page.
  const HomePage();

  @override
  Component build(BuildContext context) {
    final user = context.maybe<CurrentUser>();
    return Document(
      title: 'Home',
      head: [link(href: '/styles.css', rel: 'stylesheet')],
      body: main_([
        h1([Component.text('Hello from grund and Jaspr')]),
        if (user == null)
          a(href: '/login', [Component.text('Sign in')])
        else
          form(action: '/logout', method: FormMethod.post, [
            Component.text('Signed in as \${user.id}. '),
            button(type: ButtonType.submit, [Component.text('Sign out')]),
          ]),
      ]),
    );
  }
}
''';

  static const _loginPage = '''
import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

/// The sign-in form; it posts the name to `AccountApi`.
final class LoginPage extends StatelessComponent {
  /// Creates the page.
  const LoginPage();

  @override
  Component build(BuildContext context) => Document(
    title: 'Sign in',
    head: [link(href: '/styles.css', rel: 'stylesheet')],
    body: main_([
      h1([Component.text('Sign in')]),
      form(action: '/login', method: FormMethod.post, [
        label(htmlFor: 'name', [Component.text('Name ')]),
        input(id: 'name', name: 'name', type: InputType.text),
        button(type: ButtonType.submit, [Component.text('Sign in')]),
      ]),
    ]),
  );
}
''';

  static const _styles = '''
body { font-family: system-ui, sans-serif; margin: 2rem auto; max-width: 40rem; }
''';

  // `TestApp` never makes the io adapter listen, so the test needs no socket.
  static String _appTest(String name) =>
      '''
import 'package:grund/testing.dart';
import 'package:grund_http/testing.dart';
import 'package:$name/src/app_module.dart';
import 'package:test/test.dart';

void main() {
  late TestApp app;
  late TestClient client;

  setUp(() async {
    app = await TestApp.start(root: const AppModule());
    client = TestClient.of(app);
  });
  tearDown(() => app.close());

  test('GET / renders the start page', () async {
    final page = await client.get('/');

    expect(page.status, 200);
    expect(page.headers['content-type'], 'text/html; charset=utf-8');
    expect(page.text, contains('Sign in'));
  });

  test('signing in sets the session cookie; the page sees the user', () async {
    final login = await client.request(
      'POST',
      '/login',
      body: 'name=ann',
      headers: {'content-type': 'application/x-www-form-urlencoded'},
    );
    final cookie = login.headers['set-cookie'] ?? '';
    final page = await client.get(
      '/',
      headers: {'cookie': cookie.split(';').first},
    );

    expect(login.status, 303);
    expect(cookie, contains('HttpOnly'));
    expect(page.text, contains('Signed in as ann.'));
  });
}
''';
}
```

`packages/grund_cli/lib/src/init/project_kind.dart` (зміни):

```diff
--- a/packages/grund_cli/lib/src/init/project_kind.dart
+++ b/packages/grund_cli/lib/src/init/project_kind.dart
@@ -1,14 +1,25 @@
+import 'fullstack_template.dart';
 import 'project_template.dart';
 
-/// Which application `init` writes.
+/// Which application `init` writes (`--template`).
 enum ProjectKind {
-  /// A JSON API written with annotations.
-  api;
+  /// A JSON API written with annotations; the default.
+  api('A JSON API written with annotations.'),
+
+  /// Server-rendered Jaspr pages with cookie sessions, written with the
+  /// explicit API.
+  fullstack('Server-rendered Jaspr pages with cookie sessions.');
+
+  const ProjectKind(this.summary);
+
+  /// One line for `init --help`.
+  final String summary;
 
   /// The files of application [name] (relative path to content), sorted by
   /// path.
   Map<String, String> files(String name) => switch (this) {
     ProjectKind.api => ProjectTemplate.files(name),
+    ProjectKind.fullstack => FullstackTemplate.files(name),
   };
 
   /// The packages the new pubspec names; the new package cannot take one
@@ -22,5 +33,25 @@ enum ProjectKind {
       'lints',
       'test',
     },
+    ProjectKind.fullstack => const {
+      'grund',
+      'grund_auth',
+      'grund_cli',
+      'grund_http',
+      'grund_io',
+      'grund_jaspr',
+      'jaspr',
+      'lints',
+      'test',
+    },
+  };
+
+  /// The commands `init` suggests after `dart pub get`.
+  List<String> get nextSteps => switch (this) {
+    ProjectKind.api => const [
+      'dart run grund_cli gen',
+      'dart run bin/main.dart',
+    ],
+    ProjectKind.fullstack => const ['dart run grund_cli dev'],
   };
 }
```

- [ ] **Крок 6: Опція `--template`**

`packages/grund_cli/lib/src/cli/init_command.dart` (зміни):

```diff
--- a/packages/grund_cli/lib/src/cli/init_command.dart
+++ b/packages/grund_cli/lib/src/cli/init_command.dart
@@ -1,14 +1,26 @@
 import 'package:args/command_runner.dart';
 
+import '../init/project_kind.dart';
 import '../init/project_scaffold.dart';
 import 'cli_exit_code.dart';
 import 'grund_cli.dart';
 import 'shell_word.dart';
 
-/// `init <directory>`: scaffolds a new application.
+/// `init [--template <name>] <directory>`: scaffolds a new application of a
+/// [ProjectKind].
 final class InitCommand extends Command<int> {
   /// Creates the command of [cli].
-  InitCommand(this.cli);
+  InitCommand(this.cli) {
+    argParser.addOption(
+      'template',
+      allowed: [for (final kind in ProjectKind.values) kind.name],
+      allowedHelp: {
+        for (final kind in ProjectKind.values) kind.name: kind.summary,
+      },
+      defaultsTo: ProjectKind.api.name,
+      help: 'What the new application is.',
+    );
+  }
 
   /// The command line this command belongs to.
   final GrundCli cli;
@@ -21,7 +33,7 @@ final class InitCommand extends Command<int> {
       'Creates a grund application in a new or empty directory.';
 
   @override
-  String get invocation => 'grund_cli init <directory>';
+  String get invocation => 'grund_cli init [--template <name>] <directory>';
 
   @override
   void printUsage() => cli.out.writeln(usage);
@@ -33,7 +45,10 @@ final class InitCommand extends Command<int> {
       usageException('init takes exactly one directory.');
     }
     final target = options.rest.single;
-    final scaffold = ProjectScaffold(target);
+    final kind = ProjectKind.values.byName(
+      options.option('template') ?? ProjectKind.api.name,
+    );
+    final scaffold = ProjectScaffold(target, kind: kind);
     final files = scaffold.write();
     cli.out
       ..writeln('Created package ${scaffold.name} in ${scaffold.directory}:')
@@ -41,8 +56,7 @@ final class InitCommand extends Command<int> {
       ..writeln('Next:')
       ..writeln('  cd ${ShellWord.quote(target)}')
       ..writeln('  dart pub get')
-      ..writeln('  dart run grund_cli gen')
-      ..writeln('  dart run bin/main.dart');
+      ..writeAll([for (final step in kind.nextSteps) '  $step\n']);
     return CliExitCode.success.code;
   }
 }
```

`packages/grund_cli/CHANGELOG.md` (зміни):

```diff
--- a/packages/grund_cli/CHANGELOG.md
+++ b/packages/grund_cli/CHANGELOG.md
@@ -1,3 +1,10 @@
+## 0.1.2
+
+- `init --template fullstack` scaffolds server-rendered Jaspr pages with
+  cookie sessions (`grund_jaspr`, `grund_auth`), a sign-in form, a
+  stylesheet in `web/` and tests; `--template api` (the default) is the
+  previous scaffold.
+
 ## 0.1.1
 
 - `init` scaffolds a `test/` directory with a smoke test and the `test` dev dependency.
```

- [ ] **Крок 7: Тести**

Run: `cd packages/grund_cli && dart test test/init_fullstack_test.dart` → `+5: All tests passed!`; `dart test` → `+160: All tests passed!`.
Run: `cd packages/grund_cli && dart test integration/init_fullstack_test.dart` → `+1: All tests passed!` (тести нового застосунку проходять: стартова сторінка, вхід ставить cookie сесії, сторінка бачить користувача).

- [ ] **Крок 8: Перевірки і коміт**

Run: `dart analyze` → `No issues found!`; `dart format packages example` → `(0 changed)`; `wc -l packages/grund_cli/lib/src/init/fullstack_template.dart` → 270.

```bash
git add \
  packages/grund_cli/CHANGELOG.md \
  packages/grund_cli/integration/init_fullstack_test.dart \
  packages/grund_cli/lib/src/cli/init_command.dart \
  packages/grund_cli/lib/src/init/fullstack_template.dart \
  packages/grund_cli/lib/src/init/project_kind.dart \
  packages/grund_cli/test/init_fullstack_test.dart
git commit -m "feat(cli): init --template fullstack" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git show --stat --format=%s HEAD   # 6 файлів, лише ці
```

---
### Задача 12: Автооновлення відкритих сторінок у `grund dev`

**Мета (spec 4.6, доповнення `fbf37cb`):** після успішного hot reload з reassemble і після того, як перезапущений процес знову обслуговує, відкриті в браузері сторінки перезавантажуються самі. `grund dev` піднімає `LiveReloadHub` — точку server-sent events на `127.0.0.1` і ефемерному порту, що переживає перезапуски застосунку й закривається разом з `dev` (RF7), — і передає її адресу дочірньому процесу у змінній `GRUND_LIVE_RELOAD_URL`. `grund_jaspr` (лише поза product-збіркою і лише коли змінна є) вставляє перед останнім `</body>` кожної HTML-сторінки скрипт `new EventSource(url)` з `location.reload()` на подію `reload`; адреса — JSON-рядок з екранованим `<`, тож не закриває ні рядок, ні елемент (RF6). Статичні файли, не-HTML відповіді і застосунки без `grund_jaspr` нічого не отримують.

Відкинуті варіанти (spec 4.6): SSE-точка в самому застосунку (потрібне нове API ядра, а з'єднання рветься на кожному перезапуску процесу) і проксі `jaspr serve` (його HotReloader повторно запускає `main`). Нового API в ядрі `grund` немає.

Задача з чотирьох комітів: 12a — рефакторинг (командний рядок застосунку як значення `AppCommand`), 12b — тестовий рефакторинг (помічники інтеграційного `dev_test.dart` у `integration/helpers/dev_run.dart`, щоб їх ділив новий `dev_jaspr_test.dart`), 12c — точка SSE і проводка в `grund_cli`, 12d — скрипт у `grund_jaspr` і наскрізний інтеграційний тест.

**Files:**
- Create: `packages/grund_cli/lib/src/dev/app_command.dart` (12a), `packages/grund_cli/integration/helpers/dev_run.dart` (12b), `packages/grund_cli/lib/src/dev/live_reload_hub.dart` (12c), `packages/grund_jaspr/lib/src/live_reload_script.dart` (12d)
- Modify: `packages/grund_cli/lib/src/dev/{app_launcher,app_process,dev_target,dev_session}.dart` (12a, 12c), `packages/grund_cli/lib/src/dev/{reload_client,reload_timeouts}.dart`, `packages/grund_cli/lib/src/cli/dev_command.dart`, `packages/grund_cli/CHANGELOG.md` (12c), `packages/grund_jaspr/lib/src/{jaspr_config,page_renderer,jaspr_pages,jaspr_module}.dart` (12d)
- Test: `packages/grund_cli/test/{app_process_test,reload_client_test,reload_client_timeouts_test}.dart`, `packages/grund_cli/test/helpers/failing_launcher.dart` (12a, 12c); `packages/grund_cli/integration/dev_test.dart` (12b); `packages/grund_cli/test/{live_reload_hub_test,dev_session_serving_test,dev_live_reload_test}.dart`, `packages/grund_cli/test/helpers/{dev,event_client}.dart` (12c); `packages/grund_jaspr/test/{live_reload_script_test,live_reload_pages_test}.dart`, `packages/grund_cli/integration/{dev_jaspr_test.dart,helpers/site_sources.dart}` (12d)

**Interfaces:**
- Consumes: задача 9 (`JasprPages`, `PageRenderer`, `JasprModule`, `JasprSetupError`), задача 8 (`JasprConfig`), задача 7 (`JasprResponse.isHtml`); у `grund_cli` — `AppProcess`, `AppLauncher`, `DevTarget`, `DevSession`, `ReloadClient` (`reassembleMethod`, `_isolateWith`, `_isolateIds`), `ReloadTimeouts`, `Reloaded`/`ReloadRejected`/`ReloadFailed`, `DevCommand`.
- Produces:

```dart
// grund_cli
final class AppCommand {
  const AppCommand(String entry, {required String workingDirectory,
      List<String> arguments = const [], Map<String, String> environment = const {} /* 12c */});
}
AppLauncher.start(AppCommand command, {required StringSink out, required StringSink err});
AppProcess.start(AppCommand command, {...}); // 12c: Process.start(..., environment: command.environment)
DevTarget(PackageRoot package, {required String entry, required List<String> arguments,
    Map<String, String> environment = const {} /* 12c */});
AppCommand get DevTarget.command;
final class LiveReloadHub {                                           // 12c
  static const environmentVariable = 'GRUND_LIVE_RELOAD_URL';
  static Future<LiveReloadHub> start({Duration keepAlive = const Duration(seconds: 15)});
  final Uri url; Map<String, String> get environment;
  void broadcastReload(); Future<void> close();
}
DevSession(DevTarget target, {required DevPrinter printer, required StringSink out,
    AppLauncher launcher = const AppLauncher(), void Function()? onServing /* 12c */});
Future<bool> ReloadClient.waitUntilServing();                         // 12c
ReloadTimeouts({..., Duration serving = const Duration(seconds: 30)});  // 12c
// grund_jaspr (12d)
abstract final class LiveReloadScript { // поза barrel
  static const environmentVariable = 'GRUND_LIVE_RELOAD_URL';
  static Uri? urlFrom(Map<String, String> environment, {bool isProduct = bool.fromEnvironment('dart.vm.product')});
  static HttpResponse addTo(HttpResponse response, Uri url);
  static String inject(String html, Uri url);
  static String tag(Uri url);
}
JasprConfig({..., Uri? liveReloadUrl}); JasprConfig withLiveReloadUrl(Uri? url);
PageRenderer(Component Function() app, {Uri? liveReloadUrl});
```

`GRUND_LIVE_RELOAD_URL` оголошено двічі (`LiveReloadHub` у `grund_cli` і `LiveReloadScript` у `grund_jaspr`): пакети не залежать один від одного, і спільного місця для константи немає; обидва тести перевіряють саме цей рядок.

#### 12a. Рефакторинг: `AppCommand`

- [ ] **Крок 1: Тести на новий виклик**

`packages/grund_cli/test/helpers/failing_launcher.dart` (зміни):

```diff
--- a/packages/grund_cli/test/helpers/failing_launcher.dart
+++ b/packages/grund_cli/test/helpers/failing_launcher.dart
@@ -1,3 +1,4 @@
+import 'package:grund_cli/src/dev/app_command.dart';
 import 'package:grund_cli/src/dev/app_launcher.dart';
 import 'package:grund_cli/src/dev/app_process.dart';
 import 'package:grund_cli/src/dev/reload_client.dart';
@@ -31,21 +32,13 @@ final class FailingLauncher extends AppLauncher {
   final started = <AppProcess>[];
 
   @override
-  Future<AppProcess> start({
-    required String target,
-    required List<String> arguments,
-    required String workingDirectory,
+  Future<AppProcess> start(
+    AppCommand command, {
     required StringSink out,
     required StringSink err,
   }) async {
     await Future<void>.delayed(startDelay);
-    final process = await super.start(
-      target: target,
-      arguments: arguments,
-      workingDirectory: workingDirectory,
-      out: out,
-      err: err,
-    );
+    final process = await super.start(command, out: out, err: err);
     started.add(process);
     return process;
   }
```

`packages/grund_cli/test/app_process_test.dart` (зміни):

```diff
--- a/packages/grund_cli/test/app_process_test.dart
+++ b/packages/grund_cli/test/app_process_test.dart
@@ -1,6 +1,7 @@
 import 'dart:async';
 import 'dart:io';
 
+import 'package:grund_cli/src/dev/app_command.dart';
 import 'package:grund_cli/src/dev/app_process.dart';
 import 'package:test/test.dart';
 
@@ -14,9 +15,11 @@ Future<(AppProcess, LineSink, LineSink)> startProgram(String source) async {
   final out = LineSink();
   final err = LineSink();
   final app = await AppProcess.start(
-    target: 'bin/main.dart',
-    arguments: ['an argument'],
-    workingDirectory: dir.path,
+    AppCommand(
+      'bin/main.dart',
+      workingDirectory: dir.path,
+      arguments: ['an argument'],
+    ),
     out: out,
     err: err,
   );
@@ -62,9 +65,7 @@ void main() => print(pid);
     final dir = TempDir.create();
     final err = LineSink();
     final app = await AppProcess.start(
-      target: 'bin/missing.dart',
-      arguments: const [],
-      workingDirectory: dir.path,
+      AppCommand('bin/missing.dart', workingDirectory: dir.path),
       out: LineSink(),
       err: err,
     );
```

`packages/grund_cli/test/reload_client_test.dart` (зміни):

```diff
--- a/packages/grund_cli/test/reload_client_test.dart
+++ b/packages/grund_cli/test/reload_client_test.dart
@@ -1,3 +1,4 @@
+import 'package:grund_cli/src/dev/app_command.dart';
 import 'package:grund_cli/src/dev/app_process.dart';
 import 'package:grund_cli/src/dev/reload_client.dart';
 import 'package:grund_cli/src/dev/reload_result.dart';
@@ -17,9 +18,7 @@ final class Running {
     final out = LineSink();
     final err = LineSink();
     final process = await AppProcess.start(
-      target: 'bin/main.dart',
-      arguments: const [],
-      workingDirectory: app.package.dir.path,
+      AppCommand('bin/main.dart', workingDirectory: app.package.dir.path),
       out: out,
       err: err,
     );
```

`packages/grund_cli/test/reload_client_timeouts_test.dart` (зміни):

```diff
--- a/packages/grund_cli/test/reload_client_timeouts_test.dart
+++ b/packages/grund_cli/test/reload_client_timeouts_test.dart
@@ -1,3 +1,4 @@
+import 'package:grund_cli/src/dev/app_command.dart';
 import 'package:grund_cli/src/dev/app_process.dart';
 import 'package:grund_cli/src/dev/reload_client.dart';
 import 'package:grund_cli/src/dev/reload_result.dart';
@@ -63,9 +64,7 @@ void main() {
           "  print('up');\n}\n",
     );
     final process = await AppProcess.start(
-      target: entry,
-      arguments: const [],
-      workingDirectory: dir.path,
+      AppCommand(entry, workingDirectory: dir.path),
       out: LineSink(),
       err: LineSink(),
     );
```

Run: `cd packages/grund_cli && dart test test/app_process_test.dart`
Expected: FAIL — помилка компіляції: `AppCommand` не визначено.

- [ ] **Крок 2: Рефакторинг**

`packages/grund_cli/lib/src/dev/app_command.dart` (файл цілком, 19 рядків):

```dart
/// The command line of the application process: `dart <entry> <arguments>`
/// in [workingDirectory].
final class AppCommand {
  /// Creates the command.
  const AppCommand(
    this.entry, {
    required this.workingDirectory,
    this.arguments = const [],
  });

  /// The entry point, absolute or relative to [workingDirectory].
  final String entry;

  /// The directory the process starts in.
  final String workingDirectory;

  /// The arguments of the application's `main`.
  final List<String> arguments;
}
```

`packages/grund_cli/lib/src/dev/app_process.dart` (зміни):

```diff
--- a/packages/grund_cli/lib/src/dev/app_process.dart
+++ b/packages/grund_cli/lib/src/dev/app_process.dart
@@ -2,6 +2,8 @@ import 'dart:async';
 import 'dart:convert';
 import 'dart:io';
 
+import 'app_command.dart';
+
 /// The user's application, running in a child Dart VM with the VM service
 /// on an ephemeral loopback port.
 ///
@@ -24,21 +26,18 @@ final class AppProcess {
     r'^The Dart VM service is listening on (http://\S+)$',
   );
 
-  /// Starts `dart <vmFlags> <target> <arguments>` in [workingDirectory],
-  /// forwarding the child's stdout lines to [out] and stderr lines to
-  /// [err].
-  static Future<AppProcess> start({
-    required String target,
-    required List<String> arguments,
-    required String workingDirectory,
+  /// Starts `dart <vmFlags> <entry> <arguments>` of [command], forwarding
+  /// the child's stdout lines to [out] and stderr lines to [err].
+  static Future<AppProcess> start(
+    AppCommand command, {
     required StringSink out,
     required StringSink err,
   }) async {
     final process = await Process.start(Platform.resolvedExecutable, [
       ...vmFlags,
-      target,
-      ...arguments,
-    ], workingDirectory: workingDirectory);
+      command.entry,
+      ...command.arguments,
+    ], workingDirectory: command.workingDirectory);
     final serviceUri = Completer<Uri?>();
     final stdoutDone = _lines(process.stdout).listen((line) {
       final banner = serviceUri.isCompleted ? null : _banner.firstMatch(line);
```

`packages/grund_cli/lib/src/dev/app_launcher.dart` (зміни):

```diff
--- a/packages/grund_cli/lib/src/dev/app_launcher.dart
+++ b/packages/grund_cli/lib/src/dev/app_launcher.dart
@@ -1,3 +1,4 @@
+import 'app_command.dart';
 import 'app_process.dart';
 import 'reload_client.dart';
 import 'reload_timeouts.dart';
@@ -14,19 +15,11 @@ class AppLauncher {
   final ReloadTimeouts timeouts;
 
   /// Starts the application; see [AppProcess.start].
-  Future<AppProcess> start({
-    required String target,
-    required List<String> arguments,
-    required String workingDirectory,
+  Future<AppProcess> start(
+    AppCommand command, {
     required StringSink out,
     required StringSink err,
-  }) => AppProcess.start(
-    target: target,
-    arguments: arguments,
-    workingDirectory: workingDirectory,
-    out: out,
-    err: err,
-  );
+  }) => AppProcess.start(command, out: out, err: err);
 
   /// Connects to the VM service at [serviceUri]; see [ReloadClient.connect].
   Future<ReloadClient?> connect(Uri serviceUri) =>
```

`packages/grund_cli/lib/src/dev/dev_target.dart` (зміни):

```diff
--- a/packages/grund_cli/lib/src/dev/dev_target.dart
+++ b/packages/grund_cli/lib/src/dev/dev_target.dart
@@ -3,6 +3,7 @@ import 'dart:io';
 import 'package:path/path.dart' as p;
 
 import '../package/package_root.dart';
+import 'app_command.dart';
 
 /// What `dev` runs: the entry point of [package] and the arguments of its
 /// `main`.
@@ -19,6 +20,10 @@ final class DevTarget {
   /// The arguments of the application's `main`.
   final List<String> arguments;
 
+  /// The command line that runs the application in its package.
+  AppCommand get command =>
+      AppCommand(entry, workingDirectory: package.path, arguments: arguments);
+
   /// The Dart files the application is built from, as far as `dev` watches
   /// them: `lib/` and the directory of the entry point.
   List<String> sources() => [
```

`packages/grund_cli/lib/src/dev/dev_session.dart` (зміни):

```diff
--- a/packages/grund_cli/lib/src/dev/dev_session.dart
+++ b/packages/grund_cli/lib/src/dev/dev_session.dart
@@ -154,9 +154,7 @@ final class DevSession {
     if (_stopped) return;
     _shapes.remember(target.sources());
     final process = await launcher.start(
-      target: target.entry,
-      arguments: target.arguments,
-      workingDirectory: target.package.path,
+      target.command,
       out: out,
       err: printer.err,
     );
```

- [ ] **Крок 3: Тести, перевірки, коміт**

Run: `cd packages/grund_cli && dart test` → `+160: All tests passed!` (як до рефакторингу).
Run: `dart analyze` → `No issues found!`; `dart format packages example` → `(0 changed)`.

```bash
git add \
  packages/grund_cli/lib/src/dev/app_command.dart \
  packages/grund_cli/lib/src/dev/app_launcher.dart \
  packages/grund_cli/lib/src/dev/app_process.dart \
  packages/grund_cli/lib/src/dev/dev_session.dart \
  packages/grund_cli/lib/src/dev/dev_target.dart \
  packages/grund_cli/test/app_process_test.dart \
  packages/grund_cli/test/helpers/failing_launcher.dart \
  packages/grund_cli/test/reload_client_test.dart \
  packages/grund_cli/test/reload_client_timeouts_test.dart
git commit -m "refactor(cli): pass the application command line as an AppCommand" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git show --stat --format=%s HEAD   # 9 файлів, лише ці
```

#### 12b. Помічники інтеграційних тестів `dev`

- [ ] **Крок 4: Перенести помічники**

Перенести `until`, `isListening`, `killStrays`, `freePort`, `hello` і `DevRun` з `integration/dev_test.dart` без змін поведінки:

`packages/grund_cli/integration/helpers/dev_run.dart` (файл цілком, 99 рядків):

```dart
import 'dart:async';
import 'dart:io';

import 'package:grund_cli/grund_cli.dart';
import 'package:test/test.dart';

import '../../test/helpers/hello_app.dart';
import '../../test/helpers/line_sink.dart';

/// Waits until [lines] has [count] lines that satisfy [test], in any order
/// with the other lines (the application prints while dev does).
Future<void> until(
  LineSink lines,
  bool Function(String line) test, {
  int count = 1,
}) async {
  while (lines.lines.where(test).length < count) {
    await lines.next();
  }
}

bool isListening(String line) => HelloApp.portIn(line) != null;

/// Kills the application processes `dev` reported in [lines] (`Started ...
/// (pid N`) that are still running, so a failing test leaves none behind.
void killStrays(LineSink lines) {
  final started = RegExp(r'^Started .* \(pid (\d+),');
  for (final line in lines.lines) {
    final pid = int.tryParse(started.firstMatch(line)?[1] ?? '');
    if (pid == null || !_isApplication(pid)) continue;
    Process.killPid(pid, ProcessSignal.sigkill);
  }
}

// The pid may have been reused after a clean shutdown; where /proc tells
// what it runs, only a child VM with the VM service is killed.
bool _isApplication(int pid) {
  final command = File('/proc/$pid/cmdline');
  return !command.existsSync() ||
      command.readAsStringSync().contains('--enable-vm-service');
}

/// A loopback port that was free a moment ago.
Future<int> freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

/// The answer of `GET /hello` on [port].
Future<Map<String, Object?>> hello(int port) async =>
    await HelloApp.get(port, '/hello') as Map<String, Object?>;

/// `dev` of the application in a package directory, serving on [port],
/// run in-process.
final class DevRun {
  DevRun._(this.port, this.lines, this.keys, this._stop, this.exit);

  /// Starts `dev` of the package in [directory], passing [port] to `main`,
  /// and waits until the application prints `listening on <port>`.
  static Future<DevRun> start(String directory, {required int port}) async {
    final lines = LineSink();
    final keys = StreamController<String>();
    final stop = Completer<void>();
    final exit = GrundCli(
      out: lines,
      err: lines,
      interruption: Interruption(untilStopped: () => stop.future),
      keys: () => keys.stream,
    ).run(['dev', '-C', directory, '--', '$port']);
    final run = DevRun._(port, lines, keys, stop, exit);
    addTearDown(() => killStrays(lines));
    addTearDown(run.stop);
    await until(lines, (line) => line.startsWith('Watching lib/ and bin/'));
    await until(lines, isListening);
    return run;
  }

  /// The port the application serves on.
  final int port;

  /// What `dev` and the application printed.
  final LineSink lines;

  /// The terminal keys `dev` reads.
  final StreamController<String> keys;

  final Completer<void> _stop;

  /// The exit code of `dev`.
  final Future<int> exit;

  /// Stops `dev` as Ctrl+C does and returns its exit code.
  Future<int> stop() {
    if (!_stop.isCompleted) _stop.complete();
    return exit;
  }
}
```

`packages/grund_cli/integration/dev_test.dart` (зміни):

```diff
--- a/packages/grund_cli/integration/dev_test.dart
+++ b/packages/grund_cli/integration/dev_test.dart
@@ -12,107 +12,29 @@ import 'package:test/test.dart';
 
 import '../test/helpers/hello_app.dart';
 import '../test/helpers/line_sink.dart';
+import 'helpers/dev_run.dart';
 
-/// Waits until [lines] has [count] lines that satisfy [test], in any order
-/// with the other lines (the application prints while dev does).
-Future<void> until(
-  LineSink lines,
-  bool Function(String line) test, {
-  int count = 1,
-}) async {
-  while (lines.lines.where(test).length < count) {
-    await lines.next();
-  }
-}
-
-bool isListening(String line) => HelloApp.portIn(line) != null;
-
-/// Kills the application processes `dev` reported in [lines] (`Started ...
-/// (pid N`) that are still running, so a failing test leaves none behind.
-void killStrays(LineSink lines) {
-  final started = RegExp(r'^Started .* \(pid (\d+),');
-  for (final line in lines.lines) {
-    final pid = int.tryParse(started.firstMatch(line)?[1] ?? '');
-    if (pid == null || !_isApplication(pid)) continue;
-    Process.killPid(pid, ProcessSignal.sigkill);
-  }
-}
-
-// The pid may have been reused after a clean shutdown; where /proc tells
-// what it runs, only a child VM with the VM service is killed.
-bool _isApplication(int pid) {
-  final command = File('/proc/$pid/cmdline');
-  return !command.existsSync() ||
-      command.readAsStringSync().contains('--enable-vm-service');
-}
-
-/// A loopback port that was free a moment ago.
-Future<int> freePort() async {
-  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
-  final port = socket.port;
-  await socket.close();
-  return port;
-}
-
-/// The answer of `GET /hello` on [port].
-Future<Map<String, Object?>> hello(int port) async =>
-    await HelloApp.get(port, '/hello') as Map<String, Object?>;
-
-/// `dev` of the `hello` application on [port], run in-process.
-final class DevRun {
-  DevRun._(this.app, this.port, this.lines, this.keys, this._stop, this.exit);
-
-  /// Starts `dev` and waits until the application listens.
-  static Future<DevRun> start() async {
-    final app = await HelloApp.create();
-    final port = await freePort();
-    final lines = LineSink();
-    final keys = StreamController<String>();
-    final stop = Completer<void>();
-    final exit = GrundCli(
-      out: lines,
-      err: lines,
-      interruption: Interruption(untilStopped: () => stop.future),
-      keys: () => keys.stream,
-    ).run(['dev', '-C', app.package.dir.path, '--', '$port']);
-    final run = DevRun._(app, port, lines, keys, stop, exit);
-    addTearDown(() => killStrays(lines));
-    addTearDown(run.stop);
-    await until(lines, (line) => line.startsWith('Watching lib/ and bin/'));
-    await until(lines, isListening);
-    return run;
-  }
-
-  final HelloApp app;
-  final int port;
-  final LineSink lines;
-  final StreamController<String> keys;
-  final Completer<void> _stop;
-
-  /// The exit code of `dev`.
-  final Future<int> exit;
-
-  /// Stops `dev` as Ctrl+C does and returns its exit code.
-  Future<int> stop() {
-    if (!_stop.isCompleted) _stop.complete();
-    return exit;
-  }
+/// Starts `dev` of a new `hello` application on a free port.
+Future<(HelloApp, DevRun)> startHello() async {
+  final app = await HelloApp.create();
+  final dev = await DevRun.start(app.package.dir.path, port: await freePort());
+  return (app, dev);
 }
 
 void main() {
   // The roadmap's dev test: a body change keeps the process, a new route
   // appears, a new field restarts the application in a new process.
   test('dev reloads bodies and routes and restarts on a new field', () async {
-    final dev = await DevRun.start();
+    final (app, dev) = await startHello();
     final first = (await hello(dev.port))['pid'];
 
-    dev.app.edit('lib/src/greeter.dart', 'hello v1', 'hello v2');
+    app.edit('lib/src/greeter.dart', 'hello v1', 'hello v2');
     await until(dev.lines, (line) => line.startsWith('Reloaded '));
     expect(await hello(dev.port), {'text': 'hello v2', 'pid': first});
 
     // Review Focus 8: the route reaches the application only through the
     // generated file, which is written before the reload.
-    dev.app.edit(
+    app.edit(
       'lib/src/hello_api.dart',
       "  @Get('/')",
       "  @Get('/bye')\n  Map<String, Object> bye() => {'text': 'bye'};\n\n"
@@ -124,7 +46,7 @@ void main() {
     expect((await hello(dev.port))['pid'], first);
 
     // Review Focus 6: the new process binds the port the old one held.
-    dev.app.edit(
+    app.edit(
       'lib/src/greeter.dart',
       'String greet',
       'int count = 0;\n\n  String greet',
@@ -146,11 +68,11 @@ void main() {
 
   test('a storm of saves ends with the last version in one process', () async {
     // Review Focus 4.
-    final dev = await DevRun.start();
+    final (app, dev) = await startHello();
     final first = (await hello(dev.port))['pid'];
 
     for (var version = 2; version <= 6; version++) {
-      dev.app.edit(
+      app.edit(
         'lib/src/greeter.dart',
         'hello v${version - 1}',
         'hello v$version',
@@ -168,9 +90,9 @@ void main() {
   });
 
   test('a compile error in bin/ keeps the previous code running', () async {
-    final dev = await DevRun.start();
+    final (app, dev) = await startHello();
 
-    dev.app.edit('bin/main.dart', 'final adapter', 'final adapter = 1;\n  var');
+    app.edit('bin/main.dart', 'final adapter', 'final adapter = 1;\n  var');
     await until(dev.lines, (line) => line.startsWith('Hot reload failed; '));
     expect((await hello(dev.port))['text'], 'hello v1');
   });
```

- [ ] **Крок 5: Тести, перевірки, коміт**

Run: `cd packages/grund_cli && dart test integration/dev_test.dart` → `+5: All tests passed!` (близько 35 с).
Run: `dart analyze` → `No issues found!`; `dart format packages example` → `(0 changed)`.

```bash
git add \
  packages/grund_cli/integration/dev_test.dart \
  packages/grund_cli/integration/helpers/dev_run.dart
git commit -m "test(cli): move the dev integration helpers to integration/helpers" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git show --stat --format=%s HEAD   # 2 файлів, лише ці
```

#### 12c. Точка SSE у `grund dev`

- [ ] **Крок 6: Тестові помічники**

`EventClient` — читач потоку server-sent events через `dart:io` `HttpClient` (події, коментарі, кінець потоку; `rest()` — усе, що лишилося, щоб тест не залежав від того, коли саме прийде подія); `Dev` у `helpers/dev.dart` передає `onServing` у `DevSession`.

`packages/grund_cli/test/helpers/event_client.dart` (файл цілком, 55 рядків):

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A reader of a server-sent events stream, line by line.
final class EventClient {
  EventClient._(this._client, this.response, this._lines);

  /// Connects to [url] and waits for the response head.
  static Future<EventClient> connect(Uri url) async {
    final client = HttpClient();
    final response = await (await client.getUrl(url)).close();
    final lines = StreamIterator(
      response.transform(utf8.decoder).transform(const LineSplitter()),
    );
    return EventClient._(client, response, lines);
  }

  static const _wait = Duration(seconds: 30);

  final HttpClient _client;
  final StreamIterator<String> _lines;

  /// The response head.
  final HttpClientResponse response;

  /// The name of the next event, or `null` when the stream ends first.
  Future<String?> nextEvent() async {
    while (await _lines.moveNext().timeout(_wait)) {
      final line = _lines.current;
      if (line.startsWith('event: ')) return line.substring('event: '.length);
    }
    return null;
  }

  /// The names of the events until the stream ends.
  Future<List<String>> rest() async {
    final names = <String>[];
    for (var name = await nextEvent(); name != null; name = await nextEvent()) {
      names.add(name);
    }
    return names;
  }

  /// Whether the comment `: <text>` arrives before the stream ends.
  Future<bool> nextComment(String text) async {
    while (await _lines.moveNext().timeout(_wait)) {
      if (_lines.current == ': $text') return true;
    }
    return false;
  }

  /// Drops the connection.
  void close() => _client.close(force: true);
}
```

`packages/grund_cli/test/helpers/dev.dart` (зміни):

```diff
--- a/packages/grund_cli/test/helpers/dev.dart
+++ b/packages/grund_cli/test/helpers/dev.dart
@@ -18,8 +18,13 @@ final class Dev {
   static Future<Dev> start({
     AppLauncher? launcher,
     void Function(HelloApp app)? prepare,
+    void Function()? onServing,
   }) async {
-    final dev = await create(launcher: launcher, prepare: prepare);
+    final dev = await create(
+      launcher: launcher,
+      prepare: prepare,
+      onServing: onServing,
+    );
     await dev.change(const []);
     return dev;
   }
@@ -28,6 +33,7 @@ final class Dev {
   static Future<Dev> create({
     AppLauncher? launcher,
     void Function(HelloApp app)? prepare,
+    void Function()? onServing,
   }) async {
     final app = await HelloApp.create();
     prepare?.call(app);
@@ -43,6 +49,7 @@ final class Dev {
       printer: DevPrinter('bin/main.dart', lines, lines),
       out: lines,
       launcher: launcher ?? const AppLauncher(),
+      onServing: onServing,
     );
     addTearDown(session.stop);
     return Dev._(app, lines, generation, session);
```

- [ ] **Крок 7: Падаючі тести**

`packages/grund_cli/test/live_reload_hub_test.dart` (файл цілком, 89 рядків):

```dart
import 'dart:io';

import 'package:grund_cli/src/dev/live_reload_hub.dart';
import 'package:test/test.dart';

import 'helpers/event_client.dart';

/// A started hub, closed after the test.
Future<LiveReloadHub> startHub({
  Duration keepAlive = const Duration(seconds: 15),
}) async {
  final hub = await LiveReloadHub.start(keepAlive: keepAlive);
  addTearDown(hub.close);
  return hub;
}

/// A page connected to [hub], dropped after the test.
Future<EventClient> connect(LiveReloadHub hub) async {
  final page = await EventClient.connect(hub.url);
  addTearDown(page.close);
  await page.nextComment('connected');
  return page;
}

void main() {
  test('listens on loopback and passes its URL in the environment', () async {
    final hub = await startHub();

    expect(hub.url.host, '127.0.0.1');
    expect(hub.environment, {'GRUND_LIVE_RELOAD_URL': '${hub.url}'});
  });

  test('answers an event stream any origin may read', () async {
    final hub = await startHub();

    final page = await connect(hub);

    final headers = page.response.headers;
    expect(headers.contentType?.mimeType, 'text/event-stream');
    expect(headers.value('access-control-allow-origin'), '*');
    expect(headers.value('cache-control'), 'no-cache');
  });

  test('every connected page receives reload', () async {
    final hub = await startHub();
    final first = await connect(hub);
    final second = await connect(hub);

    hub.broadcastReload();

    expect(await first.nextEvent(), 'reload');
    expect(await second.nextEvent(), 'reload');
  });

  test('sends a keep-alive comment', () async {
    final hub = await startHub(keepAlive: const Duration(milliseconds: 50));

    final page = await connect(hub);

    expect(await page.nextComment('keep-alive'), isTrue);
  });

  test('a page that left does not stop the next broadcast', () async {
    final hub = await startHub();
    hub.broadcastReload();
    (await connect(hub)).close();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final page = await connect(hub);

    hub
      ..broadcastReload()
      ..broadcastReload();

    expect(await page.nextEvent(), 'reload');
  });

  test('close ends every stream and frees the port (RF7)', () async {
    final hub = await LiveReloadHub.start();
    final page = await connect(hub);

    await hub.close();

    expect(await page.nextEvent(), isNull);
    await expectLater(
      EventClient.connect(hub.url),
      throwsA(isA<SocketException>()),
    );
  });
}
```

`packages/grund_cli/test/dev_session_serving_test.dart` (файл цілком, 70 рядків):

```dart
import 'dart:async';

import 'package:test/test.dart';

import 'helpers/dev.dart';

/// Counts the calls of a callback and lets a test wait for the next one.
final class Calls {
  var count = 0;
  final _calls = StreamController<int>.broadcast();
  void call() => _calls.add(++count);
  Future<void> reach(int n) async {
    if (count >= n) return;
    await _calls.stream
        .firstWhere((c) => c >= n)
        .timeout(const Duration(seconds: 30));
  }
}

void main() {
  test('a started application announces once it serves', () async {
    final served = Calls();
    final dev = await Dev.start(onServing: served.call);
    await dev.listening();

    await served.reach(1);
    expect(served.count, 1);
  });

  test('a reload announces after the reassemble', () async {
    final served = Calls();
    final dev = await Dev.start(onServing: served.call);
    await served.reach(1);

    dev.app.edit('lib/src/greeter.dart', 'hello v1', 'hello v2');
    await dev.change(['lib/src/greeter.dart']);

    expect(served.count, 2);
  });

  test('a restart announces once the new process serves', () async {
    final served = Calls();
    final dev = await Dev.start(onServing: served.call);
    final before = await Dev.hello(await dev.listening());
    await served.reach(1);

    dev.app.edit(
      'lib/src/greeter.dart',
      'String greet',
      'int count = 0;\n  String greet',
    );
    await dev.change(['lib/src/greeter.dart']);
    final after = await Dev.hello(await dev.listening());

    await served.reach(2);
    expect(after['pid'], isNot(before['pid']));
  });

  test('sources with problems announce nothing', () async {
    final served = Calls();
    final dev = await Dev.start(onServing: served.call);
    await served.reach(1);

    dev.app.edit('lib/src/greeter.dart', "'hello v1';", "'hello v2'");
    await dev.change(['lib/src/greeter.dart']);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(served.count, 1);
  });
}
```

`packages/grund_cli/test/dev_live_reload_test.dart` (файл цілком, 49 рядків):

```dart
import 'dart:async';

import 'package:grund_cli/grund_cli.dart';
import 'package:test/test.dart';

import 'helpers/dev_sources.dart';
import 'helpers/event_client.dart';
import 'helpers/line_sink.dart';
import 'helpers/temp_package.dart';

/// The `hello` application, printing the live reload URL it was given.
final _files = {
  ...DevSources.files,
  'bin/main.dart': DevSources.main.replaceFirst(
    "  print('listening",
    "  print('live reload \${Platform.environment['GRUND_LIVE_RELOAD_URL']}');\n"
        "  print('listening",
  ),
};

void main() {
  test('dev passes its live reload URL and announces a reload there', () async {
    final package = await TempPackage.create('hello', _files);
    final out = LineSink();
    final keys = StreamController<String>();
    final stop = Completer<void>();
    final done = GrundCli(
      out: out,
      err: out,
      interruption: Interruption(untilStopped: () => stop.future),
      keys: () => keys.stream,
    ).run(['dev', '-C', package.dir.path]);
    final line = await out.nextWhere((line) => line.startsWith('live reload '));
    final events = await EventClient.connect(
      Uri.parse(line.substring('live reload '.length)),
    );
    addTearDown(events.close);
    await events.nextComment('connected');

    keys.add('r');
    await out.nextWhere((line) => line.startsWith('Reloaded '));
    stop.complete();

    expect(await done, 0);
    // The start may have been announced before the page connected; the
    // reload of `r` was announced after it. The stream ends with dev.
    expect(await events.rest(), contains('reload'));
  });
}
```

`packages/grund_cli/test/app_process_test.dart` (зміни):

```diff
--- a/packages/grund_cli/test/app_process_test.dart
+++ b/packages/grund_cli/test/app_process_test.dart
@@ -131,4 +131,30 @@ Future<void> main() async {
 
     expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
   }, testOn: '!windows');
+
+  test('the child gets the variables of its command and of dev', () async {
+    final dir = TempDir.create();
+    dir.write('bin/main.dart', '''
+import 'dart:io';
+
+void main() {
+  print(Platform.environment['GRUND_TEST_VARIABLE']);
+  print(Platform.environment.containsKey('PATH'));
+}
+''');
+    final out = LineSink();
+    final app = await AppProcess.start(
+      AppCommand(
+        'bin/main.dart',
+        workingDirectory: dir.path,
+        environment: const {'GRUND_TEST_VARIABLE': 'passed'},
+      ),
+      out: out,
+      err: LineSink(),
+    );
+    addTearDown(() => app.stop(killGrace: Duration.zero));
+
+    await app.exitCode;
+    expect(out.lines, ['passed', 'true']);
+  });
 }
```

`packages/grund_cli/test/reload_client_test.dart` (зміни):

```diff
--- a/packages/grund_cli/test/reload_client_test.dart
+++ b/packages/grund_cli/test/reload_client_test.dart
@@ -137,4 +137,10 @@ final class Broken {
 
     expect(await running.process.exitCode, 0);
   });
+
+  test('a serving grund application is found serving', () async {
+    final running = await Running.start();
+
+    expect(await running.client.waitUntilServing(), isTrue);
+  });
 }
```

`packages/grund_cli/test/reload_client_timeouts_test.dart` (зміни):

```diff
--- a/packages/grund_cli/test/reload_client_timeouts_test.dart
+++ b/packages/grund_cli/test/reload_client_timeouts_test.dart
@@ -13,8 +13,34 @@ const _short = ReloadTimeouts(
   connect: Duration(milliseconds: 300),
   reload: Duration(milliseconds: 300),
   close: Duration(milliseconds: 300),
+  serving: Duration(milliseconds: 300),
 );
 
+/// Starts a Dart program without grund that keeps running, and connects
+/// to it with [timeouts].
+Future<ReloadClient> _clientOfProcessWithoutGrund({
+  ReloadTimeouts timeouts = const ReloadTimeouts(),
+}) async {
+  final dir = TempDir.create();
+  final entry = dir.write(
+    'main.dart',
+    "import 'dart:async';\n\n"
+        "void main() {\n  Timer(const Duration(minutes: 5), () {});\n"
+        "  print('up');\n}\n",
+  );
+  final process = await AppProcess.start(
+    AppCommand(entry, workingDirectory: dir.path),
+    out: LineSink(),
+    err: LineSink(),
+  );
+  addTearDown(() => process.stop(killGrace: Duration.zero));
+  final uri = await process.serviceUri ?? fail('No VM service.');
+  final client = await ReloadClient.connect(uri, timeouts: timeouts);
+  if (client == null) fail('No connection.');
+  addTearDown(client.dispose);
+  return client;
+}
+
 /// Connects to a VM service that opens the connection and never answers.
 Future<ReloadClient> _connectedToHungService() async {
   final service = await HungVmService.start(webSocket: true);
@@ -56,22 +82,7 @@ void main() {
   });
 
   test('a process without grund reloads and skips the reassemble', () async {
-    final dir = TempDir.create();
-    final entry = dir.write(
-      'main.dart',
-      "import 'dart:async';\n\n"
-          "void main() {\n  Timer(const Duration(minutes: 5), () {});\n"
-          "  print('up');\n}\n",
-    );
-    final process = await AppProcess.start(
-      AppCommand(entry, workingDirectory: dir.path),
-      out: LineSink(),
-      err: LineSink(),
-    );
-    addTearDown(() => process.stop(killGrace: Duration.zero));
-    final uri = await process.serviceUri ?? fail('No VM service.');
-    final client = await ReloadClient.connect(uri) ?? fail('No connection.');
-    addTearDown(client.dispose);
+    final client = await _clientOfProcessWithoutGrund();
 
     final result = await client.reload();
 
@@ -79,4 +90,17 @@ void main() {
     expect((result as Reloaded).changes, isNull);
     expect(result.reassembleError, isNull);
   });
+
+  test('a process without grund never serves', () async {
+    final client = await _clientOfProcessWithoutGrund(timeouts: _short);
+
+    expect(await client.waitUntilServing(), isFalse);
+  });
+
+  test('a VM service that never answers never serves', () async {
+    final client = await _connectedToHungService();
+    addTearDown(client.dispose);
+
+    expect(await client.waitUntilServing(), isFalse);
+  });
 }
```

Run: `cd packages/grund_cli && dart test test/live_reload_hub_test.dart test/dev_session_serving_test.dart test/dev_live_reload_test.dart`
Expected: FAIL — помилка компіляції: `LiveReloadHub`, `DevSession(onServing:)`, `waitUntilServing` не визначено.

- [ ] **Крок 8: Точка SSE**

`packages/grund_cli/lib/src/dev/live_reload_hub.dart` (файл цілком, 88 рядків):

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The server-sent events endpoint of `dev` that makes open pages reload:
/// it sends `event: reload` after every successful hot reload and once a
/// restarted application serves again.
///
/// It listens on 127.0.0.1 and an ephemeral port, outlives restarts of the
/// application and closes with `dev`. Every request gets the event stream,
/// with `access-control-allow-origin: *` (the page comes from the
/// application's origin) and a comment every [keepAlive] so that proxies
/// and browsers keep the connection open.
final class LiveReloadHub {
  LiveReloadHub._(this._server, this.url, Duration keepAlive) {
    _keepAlive = Timer.periodic(keepAlive, (_) => _send(': keep-alive\n\n'));
  }

  /// The variable that passes [url] to the application.
  static const environmentVariable = 'GRUND_LIVE_RELOAD_URL';

  /// Starts the endpoint; [keepAlive] is for tests.
  static Future<LiveReloadHub> start({
    Duration keepAlive = const Duration(seconds: 15),
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final hub = LiveReloadHub._(
      server,
      Uri.parse('http://127.0.0.1:${server.port}/'),
      keepAlive,
    );
    server.listen(hub._accept);
    return hub;
  }

  final HttpServer _server;
  final _clients = <HttpResponse>{};
  late final Timer _keepAlive; // Set in the constructor body.

  /// Where pages connect.
  final Uri url;

  /// The environment of the application process: [environmentVariable]
  /// with [url].
  Map<String, String> get environment => {environmentVariable: '$url'};

  /// Tells every connected page to reload; nothing happens without one.
  void broadcastReload() => _send('event: reload\ndata: \n\n');

  /// Ends every stream and stops listening.
  Future<void> close() async {
    _keepAlive.cancel();
    final clients = List.of(_clients);
    _clients.clear();
    // Each stream ends cleanly; a page that is gone or does not read is
    // cut off by the forced close below.
    await Future.wait([
      for (final client in clients)
        client.close().catchError(
          (Object _) {},
          test: (error) => error is IOException,
        ),
    ]).timeout(const Duration(seconds: 1), onTimeout: () => const []);
    await _server.close(force: true);
  }

  void _accept(HttpRequest request) {
    final response = request.response
      ..bufferOutput = false
      ..headers.set('content-type', 'text/event-stream')
      ..headers.set('cache-control', 'no-cache')
      ..headers.set('access-control-allow-origin', '*');
    _clients.add(response);
    response.add(utf8.encode(': connected\n\n'));
    // A page that went away ends its response with an I/O error; it is
    // simply no longer a client.
    response.done
        .catchError((Object _) {}, test: (error) => error is IOException)
        .whenComplete(() => _clients.remove(response));
  }

  void _send(String event) {
    final bytes = utf8.encode(event);
    for (final client in _clients) {
      client.add(bytes);
    }
  }
}
```

- [ ] **Крок 9: Змінні середовища дочірнього процесу**

`packages/grund_cli/lib/src/dev/app_command.dart` (зміни):

```diff
--- a/packages/grund_cli/lib/src/dev/app_command.dart
+++ b/packages/grund_cli/lib/src/dev/app_command.dart
@@ -1,11 +1,13 @@
 /// The command line of the application process: `dart <entry> <arguments>`
-/// in [workingDirectory].
+/// in [workingDirectory], with [environment] added to the environment of
+/// `dev`.
 final class AppCommand {
   /// Creates the command.
   const AppCommand(
     this.entry, {
     required this.workingDirectory,
     this.arguments = const [],
+    this.environment = const {},
   });
 
   /// The entry point, absolute or relative to [workingDirectory].
@@ -16,4 +18,7 @@ final class AppCommand {
 
   /// The arguments of the application's `main`.
   final List<String> arguments;
+
+  /// Variables added to the environment `dev` itself runs with.
+  final Map<String, String> environment;
 }
```

`packages/grund_cli/lib/src/dev/app_process.dart` (зміни):

```diff
--- a/packages/grund_cli/lib/src/dev/app_process.dart
+++ b/packages/grund_cli/lib/src/dev/app_process.dart
@@ -33,11 +33,12 @@ final class AppProcess {
     required StringSink out,
     required StringSink err,
   }) async {
-    final process = await Process.start(Platform.resolvedExecutable, [
-      ...vmFlags,
-      command.entry,
-      ...command.arguments,
-    ], workingDirectory: command.workingDirectory);
+    final process = await Process.start(
+      Platform.resolvedExecutable,
+      [...vmFlags, command.entry, ...command.arguments],
+      workingDirectory: command.workingDirectory,
+      environment: command.environment,
+    );
     final serviceUri = Completer<Uri?>();
     final stdoutDone = _lines(process.stdout).listen((line) {
       final banner = serviceUri.isCompleted ? null : _banner.firstMatch(line);
```

`packages/grund_cli/lib/src/dev/dev_target.dart` (зміни):

```diff
--- a/packages/grund_cli/lib/src/dev/dev_target.dart
+++ b/packages/grund_cli/lib/src/dev/dev_target.dart
@@ -9,7 +9,12 @@ import 'app_command.dart';
 /// `main`.
 final class DevTarget {
   /// Creates the target; [entry] is absolute.
-  const DevTarget(this.package, {required this.entry, required this.arguments});
+  const DevTarget(
+    this.package, {
+    required this.entry,
+    required this.arguments,
+    this.environment = const {},
+  });
 
   /// The package of the application.
   final PackageRoot package;
@@ -20,9 +25,16 @@ final class DevTarget {
   /// The arguments of the application's `main`.
   final List<String> arguments;
 
+  /// Variables added to the environment of the application.
+  final Map<String, String> environment;
+
   /// The command line that runs the application in its package.
-  AppCommand get command =>
-      AppCommand(entry, workingDirectory: package.path, arguments: arguments);
+  AppCommand get command => AppCommand(
+    entry,
+    workingDirectory: package.path,
+    arguments: arguments,
+    environment: environment,
+  );
 
   /// The Dart files the application is built from, as far as `dev` watches
   /// them: `lib/` and the directory of the entry point.
```

- [ ] **Крок 10: Коли застосунок обслуговує**

`waitUntilServing` чекає, доки ізолят застосунку зареєструє `ext.grund.reassemble` (так `dev` знає, що grund піднявся), до `ReloadTimeouts.serving`; процес без grund або VM service, що не відповідає, — `false` без помилки («Рішення плану», п. 16).

`packages/grund_cli/lib/src/dev/reload_timeouts.dart` (зміни):

```diff
--- a/packages/grund_cli/lib/src/dev/reload_timeouts.dart
+++ b/packages/grund_cli/lib/src/dev/reload_timeouts.dart
@@ -7,6 +7,7 @@ final class ReloadTimeouts {
     this.reload = const Duration(seconds: 60),
     this.close = const Duration(seconds: 5),
     this.serviceUri = const Duration(seconds: 30),
+    this.serving = const Duration(seconds: 30),
   });
 
   /// Opening the connection to the VM service.
@@ -20,4 +21,8 @@ final class ReloadTimeouts {
 
   /// The child printing its VM service address after it started.
   final Duration serviceUri;
+
+  /// A started application registering its reassemble extension, which
+  /// grund does once its runners serve.
+  final Duration serving;
 }
```

`packages/grund_cli/lib/src/dev/reload_client.dart` (зміни):

```diff
--- a/packages/grund_cli/lib/src/dev/reload_client.dart
+++ b/packages/grund_cli/lib/src/dev/reload_client.dart
@@ -20,6 +20,9 @@ final class ReloadClient {
   /// The extension `Application` registers to close before a restart.
   static const closeMethod = 'ext.grund.close';
 
+  /// How often [waitUntilServing] looks for the reassemble extension.
+  static const servingPollInterval = Duration(milliseconds: 100);
+
   final VmService _service;
   final ReloadTimeouts _timeouts;
 
@@ -87,6 +90,33 @@ final class ReloadClient {
     );
   }
 
+  /// Whether a grund application of the process serves within
+  /// [ReloadTimeouts.serving]: grund registers the reassemble extension
+  /// once the runners of an `App` started. `false` for a process without
+  /// grund, and when the connection ends meanwhile.
+  Future<bool> waitUntilServing() async {
+    try {
+      return await _pollServing().timeout(_timeouts.serving);
+    } on TimeoutException {
+      return false;
+    } on RPCError {
+      return false;
+    } on SentinelException {
+      return false;
+    }
+  }
+
+  Future<bool> _pollServing() async {
+    final waited = Stopwatch()..start();
+    while (waited.elapsed < _timeouts.serving) {
+      if (await _isolateWith(reassembleMethod, await _isolateIds()) != null) {
+        return true;
+      }
+      await Future<void>.delayed(servingPollInterval);
+    }
+    return false;
+  }
+
   /// Closes the grund applications of the process (they finish their
   /// requests in flight), waiting up to [ReloadTimeouts.close] for the
   /// whole exchange; any failure is left to the restart, which ends the
```

`DevSession` викликає `onServing` після `Reloaded(reassembleError: null)` і (не чекаючи, `unawaited`) коли щойно запущений процес почав обслуговувати; reload із помилкою reassemble, відхилений reload (той перезапускає процес) і невдала компіляція подію не надсилають.

`packages/grund_cli/lib/src/dev/dev_session.dart` (зміни):

```diff
--- a/packages/grund_cli/lib/src/dev/dev_session.dart
+++ b/packages/grund_cli/lib/src/dev/dev_session.dart
@@ -22,12 +22,15 @@ final class DevSession {
   /// Creates the session for [target], printing through [printer] and
   /// forwarding the application's stdout to [out] and its stderr to the
   /// printer's error sink. The application is started and reached through
-  /// [launcher] (tests replace it to make these steps fail).
+  /// [launcher] (tests replace it to make these steps fail). [onServing]
+  /// runs whenever the application serves new code: after a reload with a
+  /// successful reassemble, and once a started application serves.
   DevSession(
     this.target, {
     required this.printer,
     required this.out,
     this.launcher = const AppLauncher(),
+    this.onServing,
   });
 
   /// What runs: the entry point, its package and its arguments.
@@ -42,6 +45,10 @@ final class DevSession {
   /// Starts the processes and connects to them.
   final AppLauncher launcher;
 
+  /// Called when the application serves new code (`dev` tells open pages
+  /// to reload); `null` for none.
+  final void Function()? onServing;
+
   final _shapes = ShapeTracker();
   Future<void> _tail = Future<void>.value();
   final _unapplied = <String>{};
@@ -137,7 +144,14 @@ final class DevSession {
     // The application died meanwhile and said so; its reload result is moot.
     if (!identical(_running, running)) return;
     printer.reloaded(result);
-    if (result is ReloadRejected) await _replace();
+    switch (result) {
+      case Reloaded(reassembleError: null):
+        onServing?.call();
+      case ReloadRejected():
+        await _replace();
+      case Reloaded() || ReloadFailed():
+        break;
+    }
   }
 
   Future<void> _restart(String reason) async {
@@ -184,6 +198,19 @@ final class DevSession {
     _running = running;
     printer.started(process.pid, uri);
     unawaited(process.exitCode.then((code) => _exited(running, code)));
+    if (onServing case final announce?) {
+      unawaited(_announceWhenServing(running, announce));
+    }
+  }
+
+  // Not awaited: a process without grund never serves, and the session
+  // must go on meanwhile.
+  Future<void> _announceWhenServing(
+    _Running running,
+    void Function() announce,
+  ) async {
+    final serving = await running.client.waitUntilServing();
+    if (serving && identical(_running, running)) announce();
   }
 
   Future<ReloadClient?> _connect(AppProcess process, Uri uri) async {
```

- [ ] **Крок 11: Проводка в `dev`**

Точка стартує до першого запуску застосунку і закривається в `finally` після зупинки сесії, тож не тримає процес `dev` (RF7).

`packages/grund_cli/lib/src/cli/dev_command.dart` (зміни):

```diff
--- a/packages/grund_cli/lib/src/cli/dev_command.dart
+++ b/packages/grund_cli/lib/src/cli/dev_command.dart
@@ -8,6 +8,7 @@ import 'package:watcher/watcher.dart';
 import '../dev/dev_printer.dart';
 import '../dev/dev_session.dart';
 import '../dev/dev_target.dart';
+import '../dev/live_reload_hub.dart';
 import '../dev/merged_watcher.dart';
 import '../dev/terminal_keys.dart';
 import '../generate/generation_session.dart';
@@ -67,8 +68,33 @@ final class DevCommand extends Command<int> {
     final options = argResults ?? (throw StateError('dev was not parsed.'));
     final package = PackageRoot.open(options.option('directory') ?? '.');
     final target = _target(package, options.option('target') ?? '');
+    // Open pages reconnect to the same endpoint across restarts; it ends
+    // with dev.
+    final liveReload = await LiveReloadHub.start();
+    try {
+      await _serve(package, target, options.rest, liveReload);
+    } finally {
+      await liveReload.close();
+    }
+    return CliExitCode.success.code;
+  }
+
+  Future<void> _serve(
+    PackageRoot package,
+    String target,
+    List<String> arguments,
+    LiveReloadHub liveReload,
+  ) async {
     final session = GenerationSession(package, generator: cli.generator);
-    final dev = _session(package, target, options.rest);
+    final dev = _session(
+      DevTarget(
+        package,
+        entry: target,
+        arguments: arguments,
+        environment: liveReload.environment,
+      ),
+      liveReload,
+    );
     final failure = Completer<void>();
     final keys = cli.keys().listen((key) => _press(dev, key, failure));
     final (:stopped, :subscription) = cli.interruption.listen(
@@ -89,7 +115,6 @@ final class DevCommand extends Command<int> {
         await subscription.cancel();
       }
     }
-    return CliExitCode.success.code;
   }
 
   Future<void> _run(
@@ -115,14 +140,19 @@ final class DevCommand extends Command<int> {
     }
   }
 
-  DevSession _session(PackageRoot package, String entry, List<String> rest) {
+  DevSession _session(DevTarget target, LiveReloadHub liveReload) {
     if (TerminalKeys.isInteractive) {
       cli.out.writeln('Press r to hot reload, R to hot restart.');
     }
     return DevSession(
-      DevTarget(package, entry: entry, arguments: rest),
-      printer: DevPrinter(package.display(entry), cli.out, cli.err),
+      target,
+      printer: DevPrinter(
+        target.package.display(target.entry),
+        cli.out,
+        cli.err,
+      ),
       out: cli.out,
+      onServing: liveReload.broadcastReload,
     );
   }
 
```

`packages/grund_cli/CHANGELOG.md` (зміни):

```diff
--- a/packages/grund_cli/CHANGELOG.md
+++ b/packages/grund_cli/CHANGELOG.md
@@ -4,6 +4,11 @@
   cookie sessions (`grund_jaspr`, `grund_auth`), a sign-in form, a
   stylesheet in `web/` and tests; `--template api` (the default) is the
   previous scaffold.
+- `dev` reloads open pages: it serves server-sent events on a loopback
+  port, passes the URL in `GRUND_LIVE_RELOAD_URL` and sends `reload` after
+  every reload with a successful reassemble and once a started or
+  restarted application serves (`grund_jaspr` adds the listening script to
+  its pages).
 
 ## 0.1.1
 
```

- [ ] **Крок 12: Тести**

Run: `cd packages/grund_cli && dart test test/live_reload_hub_test.dart` → `+6: All tests passed!` (серед них «close ends every stream and frees the port (RF7)»); `dart test test/dev_session_serving_test.dart` → `+4: All tests passed!`; `dart test test/dev_live_reload_test.dart` → `+1: All tests passed!`; увесь пакет `dart test` → `+175: All tests passed!` (близько хвилини).
Run: `cd packages/grund_cli && dart test integration/dev_test.dart` → `+5: All tests passed!` («a failing run ends the dev process with 70, not a hang» — уже з точкою SSE).

- [ ] **Крок 13: Перевірки і коміт**

Run: `dart analyze` → `No issues found!`; `dart format packages example` → `(0 changed)`; `wc -l packages/grund_cli/lib/src/dev/dev_session.dart packages/grund_cli/lib/src/cli/dev_command.dart` → 259 і 230 (< 300).

```bash
git add \
  packages/grund_cli/CHANGELOG.md \
  packages/grund_cli/lib/src/cli/dev_command.dart \
  packages/grund_cli/lib/src/dev/app_command.dart \
  packages/grund_cli/lib/src/dev/app_process.dart \
  packages/grund_cli/lib/src/dev/dev_session.dart \
  packages/grund_cli/lib/src/dev/dev_target.dart \
  packages/grund_cli/lib/src/dev/live_reload_hub.dart \
  packages/grund_cli/lib/src/dev/reload_client.dart \
  packages/grund_cli/lib/src/dev/reload_timeouts.dart \
  packages/grund_cli/test/app_process_test.dart \
  packages/grund_cli/test/dev_live_reload_test.dart \
  packages/grund_cli/test/dev_session_serving_test.dart \
  packages/grund_cli/test/helpers/dev.dart \
  packages/grund_cli/test/helpers/event_client.dart \
  packages/grund_cli/test/live_reload_hub_test.dart \
  packages/grund_cli/test/reload_client_test.dart \
  packages/grund_cli/test/reload_client_timeouts_test.dart
git commit -m "feat(cli): dev tells open pages to reload" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git show --stat --format=%s HEAD   # 17 файлів, лише ці
```

#### 12d. Скрипт у сторінках `grund_jaspr`

- [ ] **Крок 14: Падаючі тести**

`packages/grund_jaspr/test/live_reload_script_test.dart` (файл цілком, 120 рядків):

```dart
import 'dart:convert';

import 'package:grund_http/grund_http.dart';
import 'package:grund_jaspr/src/jaspr_error.dart';
import 'package:grund_jaspr/src/live_reload_script.dart';
import 'package:test/test.dart';

void main() {
  final url = Uri.parse('http://127.0.0.1:9000/');

  group('urlFrom', () {
    test('reads the variable grund dev sets', () {
      final read = LiveReloadScript.urlFrom({
        'GRUND_LIVE_RELOAD_URL': 'http://127.0.0.1:9000/',
      }, isProduct: false);

      expect(read, url);
    });

    test('is null without the variable', () {
      expect(LiveReloadScript.urlFrom(const {}, isProduct: false), isNull);
    });

    test('is null in a product build, whatever the variable says', () {
      final read = LiveReloadScript.urlFrom({
        'GRUND_LIVE_RELOAD_URL': 'http://127.0.0.1:9000/',
      }, isProduct: true);

      expect(read, isNull);
    });

    for (final value in ['ftp://127.0.0.1/', '/relative', 'http://', '::']) {
      test('refuses "$value"', () {
        expect(
          () => LiveReloadScript.urlFrom({
            'GRUND_LIVE_RELOAD_URL': value,
          }, isProduct: false),
          throwsA(isA<JasprSetupError>()),
        );
      });
    }
  });

  group('inject', () {
    test('puts the script before the last </body>', () {
      final html = LiveReloadScript.inject(
        '<body>a</body><!-- </body> --></BODY></html>',
        url,
      );

      expect(
        html,
        '<body>a</body><!-- </body> -->${LiveReloadScript.tag(url)}'
        '</BODY></html>',
      );
    });

    test('appends the script to HTML without </body>', () {
      expect(
        LiveReloadScript.inject('<p>a</p>', url),
        '<p>a</p>${LiveReloadScript.tag(url)}',
      );
    });
  });

  test('the tag listens for reload at the URL', () {
    expect(
      LiveReloadScript.tag(url),
      '<script>new EventSource("http://127.0.0.1:9000/")'
      '.addEventListener("reload",function(){location.reload()})</script>',
    );
  });

  test('the URL cannot close the script or the string', () {
    final tag = LiveReloadScript.tag(
      Uri.parse('http://127.0.0.1:9000/a"b</script>\\'),
    );
    final literal = tag.substring(
      '<script>new EventSource('.length,
      tag.indexOf(').addEventListener'),
    );

    expect(tag.indexOf('</script>'), tag.length - '</script>'.length);
    expect(jsonDecode(literal), startsWith('http://127.0.0.1:9000/a'));
  });

  group('addTo', () {
    test('leaves a response that is not HTML as it is', () {
      final response = HttpResponse.bytes(
        utf8.encode('<feed></feed>'),
        headers: HeaderMap.of({'content-type': 'application/xml'}),
      );

      expect(
        identical(LiveReloadScript.addTo(response, url), response),
        isTrue,
      );
    });

    test('adds the script to UTF-8 HTML and keeps status and headers', () {
      final response = HttpResponse(
        203,
        headers: HeaderMap.of({
          'content-type': 'text/html; charset=utf-8',
          'x-page': 'yes',
        }),
        body: BytesBody(utf8.encode('<body>ü</body>')),
      );

      final added = LiveReloadScript.addTo(response, url);

      expect(added.status, 203);
      expect(added.headers['x-page'], 'yes');
      expect(
        utf8.decode((added.body as BytesBody).bytes),
        '<body>ü${LiveReloadScript.tag(url)}</body>',
      );
    });
  });
}
```

`packages/grund_jaspr/test/live_reload_pages_test.dart` (файл цілком, 67 рядків):

```dart
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:test/test.dart';

import 'helpers/pages.dart';
import 'helpers/pages_app.dart';
import 'helpers/temp_dir.dart';

void main() {
  final url = Uri.parse('http://127.0.0.1:9/</script>');

  test('a page gets the live reload script before </body>', () async {
    final client = await PagesApp.start([
      JasprModule(
        app: UrlPage.new,
        config: JasprConfig(liveReloadUrl: url),
      ),
    ]);

    final response = await client.get('/');

    expect(response.text, contains('new EventSource("http://127.0.0.1:9/'));
    expect(response.text, isNot(contains('/</script>"')));
    expect(
      response.text.indexOf('EventSource'),
      lessThan(response.text.lastIndexOf('</body>')),
    );
  });

  test('a page gets no script without a URL', () async {
    final client = await PagesApp.start([const JasprModule(app: UrlPage.new)]);

    final response = await client.get('/');

    expect(response.text, isNot(contains('EventSource')));
  });

  test('a page that is not HTML gets no script', () async {
    final client = await PagesApp.start([
      JasprModule(
        app: FeedPage.new,
        config: JasprConfig(liveReloadUrl: url),
      ),
    ]);

    final response = await client.get('/feed.xml');

    expect(response.text, isNot(contains('EventSource')));
  });

  test('a static HTML file is served as it is', () async {
    final dir = TempDir.create();
    dir.write('web/about.html', '<html><body>about</body></html>');
    final client = await PagesApp.start([
      JasprModule(
        app: UrlPage.new,
        config: JasprConfig(
          staticDirectory: dir.resolve('web'),
          liveReloadUrl: url,
        ),
      ),
    ]);

    final response = await client.get('/about.html');

    expect(response.text, '<html><body>about</body></html>');
  });
}
```

Run: `cd packages/grund_jaspr && dart test test/live_reload_script_test.dart test/live_reload_pages_test.dart`
Expected: FAIL — помилка компіляції: `src/live_reload_script.dart` не існує, `JasprConfig` не має `liveReloadUrl`.

- [ ] **Крок 15: Скрипт**

`packages/grund_jaspr/lib/src/live_reload_script.dart` (файл цілком, 71 рядків):

```dart
import 'dart:convert';

import 'package:grund_http/grund_http.dart';

import 'jaspr_error.dart';
import 'jaspr_response.dart';

/// The script that reloads a page in the browser when `grund dev` reloaded
/// or restarted the application.
///
/// `grund dev` serves server-sent events on a loopback port and passes its
/// URL in [environmentVariable]; the script listens there for `reload`.
abstract final class LiveReloadScript {
  /// The variable `grund dev` sets for the application it runs.
  static const environmentVariable = 'GRUND_LIVE_RELOAD_URL';

  static const _isProduct = bool.fromEnvironment('dart.vm.product');

  /// The URL in [environment], or `null` when it is not set or [isProduct];
  /// throws [JasprSetupError] when it is not an absolute `http` URL.
  static Uri? urlFrom(
    Map<String, String> environment, {
    bool isProduct = _isProduct,
  }) {
    final value = environment[environmentVariable];
    if (isProduct || value == null) return null;
    final url = Uri.tryParse(value);
    if (url == null || !url.isScheme('http') || url.host.isEmpty) {
      throw JasprSetupError(
        '$environmentVariable must be an absolute http URL; it is "$value".',
      );
    }
    return url;
  }

  /// [response] with the script for [url] before its last `</body>`, or at
  /// its end without one; a response that is not UTF-8 HTML is returned as
  /// it is.
  static HttpResponse addTo(HttpResponse response, Uri url) {
    final type = response.headers['content-type']?.toLowerCase() ?? '';
    final body = response.body;
    if (!JasprResponse.isHtml(type) ||
        !type.contains('charset=utf-8') ||
        body is! BytesBody) {
      return response;
    }
    return HttpResponse(
      response.status,
      headers: response.headers,
      body: BytesBody(utf8.encode(inject(utf8.decode(body.bytes), url))),
    );
  }

  /// [html] with the script for [url] before its last `</body>` (in any
  /// case), or appended when there is none.
  static String inject(String html, Uri url) {
    final end = html.toLowerCase().lastIndexOf('</body>');
    final script = tag(url);
    return end < 0
        ? '$html$script'
        : '${html.substring(0, end)}$script${html.substring(end)}';
  }

  /// The `<script>` element for [url]. The URL is a JSON string with `<`
  /// escaped, so it cannot close the element.
  static String tag(Uri url) {
    final literal = jsonEncode('$url').replaceAll('<', r'\u003c');
    return '<script>new EventSource($literal).addEventListener("reload",'
        'function(){location.reload()})</script>';
  }
}
```

- [ ] **Крок 16: Конфіг, рендер, модуль**

`JasprModule` бере `config.liveReloadUrl`, а коли його немає — `LiveReloadScript.urlFrom(Platform.environment)` (поза product-збіркою; не абсолютна `http`-адреса — `JasprSetupError`, загорнута в `ProviderCreationError`, коли контейнер створює `JasprPages`). `PageRenderer` додає скрипт до відрендереної сторінки; статичні файли йдуть повз нього.

`packages/grund_jaspr/lib/src/jaspr_config.dart` (зміни):

```diff
--- a/packages/grund_jaspr/lib/src/jaspr_config.dart
+++ b/packages/grund_jaspr/lib/src/jaspr_config.dart
@@ -4,6 +4,7 @@ final class JasprConfig {
   const JasprConfig({
     this.staticDirectory = 'web',
     this.pageSuffixes = const ['html', 'htm', 'xml'],
+    this.liveReloadUrl,
   });
 
   /// The directory of the static files; a relative path is resolved
@@ -15,4 +16,17 @@ final class JasprConfig {
   /// another extension that is not a static file is a 404 instead of a
   /// page, the way Jaspr's own server does it.
   final List<String> pageSuffixes;
+
+  /// Where the live reload script of a page listens for `reload` events;
+  /// `null` adds no script. `JasprModule` fills it from the
+  /// `GRUND_LIVE_RELOAD_URL` that `grund dev` passes, outside product
+  /// builds, when it is `null`.
+  final Uri? liveReloadUrl;
+
+  /// A copy with [url] as the [liveReloadUrl].
+  JasprConfig withLiveReloadUrl(Uri? url) => JasprConfig(
+    staticDirectory: staticDirectory,
+    pageSuffixes: pageSuffixes,
+    liveReloadUrl: url,
+  );
 }
```

`packages/grund_jaspr/lib/src/page_renderer.dart` (зміни):

```diff
--- a/packages/grund_jaspr/lib/src/page_renderer.dart
+++ b/packages/grund_jaspr/lib/src/page_renderer.dart
@@ -5,17 +5,22 @@ import 'grund_scope.dart';
 import 'jaspr_error.dart';
 import 'jaspr_request.dart';
 import 'jaspr_response.dart';
+import 'live_reload_script.dart';
 
 /// Renders the page of one request: a new root component from [app] under
 /// a [GrundScope], through Jaspr, into an [HttpResponse].
 final class PageRenderer {
-  /// Renders [app].
-  const PageRenderer(this.app);
+  /// Renders [app]; with [liveReloadUrl], an HTML page gets the live reload
+  /// script.
+  const PageRenderer(this.app, {this.liveReloadUrl});
 
   /// Builds the root component; called for every request, so a hot reload
   /// shows in the next page.
   final Component Function() app;
 
+  /// Where the live reload script listens; `null` adds none.
+  final Uri? liveReloadUrl;
+
   /// The page for [c]; throws [PageRenderError] when Jaspr answers 500.
   Future<HttpResponse> render(HttpCtx c) async {
     final rendered = await renderComponent(
@@ -25,6 +30,8 @@ final class PageRenderer {
     if (rendered.statusCode == StatusCode.internalServerError) {
       throw PageRenderError(method: c.request.method, path: c.request.uri.path);
     }
-    return JasprResponse.from(rendered);
+    final response = JasprResponse.from(rendered);
+    final url = liveReloadUrl;
+    return url == null ? response : LiveReloadScript.addTo(response, url);
   }
 }
```

`packages/grund_jaspr/lib/src/jaspr_pages.dart` (зміни):

```diff
--- a/packages/grund_jaspr/lib/src/jaspr_pages.dart
+++ b/packages/grund_jaspr/lib/src/jaspr_pages.dart
@@ -20,7 +20,7 @@ final class JasprPages extends HttpApi {
     super.injector, {
     required Component Function() app,
     JasprConfig config = const JasprConfig(),
-  }) : _renderer = PageRenderer(app),
+  }) : _renderer = PageRenderer(app, liveReloadUrl: config.liveReloadUrl),
        _files = StaticFiles(config.staticDirectory),
        _pageSuffixes = config.pageSuffixes;
 
```

`packages/grund_jaspr/lib/src/jaspr_module.dart` (зміни):

```diff
--- a/packages/grund_jaspr/lib/src/jaspr_module.dart
+++ b/packages/grund_jaspr/lib/src/jaspr_module.dart
@@ -1,9 +1,12 @@
+import 'dart:io';
+
 import 'package:grund/grund.dart';
 import 'package:jaspr/server.dart';
 
 import 'jaspr_config.dart';
 import 'jaspr_pages.dart';
 import 'jaspr_setup.dart';
+import 'live_reload_script.dart';
 
 /// Server-side rendered pages of the Jaspr component [app], served by the
 /// application's `HttpModule` next to its APIs.
@@ -38,17 +41,23 @@ final class JasprModule extends Module {
   @override
   final List<Module> imports;
 
-  /// The static directory and the page suffixes.
+  /// The static directory, the page suffixes and the live reload URL.
   final JasprConfig config;
 
   @override
   List<Binding<Object>> get bindings => [
     Singleton<JasprPages>(
-      (i) => JasprPages(i, app: app, config: config),
+      (i) => JasprPages(i, app: app, config: _withEnvironment()),
       dependsOn: const [],
     ),
   ];
 
   @override
   void onInit(Injector injector) => JasprSetup.ensureInitialized();
+
+  JasprConfig _withEnvironment() => config.liveReloadUrl != null
+      ? config
+      : config.withLiveReloadUrl(
+          LiveReloadScript.urlFrom(Platform.environment),
+        );
 }
```

- [ ] **Крок 17: Тести `grund_jaspr`**

Run: `cd packages/grund_jaspr && dart test test/live_reload_script_test.dart` → `+13: All tests passed!` (серед них «the URL cannot close the script or the string», RF6); `dart test test/live_reload_pages_test.dart` → `+4: All tests passed!` (скрипт є в HTML-сторінці з адресою; немає без адреси, в XML-сторінці і в статичному `.html`, RF6); увесь пакет `dart test` → `+66: All tests passed!`.

- [ ] **Крок 18: Наскрізний інтеграційний тест**

Справжній `grund dev` над маленьким сайтом (`site_sources.dart`, сторінка показує свій pid): сторінка містить скрипт з адресою точки; після правки тексту компонента точка надсилає `reload`, а наступна відповідь має новий текст **без перезапуску** (той самий pid); після `R` (перезапуск) — знову `reload` і новий pid; після зупинки `dev` потік закінчується (RF7).

`packages/grund_cli/integration/helpers/site_sources.dart` (файл цілком, 62 рядків):

```dart
/// Sources of a small application `site` in the explicit API: one Jaspr
/// page at `/` that shows its version and the pid, served on the loopback
/// port of its first argument; it prints `listening on <port>`.
abstract final class SiteSources {
  /// The entry point.
  static const main = '''
import 'dart:io';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:site/site.dart';

Future<void> main(List<String> arguments) async {
  final port = int.parse(arguments.first);
  final app = App(
    root: const SiteModule(),
    overrides: [
      Singleton<HttpConfig>(
        (_) => HttpConfig(address: InternetAddress.loopbackIPv4, port: port),
        dependsOn: const [],
      ),
    ],
  );
  await app.start();
  print('listening on \$port');
}
''';

  /// `lib/site.dart`.
  static const site = '''
import 'dart:io';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_io/grund_io.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart' hide Key;

final class SiteModule extends Module {
  const SiteModule();

  @override
  List<Module> get imports => const [
    HttpModule(),
    IoAdapterModule(),
    JasprModule(app: HomePage.new),
  ];
}

final class HomePage extends StatelessComponent {
  const HomePage();

  @override
  Component build(BuildContext context) =>
      Document(body: p([Component.text('page v1 pid \$pid')]));
}
''';

  /// The files of the application.
  static const files = {'bin/main.dart': main, 'lib/site.dart': site};
}
```

`packages/grund_cli/integration/dev_jaspr_test.dart` (файл цілком, 62 рядків):

```dart
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../test/helpers/event_client.dart';
import '../test/helpers/temp_package.dart';
import 'helpers/dev_run.dart';
import 'helpers/site_sources.dart';

/// The HTML of `GET /` on [port].
Future<String> page(int port) async {
  final client = HttpClient();
  try {
    final request = await client.get('127.0.0.1', port, '/');
    return await utf8.decodeStream(await request.close());
  } finally {
    client.close(force: true);
  }
}

/// The URL the live reload script of [html] listens on.
Uri liveReloadUrl(String html) {
  final match = RegExp(r'new EventSource\("([^"]+)"\)').firstMatch(html);
  return Uri.parse(match?[1] ?? fail('No live reload script in $html'));
}

void main() {
  test(
    'a page edit shows in the next response and reloads open pages',
    () async {
      final package = await TempPackage.create('site', SiteSources.files);
      final dev = await DevRun.start(package.dir.path, port: await freePort());
      final first = await page(dev.port);
      final events = await EventClient.connect(liveReloadUrl(first));
      addTearDown(events.close);
      expect(await events.nextComment('connected'), isTrue);

      package.dir.write(
        'lib/site.dart',
        SiteSources.site.replaceFirst('page v1', 'page v2'),
      );

      expect(await events.nextEvent(), 'reload');
      final second = await page(dev.port);
      expect(second, contains('page v2'));
      expect(_pid(second), _pid(first));

      dev.keys.add('R');
      expect(await events.nextEvent(), 'reload');
      expect(_pid(await page(dev.port)), isNot(_pid(first)));

      await dev.stop();
      expect(await events.nextEvent(), isNull);
    },
  );
}

String? _pid(String html) => RegExp(r'pid (\d+)').firstMatch(html)?[1];
```

Run: `cd packages/grund_cli && dart test integration` → `+7: All tests passed!` (`dev_test` 5, `init_fullstack_test` 1, `dev_jaspr_test` 1; близько 40 с).

- [ ] **Крок 19: Перевірки і коміт**

Run: `dart analyze` → `No issues found!`; `dart format packages example` → `(0 changed)`; `cd example && dart test` → `+90: All tests passed!` (приклад без змінної середовища — без скрипта).

```bash
git add \
  packages/grund_cli/integration/dev_jaspr_test.dart \
  packages/grund_cli/integration/helpers/site_sources.dart \
  packages/grund_jaspr/lib/src/jaspr_config.dart \
  packages/grund_jaspr/lib/src/jaspr_module.dart \
  packages/grund_jaspr/lib/src/jaspr_pages.dart \
  packages/grund_jaspr/lib/src/live_reload_script.dart \
  packages/grund_jaspr/lib/src/page_renderer.dart \
  packages/grund_jaspr/test/live_reload_pages_test.dart \
  packages/grund_jaspr/test/live_reload_script_test.dart
git commit -m "feat(jaspr): reload open pages under grund dev" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git show --stat --format=%s HEAD   # 9 файлів, лише ці
```

---
### Задача 13: Документація і супровід

**Мета:** користувацька документація англійською для сторінок, сесій і live reload; повні README і CHANGELOG нових пакетів (бали pub.dev: опис, приклад, документація всіх публічних членів — уже є з задач 3–9 і 12); `CLAUDE.md` знає про два нові пакети, правило «`jaspr` лише в `grund_jaspr` і прикладі» і нову виняткову межу `BodyReader`; `docs/RELEASING.md`, CI (з задач 1, 3) і `publish.yaml` знають десять опублікованих пакетів; роадмап (spec §7) отримує етап G7a. **Жодного підняття `version:`**: нові пакети вже `0.1.0`, `grund_http` і `grund_cli` лишаються `0.1.0`/`0.1.1` із записами під `## 0.1.1`/`## 0.1.2` у CHANGELOG (задачі 2, 11, 12). Роадмап переписано на віхи без номерів версій, бо spec §7 («lockstep», «0.2.0…») суперечить чинному `docs/RELEASING.md` («Рішення плану», п. 15).

**Files:**
- Create: `docs/jaspr.md`
- Modify: `docs/{dev-mode,getting-started,http-and-hooks,faq,RELEASING}.md`, `docs/superpowers/ROADMAP.md`, `README.md`, `CLAUDE.md`, `.github/workflows/publish.yaml`, `packages/grund_jaspr/{README,CHANGELOG}.md`, `packages/grund_auth/{README,CHANGELOG}.md`, `packages/grund_cli/README.md`

**Interfaces:**
- Consumes: усе API задач 1–12 (імена в документації мусять збігатися з кодом: `JasprModule(app:, imports:, config:)`, `JasprConfig(staticDirectory:, pageSuffixes:, liveReloadUrl:)`, `GrundScope.of(context).cookies`, `context.call/maybe/injector`, `SessionModule(config:, store:)`, `SessionConfig(cookieName:, secure:, maxAge:, sameSite:, sameOrigin:)`, `Sessions.start/end/current`, `SessionHook`, `SameOriginHook`, `SetCookie(...).toHeader()`, `c.form()`, `StatusCode.seeOther`, `GRUND_LIVE_RELOAD_URL`, `init --template fullstack`).
- Produces: нічого для коду.

- [ ] **Крок 1: Посібник `docs/jaspr.md`**

Розділи: сторінка, модуль (API-маршрут `GET /` — `DuplicateRouteError`: `/` належить сторінкам), вхід, статичні файли, тестування, «Hot reload» (правка компонента — у наступній відповіді без перезапуску; новий маршрут — reassemble; нове поле — перезапуск; **не запускати під `jaspr serve`**), «Things to know» (попередження `.client.dart` при першому рендері — нешкідливе, не приглушується; cookie через `GrundScope.of(context).cookies`; компонент, що кидає, — 500 problem+json; сторінки `private, no-cache`; сесії в пам'яті; `useIsolates` — `JasprSetupError`).

`docs/jaspr.md` (файл цілком, 187 рядків):

````markdown
# Pages and sessions: Jaspr and grund_auth

One grund process can serve the JSON API and HTML pages rendered on the
server by [Jaspr](https://pub.dev/packages/jaspr), with one dependency
injection, one lifecycle and one cookie session:

- [`grund_jaspr`](../packages/grund_jaspr) renders pages: `JasprModule`
  serves `GET /` and `GET /*` below the API routes, and components read the
  call scope of their request (`context.call<T>()`).
- [`grund_auth`](../packages/grund_auth) keeps sessions: `Sessions.start`
  sets an `HttpOnly` cookie with an opaque token, and `SessionHook` puts
  the `CurrentUser` of every request with a live session in its call scope,
  where handlers and pages read it.

This release renders on the server only: there is no hydration (`@client`),
no client bundle and no `jaspr_builder`.

```sh
grund init --template fullstack my_site
cd my_site
dart pub get
grund dev        # http://localhost:8080
```

## A page

```dart
import 'package:grund_auth/grund_auth.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

final class HomePage extends StatelessComponent {
  const HomePage();

  @override
  Component build(BuildContext context) {
    final user = context.maybe<CurrentUser>();
    final tasks = context.call<TasksService>().list();
    return Document(
      title: 'Tasks',
      body: div([
        p([Component.text(user == null ? 'Signed out.' : 'Hi ${user.id}.')]),
        ul([for (final task in tasks) li([Component.text(task.title)])]),
      ]),
    );
  }
}
```

`context.call<T>()`, `context.maybe<T>()` and `context.injector` have the
semantics of `HttpCtx`: the bindings visible to `JasprModule` (the exports
of its `imports:` and of global modules) and what hooks `set` for this
request. `Component.text` escapes its text, so a user name cannot inject
markup.

`package:jaspr/server.dart` and `package:grund/grund.dart` both declare
`Key`. A file that imports both hides Jaspr's:
`import 'package:jaspr/server.dart' hide Key;`. A page file that imports
only `grund_jaspr` and `grund_auth` needs nothing hidden.

## The module

```dart
final class AppModule extends Module {
  const AppModule();

  @override
  List<Module> get imports => const [
    HttpModule(use: [HookRef<SessionHook>.type()]),
    IoAdapterModule(),
    SessionModule(config: SessionConfig(secure: false)), // dev over http
    JasprModule(app: Site.new, imports: [TasksModule()]),
  ];
}
```

- `JasprModule` does not import `HttpModule`; the application imports it
  once, and its hooks and middleware run for pages too.
- `app` builds the root component for **every request**. Route between
  pages inside it, with `context.url` or `jaspr_router`.
- API routes win: a literal or `:param` segment beats the pages' `*`, so
  `/tasks/1` is the API's and `/about` is a page. `GET /` belongs to the
  pages: an API route `GET /` is a `DuplicateRouteError` at startup.
- `JasprModule(app:)` takes a function, which an annotation cannot hold:
  write the module that imports it with the explicit API. It can sit next
  to annotated modules (the example's `WebModule` does).

## Signing in

The page posts a form to an ordinary `HttpApi`; the handler checks the
credential itself (this release has no password or OAuth support), starts
the session and redirects with 303:

```dart
Route.post('/login', (c) async {
  final form = await c.form();
  final user = await accounts.verify(
    form.string('name', minLength: 1),
    form.string('password'),
  ); // yours
  await sessions.start(c, user.id);
  return HttpResponse.redirect(Uri.parse('/'), status: StatusCode.seeOther);
}),
```

`c.form()` reads an `application/x-www-form-urlencoded` body into the
`Params` readers (a problem points at `/body/<name>`). `Sessions.start`
throws away the session the request came with and creates a new token, so a
cookie planted before the sign-in never becomes valid. The next `GET /`
passes `SessionHook`, and the page sees `context.maybe<CurrentUser>()`.
`Sessions.end(c)` signs out.

The cookie is `HttpOnly`, `SameSite=Lax`, `Path=/`, `Secure` unless
`SessionConfig(secure: false)` (development over plain `http` only), with
an absolute lifetime of 7 days. A handler can set cookies of its own next
to the session's (`SetCookie(...).toHeader()` on `c.response.headers` or in
a returned `HttpResponse`); every `set-cookie` reaches the browser.

Cross-site form posts are refused: `SessionHook` answers an unsafe request
whose `sec-fetch-site` is another site, or whose `origin` is not the
`host`, with a 403 `cross_site_request`. The
[`grund_auth` README](../packages/grund_auth/README.md) has every rule.

## Static files

`web/` next to `pubspec.yaml` is served before pages: `web/styles.css` is
`GET /styles.css`. Run the application from the package root (`grund dev`
does). Paths with dot segments, separators or links out of the directory
are never files. `JasprConfig(staticDirectory:)` names another directory.

## Testing

`TestApp` and `TestClient` render pages without a socket:

```dart
test('the home page lists the tasks', () async {
  final app = await TestApp.start(root: const AppModule());
  addTearDown(app.close);

  final page = await TestClient.of(app).get('/');

  expect(page.status, 200);
  expect(page.headers['content-type'], 'text/html; charset=utf-8');
  expect(page.text, contains('<li>Read the grund README</li>'));
});
```

A form post is `client.request('POST', '/login', body: 'name=ann',
headers: {'content-type': 'application/x-www-form-urlencoded'})`; send the
session back with `headers: {'cookie': ...}`.

## Hot reload

`grund dev` serves pages like any route: an edited component shows in the
next response, without a restart (the process id stays), because `app` is
called for every request. A new route of an `HttpApi` is picked up by the
reassemble; a new field restarts the process, as everywhere in
[dev mode](dev-mode.md).

Open pages reload themselves: `dev` passes the URL of its event stream in
`GRUND_LIVE_RELOAD_URL`, and `JasprModule` adds a small script before the
last `</body>` of every HTML page, which reloads the page after every
reload or restart. Nothing is added in a product build, without the
variable, to other responses or to static files.

Run the application under `grund dev`, not under `jaspr serve`: Jaspr's
dev server runs `main` again on every change and serves its own client
build.

## Things to know

- **The first render prints a warning about `.client.dart`** to stdout
  (`[WARNING] ...`). It is harmless: this release has no client
  components.
- **Read cookies with `GrundScope.of(context).cookies`**, not with Jaspr's
  `context.cookies`, which throws on a malformed `cookie` header.
- **A component that throws** is a 500 `application/problem+json`
  (`PageRenderError`); Jaspr prints the error to stderr. HTML error pages
  come later.
- **Pages are `private, no-cache`** unless a component sets
  `cache-control`: a page may depend on the session.
- **Sessions live in memory**: they end with the process (a restart under
  `grund dev` signs everyone out) and are not shared between processes.
- **Jaspr is initialized once per process**, without isolates. Calling
  `Jaspr.initializeApp(useIsolates: true)` yourself is a
  `JasprSetupError`.
````

- [ ] **Крок 2: Решта `docs/`**

`docs/dev-mode.md` (зміни):

````diff
--- a/docs/dev-mode.md
+++ b/docs/dev-mode.md
@@ -62,6 +62,27 @@ initializer, which a reload could handle, still restarts.
 - An application that exits or does not start is started again after the
   next change, never in a loop.
 
+## Pages reload in the browser
+
+`dev` also serves a stream of server-sent events on an ephemeral port of
+the loopback interface and passes its URL to the application in the
+environment variable `GRUND_LIVE_RELOAD_URL`. It sends the event `reload`
+after every reload whose reassemble succeeded and once a started or
+restarted application serves. Pages that listen there reload themselves:
+`grund_jaspr` adds the listening script to every HTML page it renders (see
+[Pages and sessions](jaspr.md#hot-reload)); any other page can do the same
+with
+
+```html
+<script>
+  new EventSource("<the URL>").addEventListener("reload", () => location.reload());
+</script>
+```
+
+The stream outlives restarts of the application and ends when `dev` stops.
+It listens on loopback only: a browser on another machine does not reach
+it (the page still works, it only does not reload).
+
 ## Keys
 
 In a terminal, `r` reloads and `R` restarts (both also start an
````

`docs/getting-started.md` (зміни):

```diff
--- a/docs/getting-started.md
+++ b/docs/getting-started.md
@@ -176,6 +176,13 @@ Everything the generator writes can be written by hand; the README's
 application on the explicit API, and [modules-and-di.md](modules-and-di.md)
 and [http-and-hooks.md](http-and-hooks.md) explain it.
 
+## A site with pages
+
+`grund init --template fullstack my_site` writes an application with HTML
+pages rendered on the server by Jaspr, a sign-in form and a cookie session,
+on the explicit API (no `gen` needed; `grund dev` runs it and reloads open
+pages). See [Pages and sessions](jaspr.md).
+
 ## Next
 
 - [Modules and dependency injection](modules-and-di.md)
```

`docs/http-and-hooks.md` (зміни):

```diff
--- a/docs/http-and-hooks.md
+++ b/docs/http-and-hooks.md
@@ -66,6 +66,7 @@ A handler receives an `HttpCtx` (`c`) that lives for one request:
 | `c.path`, `c.query`, `c.headers`, `c.cookies` | typed `Params` readers |
 | `await c.body(T.fromJson)` | the JSON object body as a `T` |
 | `await c.bodyList(T.fromJson)` | a JSON array of objects, as `List<T>` |
+| `await c.form()` | an `application/x-www-form-urlencoded` body, as `Params` |
 | `await c.bytes()` | the raw body |
 | `c.request` | the `HttpRequest` (method, `uri`, headers, body stream) |
 | `c.response` | the `ResponseHead` being built: `status` and `headers` |
@@ -85,6 +86,9 @@ of a repeated parameter. An absent required value is a 400
 `pointer` (`/query/limit`). A body that is not JSON, not an object, or that
 `fromJson` rejects is a 400 (`body_invalid`, pointer `/body`); one over
 `HttpConfig.maxBodyBytes` (1 MiB by default) is a 413 (`body_too_large`).
+`c.form()` reads the fields of a form post with the same readers (a problem
+points at `/body/<name>`); a malformed escape or UTF-8 sequence is a 400
+`body_invalid`. It does not check the `content-type`.
 
 ## Results
 
```

`docs/faq.md` (зміни):

```diff
--- a/docs/faq.md
+++ b/docs/faq.md
@@ -8,6 +8,12 @@ write it. Applications, tests and libraries work without any code
 generation, and the two styles mix in one graph: a generated module can
 import a hand-written one and the other way round.
 
+**Can grund serve HTML pages?**
+Yes, server-side rendered with Jaspr in the same process as the API:
+`grund_jaspr` serves the pages and static files, `grund_auth` adds a
+cookie session that pages and handlers share. Hydration (`@client`) is not
+supported yet. See [jaspr.md](jaspr.md).
+
 **Where is the controller, the guard, the pipe, the interceptor, the filter?**
 An `HttpApi` (`@Api`) is the controller. One type, `HttpHook`, replaces the
 rest: `before` is a guard (throw to refuse), `before` and `after` together are
```

- [ ] **Крок 3: README і CHANGELOG нових пакетів**

`packages/grund_jaspr/README.md` (зміни):

````diff
--- a/packages/grund_jaspr/README.md
+++ b/packages/grund_jaspr/README.md
@@ -2,4 +2,112 @@
 
 Server-side rendered [Jaspr](https://pub.dev/packages/jaspr) pages in a
 grund application: one process serves the API and the pages, with one
-dependency injection and one lifecycle.
+dependency injection, one lifecycle and the same hooks.
+
+```dart
+import 'package:grund/grund.dart';
+import 'package:grund_http/grund_http.dart';
+import 'package:grund_io/grund_io.dart';
+import 'package:grund_jaspr/grund_jaspr.dart';
+import 'package:jaspr/dom.dart';
+import 'package:jaspr/server.dart' hide Key;
+
+final class HomePage extends StatelessComponent {
+  const HomePage();
+
+  @override
+  Component build(BuildContext context) {
+    // VisitCounter is a singleton that CounterModule exports.
+    final count = context.call<VisitCounter>().visit();
+    return Document(body: p([Component.text('Visit number $count.')]));
+  }
+}
+
+final class AppModule extends Module {
+  const AppModule();
+
+  @override
+  List<Module> get imports => const [
+    HttpModule(),
+    IoAdapterModule(),
+    JasprModule(app: HomePage.new, imports: [CounterModule()]),
+  ];
+}
+
+Future<void> main() => App(root: const AppModule()).run();
+```
+
+`package:jaspr/server.dart` and `package:grund/grund.dart` both declare
+`Key`: in a file that imports both, hide Jaspr's (`hide Key`). The example
+tab has the whole program.
+
+## Pages
+
+- `JasprModule(app:)` serves `GET /` and `GET /*` (and `HEAD` with them)
+  below every API route: a literal or `:param` segment of an API wins over
+  `*`, so `/tasks/1` stays the API's and `/about` is a page.
+- `app` is called for **every request** and builds the root component;
+  route between pages in it (with `context.url`, or `jaspr_router`). Under
+  `grund dev` an edited component shows in the next response.
+- `JasprModule` does not import `HttpModule`: the application imports it
+  once, with its own hooks, middleware and configuration, and pages go
+  through them like any route (a global hook runs before a page is built).
+- A component reads the request's call scope through `BuildContext`:
+  `context.call<T>()` (throws when there is none), `context.maybe<T>()`,
+  `context.injector`; the semantics are those of `HttpCtx`. The bindings
+  visible there are the exports of `JasprModule(imports:)` and of global
+  modules, plus what hooks `set` for the request (`grund_auth`'s
+  `CurrentUser`). `GrundScope.of(context)` is the `HttpCtx` itself: read
+  cookies with `GrundScope.of(context).cookies`, not with Jaspr's
+  `context.cookies`, which throws on a malformed `cookie` header.
+- The response keeps everything Jaspr set: the status, every `set-cookie`
+  (`context.setCookie`), other headers. An HTML page without a charset gets
+  `text/html; charset=utf-8`; a page without `cache-control` gets
+  `private, no-cache` (a page may depend on the session). `content-length`
+  is left to the adapter.
+- A component that throws (Jaspr prints the error and answers 500) is a
+  `PageRenderError`, answered like any failure as a 500
+  `application/problem+json`. HTML error pages are not part of this
+  release.
+
+## Static files
+
+`JasprConfig(staticDirectory: 'web')` (the default) serves the files of
+`web/` before pages: `GET /styles.css` is `web/styles.css` with its type
+and `cache-control: no-cache`.
+
+- The directory is resolved against the working directory: run the
+  application from its package root. A directory that does not exist
+  serves nothing; it is not an error.
+- A path maps to a file only when every segment is a plain name: not empty,
+  not starting with `.` (no `..`, no `.env`), without `/`, `\`, `:` or
+  control characters (a percent-encoded `%2F` arrives decoded in a
+  segment), and the file, with symbolic links resolved, lies inside the
+  directory. Anything else is not a file, and the path is a page or a 404.
+- A path whose extension is not a page suffix
+  (`JasprConfig(pageSuffixes:)`, by default `html`, `htm` and `xml`) and
+  that is not a file is a 404 `file_not_found`, not a page.
+
+## Live reload
+
+Under `grund dev`, open pages reload themselves after every reload or
+restart of the application. `dev` passes the URL of its event stream in
+`GRUND_LIVE_RELOAD_URL`, and `JasprModule` then adds a small script before
+the last `</body>` of every HTML page it renders. Nothing is added in a
+product build (`dart compile exe`), without the variable, to responses that
+are not UTF-8 HTML, or to static files. `JasprConfig(liveReloadUrl:)` sets
+the URL by hand.
+
+## Things to know
+
+- Jaspr's process-wide state is initialized once, in `onInit`, without
+  isolates; several applications in one process (tests) share it. A
+  `Jaspr.initializeApp(useIsolates: true)` of your own is a
+  `JasprSetupError`: a page reads the call scope of its request, which
+  another isolate cannot reach.
+- The first render prints a `[WARNING]` about a missing `.client.dart`
+  file to stdout. It is harmless: there are no client components in this
+  release.
+- Do not run the application under `jaspr serve`; use `grund dev`.
+- Not in this release: hydration (`@client`), `jaspr_builder`, HTML error
+  pages.
````

`packages/grund_jaspr/CHANGELOG.md` (зміни):

```diff
--- a/packages/grund_jaspr/CHANGELOG.md
+++ b/packages/grund_jaspr/CHANGELOG.md
@@ -1,3 +1,21 @@
 ## 0.1.0
 
 Initial release.
+
+- `JasprModule(app:, imports:, config:)`: serves server-side rendered Jaspr
+  pages on `GET /` and `GET /*` below the application's API routes, through
+  its `HttpModule` hooks and middleware; the root component is built for
+  every request.
+- `GrundScope` and the `BuildContext` extension `GrundContext`:
+  `context.call<T>()`, `context.maybe<T>()` and `context.injector` read the
+  call scope of the request being rendered.
+- The response keeps Jaspr's status and headers, every `set-cookie`
+  included; HTML gets a UTF-8 charset and pages `private, no-cache` unless
+  the page set its own.
+- Static files from `JasprConfig.staticDirectory` (`web/`), refusing dot
+  segments, separators and paths that leave the directory; a path with an
+  extension that is not a page suffix and not a file is a 404.
+- A page that fails to render is a `PageRenderError` (a 500
+  `application/problem+json`).
+- Under `grund dev` (`GRUND_LIVE_RELOAD_URL`), HTML pages get a script that
+  reloads them after every reload or restart; never in product builds.
```

`packages/grund_auth/README.md` (зміни):

````diff
--- a/packages/grund_auth/README.md
+++ b/packages/grund_auth/README.md
@@ -3,3 +3,113 @@
 Cookie sessions for grund applications: an opaque session token in an
 `HttpOnly` cookie, a global hook that puts the `CurrentUser` of a request in
 its call scope, and a same-origin check for unsafe requests.
+
+```dart
+final class AccountApi extends HttpApi {
+  AccountApi(super.injector, this._sessions);
+
+  final Sessions _sessions;
+
+  @override
+  List<Route> get routes => [
+    Route.post('/login', _login),
+    Route.get('/me', (c) => {'user': c.maybe<CurrentUser>()?.id}),
+  ];
+
+  Future<HttpResponse> _login(HttpCtx c) async {
+    final name = (await c.form()).string('name', minLength: 1);
+    // Check a password or another credential here before signing in.
+    await _sessions.start(c, name);
+    return HttpResponse.redirect(Uri.parse('/me'), status: StatusCode.seeOther);
+  }
+}
+
+final class AppModule extends Module {
+  const AppModule();
+
+  @override
+  List<Module> get imports => const [
+    HttpModule(use: [HookRef<SessionHook>.type()]),
+    IoAdapterModule(),
+    // Plain http here; keep the default `secure: true` behind HTTPS.
+    SessionModule(config: SessionConfig(secure: false)),
+  ];
+
+  @override
+  List<Binding<Object>> get bindings => [
+    Singleton<AccountApi>(
+      (i) => AccountApi(i, i<Sessions>()),
+      dependsOn: const [Key<Sessions>()],
+    ),
+  ];
+}
+```
+
+This package checks no credentials: the application verifies a password,
+a one-time code or anything else, then calls `Sessions.start`.
+
+## Sessions
+
+- `SessionModule` is global and binds `SessionConfig`, `SessionStore`
+  (`InMemorySessionStore` unless `store:` creates another), `Sessions` and
+  `SessionHook`. Register the hook once, globally:
+  `HttpModule(use: [HookRef<SessionHook>.type()])`.
+- `Sessions.start(c, userId)` deletes the session the request came with,
+  creates a new one under a fresh token and sets its cookie. A token known
+  before the sign-in never becomes valid, so a planted cookie cannot fix
+  the session. It also puts the `CurrentUser` in the call scope of the
+  request.
+- `Sessions.end(c)` deletes the session and sends the cookie empty with
+  `Max-Age=0`. `Sessions.current(c)` is the live session or `null`.
+- `SessionHook` puts `CurrentUser(userId)` in the call scope of a request
+  with a live session: `c.maybe<CurrentUser>()` in a handler or hook,
+  `context.maybe<CurrentUser>()` in a `grund_jaspr` page. No cookie, a
+  value that is not a token, an unknown or an expired session is not an
+  error: the request simply has no `CurrentUser`.
+- A token is 32 bytes of `Random.secure()`, base64url without padding (43
+  characters). The cookie carries only the token; nothing is signed and
+  there are no keys. A session lasts `SessionConfig.maxAge` (7 days) from
+  the sign-in and is not extended by use.
+- `InMemorySessionStore` loses its sessions when the process ends and is
+  not shared between processes. Implement `SessionStore` (`create`, `read`,
+  `delete`) for a durable one.
+
+## The cookie
+
+`SessionConfig` names the cookie (`grund_sid`) and sets `secure` (on by
+default), `maxAge`, `sameSite` (`Lax`) and `sameOrigin`. The cookie is
+always `HttpOnly` with `Path=/` and no `Domain`:
+
+```text
+set-cookie: grund_sid=<token>; Max-Age=604800; Path=/; Secure; HttpOnly; SameSite=Lax
+```
+
+The configuration is checked when the application starts and throws a
+`SessionConfigError` before the server serves: a name that is not a cookie
+token, a `maxAge` under one second, `SameSite=None` without `Secure`, or a
+`__Host-`/`__Secure-` name without `Secure`. Turn `secure` off only for
+development over plain `http`.
+
+`SetCookie` writes any other cookie the same checked way:
+`c.response.headers.add('set-cookie', SetCookie('theme', 'dark').toHeader())`.
+A name that is not a token, a value with a space, quote, comma, semicolon,
+backslash or control character, a path with `;`, a negative `maxAge` or
+`SameSite=None` without `Secure` throws a `CookieFormatError`, so a value
+taken from a request cannot add attributes or headers. Several
+`set-cookie` headers (the session's and the handler's own) all reach the
+client.
+
+## Cross-site requests
+
+With `SessionConfig.sameOrigin` (the default) `SessionHook` refuses an
+unsafe request (not `GET`, `HEAD` or `OPTIONS`) that a browser sent from
+another site with a 403 `cross_site_request`: one whose `sec-fetch-site`
+is neither `same-origin` nor `none`, or whose `origin` does not name the
+`host` it was sent to. A request without these headers (curl, another
+server) passes. `SameOriginHook` is the same check for an application
+without sessions. Together with `SameSite=Lax` it replaces CSRF tokens for
+browsers that send these headers; behind a proxy that rewrites `host`,
+forward the original one.
+
+Not in this release: passwords, OAuth, JWT, CSRF tokens, roles, durable
+stores.
````

`packages/grund_auth/CHANGELOG.md` (зміни):

```diff
--- a/packages/grund_auth/CHANGELOG.md
+++ b/packages/grund_auth/CHANGELOG.md
@@ -1,3 +1,14 @@
 ## 0.1.0
 
 Initial release.
+
+- `SessionModule`, `SessionConfig`, `Sessions` (`start`, `end`,
+  `current`): cookie sessions with an opaque random token, a new token on
+  every sign-in (no session fixation) and an absolute lifetime.
+- `SessionHook`: puts the `CurrentUser` of a live session in the call
+  scope and, with `SessionConfig.sameOrigin`, refuses unsafe cross-site
+  requests; `SameOriginHook` is that check alone.
+- `SessionStore` and `InMemorySessionStore`.
+- `SetCookie`, `CookieAttributes` and `SameSitePolicy`: `set-cookie`
+  values checked against RFC 6265 (`CookieFormatError`); an invalid
+  `SessionConfig` is a `SessionConfigError` at startup.
```

- [ ] **Крок 4: README `grund_cli` і кореневий README**

README `grund_cli` називає версії, яких потребує шаблон `fullstack` (`grund_http ^0.1.1`, `grund_auth`/`grund_jaspr ^0.1.0`, `jaspr '>=0.23.5 <0.24.0'`).

`packages/grund_cli/README.md` (зміни):

````diff
--- a/packages/grund_cli/README.md
+++ b/packages/grund_cli/README.md
@@ -13,6 +13,7 @@ dart run grund_cli gen --directory packages/shop
 dart run grund_cli dev                    # run bin/main.dart, hot reload on every change
 dart run grund_cli dev -t bin/server.dart -- --port 8080
 dart run grund_cli init my_app            # a new package in ./my_app
+dart run grund_cli init --template fullstack my_site   # pages and sessions
 ```
 
 `--directory` is `-C`, `--watch` is `-w` and `--target` is `-t`. Installed as
@@ -142,6 +143,13 @@ Restarting bin/main.dart: lib/src/greeter.dart changed a field, a constructor or
   5 s, a reload 60 s, closing the applications 5 s and the application's
   first sign of life 30 s; then the step fails with a message and `dev`
   goes on (or, for the last, stops the application until the next change).
+- Open pages reload themselves. `dev` serves server-sent events on an
+  ephemeral loopback port for as long as it runs and passes their URL to
+  the application in `GRUND_LIVE_RELOAD_URL`; it sends `event: reload`
+  after every reload whose reassemble succeeded and once a started or
+  restarted application serves (the reassemble extension answers). A
+  `grund_jaspr` application adds the listening script to its pages; nothing
+  else changes for an application that ignores the variable.
 - `dev` runs the target with `dart <target>`, not `dart run`: no implicit
   `pub get` on every restart, and one process whose `pid` is the
   application's. Run `dart pub get` after editing `pubspec.yaml`, then
@@ -149,9 +157,12 @@ Restarting bin/main.dart: lib/src/greeter.dart changed a field, a constructor or
 
 ## init
 
-`init <directory>` writes a new package into a new or empty directory; the
-directory name is the package name (lowercase_with_underscores, not a Dart
-reserved word, and not one of the packages the template depends on):
+`init [--template <name>] <directory>` writes a new package into a new or
+empty directory; the directory name is the package name
+(lowercase_with_underscores, not a Dart reserved word, and not one of the
+packages the template depends on). There are two templates.
+
+`--template api` (the default) is a JSON API written with annotations:
 `pubspec.yaml`, `analysis_options.yaml`, `.gitignore`, `lib/src/hello.dart`
 (a service and an `@Api` with its `part`), `lib/src/app_module.dart` (the
 root `AppModule`, which imports `HttpModule` and `IoAdapterModule`) and
@@ -171,8 +182,27 @@ dart run bin/main.dart    # GET http://localhost:8080/hello?name=you
 The scaffold's entry point is `bin/main.dart`, so `dart run grund_cli dev`
 runs it without `--target`.
 
-The scaffold depends on `grund`, `grund_http`, `grund_io` and `grund_cli`
-at `^0.1.0`. To try it against a checkout of the
+`--template fullstack` is a site written with the explicit API, served by
+`grund_jaspr` with sessions from `grund_auth`: `lib/src/app_module.dart`
+(`HttpModule` with the `SessionHook`, `SessionModule`, `JasprModule`, the
+`AccountApi` that signs in and out through forms), the pages in
+`lib/src/pages/` (a home page that greets the signed-in user, a sign-in
+page), `web/styles.css`, `bin/main.dart` and `test/app_test.dart` (the
+home page and a sign-in through `TestApp`). It needs no `gen`:
+
+```sh
+cd my_site
+dart pub get
+dart run grund_cli dev    # http://localhost:8080
+```
+
+The session cookie is `Secure` only in product builds, so sign-in works
+over plain `http` under `dev`; serve a product build behind HTTPS.
+
+The api scaffold depends on `grund`, `grund_http`, `grund_io` and
+`grund_cli` at `^0.1.0`; the fullstack one also on `grund_auth` and
+`grund_jaspr` at `^0.1.0`, on `grund_http` at `^0.1.1` and on `jaspr`
+`>=0.23.5 <0.24.0`. To try a scaffold against a checkout of the
 repository instead of pub.dev, add to its `pubspec.yaml` (with your path):
 
 ```yaml
@@ -185,6 +215,9 @@ dependency_overrides:
   grund_io: {path: ../grund/packages/grund_io}
 ```
 
+(and, for the fullstack scaffold, `grund_auth` and `grund_jaspr` the same
+way).
+
 ## Exit codes
 
 | Code | When |
````

`README.md` (зміни):

```diff
--- a/README.md
+++ b/README.md
@@ -153,6 +153,13 @@ Future<void> main() => App(root: const AppModule()).run();
 The two styles mix freely: a generated module can import a hand-written one
 and the other way round.
 
+### Pages and sessions
+
+`grund init --template fullstack my_site` writes a site whose HTML pages
+are rendered on the server by Jaspr (`grund_jaspr`) in the same process as
+its API, with a cookie session (`grund_auth`) that pages and handlers both
+see. See [docs/jaspr.md](docs/jaspr.md).
+
 ## Packages
 
 | Package | What it is |
@@ -165,6 +172,8 @@ and the other way round.
 | [`grund_http_generator`](packages/grund_http_generator) | The `@Api` part of the generator: routes, parameters, hooks, validators, bodies. |
 | [`grund_cli`](packages/grund_cli) | The `grund` command: `gen`, `gen --watch`, `dev` (hot reload), `init`. |
 | [`grund_build`](packages/grund_build) | The same generation as a build_runner builder. |
+| [`grund_jaspr`](packages/grund_jaspr) | `JasprModule`: server-side rendered Jaspr pages and static files next to the API, with the call scope in every component. |
+| [`grund_auth`](packages/grund_auth) | Cookie sessions: `SessionModule`, `Sessions`, `SessionHook` (the `CurrentUser` of a request), `SameOriginHook`, `SetCookie`. |
 
 Every package README lists the exact rules of that package.
 
@@ -203,6 +212,7 @@ GraphQL, microservice transports, OpenAPI generation. See
 - [Annotations and code generation](docs/annotations-and-codegen.md)
 - [Adapters: dart:io and shelf](docs/adapters.md)
 - [Dev mode and hot reload](docs/dev-mode.md)
+- [Pages and sessions: Jaspr and grund_auth](docs/jaspr.md)
 - [build_runner](docs/build-runner.md)
 - [Logging](docs/logging.md)
 - [Testing](docs/testing.md)
```

- [ ] **Крок 5: `CLAUDE.md`**

`CLAUDE.md` (зміни):

```diff
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -22,14 +22,17 @@ pluggable HTTP adapters. It is a Dart pub workspace of pure-Dart packages.
   stage ships.
 - User documentation: `README.md` and `docs/*.md` (English); the example
   application: `example/` (`tasks_api`, a workspace member, not published;
-  the same application in annotations and in the explicit API, tested end to
-  end on both adapters); releases: `docs/RELEASING.md`.
+  the same application in annotations and in the explicit API, with Jaspr
+  pages and a session, tested end to end on both adapters); releases:
+  `docs/RELEASING.md`.
 - Packages (published, versioned independently): `grund` (core: modules, DI, runners,
   logging, no HTTP), `grund_http` (HTTP values, hooks, routing, server
   runner, adapter contract, HTTP annotations), `grund_io` and `grund_shelf`
   (adapters), `grund_generator` (core generator, no HTTP),
   `grund_http_generator` (`@Api` generator), `grund_cli` (`gen`, `dev`,
-  `init`), `grund_build` (build_runner builder). Unpublished:
+  `init`), `grund_build` (build_runner builder), `grund_jaspr`
+  (server-side rendered Jaspr pages and static files), `grund_auth`
+  (cookie sessions). Unpublished:
   `grund_conformance` (adapter test suite), the fixture packages
   `cases_app`, `http_cases_app`, `users_app`, and `example`.
 
@@ -79,7 +82,7 @@ only. It has not run yet.
 
 ## Releases
 
-- The eight published packages are versioned independently: only a
+- The ten published packages are versioned independently: only a
   changed package gets a new version. A constraint between workspace
   members is the lowest version that has what the dependent needs. A release
   is made by pushing the tag `<package>-vX.Y.Z`, which runs
@@ -122,7 +125,9 @@ only. It has not run yet.
   URI, the HTTP prefix supplied by `ApiConstruct`, and the boundary test
   below is unchanged; `analyzer` is allowed only in `grund_generator`/
   `grund_http_generator`/`grund_cli`/`grund_build`, `vm_service` only in
-  `grund_cli`, and `build` only in `grund_build`. `dart:developer` (SDK) is allowed in the core for
+  `grund_cli`, `build` only in `grund_build`, and `jaspr` only in
+  `grund_jaspr` and the example (`grund_auth` does not depend on it, and
+  `grund_jaspr` not on `grund_auth`). `dart:developer` (SDK) is allowed in the core for
   the hot reload service extensions, which register only outside product
   mode.
 - **The core generator knows no HTTP.** `grund_generator` reads modules,
@@ -198,8 +203,12 @@ only. It has not run yet.
   interruption:, keys:)`), never as a child process. The exceptions are
   `dev`'s: its tests start the user's application as a child process with
   the VM service on loopback (`AppProcess`, `DevSession`), and
-  `integration/dev_test.dart` (run with `dart test integration`, not part
-  of `dart test`) also runs the real `grund dev` as a child process.
+  `integration/` (run with `dart test integration`, not part of `dart
+  test`) runs the real `grund dev` as a child process (`dev_test.dart`,
+  and `dev_jaspr_test.dart`: a page edit and the live reload event) and
+  runs the tests of a fresh `init --template fullstack` package with the
+  VM directly against this workspace (`init_fullstack_test.dart`, no `pub
+  get`).
   `grund_build` tests build in memory with `build_test`
   (`TestReaderWriter` + `loadIsolateSources()`, no `pub get`), and compare
   with the CLI through `GenerationSession` on a `TempDir` package;
@@ -287,7 +296,8 @@ producing a response):
   catches the same error while encoding `details` and falls back to a body
   without them, so the last-resort 500 is always produced; `BodyReader`
   turns a `FormatException` or the `TypeError` of a failed cast in a user
-  `fromJson` into a 400 (any other failure is a bug and propagates);
+  `fromJson`, and the `FormatException` of a malformed form body (`c.form()`),
+  into a 400 (any other failure is a bug and propagates);
   `RequestDispatcher` answers 400 for a malformed percent-encoding of the
   path (`FormatException` of `Uri.pathSegments`);
 - the `dev` command boundary (`grund_cli`): `DevCommand` catches `on
```

- [ ] **Крок 6: Роадмап (spec §7)**

`docs/superpowers/ROADMAP.md` (зміни):

```diff
--- a/docs/superpowers/ROADMAP.md
+++ b/docs/superpowers/ROADMAP.md
@@ -16,40 +16,46 @@ reload, build_runner-драйвер, приклад і документація)
 Попередні пункти v1.1/v2.0 (OpenAPI, lifecycle, GraphQL) поглинуті етапами
 нижче.
 
-## grund: релізи 0.x → 1.0
+## grund: віхи 0.x → 1.0
 
-Випускаємо частинами: кожен реліз дає робочу платформу з тим, що вже є, і
+Випускаємо частинами: кожна віха дає робочу платформу з тим, що вже є, і
 публікується на pub.dev. Обсяг 1.0 — увесь v1 з рамки (auth, realtime,
 infra); 0.x — шлях до нього. До 1.0 несумісні зміни дозволені в мінорній
 версії й позначаються `**Breaking:**` у CHANGELOG.
 
-Кожен реліз закінчується однаковим кроком випуску: CHANGELOG усіх пакетів,
-README і quick start для того, що вже є, приклад покриває всі опубліковані
-модулі, `publish --dry-run` без попереджень; публікацію й теги робить
-мейнтейнер вручну за `docs/RELEASING.md`. Версія lockstep: усі `grund_*`
-мають одну версію; новий пакет зʼявляється з версією свого релізу.
+Версії пакетів незалежні (`docs/RELEASING.md`): реліз пакета — тег
+`<package>-vX.Y.Z`, нову версію отримує лише змінений пакет (несумісна зміна —
+мінорна, решта — патч), обмеження між членами workspace — найнижча версія, що
+має потрібне залежному. Новий пакет починає з `0.1.0`; першу версію публікують
+вручну. Віха закінчується однаковим кроком випуску: CHANGELOG кожного зміненого
+пакета, README і quick start для того, що вже є, приклад покриває всі
+опубліковані модулі, `publish --dry-run` без попереджень для всіх пакетів;
+версії, теги й публікацію робить мейнтейнер вручну за `docs/RELEASING.md`.
 
-| Реліз | Етапи | Пакети, що додаються | Має бути опубліковано заздалегідь | Готово, коли |
+| Віха | Етапи | Пакети, що додаються | Має бути опубліковано заздалегідь | Готово, коли |
 |---|---|---|---|---|
-| **0.1.0** — REST з контрактом | G1, G2 | `grund`, `grund_http`, `grund_io`, `grund_shelf`, `grund_generator`, `grund_http_generator`, `grund_cli`, `grund_build`, `grund_openapi` | — (typed_openapi T1–T2 потрібні лише контрактним тестам у неопублікованому `example/`) | Етапи G1 і G2 здані; крок випуску |
-| **0.2.0** — дані | G3 | `grund_basalt`, `grund_basalt_postgres`, `grund_basalt_sqlite` | basalt з B1–B3 | G3 здано; крок випуску |
-| **0.3.0** — auth | G4 | `grund_auth`, `grund_auth_oauth` | basalt з B4; token_manager K1 | G4 здано; крок випуску |
-| **0.4.0** — realtime | G5 | `grund_sse`, `grund_redis`, `grund_pubsub` | typed_sse 0.1.0 (S1); typed_openapi з T4 | G5 здано; крок випуску |
-| **0.5.0** — інфраструктура | G6 | `grund_jobs`, `grund_cache`, `grund_storage`, `grund_storage_s3`, `grund_observability` | — (basalt B2 вийшов у 0.2.0) | G6 здано; крок випуску |
-| **0.6.0** — WebSocket, Jaspr, init | G7 | `grund_ws`, `grund_jaspr`, шаблони `grund_cli init` | — | G7 здано; крок випуску |
-| **1.0.0** — стабілізація | G8 | — | typed_openapi 0.1.0 (T5) | Публічний API заморожено, застарілі члени прибрано, сайт документації, гайд міграції з 0.x, відгуки з 0.x закриті або перенесені |
+| **REST** ✅ | G1 | `grund`, `grund_http`, `grund_io`, `grund_shelf`, `grund_generator`, `grund_http_generator`, `grund_cli`, `grund_build` (опубліковано `0.1.x`) | — | Здано |
+| **Сторінки й сесії** | G7a | `grund_jaspr`, `grund_auth` (лише сесії); шаблон `grund init --template fullstack` | — | G7a здано; крок випуску (`grund_http` з `c.form()` і злиттям `set-cookie` — раніше за нові пакети й `grund_cli`) |
+| **Контракт** | G2 | `grund_openapi` | — (typed_openapi T1–T2 потрібні лише контрактним тестам у неопублікованому `example/`) | G2 здано; крок випуску |
+| **Дані** | G3 | `grund_basalt`, `grund_basalt_postgres`, `grund_basalt_sqlite` | basalt з B1–B3 | G3 здано; крок випуску |
+| **Auth** | G4 | `grund_auth_oauth`; нові можливості `grund_auth` | basalt з B4; token_manager K1 | G4 здано; крок випуску |
+| **Realtime** | G5 | `grund_sse`, `grund_redis`, `grund_pubsub` | typed_sse 0.1.0 (S1); typed_openapi з T4 | G5 здано; крок випуску |
+| **Інфраструктура** | G6 | `grund_jobs`, `grund_cache`, `grund_storage`, `grund_storage_s3`, `grund_observability` | — (basalt B2 вийшов у віхі «Дані») | G6 здано; крок випуску |
+| **WebSocket, гідратація, шаблони** | G7b | `grund_ws`; гідратація в `grund_jaspr`; решта шаблонів `grund_cli init` | — | G7b здано; крок випуску |
+| **1.0.0** — стабілізація | G8 | — | typed_openapi 0.1.0 (T5) | Усі пакети `1.0.0`; публічний API заморожено, застарілі члени прибрано, сайт документації, гайд міграції з 0.x, відгуки з 0.x закриті або перенесені |
 
 Етапи:
 
 | # | Етап | Пакети цього репо | Залежить від інших репо | Готово, коли |
 |---|---|---|---|---|
 | G1 ✅ | **Ядро, HTTP, генератор** (spec `2026-10-15-grund-core-design.md`, вивід `2026-10-15-grund-generated-output-layout-design.md`; плани `2026-10-15-grund-g1-core-http-generator.md` і `...-g1-1-output-layout.md`; перейменування `dartnest*` → `grund*` зроблено) | `grund`, `grund_http`, `grund_generator`, `grund_http_generator`, `grund_cli`, `grund_build`, `grund_io`, `grund_shelf` (анотації: `package:grund/annotations.dart` і `package:grund_http/annotations.dart`) | — | Здано: приклад `tasks_api` у двох формах проходить ті самі e2e на обох адаптерах; `grund` без HTTP у залежностях; golden-фікстура `users_app` на новій моделі (плоский `X.g.dart`, `part` для `@Api`) |
+| G7a | **Jaspr SSR і сесії** (spec `2026-10-16-grund-jaspr-design.md`; план `2026-10-16-grund-g7a-jaspr-ssr.md`) | `grund_jaspr`, `grund_auth` (сесії), `grund_http` (`c.form()`, злиття `set-cookie`), `grund_cli` (`init --template fullstack`, автооновлення сторінок у `dev`) | — | `example` віддає SSR-сторінку з даними з DI і вхід через сесію на обох адаптерах; шаблон fullstack проходить свої тести; CI зелений на 3.8.0 і stable; `publish --dry-run` без попереджень |
 | G2 | **OpenAPI** | `grund_openapi`; аналіз DTO і валідація полів у генераторі | typed_openapi T1–T2 (контрактний тест) | `GET /openapi.json` з `ETag`, Scalar UI, `export` для CI; RFC 9457 у схемах; контрактний тест: `typed_openapi check` без діагностик, згенерований клієнт проходить e2e прикладу |
 | G3 | **Дані** | `grund_basalt`, `grund_basalt_postgres`, `grund_basalt_sqlite` | basalt B1–B3 | Кілька іменованих підключень; `transactionPerRequest`; health-check і метрики пулу; e2e прикладу на Postgres (контейнер у CI) і SQLite in-memory |
-| G4 | **Auth** | `grund_auth`, `grund_auth_oauth` | basalt B4; typed_openapi T3; token_manager K1 | Сесії + JWT-стратегія, refresh-ротація з reuse detection, email+password (argon2id), Google, Apple; хуки з `SecurityScheme`; Bearer і `httpOnly` cookie; e2e через згенерований клієнт із token_manager |
+| G4 | **Auth** (сесії й cookie вже в G7a) | `grund_auth`, `grund_auth_oauth` | basalt B4; typed_openapi T3; token_manager K1 | JWT-стратегія, refresh-ротація з reuse detection, email+password (argon2id), Google, Apple; `Authenticated`/`Roles`; довговічне сховище сесій; хуки з `SecurityScheme`; Bearer і `httpOnly` cookie; e2e через згенерований клієнт із token_manager |
 | G5 | **SSE, Redis, pub/sub** | `grund_sse`, `grund_redis`, `grund_pubsub` | typed_sse S1; typed_openapi T4 | `Stream<T>` з API як SSE з `Last-Event-ID`; fan-out між двома інстансами через Redis; `InMemoryBus`; клієнт typed_openapi читає стрім |
 | G6 | **Jobs, cache, storage, observability** | `grund_jobs`, `grund_cache`, `grund_storage`, `grund_storage_s3`, `grund_observability` | basalt B2 (`QueryObserver`) | Redis Streams-черга з retry/DLQ/cron; кеш з тегами; S3 (RustFS у CI); один трейс від HTTP до SQL і джоба в OTLP; `DevExporter` через MCP і `tail` |
-| G7 | **WebSocket, Jaspr, init** | `grund_ws`, `grund_jaspr`, шаблони `grund_cli init` | — | JSON-RPC 2.0 канали з AsyncAPI 3; Jaspr SSR у тому ж процесі з cookie-сесією; `init` створює api- і fullstack-проєкт, що проходить свої тести |
+| G7b | **WebSocket, гідратація, шаблони** | `grund_ws`, `grund_jaspr` (гідратація, `@client`), шаблони `grund_cli init` | — | JSON-RPC 2.0 канали з AsyncAPI 3; гідратовані компоненти Jaspr у тому ж процесі; решта шаблонів `init` проходить свої тести |
 | G8 | **Стабілізація 1.0** | усі пакети, сайт документації | typed_openapi T5 | Див. рядок 1.0.0 вище |
 
 ## Після 1.0
```

- [ ] **Крок 7: Релізи**

Нові пакети публікуються першими версіями вручну, далі — тегами `grund_auth-vX.Y.Z`/`grund_jaspr-vX.Y.Z` через `publish.yaml` (після налаштування OIDC на pub.dev, як для решти).

`docs/RELEASING.md` (зміни):

````diff
--- a/docs/RELEASING.md
+++ b/docs/RELEASING.md
@@ -7,7 +7,7 @@ change here publishes anything.
 
 ## Packages
 
-Eight packages are published. Each has its own version and its own
+Ten packages are published. Each has its own version and its own
 release: only a package that changed gets a new version and a `CHANGELOG.md`
 entry, and a release of package `P` is made by pushing the tag `P-vX.Y.Z`.
 
@@ -17,6 +17,8 @@ entry, and a release of package `P` is made by pushing the tag `P-vX.Y.Z`.
 | `grund_http` | `grund` |
 | `grund_io` | `grund`, `grund_http` |
 | `grund_shelf` | `grund`, `grund_http` |
+| `grund_auth` | `grund`, `grund_http` (dev: `grund_io`) |
+| `grund_jaspr` | `grund`, `grund_http` (dev: `grund_io`) |
 | `grund_generator` | none (dev: `grund`, fixture `cases_app`) |
 | `grund_http_generator` | `grund_generator` (dev: `grund`, `grund_http`, fixtures `http_cases_app`, `users_app`) |
 | `grund_cli` | `grund_generator`, `grund_http_generator` |
@@ -67,8 +69,10 @@ package that already exists on pub.dev. Once per package:
    package's `pubspec.yaml`. Raise a constraint on another workspace member
    only when the dependent needs its new version. If the scaffold or a
    README snippet names a version users should depend on
-   (`packages/grund_cli/lib/src/init/project_template.dart`, `grundVersion`),
-   keep it resolvable: it must name a version that exists.
+   (`packages/grund_cli/lib/src/init/project_template.dart`, `grundVersion`;
+   `fullstack_template.dart`, which also names `grund_http`, `grund_auth`,
+   `grund_jaspr` and `jaspr`), keep it resolvable: it must name a version
+   that exists.
 3. Add a `## x.y.z` section at the top of the `CHANGELOG.md` of each package
    being released. The publish workflow and pub both require it.
 4. Run the checks on a clean `master`:
@@ -87,8 +91,9 @@ package that already exists on pub.dev. Once per package:
    65):
 
    ```sh
-   for package in grund grund_http grund_io grund_shelf grund_generator \
-       grund_http_generator grund_cli grund_build; do
+   for package in grund grund_http grund_io grund_shelf grund_auth \
+       grund_jaspr grund_generator grund_http_generator grund_cli \
+       grund_build; do
      (cd "packages/$package" && dart pub publish --dry-run) || break
    done
    ```
````

`.github/workflows/publish.yaml` (зміни):

```diff
--- a/.github/workflows/publish.yaml
+++ b/.github/workflows/publish.yaml
@@ -22,6 +22,8 @@ on:
       - 'grund_http-v*'
       - 'grund_io-v*'
       - 'grund_shelf-v*'
+      - 'grund_auth-v*'
+      - 'grund_jaspr-v*'
       - 'grund_generator-v*'
       - 'grund_http_generator-v*'
       - 'grund_cli-v*'
```

- [ ] **Крок 8: Перевірки**

Run (з кореня): `dart analyze` → `No issues found!`; `dart format packages example` → `(0 changed)`.
Run: `for p in grund grund_http grund_io grund_shelf grund_auth grund_jaspr grund_generator grund_http_generator grund_cli grund_build; do (cd packages/$p && dart pub publish --dry-run 2>&1 | grep 'Package has'); done`
Expected: десять рядків `Package has 0 warnings.`
Run: `grep -rn "jaspr serve" docs packages/grund_jaspr/README.md` — лише застереження «не запускати під `jaspr serve`».

- [ ] **Крок 9: Коміт**

```bash
git add \
  .github/workflows/publish.yaml \
  CLAUDE.md \
  README.md \
  docs/RELEASING.md \
  docs/dev-mode.md \
  docs/faq.md \
  docs/getting-started.md \
  docs/http-and-hooks.md \
  docs/jaspr.md \
  docs/superpowers/ROADMAP.md \
  packages/grund_auth/CHANGELOG.md \
  packages/grund_auth/README.md \
  packages/grund_cli/README.md \
  packages/grund_jaspr/CHANGELOG.md \
  packages/grund_jaspr/README.md
git commit -m "docs: pages and sessions, live reload, ten published packages" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git show --stat --format=%s HEAD   # 15 файлів, лише ці
```

---
### Задача 14: Фінальна перевірка і реєстр неперевіреного

**Мета:** підтвердити spec §10 («Готово, коли») на гілці `g7a-jaspr` тими самими командами, що й CI (`.github/workflows/ci.yaml`), і віддати користувачу звіт разом із реєстром «Що не перевірено». Задача нічого не змінює і не комітить. Якщо перевірка падає, виправлення йде окремим комітом `fix(<scope>): …` з тестом, що без нього падає, у файлах задачі-власника; після нього кроки 2–6 повторюються.

**Files:** жодних.

**Interfaces:**
- Consumes: усі коміти задач 1–13.
- Produces: звіт користувачу (результат кроків 1–7, крок 8 — якщо виконано, і реєстр «Що не перевірено»).

- [ ] **Крок 1: Гілка**

Run: `git log --oneline master..g7a-jaspr | wc -l`
Expected: `18` (задачі 1, 3–10 і 13 — по одному коміту, 2 і 11 — по два, 12 — чотири).
Run: `git status --short`
Expected: жодного файла, який створює або змінює цей план (чужі зміни в робочому дереві не чіпати).

- [ ] **Крок 2: Залежності, аналіз, формат (з кореня)**

Run: `dart pub get` → код виходу 0.
Run: `dart analyze --fatal-infos` → `No issues found!`
Run: `dart format --set-exit-if-changed packages example` → `Formatted 711 files (0 changed)` (число файлів — на `1a8755e` з цим планом; важить лише `0 changed`), код виходу 0.

- [ ] **Крок 3: Тести, як у CI**

Run:

```bash
for dir in packages/*/ example/; do echo "$dir: $( (cd "$dir" && dart test 2>&1) | tail -1)"; done
```

Expected (Dart 3.13.5, Linux; час — орієнтовно):

```text
packages/grund/: 00:00 +200: All tests passed!
packages/grund_auth/: 00:00 +64: All tests passed!
packages/grund_build/: 00:26 +27: All tests passed!
packages/grund_cli/: 01:00 +175: All tests passed!
packages/grund_conformance/: 00:00 +14: All tests passed!
packages/grund_generator/: 00:11 +186: All tests passed!
packages/grund_http/: 00:00 +255: All tests passed!
packages/grund_http_generator/: 00:11 +100: All tests passed!
packages/grund_io/: 00:02 +52: All tests passed!
packages/grund_jaspr/: 00:00 +66: All tests passed!
packages/grund_shelf/: 00:02 +73: All tests passed!
example/: 00:07 +90: All tests passed!
```

- [ ] **Крок 4: Інтеграційні тести і бенчмарк (як у CI)**

Run: `cd packages/grund_cli && dart test integration` → `+7: All tests passed!` (близько 40 с: п'ять наявних тестів `dev_test.dart`; `dev_jaspr_test.dart` — правка сторінки під справжнім `dev` видна в наступній відповіді, а відкриті сторінки отримують `event: reload`; `init_fullstack_test.dart` — тести нового проєкту `fullstack`).
Run: `cd packages/grund_build && dart test integration` → `+1: All tests passed!` (близько 30 с).
Run: `cd packages/grund_cli && dart test benchmark` → `+1: All tests passed!`

- [ ] **Крок 5: Пробна публікація десяти пакетів**

На чистому дереві (змінений файл під git — теж попередження):

```bash
for p in grund grund_http grund_io grund_shelf grund_auth grund_jaspr grund_generator grund_http_generator grund_cli grund_build; do
  echo "$p: $( (cd packages/$p && dart pub publish --dry-run 2>&1) | grep 'Package has')"
done
```

Expected: десять рядків `<пакет>: Package has 0 warnings.`

- [ ] **Крок 6: Ліміти**

Run: `git diff --name-only --diff-filter=AM master..g7a-jaspr -- 'packages/*/lib/*.dart' 'example/lib/*.dart' | xargs wc -l | sort -n | tail -3`
Expected: найбільший — `270 packages/grund_cli/lib/src/init/fullstack_template.dart` (плаский каталог), далі `259 packages/grund_cli/lib/src/dev/dev_session.dart`; усі ≤ 300.
Run: `git diff --name-only --diff-filter=AM master..g7a-jaspr -- '*_test.dart' 'packages/*/test/helpers/*.dart' 'packages/*/integration/*.dart' | xargs wc -l | sort -n | tail -3`
Expected: найбільший — `324 packages/grund_http/test/ctx/http_ctx_test.dart` (наявний, 273 до задачі 2), далі `229 packages/grund_jaspr/test/jaspr_pages_test.dart`; усі ≤ 500.

- [ ] **Крок 7: Spec §10, пункт за пунктом**

| Пункт §10 | Доказ | Стан |
|---|---|---|
| Приклад віддає SSR-сторінки й сесійний вхід на обох адаптерах | `example/test/web_e2e_test.dart` (крок 3, `example/ +90`) | перевірено |
| Проєкт `init --template fullstack` проходить свої тести | `packages/grund_cli/integration/init_fullstack_test.dart` (крок 4) | перевірено проти workspace; проти pub.dev — після релізу («Що не перевірено») |
| CI зелений на 3.8.0 і stable | — | не перевірено локально («Що не перевірено») |
| Dry-run без попереджень для `grund_jaspr` і `grund_auth` | крок 5 | перевірено (і для решти восьми) |
| Документація й роадмап оновлені | задача 13; `grep -rn "jaspr serve" docs packages/grund_jaspr/README.md` — лише застереження | перевірено |

- [ ] **Крок 8 (необов'язковий, вручну): браузер**

```bash
cd example && dart run grund_cli dev
```

Відкрити `http://localhost:8080`: список задач і посилання «Sign in». «Sign in» → форма з полем «Name» → після надсилання повернення на `/` з «Signed in.» і «Signed in as <ім'я>.»; «Sign out» → знову «Sign in». Змінити текст `'Tasks'` у `h1` в `example/lib/src/web/home_page.dart` і зберегти: `dev` перезавантажує код, і відкрита сторінка оновлюється сама, без F5. `R` у терміналі `dev` — перезапуск процесу; сторінка оновлюється, щойно новий процес відповідає. Сесія після `R` зникає (сховище в пам'яті) — очікувано. Повернути правку вручну, зупинити `dev` (Ctrl+C).

- [ ] **Крок 9: Звіт**

Звіт користувачу: результат кроків 1–7 (і 8, якщо виконано), відхилення від очікуваного виводу, і реєстр «Що не перевірено» з поміткою, що з нього закрито. Коміту в цій задачі немає. Пушити, тегувати, публікувати — не можна: це робить мейнтейнер за `docs/RELEASING.md` (див. «Обов'язки релізу»).

---
## Самоперевірка плану

**1. Покриття spec.**

| Spec | Де |
|---|---|
| §1 мета й межі (SSR без гідратації, сесії без облікових даних) | задачі 7–10; межі — `docs/jaspr.md`, README `grund_auth` (задача 13) |
| §2 вхідні факти Jaspr 0.23.5 | задача 1 (тест-контракт) |
| §4 схема: API-маршрути старші, `GET /` і `GET /*`, статика, рендер | задача 9 («an API route wins over the page catch-all», `jaspr_pages_test.dart`) |
| §4.1 `JasprModule`, `app()` на кожен запит, `GrundScope`, `context.injector/call/maybe`, відображення запиту й відповіді, charset, `cache-control`, `HEAD`, ідемпотентна ініціалізація, статика, `allowedPathSuffixes` | задачі 7, 8, 9 (відхилення — «Рішення плану», пп. 1–3, 6, 9–11) |
| §4.2 `CurrentUser`, `SessionStore`, `InMemorySessionStore`, `Session`, токен 32 байти `Random.secure` base64url, `Sessions.start/end` з ротацією, `SessionHook`, атрибути cookie, `SetCookie`, `SameOriginHook` | задачі 3–6 (відхилення — пп. 5, 7, 8) |
| §4.3 шаблон `fullstack` і приклад | задачі 10, 11 (п. 13) |
| §4.4 потік входу | задача 10 (`LoginApi`), шаблон задачі 11; `c.form()` і 303 — задача 2 (п. 4) |
| §4.5 злиття `set-cookie` у `grund_http` | задача 2a |
| §4.6 автооновлення в dev (доповнення `fbf37cb`) | задача 12 (п. 16) |
| §5 помилки: problem+json, типізована помилка конфігу до старту, відсутній `staticDirectory` — не помилка | задачі 5 («SessionModule refuses an invalid config when the app starts»), 8 («a directory that does not exist serves nothing»), 9 («a page that throws answers a 500 problem without the detail») |
| §6 тести | кожен пункт має тест у задачах 2–12; «`pub get` у робочому просторі» для шаблону замінено (п. 14); Dart 3.8.0 — CI («Що не перевірено») |
| §7 роадмап | задача 13 (п. 15) |
| §8 рішення на перегляд | 1 — префіксний імпорт `auth.CurrentUser` у прикладі (задача 10); 2 — `SameSite=Lax` + same-origin без CSRF-токенів (задачі 5, 6); 3 — 7 діб абсолютно (задача 5); 4 — статика (задача 8); 5 — `Secure` за замовчуванням, шаблон вимикає поза product (задачі 5, 11); 6 — problem+json (задача 9) |
| §9 ризики | Jaspr закріплено `>=0.23.5 <0.24.0` і тест-контракт (задача 1); статика власна (задача 8); ініціалізація в `onInit`, тести на `TestApp` (задача 9); флор 3.8 — CI |
| §10 готово, коли | задача 14, крок 7 |

**2. Заглушки.** Немає «TBD», «додати обробку помилок», «як у задачі N»: кожен крок з кодом містить файл цілком або дифф, вставлені скриптом з перевірених комітів-стадій; кожна команда має очікуваний вивід. Там, де очікується падіння компіляції, помилку описано словами (точний текст компілятора залежить від версії SDK).

**3. Узгодженість типів.** Сигнатури в блоках Interfaces узято з коду стадій; імена, які вживають пізніші задачі, збігаються: `SessionModule(config:, store:)`, `SessionConfig(secure:)`, `Sessions.start(c, userId)`, `HookRef<SessionHook>.type()` (задачі 5, 6 → 10, 11, 13); `JasprModule(app:, imports:, config:)`, `JasprConfig.liveReloadUrl`, `GrundScope.of(context).cookies` (задачі 8, 9, 12d → 10, 11, 13); `AppCommand`, `LiveReloadHub`, `ReloadClient.waitUntilServing` (задачі 12a, 12c); змінна `GRUND_LIVE_RELOAD_URL` однакова в `LiveReloadHub` (`grund_cli`) і `LiveReloadScript` (`grund_jaspr`) — два оголошення свідомо, бо пакети не залежать один від одного.

**4. Review Focus.** RF1–RF7 мають тести в задачах-власниках (розділ «Review Focus»); кожен такий тест пройшов на своєму коміті-стадії.

**5. Ліміти.** 62 нові або змінені файли `lib/`; найбільші — `fullstack_template.dart` 270 (плаский каталог; рядковий метод `_appTest` — 45 рядків літерала, як і методи наявного `project_template.dart`; виняток позначено в doc класу), `dev_session.dart` 259; файли `grund_auth`/`grund_jaspr` ≤ 87. Найбільший змінений тест — наявний `http_ctx_test.dart` 324 (було 273), найбільший новий — `jaspr_pages_test.dart` 229. Без `dynamic`. `late` у `lib/` — лише `LiveReloadHub._keepAlive` з коментарем; у тестах — поля `setUp`, як у наявних тестах (частина з коментарем, частина без, як і в `1a8755e`).

**6. Межі винятків.** Нові перехоплення: `BodyReader` — `FormatException` тіла форми → 400 (записано в `CLAUDE.md`, задача 13); `StaticFiles` — `FileSystemException` → «не файл»; `ReloadClient.waitUntilServing` — `TimeoutException`, `RPCError`, `SentinelException` → `false`; `LiveReloadHub` — `catchError` лише для `IOException` сторінки, що пішла; тестовий `ScopelessPage` ловить `MissingGrundScopeError` (це `GrundError`, тобто `Exception`). Жодного нового `on Object`, жодного `catch` без `on`.

---

## Що не перевірено

### Обов'язки релізу (мейнтейнер, поза цим планом)

1. `grund_http`: поставити `version: 0.1.1` (розділ `## 0.1.1` уже є) — або `0.2.0`, якщо нове значення `ParamLocation.form` вирішено вважати несумісністю («Рішення плану», п. 4); тоді перейменувати розділ CHANGELOG і випустити залежні пакети.
2. `grund_auth` і `grund_jaspr`: підняти `grund_http: ^0.1.1` в обох `pubspec.yaml` **до** їхнього першого релізу. Без злиття `set-cookie` з 0.1.1 cookie обробника губиться, а з `^0.1.0` користувач може отримати 0.1.0. У workspace це можливо лише після кроку 1, тому план лишає `^0.1.0`.
3. Порядок: `grund_http` → `grund_auth` і `grund_jaspr` (перші версії вручну, далі OIDC і теги `grund_auth-v*`/`grund_jaspr-v*`, які `publish.yaml` після задачі 13 уже знає) → `grund_cli 0.1.2` останнім: шаблон `fullstack` називає `grund_http ^0.1.1`, `grund_auth`/`grund_jaspr ^0.1.0`.
4. Після релізу вручну: `grund init --template fullstack my_site && cd my_site && dart pub get && dart test` проти pub.dev.

### Реєстр неперевіреного

| Що | Чому не перевірено | Як закрити |
|---|---|---|
| Dart 3.8.0 (флор `^3.8.0`; `jaspr 0.23.5` сам вимагає `>=3.8.0`, транзитивні залежності — ні) | локально лише Dart 3.13.5 | CI-матриця `['3.8.0', stable]` після пушу |
| CI GitHub Actions загалом (`ci.yaml`, `publish.yaml`) | ще жодного разу не запускався | перший пуш гілки |
| Шаблон `fullstack` проти pub.dev | версії `grund_http 0.1.1`, `grund_auth`/`grund_jaspr 0.1.0` ще не опубліковані; тест розв'язує workspace | «Обов'язки релізу», п. 4 |
| Бали pana (мета 160/160 для нових пакетів) | `pana` не запускався; є лише dry-run з 0 попереджень | `dart pub global activate pana`, потім `dart pub global run pana packages/grund_auth` і так само для `packages/grund_jaspr` |
| Справжній браузер: `EventSource`, перепідключення після перезапуску, mixed content (сторінка за https, точка SSE — `http://127.0.0.1`), CORS `*` | тести говорять SSE через `HttpClient` | задача 14, крок 8; https — вручну |
| Відкриття сторінки з іншого пристрою в LAN | точка SSE слухає лише loopback, тож автооновлення там мовчки не працює | очікувана поведінка; описати, якщо спитають |
| Проксі, що переписує `Host` | same-origin порівнює `Origin` з `host`; поведінку описано в README `grund_auth`, із проксі не перевірено | вручну за nginx/Caddy |
| `@client`-компоненти, `jaspr_builder`, гідратація | поза зрізом (spec §1); попередження Jaspr про `.client.dart` лише задокументовано | наступний етап |
| `Jaspr.initializeApp(useIsolates: true)` | відхиляється `JasprSetupError`; рендер в ізолятах не пробувався | — |
| Статика: великі файли, `Range`, `ETag`/`Last-Modified`, стиснення | `StaticFiles` віддає файл цілком з `cache-control: no-cache` без валідаторів | окремий етап або CDN/проксі перед застосунком |
| Reload і reassemble під одночасними запитами | тести шлють запити після reload, не під час | навантажувальний тест у `dev` |
| Асинхронна побудова (async-компоненти, `FutureBuilder` на сервері) | приклад і тести — лише синхронні компоненти | тест у `grund_jaspr` при першому користувачі |
| macOS і Windows (шляхи й символьні посилання в статиці, сигнали `dev`) | лише Linux | CI на інших ОС, якщо його додадуть |

## Виконання

Рекомендовано subagent-driven (`superpowers:subagent-driven-development`): 14 задач, 18 комітів, пізніші задачі (10, 11, 12d, 13) спираються на імена й сигнатури ранніх, а помилка в cookie чи в статиці — це проблема безпеки, тож рецензент після кожної задачі виправданий. Перед виконанням користувач переглядає план.
