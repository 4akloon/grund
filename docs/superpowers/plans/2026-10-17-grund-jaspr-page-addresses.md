# grund_jaspr і grund_http: адреси сторінок, альтернативні подання й файли сайту — план реалізації

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Мета:**
- сайт має одне канонічне написання URL сторінки (`TrailingSlash`, 308) і публічне джерело (`baseUrl`);
- сторінка оголошує альтернативні подання (`PageAlternate.markdown`) з власним URL і узгодженням за `Accept`;
- сайт оголошує згенеровані файли (`SiteFile`);
- `PageExtension` вилучено;
- `grund_http` отримує `AcceptHeader`, злиття `vary`/`link`, 301/308, параметри з суфіксом (`:slug.md`) і `TestClient.head`.

**Архітектура:**
- спершу рефакторинг: перевірки й видача відповіді виносяться з `PagesApi`/`SiteApi` у малі внутрішні колаборатори (`ReservedPaths`, `PageDeclarationCheck`, `SiteDeclarationCheck`, `PageResponder`, `PageAddress`);
- далі можливості `grund_http`;
- потім вилучення `PageExtension`;
- потім адресна модель (`PageAddress`, `CanonicalRedirect`), альтернативи (`AlternateNegotiation`) і файли сайту;
- маршрути альтернатив і файлів — звичайні `Route.get` у `PagesApi`/`SiteApi` з тими самими хуками.

**Стек:** Dart `^3.13.0`, `jaspr >=0.23.5 <0.24.0`, `package:path`, `package:test`.

**Spec:** `docs/superpowers/specs/2026-10-17-grund-jaspr-page-addresses-design.md` (далі «spec»; §N — його розділи).

## Глобальні обмеження

- **Мова й коміти.**
  - Код, doc-коментарі, README, `docs/*.md` і коміти — англійською; `docs/superpowers/**` — українською.
  - Коміти: Conventional Commits, закінчуються `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- **Нічого не пушити, не тегувати, не публікувати; жодних змін `version:` у pubspec і обмежень між пакетами.**
  - `grund_jaspr` лишається з `grund_http: ^0.2.0`: workspace розвʼязує локальний пакет; обмеження піднімає мейнтейнер під час випуску, spec §7.
  - Секції CHANGELOG `grund_http` 0.3.0, `grund_http_generator` 0.2.0 і `grund_jaspr` 0.3.0 уже є.
- **Робоче місце.** Worktree `/home/genius/projects/grund-addresses`, гілка `jaspr-page-addresses` (від master).
- **Середовище й перевірки.** `export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"`. Після кожної задачі:
  - `dart analyze` (корінь) — `No issues found!`;
  - `dart test` змінених пакетів;
  - `dart format packages example` змінює 0 файлів.
- **Ліміти CLAUDE.md:**
  - файл у `lib/` ≤ 300 рядків (`wc -l`), тест ≤ 500;
  - метод ≤ 40 рядків, параметрів ≤ 5, вкладеність ≤ 3;
  - один публічний клас (або sealed-родина) на файл;
  - `///` на кожному публічному члені; без `// ignore:`;
  - функції верхнього рівня — ні (статичні члени `abstract final class`);
  - можливості Dart 3.13, де коротше й зрозуміліше;
  - `catch` лише з `on` і без `Error`.
- **Залежності.** Нових залежностей немає. Тести не ходять у мережу.
- **Точні значення зі spec:**
  - **`AcceptHeader`.** Граматика `q`: `^(0(\.\d{0,3})?|1(\.0{0,3})?)$`, інакше 0. Відсутній, порожній чи заголовок із пробілів — «відсутній»: якість 1 для всього, `names` false. Специфічність: точний діапазон, потім `type/*`, потім `*/*`. Повтор бере найвищу якість.
  - **Узгодження.** Альтернатива, коли `names(m) && qualityOf(m) >= qualityOf('text/html')`. Найвища якість виграє, нічию вирішує порядок оголошення. `406` немає.
  - **Суфікс маршруту.** `(\.[A-Za-z0-9_~-]+)+`, з урахуванням регістру. Пріоритет: літерал > суфікс (довший першим) > параметр > `*`. Значення непорожнє.
  - **Суфікс альтернативи.** `^(\.[a-z0-9]+)+$`. Корінь сайту дає `<шлях сайту>/index<suffix>`.
  - **Редирект.** 308, `cache-control: max-age=3600`, `location` = `Uri(path:, query:)`. Лише `never`/`always`. Після хуків, до будівника.
  - **`TrailingSlash`.** За замовчуванням `never`. `always` не додає слеш до кореня й до останнього сегмента з розширенням.
  - **Заголовки альтернатив і файлів сайту:**
    - `content-type: <mediaType>; charset=utf-8`;
    - `cache-control: private, no-cache`, якщо `c.response` не задав свого;
    - canonical `Link` лише з `baseUrl`, на власному URL альтернативи.
  - **Узгоджені відповіді сторінки.** `vary: accept` на кожній; `link` з `rel="alternate"` на HTML.
  - **`baseUrl`:** `http`/`https`, хост, шлях порожній або `/`, без query, фрагмента й userinfo.

## Огляд файлів

| Файл | Дія | Відповідальність |
| --- | --- | --- |
| `grund_http/lib/src/http/accept_header.dart`, `lib/grund_http.dart` | нов./змін. | `AcceptHeader` і експорт |
| `grund_http/lib/src/http/{http_response,status_code}.dart` | змін. | `withVary`, злиття `vary`/`link`, 301/308 |
| `grund_http/lib/src/testing/test_client.dart` | змін. | `head` |
| `grund_http/lib/src/routing/{pattern_segment,route_pattern,router}.dart` | змін. | параметр із суфіксом |
| `grund_http_generator/lib/src/construct/route_paths.dart` | змін. | паритет `parameters`/`shape` |
| `grund_jaspr/lib/src/site/{reserved_paths,page_declaration_check,site_declaration_check,page_responder}.dart`, `lib/src/page/page_address.dart` | нов. | колаборатори (рефакторинг, далі розширюються) |
| `grund_jaspr/lib/src/page/page_extension.dart`, `lib/src/site/site_extensions.dart`, `test/page_extension_test.dart` | вил. | `PageExtension` |
| `grund_jaspr/lib/src/site/{trailing_slash,canonical_redirect}.dart` | нов. | політика слеша (публічна), редирект (внутрішній) |
| `grund_jaspr/lib/src/page/page_alternate.dart`, `lib/src/site/alternate_negotiation.dart` | нов. | `PageAlternate` (публічний), вибір за `Accept` |
| `grund_jaspr/lib/src/site/site_file.dart` | нов. | `SiteFile` (публічний) |
| `grund_jaspr/lib/src/{page/page,page/page_match,page/page_path,page/non_page_requests,site/page_site,site/pages_api,site/site_api,site/site_services,site/pages,catalog/navigation_builder,catalog/sitemap_source,catalog/page_catalog,sitemap/sitemap_handlers,jaspr_module}.dart`, `lib/src/error/{page,site}_declaration_error.dart`, `lib/grund_jaspr.dart` | змін. | інтеграція |
| `grund_jaspr/test/{alternates,negotiation,trailing_slash,site_files,page_addresses,alternate_rules}_test.dart` | нов. | тести |
| `example/lib/src/web/{public_site,web_module}.dart`, `example/lib/src/web/home_markdown.dart`, `example/test/web_addresses_test.dart` | нов./змін. | приклад |
| `docs/{jaspr,http-and-hooks,testing}.md`, README і CHANGELOG `grund_http`/`grund_http_generator`/`grund_jaspr`, `CLAUDE.md`, `docs/superpowers/ROADMAP.md` | змін. | документація |

## Review Focus

Те, що spec майже не перевіряє, а помилка вдарить користувача першою (кожен пункт має тест у задачі-власниці):

1. **Таблиця прийому spec §4.7, усі рядки, через справжній маршрут сторінки** (Задача 6). Особливо:
   - нічия `text/html, text/markdown` дає Markdown;
   - `text/markdown;q=0.1, */*` дає HTML;
   - `,,;;,q=` дає HTML;
   - `HEAD` із `accept: text/markdown` дає ті самі заголовки, що й `GET`.
2. **Безпека редиректу** (Задача 5):
   - `//evil.test/x/` дає `location` `/evil.test/x` (ніколи не `//`);
   - query зберігається дослівно;
   - `%2F` у сегменті не розкодовується;
   - за `always` `/feed.xml` не отримує слеша;
   - корінь префіксного сайту `/docs/` дає `/docs` за `never`;
   - хук, що відмовляє, відповідає раніше за редирект;
   - фолбек 404 і файловий запит не переадресовуються.
3. **Злиття заголовків з хуками** (Задача 3; інтеграційно — Задача 6):
   - хук ставить `c.response.headers.add('vary', 'cookie')` і `link` → HTML сторінки несе `vary` з обома токенами й обидва `link`;
   - `vary: *` поглинає все;
   - `set-cookie` поводиться як раніше.
4. **Пріоритет суфіксних маршрутів** (Задача 4):
   - співіснують `/a/b.md` (літерал), `/a/:x.md`, `/a/:x`, `/a/*`;
   - `/a/.md` не збігається з `:x.md`;
   - `:n.gz` проти `:n.tar.gz` на `x.tar.gz` — довший суфікс;
   - `grund%2Emd` розкодовується й збігається;
   - `DELETE` на суфіксний маршрут, що має лише `GET`, дає 405, а не 404.
5. **Хуки на маршрутах альтернатив** (Задача 6):
   - альтернатива сторінки з `PageHooks(skip: …)` і з власним `use` має рівно ті хуки, що й сторінка;
   - гість на захищеній альтернативі отримує ту саму відмову, що й на сторінці;
   - попередження `HookResolver` про `skip` логуються один раз на сторінку, а не на маршрут.

---

### Задача 1: рефакторинг `grund_jaspr` — колаборатори перевірок і видачі

**Files:**
- Create `packages/grund_jaspr/lib/src/site/reserved_paths.dart`, `lib/src/site/page_declaration_check.dart`, `lib/src/site/site_declaration_check.dart`, `lib/src/site/page_responder.dart`, `lib/src/page/page_address.dart`.
- Modify `lib/src/site/pages_api.dart`, `lib/src/site/site_api.dart`, `lib/src/catalog/sitemap_source.dart`.

**Interfaces:**
- Produces (усе внутрішнє, без експорту з `grund_jaspr.dart`):
  - `abstract final class ReservedPaths { static String? reasonFor(String fullPath, {required String sitePath, required JasprConfig config}); }`: три причини `_checkNotReserved` дослівно (статика, sitemap, `rootFiles`), `null` — шлях вільний.
  - `abstract final class PageDeclarationCheck { static void check(Page page, {required PageSite site, required String fullPath, required JasprConfig config}); }`: кидає `ReservedPagePathError` (через `ReservedPaths`), `UnusedPageEntriesError`, `UndecidedPageSitemapError`, як зараз.
  - `abstract final class SiteDeclarationCheck { static void check(PageSite site, {required Type siteType, required JasprConfig config}); }`: тіло конструктора `SiteApi`.
  - `final class PageResponder`, що тримає `SiteServices`, з двома методами:
    - `Future<HttpResponse> page(HttpCtx c, {required PageSite site, required Page page, required PageMatch match})` — тіло `_serve` після створення `match`;
    - `Future<HttpResponse> notFound(HttpCtx c, PageSite site)` — 404-сторінка сайту, спільна для `PagesApi` і `SiteApi`.
  - `abstract final class PageAddress { static String encodedPath(String fullPattern, Map<String, String> params); }`: перенесений `SitemapSource._encodedPath` без змін.

**Кроки:**
- [ ] **Крок 1.** `wc -l` файлів задачі; записати числа у звіт.
- [ ] **Крок 2.** Перенести код у колаборатори; `PagesApi._route`, `SiteApi` і `SitemapSource._urlOf` кличуть їх. Тексти помилок і порядок перевірок не змінюються. Ланцюжок `PageExtension` поки лишається в `PageResponder.page`.
- [ ] **Крок 3.** `dart test` пакета зелений без змін у тестах; `dart analyze`; `wc -l`.
- [ ] **Крок 4.** Коміт `refactor(jaspr): extract page and site declaration checks, the page responder and page addresses`.

### Задача 2: `grund_http` — `AcceptHeader`, `withVary`, злиття заголовків, 301/308, `TestClient.head`

**Files:**
- Create `packages/grund_http/lib/src/http/accept_header.dart`, `test/http/accept_header_test.dart`.
- Modify `lib/src/http/http_response.dart`, `lib/src/http/status_code.dart`, `lib/src/testing/test_client.dart`, `lib/grund_http.dart`, `test/http/http_response_test.dart`; тест `head` додати до наявного тесту `TestClient` (знайти `grep -rln TestClient test`).

**Interfaces:**
- Produces:
  - `final class AcceptHeader { factory AcceptHeader.parse(String? value); double qualityOf(String mediaType); bool names(String mediaType); }` (spec §4.1);
  - `HttpResponse withVary(String header)`;
  - `mergeHeaders` за spec §4.2;
  - `StatusCode.movedPermanently = 301`, `StatusCode.permanentRedirect = 308`;
  - `Future<TestResponse> TestClient.head(String target, {Map<String, String> headers = const {}})`.

**Кроки:**
- [ ] **Крок 1: тести.**
  - `AcceptHeader`:
    - `null`/`''`/`'  '` дають 1 для будь-якого типу й `names` false;
    - `text/markdown` дає 1 і `names`;
    - `text/markdown;q=0.5` дає 0.5;
    - `Q=0.5` (регістр імені) дає 0.5;
    - `q=1.0001`, `q=abc`, `q=-1`, `q=2`, `q=.5`, `q=Infinity` дають 0;
    - `text/*;q=0.3` для `text/markdown` дає 0.3, а `names` false;
    - `*/*` дає 1 для всього, `names` false;
    - точний діапазон важливіший за `type/*`, той — за `*/*`, незалежно від порядку в заголовку;
    - повтор `text/html;q=0.2, text/html;q=0.9` дає 0.9;
    - `TEXT/Markdown` збігається;
    - `text/markdown;charset=utf-8` дає 1;
    - сміттєвий `,,;;,q=` дає 0 для всього;
    - `*/x` пропускається.
  - `withVary`:
    - додає;
    - не дублює (`Accept` проти `accept`);
    - не змінює `vary: *`;
    - зберігає наявний `vary: cookie` і лишає **один рядок** `vary: cookie, accept` (`headers['vary']` бачить обидва токени).
  - `mergeHeaders`:
    - `vary` об'єднується в порядку «свої, потім нові»;
    - `*` дає один `vary: *`;
    - `link` зберігає обидва (спершу `extra`);
    - `set-cookie` як раніше;
    - інше ім'я — свої значення.
  - `StatusCode.reasonPhrase(308)` наявний.
  - `client.head('/x')` дає статус і заголовки `GET`-маршруту.
- [ ] **Крок 2:** тести падають.
- [ ] **Крок 3: реалізація.**
  - **`AcceptHeader`.** Один розібраний список `({String type, String subtype, double quality})` плюс прапорець «відсутній». Метод `_matchQuality` обирає найспецифічніший діапазон. Символи `tchar` — регулярним виразом.
  - **`mergeHeaders`.** Тіло ділиться на малі приватні статики (`_mergedVary`, `_prepended`), щоб метод лишився ≤ 40 рядків. `///` описує всі три правила.
  - Експорт `AcceptHeader`.
- [ ] **Крок 4.**
  - `dart test` пакетів `grund_http`, `grund_io`, `grund_shelf`, `grund_jaspr`, `grund_auth` (злиття заголовків зачіпає всіх);
  - `dart analyze`; `wc -l` (`http_response.dart` 120 → ≤ 180).
  - Коміт `feat(http): add AcceptHeader, Vary merging, permanent redirect codes and TestClient.head`.

### Задача 3: `grund_http` — параметр маршруту з суфіксом і паритет генератора

**Files:**
- Modify `packages/grund_http/lib/src/routing/pattern_segment.dart`, `route_pattern.dart`, `router.dart`, `test/routing/route_pattern_test.dart`, `test/routing/router_test.dart`.
- Modify `packages/grund_http_generator/lib/src/construct/route_paths.dart` і його тест (знайти `grep -rln RoutePaths packages/grund_http_generator/test`).

**Interfaces:**
- Consumes: `_Search.visit` (`router.dart:93-115`).
- Produces:
  - `ParamSegment(String name, {String suffix = ''})`;
  - `ParamSegment.suffix`; `toString()` дає `':$name$suffix'`;
  - `_Node.suffixed` (`Map<String, _Node<V>>` за суфіксом), обхід за спаданням довжини суфікса, потім за текстом;
  - `RoutePaths.parameters('/a/:id.json')` дає `['id']`, `RoutePaths.shape('/a/:id.json')` дає `'/a/:.json'`.

**Кроки:**
- [ ] **Крок 1: тести.**
  - Шаблони:
    - `/:slug.md`, `/files/:name.tar.gz` розбираються;
    - `/:slug.`, `/:slug.m d`, `/:.md`, `/a:slug.md`, `/:slug.md.` дають `InvalidRoutePatternError`;
    - `/:x.md/:x` дає помилку повтору імені.
  - Роутер: Review Focus 4 повністю, а також:
    - значення параметра без суфікса;
    - суфікс із урахуванням регістру (`/a/x.MD` не збігається з `:x.md`);
    - `HEAD` падає на `GET` суфіксного маршруту;
    - `/a/:x.md` і `/a/:y.md` дають `DuplicateRouteError`.
  - Генератор: `parameters`/`shape` для суфікса. Якщо `http_cases_app` приймає `@Get('/:id.json')` без зміни golden-файлів `users_app` — кейс там (spec §8.4); інакше лише юніт.
- [ ] **Крок 2:** тести падають.
- [ ] **Крок 3: реалізація.** `_segment` розпізнає `^:([A-Za-z_][A-Za-z0-9_]*)((\.[A-Za-z0-9_~-]+)+)?$`. Решта гілок і тексти помилок — без змін.
  - `_Node.child` для `ParamSegment` із суфіксом бере вузол із `suffixed`. Ім'я параметра для дублікатів не важливе, як і для звичайного `:param`.
  - У `_Search.visit` між літералом і параметром іде цикл суфіксних вузлів, де `segment.endsWith(suffix) && segment.length > suffix.length`; захоплене значення — сегмент без суфікса. Якщо `visit` виходить за 40 рядків, гілку суфіксів винести в приватний метод.
  - `///` класу `Router` оновити (пріоритет).
- [ ] **Крок 4.** `dart test` у `grund_http` і `grund_http_generator`; `GRUND_UPDATE_GOLDENS` не запускати (golden-файли не мають змінитися); `dart analyze`; `wc -l` (`router.dart` 128 → ≤ 170). Коміт `feat(http): route parameters with a literal suffix such as :slug.md`.

### Задача 4: вилучити `PageExtension`

**Files:**
- Delete `packages/grund_jaspr/lib/src/page/page_extension.dart`, `lib/src/site/site_extensions.dart`, `test/page_extension_test.dart`.
- Modify `lib/src/page/page.dart`, `lib/src/page/non_page_requests.dart`, `lib/src/site/{site_services,pages,site_api,page_responder}.dart`, `lib/src/catalog/page_catalog.dart`, `lib/src/jaspr_module.dart`, `lib/grund_jaspr.dart`, `test/catalog_test.dart`, `test/page_values_test.dart` (рядок `expect(page.extensions, isEmpty)` → `page.alternates`), `test/helpers/catalog_app.dart`, `test/non_page_requests_test.dart` (якщо тестує `answer`).

**Interfaces:**
- Produces:
  - `Page` без `extensions`;
  - `SiteServices` без `extensions`;
  - `NonPageRequests` без `answer` (лишаються `isPageRequest` і `notFound`);
  - `PageCatalog` без `pagesWith`;
  - `JasprModule` не прив'язує й не експортує `Key<SiteExtensions>()`.

**Кроки:**
- [ ] **Крок 1.** Вилучити; файловий запит у `PageResponder.page` і `SiteApi` кличе `nonPage.notFound(uri)`. Тести `catalog_test.dart` про `pagesWith` і помічники `MarkdownLike`/`OtherExtension` вилучити.
- [ ] **Крок 2.** `grep -rn "PageExtension\|pagesWith\|SiteExtensions" packages example docs/*.md` — лишаються лише `docs/jaspr.md`, README і CHANGELOG (їх переписує Задача 9).
- [ ] **Крок 3.** `dart test` пакета; `dart analyze`; `wc -l`.
- [ ] **Крок 4.** Коміт `refactor(jaspr)!: remove PageExtension and the claim chain`.

### Задача 5: `TrailingSlash`, `baseUrl`, адреси сторінок, редиректи

**Files:**
- Create `packages/grund_jaspr/lib/src/site/trailing_slash.dart`, `lib/src/site/canonical_redirect.dart`, `test/trailing_slash_test.dart`, `test/page_addresses_test.dart`.
- Modify:
  - `lib/src/site/{page_site,site_declaration_check,site_api,page_responder,pages_api}.dart`;
  - `lib/src/page/{page_address,page_match}.dart`;
  - `lib/src/catalog/{navigation_builder,sitemap_source,page_catalog}.dart`;
  - `lib/src/sitemap/sitemap_handlers.dart`;
  - `lib/src/error/site_declaration_error.dart`;
  - `lib/grund_jaspr.dart`;
  - тести й помічники зі `sitemapBaseUrl`: `test/helpers/sitemap_sites.dart`, `sitemap_rules_test.dart`, `sitemap_endpoints_test.dart`, `sitemap_of_test.dart`, `page_values_test.dart`.

**Interfaces:**
- Consumes: `StatusCode.permanentRedirect` (Задача 2), `PageAddress.encodedPath` (Задача 1).
- Produces:
  - `enum TrailingSlash { ignore, never, always }` (публічний, експорт);
  - члени `PageSite`: `Uri? get baseUrl`, `TrailingSlash get trailingSlash => TrailingSlash.never`; без `sitemapBaseUrl`;
  - `InvalidSiteBaseUrlError({required Type siteType, required Uri url, required String reason})`;
  - `PageAddress.pathOf(String fullPattern, Map<String, String> params, TrailingSlash policy)`;
  - `PageMatch.path`, `PageMatch.url`;
  - `abstract final class CanonicalRedirect { static HttpResponse? forPage(Uri uri, TrailingSlash policy); static HttpResponse? forFile(Uri uri, TrailingSlash policy); }`.

**Кроки:**
- [ ] **Крок 1: перевірка** spec §8.5. Тест `PageCatalog.match(Uri.parse('/login/'))` повертає сторінку `/login`; якщо ні, виправити в `SnapshotIndex` у цій задачі й назвати у звіті.
- [ ] **Крок 2: тести** `trailing_slash_test.dart`. Сайти з `never`/`always`/`ignore`, кореневий і префіксний `/docs`; сторінки `/`, `/about`, `/projects/:slug`, `/feed.xml`.
  - **`never`:**
    - `/about/` дає 308 і `location: /about`;
    - `/about/?x=1&y` дає `/about?x=1&y`;
    - `//about` дає `/about`;
    - `/docs/` дає `/docs`;
    - `/` лишається 200;
    - `/about` дає 200 без редиректу.
  - **`always`:**
    - `/about` дає `/about/`;
    - `/projects/grund` дає `/projects/grund/`, і будівник не викликався (лічильник);
    - `/feed.xml` дає 200;
    - `/docs` дає `/docs/`.
  - **`ignore`:** обидва написання дають 200.
  - **`PageAddress.pathOf`** (spec §4.5, окремий `page_address_test.dart`): відсутній параметр, порожнє значення, `.` і `..` кидають `ArgumentError` з іменем параметра; `PageMatch(page:, params: const {}).path` для сторінки `/projects/:slug` теж.
  - **Безпека й межі:**
    - `//evil.test/about/` дає `location` `/evil.test/about`, і будь-який `location` не починається з `//`;
    - `/a%2Fb/` з параметричною сторінкою дає `location: /a%2Fb`;
    - сайт із `use: [DenyHook]` на `/about/` дає відповідь хука, а не 308;
    - `/nope/` (фолбек) дає 404 без редиректу;
    - `/logo.png/` дає 404 `file_not_found`;
    - `cache-control: max-age=3600` на 308;
    - `client.head('/about/')` дає 308.
  - `page_addresses_test.dart`:
    - `PageMatch.path` за трьох політик, із параметром `a b/c` (`a%20b%2Fc`);
    - `PageMatch.url` з `baseUrl` `https://x.test` і без нього (`null`);
    - `navOf` за `always` дає `/about/`;
    - `<loc>` у `sitemapOf` за `always` дає `https://x.test/about/`, корінь — `https://x.test/`;
    - `InvalidSiteBaseUrlError` для `ftp://x`, `https:///`, `https://x.test/app`, `https://x.test?q`, `https://x.test#f`, `https://u@x.test`;
    - `https://x.test/` приймається;
    - `GuardedSiteSitemapError` з `baseUrl`.
- [ ] **Крок 3:** тести падають.
- [ ] **Крок 4: реалізація** за spec §4.5–4.6.
  - `CanonicalRedirect` викликається першим у `PageResponder.page` (до перевірки файлового запиту), а також у маршрутах sitemap у `SiteApi`. Фолбек `/*` його не кличе.
  - Перейменування `sitemapBaseUrl` → `baseUrl` у всіх місцях з Files.
  - `NavigationBuilder._itemOf` і `SitemapSource._urlOf` беруть `PageAddress.pathOf(…, site.trailingSlash)`.
  - `PageMatch` отримує `path`/`url` як getter-и через `page.site`.
- [ ] **Крок 5.** `dart test` пакета; `dart analyze`; `wc -l` (`sitemap_source.dart` 222 має не зрости; `page_site.dart` ≤ 80). Коміт `feat(jaspr)!: trailing slash policy, base URL and canonical page addresses`.

### Задача 6: альтернативні подання сторінок

**Files:**
- Create `packages/grund_jaspr/lib/src/page/page_alternate.dart`, `lib/src/site/alternate_negotiation.dart`, `test/alternates_test.dart`, `test/negotiation_test.dart`, `test/alternate_rules_test.dart` (помічники сайтів — у `test/helpers/alternate_sites.dart`).
- Modify:
  - `lib/src/page/{page,page_match,page_address,page_path}.dart`;
  - `lib/src/site/{page_site,pages_api,page_responder,page_declaration_check}.dart`;
  - `lib/src/error/page_declaration_error.dart`;
  - `lib/grund_jaspr.dart`.

**Interfaces:**
- Consumes: `AcceptHeader`, `withVary`, суфіксні маршрути (Задачі 2–3), `CanonicalRedirect`, `PageAddress.pathOf`, `PageMatch.url` (Задача 5).
- Produces:
  - `typedef AlternateBuilder = FutureOr<String> Function(HttpCtx c, PageMatch match)`;
  - `final class PageAlternate` (spec §4.7, з `.markdown`);
  - `Page.alternates`;
  - `PageSite.requiredAlternates`;
  - `PageMatch.alternatePath(String mediaType)`;
  - `PageAddress.alternatePathOf(...)`, `PageAddress.alternatePatternOf(...)`;
  - `abstract final class AlternateNegotiation { static PageAlternate? choose(AcceptHeader accept, List<PageAlternate> alternates); }`;
  - `InvalidPageAlternateError({required String path, required String mediaType, required String reason})`;
  - `MissingPageAlternateError({required String path, required String mediaType})`.

**Кроки:**
- [ ] **Крок 1: тести** `negotiation_test.dart`: Review Focus 1 і кожен рядок таблиці spec §4.7 як окремий `test` (через список записів). Також:
  - HTML має `vary: accept` і `link: </about.md>; rel="alternate"; type="text/markdown"`, а з `baseUrl` — абсолютний;
  - сторінка без альтернатив не має ні `vary`, ні `link`;
  - хук ставить `vary: cookie` і `link` (Review Focus 3);
  - `NotFoundException` будівника альтернативи при узгодженні дає сторінку 404 сайту з `vary: accept`.
- [ ] **Крок 2: тести** `alternates_test.dart`:
  - `/index.md` для кореневого сайту, `/docs/index.md` для префіксного, `/about.md`, `/projects/grund.md`; будівник отримує `match.params['slug'] == 'grund'`;
  - `content-type: text/markdown; charset=utf-8`;
  - `cache-control: private, no-cache` і власний `cache-control` користувача (`c.response.headers.set`);
  - canonical `link` з `baseUrl` (`<https://x.test/about>; rel="canonical"`, за `always` — `/about/`) і без нього (немає);
  - `/about.md/` дає 308 на `/about.md`;
  - `NotFoundException` на `/projects/nope.md` дає problem+json 404;
  - Review Focus 5;
  - `PageMatch.alternatePath('text/markdown')`.
- [ ] **Крок 3: тести** `alternate_rules_test.dart`:
  - кожна причина `InvalidPageAlternateError` зі spec §4.7: `text/HTML`, `text/markdown; x=1`, `text/*`, `text/html`, суфікси `md`, `.MD`, `.md.`, `.html`, дубль типу, дубль суфікса, URL під `staticPath`;
  - `MissingPageAlternateError`;
  - `Page('/:slug.md')` дає `InvalidPagePathError`;
  - сторінки `/index` і `/` з `.md` дають `DuplicateRouteError` на старті.
- [ ] **Крок 4:** тести падають.
- [ ] **Крок 5: реалізація** за spec §4.7.
  - **`PagesApi.routes`:**
    - для кожної сторінки один раз `PageDeclarationCheck.check` і `HookResolver().forPage(…)`;
    - далі маршрут сторінки й маршрути альтернатив з тим самим списком хуків;
    - `name: 'GET <шаблон альтернативи>'`.
  - **`PageResponder`:**
    - `page(...)`: файловий запит → редирект → узгодження → HTML з `link` (до `vary` + `link` іде `withVary('accept')` після `JasprResponse`);
    - новий `alternate(HttpCtx c, PageAlternate alternate, PageMatch match)`: відповідь на власному URL;
    - спільний `_textResponse(HttpCtx c, String text, String mediaType)` іде в `PageResponder` (його ж використає Задача 7, отже зробити статичним і внутрішнім).
  - **Перевірки** альтернатив і `requiredAlternates` — у `PageDeclarationCheck`.
  - Ім'я параметра в `PagePath` — ідентифікатор.
- [ ] **Крок 6.** `dart test` пакета; `dart analyze`; `wc -l`:
  - `pages_api.dart` ≤ 150, `page_responder.dart` ≤ 200;
  - `page_declaration_error.dart` ≤ 230 (sealed-родина в одному файлі).
  Коміт `feat(jaspr): page alternates with their own URL and Accept negotiation`.

### Задача 7: файли сайту

**Files:**
- Create `packages/grund_jaspr/lib/src/site/site_file.dart`, `test/site_files_test.dart`.
- Modify `lib/src/site/{page_site,site_api,site_declaration_check,page_responder}.dart`, `lib/src/error/site_declaration_error.dart`, `lib/grund_jaspr.dart`.

**Interfaces:**
- Consumes: `CanonicalRedirect.forFile`, `ReservedPaths.reasonFor`, текстова відповідь (Задача 6).
- Produces:
  - `typedef SiteFileBuilder = FutureOr<String> Function(HttpCtx c)`;
  - `final class SiteFile` (spec §4.8);
  - `List<SiteFile> get files => const []` на `PageSite`;
  - `InvalidSiteFileError({required Type siteType, required String path, required String reason})`.

**Кроки:**
- [ ] **Крок 1: тести:**
  - `/robots.txt` кореневого сайту дає 200, `text/plain; charset=utf-8`, тіло будівника;
  - `/docs/llms.txt` префіксного сайту;
  - хук сайту діє (`DenyHook` дає відмову);
  - `/robots.txt/` дає 308;
  - `HEAD` працює;
  - `InvalidSiteFileError` для `robots.txt` без `/`, `/`, `/a/:x`, `/a/*`, `/a//b`, `/static/x.txt`, `/sitemap.xml` (з `baseUrl`), `text`;
  - дубль шляху дає `DuplicateRouteError`;
  - `text/html` дозволено;
  - територія (spec §4.8): `files: [SiteFile('/admin/x.txt', …)]` кореневого сайту при префіксному сайті `/admin` дає `MisplacedPagePathError` на старті; такий самий файл у самому сайті `/admin` (шлях `/x.txt`) проходить.
- [ ] **Крок 2:** тести падають.
- [ ] **Крок 3: реалізація.** `SiteApi.routes`: маршрути файлів до `/*`. Перевірки в `SiteDeclarationCheck`; перевірка території — розширення `SiteValidator._checkTerritories` повними шляхами файлів (`site/site_validator.dart`, `wc -l` перед правкою).
- [ ] **Крок 4.** `dart test` пакета; `dart analyze`; `wc -l` (`site_api.dart` ≤ 120). Коміт `feat(jaspr): generated site files such as robots.txt`.

### Задача 8: приклад

**Files:**
- Create `example/lib/src/web/home_markdown.dart` (`abstract final class HomeMarkdown { static String of(List<Task> tasks); }`), `example/test/web_addresses_test.dart`.
- Modify `example/lib/src/web/{public_site,web_module}.dart`.

**Interfaces:**
- Consumes: `TasksService.list()`, цикл `ModuleStyle` × `AdapterKind` з `web_e2e_test.dart`, `LoopbackServer`.
- Produces: `Page('/', …, alternates: [PageAlternate.markdown((c, _) => HomeMarkdown.of(c<TasksService>().list()))])`; `PublicSite.files` з `/robots.txt`.

**Кроки:**
- [ ] **Крок 1: тести** spec §4.10 на чотирьох серверах. Також `GET /login/` дає 308 і `location: /login`, і `link` не має `rel="canonical"` (у прикладу немає `baseUrl`).
- [ ] **Крок 2:** тести падають.
- [ ] **Крок 3: реалізація.**
  - `HomeMarkdown.of` дає `# Tasks` і список `- [ ] title` / `- [x] title`, рядок назви екранує `\`, `*`, `_`, `[`, `]` і `` ` ``.
  - `PublicSite` явно ставить `trailingSlash: TrailingSlash.never` — getter, щоб приклад не залежав від Для автора, п. 1.
  - Якщо `web_e2e_test.dart` перевіряє заголовки `/`, які тепер змінилися (`vary`), оновити й назвати у звіті.
- [ ] **Крок 4.** `cd example && dart test` зелений; `dart run grund_cli gen` не потрібен (анотованих файлів не змінено; перевірити golden-тест); `dart analyze`; `dart format packages example` — 0 змін. Коміт `feat(example): Markdown alternate of the home page and robots.txt`.

### Задача 9: документація і підсумкові перевірки

**Files:**
- Modify:
  - `docs/jaspr.md` (spec §4.11, з номерами рядків розділів), `docs/http-and-hooks.md`, `docs/testing.md`;
  - `packages/grund_jaspr/README.md`, `packages/grund_http/README.md` (за потреби);
  - CHANGELOG `grund_http` (0.3.0), `grund_http_generator` (0.2.0), `grund_jaspr` (0.3.0);
  - `CLAUDE.md`: «Project» і межа сторінки в «Code rules»;
  - `docs/superpowers/ROADMAP.md`: рядки G7a-pages і G7b, абзац після таблиці.

**Кроки:**
- [ ] **Крок 1: тексти** англійською за spec §4.11. Приклад `llms.txt` як `SiteFile` через `PageCatalog.pagesOf` і `PageMatch(page:, params: const {}).alternatePath('text/markdown')`, з `baseUrl`.
  - **Рецепт «кожна сторінка відповідає»:** `pagesOf` + `sitemapOf` + `client.head`. Перевірка ресурсів із `package:html` — як нотатка, без коду фреймворку.
  - **Абзац `<base>`** у «Things to know».
  - **CHANGELOG `grund_jaspr` 0.3.0** з `**Breaking:**` для:
    - вилучення `PageExtension`/`pagesWith`;
    - `sitemapBaseUrl` → `baseUrl` (з перевіркою);
    - типового `TrailingSlash.never` (`/x/` тепер 308);
    - суворіших імен параметрів `PagePath`.
  - **CHANGELOG `grund_http` 0.3.0:** нові API і поведінкова зміна `mergeHeaders` (`vary`, `link`).
  - **CHANGELOG `grund_http_generator` 0.2.0:** суфіксні параметри в `@Get` тощо.
  - **`CLAUDE.md`:** межа сторінки тепер покриває і будівник альтернативи, обраної узгодженням на URL сторінки.
- [ ] **Крок 2: підсумкові перевірки** з кореня worktree:
  - `dart pub get`; `dart analyze` (`No issues found!`);
  - `dart test` у `grund_http`, `grund_http_generator`, `grund_io`, `grund_shelf`, `grund_auth`, `grund_jaspr`; `cd example && dart test`;
  - `dart format packages example` — 0 змін (двічі);
  - `dart pub publish --dry-run` — `0 warnings` для `grund_http`, `grund_http_generator`, `grund_jaspr`;
  - `wc -l` усіх змінених файлів у межах лімітів.
- [ ] **Крок 3 (контролер):**
  - запустити приклад; у вбудованому браузері `/` дає HTML;
  - `curl -H 'accept: text/markdown' localhost:8080/` дає Markdown (дозволений локальний запит);
  - `/login/` переадресовує.
  Результат записати у звіт.
- [ ] **Крок 4: коміт** `docs: page addresses, alternates and site files`.

---

## Самоперевірка плану

**Покриття spec:**

| Розділ spec | Задача |
| --- | --- |
| §4.1–4.2, §4.4 | 2 |
| §4.3 | 3 |
| §4.9 | 4 |
| §4.5–4.6 | 5 |
| §4.7 | 6 |
| §4.8 | 7 |
| §4.10 | 8 |
| §4.11 | 9 |
| §4.12 | 1, далі розширюється в 5–7 |
| §5 (помилки) | 5 (`InvalidSiteBaseUrlError`), 6 (альтернативи, `PagePath`), 7 (`InvalidSiteFileError`) |
| §6 | тести задач 2–8 |
| §7 (версії й обмеження не чіпати) | Глобальні обмеження |
| §8.4 | Крок 1 Задачі 3 |
| §8.5 | Крок 1 Задачі 5 |
| §8.3 | перевіряє `dart analyze` Задачі 6 |
| §9 | rebase за потреби |

**Узгодженість типів:**
- `PageAddress` починається з `encodedPath` (1), отримує `pathOf` (5) та `alternatePathOf`/`alternatePatternOf` (6).
- `PageResponder` створено в 1, змінено в 4–7; його текстова відповідь зʼявляється в 6 і використовується в 7.
- `CanonicalRedirect.forFile` визначено в 5 і використано в 6–7.

**Ризики лімітів:**
- `pages_api.dart` (131) після Задачі 1 стає меншим, а в 6 росте до ~150.
- `sitemap_source.dart` (222) лише втрачає `_encodedPath`.
- `http_response.dart` 120 → ~180.
- `router.dart` 128 → ~170.
- `page_declaration_error.dart` 157 → ~230.
- Тестові файли нові, кожен < 500.
