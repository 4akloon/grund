# grund_jaspr: сторінки в модулях і сайти — план реалізації

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Мета:** сторінки Jaspr оголошуються в будь-якому модулі (`Pages.under<S>`), кілька сайтів (`PageSite`) працюють паралельно, sitemap і навігація виводяться з каталогу сторінок.

**Архітектура:** `Pages.site` і `Pages.under` повертають звичайні прив'язки з внутрішніми нащадками `HttpApi` (`SiteApi`, `PagesApi`) у модулі, що їх оголосив, тож call-scope, DI і хуки працюють як у звичайних роутах. Внутрішній раннер `pages` бере свіжий injector на `prepare`/`reassemble`, збирає знімок, перевіряє глобальні правила й живить `PageCatalog`. Статику віддає окремий `StaticApi`.

**Стек:** Dart `^3.8.0`, Jaspr 0.23.5, `grund`, `grund_http`; пакет `packages/grund_jaspr` (плюс споживачі: `example/`, `packages/grund_cli`).

**Spec:** `docs/superpowers/specs/2026-10-16-grund-jaspr-pages-design.md` (у плані «§» означає розділ цього spec; на нього плани спираються, де сказано «за §»). Розбіжність між планом і spec вирішує spec.

## Глобальні обмеження

- Код, doc-коментарі, README, CHANGELOG, коміти — англійською; документи `docs/superpowers/*` — українською. Коміти: Conventional Commits (`feat(jaspr): ...`) із закінченням `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. **Нічого не пушити, не тегувати, не публікувати.**
- Виконувати у worktree-гілці (не на `master`). `dart` не завжди в PATH: `export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"`.
- Змін у `packages/grund` і `packages/grund_http` немає. `grund_jaspr` залежить лише від `grund`, `grund_http`, `jaspr` (`>=0.23.5 <0.24.0`), `path`; ніколи від `grund_auth`.
- Ліміти (CLAUDE.md): файл у `lib/` ≤300 рядків (`wc -l`), тест ≤500, метод ≤40, параметрів ≤5, вкладеність ≤3, один публічний клас (або запечатана родина) на файл, `///` на кожному публічному члені, без `dynamic`, без `late` без коментаря, без `// ignore:`, `catch` лише з `on`; єдиний новий `catch` — `on NotFoundException` (окремого запису в CLAUDE.md про межі не потрібно). Dart 3.8: без dot shorthands і primary constructors. Статичні члени в класі, а не топ-рівневі функції.
- Слово «scope» лишається за DI; група сторінок — «site» (`PageSite`).
- Значення: `staticPath` `'/static'`; `rootFiles` `const []`; `sitemapChunkSize` `50000`; `sitemapCacheLifetime` `Duration(seconds: 60)`; логер `Logger('grund.jaspr')`; ім'я раннера `'pages'`; код 404 для файлів `file_not_found`.
- Перенесені (adopted) синглтони при hot reload тримають старий injector: каталог і глобальна валідація беруть дані **лише** зі знімка `PagesRunner`, ніколи з `injector.all` усередині синглтона.
- Після кожної задачі в `packages/grund_jaspr`: `dart analyze` («No issues found!») і `dart test` зелені; `dart format packages example` не змінює файлів. Тести: `TestApp` + `TestClient` (без мережі), хелпери в `test/helpers/`.
- Модулі в тестах оголошуються так само, як наявні (`test/helpers/pages.dart`, `GreeterModule`); `Module` — абстрактний клас з гетерами `bindings`, `imports`, `exports` (`Key`-и власних прив'язок), `global`.

## Огляд файлів (`packages/grund_jaspr/lib/src/`)

| Каталог | Файли (публічні позначено ★) |
| --- | --- |
| `page/` | `page.dart`★ (`Page`, `PageBuilder`), `page_hooks.dart`★, `page_meta.dart`★, `page_nav.dart`★, `page_sitemap.dart`★, `page_extension.dart`★, `page_path.dart` (розбір шляху), `page_match.dart`★ (`PageMatch`), `site_page.dart`★, `page_matcher.dart`, `non_page_requests.dart`, `page_renderer.dart` |
| `site/` | `page_site.dart`★, `pages.dart`★, `site_api.dart`, `pages_api.dart`, `hook_resolver.dart`, `pages_runner.dart`, `page_registry.dart` (`PageRegistry`, `PageSnapshot`), `site_validator.dart`, `static_api.dart`, `static_files.dart` (існує, переїжджає) |
| `sitemap/` | `sitemap_entries.dart`★, `sitemap_entry.dart`★, `sitemap_change_frequency.dart`★, `sitemap_url.dart`★, `sitemap_handlers.dart`, `sitemap_writer.dart`, `sitemap_chunk_cache.dart` |
| `catalog/` | `page_catalog.dart`★, `nav_item.dart`★ |
| `error/` | `jaspr_error.dart`★ (база, існує), `site_declaration_error.dart`★, `page_declaration_error.dart`★, `page_runtime_error.dart`★ |
| наявні | `jaspr_module.dart`, `jaspr_config.dart`, `grund_scope.dart`, `grund_context.dart`, `live_reload_script.dart`, … лишаються у `lib/src/` |

Переміщення наявних файлів — лише коли задача їх чіпає; barrel `lib/grund_jaspr.dart` експортує ★-файли.

## Review Focus

1. Запит до охоронюваного сайту з `//`, `%2F`, іншим регістром, `.html`, кінцевим `/`, `HEAD`: охоронці діють, сторінка не віддається гостю (Задачі 4, 5).
2. `GET /projects/x.png` і `/projects/foo.md` при сторінці `/projects/:slug`: білдер не викликається, відповідь JSON 404 `file_not_found` (Задача 6).
3. Hot reload: додано/видалено сайт чи сторінку, каталог і роути не застарівають; помилка локального правила лишає стару таблицю (Задача 7).
4. Sitemap: 0 адрес, рівно `sitemapChunkSize`, +1, порція поза діапазоном, символи `& < > ' "` і кирилиця в `<loc>`, помилка джерела не отруює кеш (Задача 10).
5. Білдер кидає не `NotFoundException` (500, не 404); `/sitemap.xml`, `/static/...` і `rootFiles` не перекриваються сторінкою `/:slug` кореневого сайту; `HEAD` на сторінку (Задачі 4, 6, 10).

---

### Задача 1: Конфігурація й база помилок

**Файли:** змінити `lib/src/jaspr_config.dart`, `lib/src/jaspr_error.dart` (→ `lib/src/error/jaspr_error.dart`), `test/jaspr_setup_test.dart` або новий `test/jaspr_config_test.dart`.

**Інтерфейси:**
- Споживає: наявні `JasprConfig(staticDirectory, pageSuffixes, liveReloadUrl)`, `JasprSetupError(reason)`.
- Створює: `JasprConfig` з новими полями `String staticPath = '/static'`, `List<String> rootFiles = const []`, `int sitemapChunkSize = 50000`, `Duration sitemapCacheLifetime = const Duration(seconds: 60)`; `validate()` додатково кидає `JasprSetupError`, якщо `staticPath` не починається з `/`, закінчується на `/` або порожній; `rootFiles` містить елемент із `/`; `sitemapChunkSize < 1`. `abstract base class JasprError extends GrundError` (було `sealed`); наявні `PageRenderError`, `JasprSetupError`, `MissingGrundScopeError` лишаються `final class`.

- [ ] **Крок 1: тести** (`jaspr_config_test.dart`): типові значення — `const JasprConfig().staticPath == '/static'`, `rootFiles` порожній, `sitemapChunkSize == 50000`, `sitemapCacheLifetime == Duration(seconds: 60)`; `expect(() => const JasprConfig(staticPath: 'static').validate(), throwsA(isA<JasprSetupError>()))`; те саме для `'/static/'`, `rootFiles: ['a/b.txt']`, `sitemapChunkSize: 0`; `withLiveReloadUrl` зберігає нові поля.
- [ ] **Крок 2:** `dart test test/jaspr_config_test.dart` — FAIL (поля не існують).
- [ ] **Крок 3:** додати поля й перевірки в `JasprConfig`; змінити `sealed class JasprError` на `abstract base class JasprError extends GrundError`; перенести файл у `error/`, оновити імпорти й barrel.
- [ ] **Крок 4:** `dart analyze && dart test` у `packages/grund_jaspr` — зелені.
- [ ] **Крок 5:** коміт `feat(jaspr): static path, sitemap and root file settings in JasprConfig`.

---

### Задача 2: Декларативні значення й правила шляху

**Файли:** створити файли `page/` і `sitemap/` з огляду (`page.dart`, `page_hooks.dart`, `page_meta.dart`, `page_nav.dart`, `page_sitemap.dart`, `page_extension.dart`, `site_page.dart`, `page_match.dart`, `page_path.dart`, `sitemap_entries.dart`, `sitemap_entry.dart`, `sitemap_change_frequency.dart`), `site/page_site.dart`, `error/site_declaration_error.dart`, `error/page_declaration_error.dart`; тести `test/page_values_test.dart`, `test/page_path_test.dart`, `test/sitemap_entries_test.dart`.

**Інтерфейси** (точні сигнатури; усі `const`, де можливо):
- `typedef PageBuilder = FutureOr<Component> Function(HttpCtx c);`
- `final class Page { const Page(this.path, {required this.build, this.meta = const PageMeta(), this.hooks = const PageHooks(), this.extensions = const []}); final String path; final PageBuilder build; final PageMeta meta; final PageHooks hooks; final List<PageExtension> extensions; }`
- `final class PageHooks { const PageHooks({this.skip = const [], this.use = const []}); final List<Type> skip; final List<HookRef<HttpHook>> use; }`
- `final class PageMeta { const PageMeta({this.title = '', this.description, this.nav, this.sitemap = const PageSitemap()}); }`
- `final class PageNav { const PageNav({this.label, this.group = 'main', this.order = 0}); }`
- `final class PageSitemap { const PageSitemap({this.included = true, this.lastModified, this.changeFrequency, this.priority, this.entries}); final SitemapEntries? entries; … }`; `enum SitemapChangeFrequency { always, hourly, daily, weekly, monthly, yearly, never }`
- `abstract interface class SitemapEntries` з `factory SitemapEntries.all(Future<List<SitemapEntry>> Function(Injector injector) load)`, `factory SitemapEntries.paged({required Future<int> Function(Injector) count, required Future<List<SitemapEntry>> Function(Injector, int offset, int limit) load})`, `Future<int> count(Injector injector)`, `Future<List<SitemapEntry>> slice(Injector injector, int offset, int limit)` (`all` рахує по довжині списку й ріже його); `final class SitemapEntry { const SitemapEntry({required this.params, this.lastModified}); final Map<String, String> params; final DateTime? lastModified; }`
- `abstract base class PageExtension { const PageExtension(); Future<HttpResponse?> respond(HttpCtx c, PageMatch match) async => null; Future<HttpResponse?> claim(HttpCtx c, Uri uri) async => null; }`
- `final class SitePage { const SitePage({required this.site, required this.page, required this.path}); final PageSite site; final Page page; final String path; }` (`path` — повний: `site.path` + шлях сторінки); `final class PageMatch { const PageMatch({required this.page, this.params = const {}}); final SitePage page; final Map<String, String> params; }`
- `abstract base class PageSite { PageSite(this.injector); final Injector injector; String get path => ''; List<HookRef<HttpHook>> get use => const []; List<Type> get skippableHooks => const []; Component shell(Component content) => content; Component notFound() => …текст «Not found»; Uri? get sitemapBaseUrl => null; }`
- `final class PagePath` (внутрішній, `page_path.dart`): `static PagePath parse(String path)` — розбиває на сегменти; літерал або `:name`; `String get normalized`; `List<String> get paramNames`; `bool get hasParams`. Кидає `InvalidPagePathError(path, reason)` для: не починається з `/`, є `*`, сегмент змішує літерал і `:`, порожнє ім'я параметра, `//`. Для сайту `static void checkSitePath(String path)` кидає `InvalidSitePathError(path, reason)` (порожній дозволено; `/seg[/seg]`, лише літерали, без кінцевого `/`).
- Помилки (`final class`, у запечатаних підродинах `SiteDeclarationError`, `PageDeclarationError`, обидві `extends JasprError`): `InvalidSitePathError({required String path, required String reason})`, `InvalidPagePathError({required String path, required String reason})`; `message` називає шлях і причину.

- [ ] **Крок 1: тести.** `page_path_test.dart`: `PagePath.parse('/projects/:slug').paramNames == ['slug']`; `parse('/')` нормалізується в `'/'`; кидають `InvalidPagePathError`: `'users'`, `'/a/*'`, `'/a-:id'`, `'/a/:'`, `'/a//b'`. `checkSitePath('')` і `'/admin'` проходять; `'/admin/'`, `'admin'`, `'/a/:b'`, `'/a/*'` кидають `InvalidSitePathError`. `page_values_test.dart`: `const Page('/', build: …)` має `meta.title == ''`, `meta.sitemap.included == true`, `meta.nav == null`; `PageNav().group == 'main'` і `order == 0`; `PageSite` за замовчуванням: `path == ''`, `use` і `skippableHooks` порожні, `sitemapBaseUrl == null`, `shell(c)` повертає той самий `c`. `sitemap_entries_test.dart`: `SitemapEntries.all((_) async => [e1, e2, e3])` дає `count == 3` і `slice(i, 1, 1)` повертає `[e2]`; `.paged` викликає `load` з `offset` і `limit`, що передали, а `count` — один раз на виклик.
- [ ] **Крок 2:** `dart test` — FAIL (типів немає).
- [ ] **Крок 3:** реалізувати типи за сигнатурами; barrel експортує ★-файли.
- [ ] **Крок 4:** `dart analyze && dart test` зелені.
- [ ] **Крок 5:** коміт `feat(jaspr): page, site and sitemap declaration values`.

---

### Задача 3: Рендер сторінки з її збігом і статусом

**Файли:** змінити `lib/src/page_renderer.dart` (→ `page/page_renderer.dart`), `lib/src/jaspr_pages.dart`, `lib/src/grund_scope.dart`, `lib/src/grund_context.dart`; тест `test/page_renderer_test.dart`, правка наявних `jaspr_pages_test.dart` лише там, де ламається конструктор.

**Інтерфейси:**
- Споживає: `PageMatch`, `SitePage` із Задачі 2.
- `PageRenderer`: конструктор `PageRenderer({this.liveReloadUrl})`; `Future<HttpResponse> render(HttpCtx c, Component page, {int status = 200, PageMatch? match})` — обгортає `page` у `GrundScope(httpContext: c, pageMatch: match, child: page)`; статус відповіді — `status`; решта як було (`PageRenderError` при 500 Jaspr).
- `GrundScope({required httpContext, PageMatch? pageMatch, required child})`; `extension GrundContext on BuildContext { PageMatch? get pageMatch }`.
- `JasprPages` (старий) поки працює через `renderer.render(c, app())`.

- [ ] **Крок 1: тести.** Через мінімальний `HttpApi` у тесті з маршрутом, що кличе `renderer.render`: `render(c, const Text('hi'), status: 404)` дає статус 404 і тіло з `hi`; компонент, що читає `context.pageMatch`, бачить `params['slug'] == 'a'` для `PageMatch(page: sp, params: {'slug': 'a'})`; без `match` `context.pageMatch == null`; компонент, що кидає, дає `PageRenderError`.
- [ ] **Крок 2:** `dart test test/page_renderer_test.dart` — FAIL.
- [ ] **Крок 3:** змінити `PageRenderer`, `GrundScope`, `GrundContext`; адаптувати старий `JasprPages` та `JasprModule` до нової сигнатури `PageRenderer`, щоб наявні тести лишились зеленими.
- [ ] **Крок 4:** `dart analyze && dart test` — зелені (наявні 10 тестових файлів без змін поведінки).
- [ ] **Крок 5:** коміт `feat(jaspr): render a page with its match and status`.

---

### Задача 4: Сайти й сторінки в модулях (наскрізний зріз)

**Файли:** створити `site/pages.dart`, `site/site_api.dart`, `site/pages_api.dart`, `site/page_registry.dart` (лише `PageRegistry` без логіки), `test/helpers/sites.dart`, `test/sites_routing_test.dart`, `test/sites_di_test.dart`; **замінити** `jaspr_module.dart` (нова форма), **видалити** `jaspr_pages.dart`; мігрувати наявні `test/helpers/pages_app.dart`, `test/helpers/pages.dart`, `jaspr_pages_test.dart`, `jaspr_routing_test.dart`, `jaspr_contract_test.dart`, `live_reload_pages_test.dart`, `jaspr_setup_test.dart`, `example/grund_jaspr_example.dart`, `test/example_test.dart` на сайти (поведінка тих тестів, що не про старий `app:`, зберігається; тести старого `app:`-контракту видаляються).

**Інтерфейси:**
- Споживає: типи Задач 1–3; `HttpApi(Injector)`, `Route.get(path, handler, {use, name})`, `HookRef`, `Key<T>()`, `Singleton<T>(create, {dependsOn: List<Key<Object>>})`.
- Створює:
  - `abstract final class Pages { static List<Binding<Object>> site<S extends PageSite>(S Function(Injector) create); static Binding<Object> under<S extends PageSite>(List<Page> Function(Injector) pages); }` — `site` повертає `[Singleton<S>(create, dependsOn: const [])` і `Singleton<SiteApi<S>>((i) => SiteApi<S>(i, i<S>()), dependsOn: [Key<S>()])]`; `under` повертає `Singleton<PagesApi<S>>((i) => PagesApi<S>(i, i<S>(), i<PageRenderer>(), pages), dependsOn: [Key<S>(), Key<PageRenderer>()])`. Явні аргументи типів скрізь (`Binding<Object>` заборонено).
  - `final class SiteApi<S extends PageSite> extends HttpApi` (`siteType => S`, `S get site`, `path => site.path`, `routes` = `[Route.get('/*', fallback, use: site.use)]`): фолбек віддає `site.notFound()` у `site.shell` через `renderer.render(c, …, status: 404)`.
  - `final class PagesApi<S extends PageSite> extends HttpApi` (`siteType => S`, `path => site.path`, `List<Page> get pages` кличе `declare(injector)` щоразу; `routes`: для кожної сторінки `Route.get(page.path, handler, use: [...site.use, ...page.hooks.use], name: 'GET <fullPath>')`). Обробник: викликає `page.build(c)`; `on NotFoundException` → `site.notFound()` у `site.shell` зі статусом 404; інакше компонент у `site.shell` зі статусом 200 і `PageMatch` (параметри з `c.path`).
  - `JasprModule({JasprConfig config = const JasprConfig()})`: `global => true`; прив'язки `JasprConfig` (з `_withEnvironment()`), `PageRenderer`, `PageRegistry`; `exports` — `Key`-и цих трьох; `onInit` як було. Без `app`, без `imports`.
  - `PageRegistry`: `PageSnapshot? current; void replace(PageSnapshot s)`; `PageSnapshot({required List<SiteApi<PageSite>> sites, required List<PagesApi<PageSite>> pages})` (наповнює Задача 7).
- Помилка валідації «немає сторінки `/`» — Задача 7; тут не перевіряється.

- [ ] **Крок 1: хелпери й тести.** `test/helpers/sites.dart`: `PublicSite extends PageSite` (`path ''`), `AdminSite` (`path '/admin'`, `use [HookRef<AdminGuard>.type()]`, `shell` обгортає в `<main class="admin">`), `AdminGuard extends HttpHook` (кидає `UnauthorizedException` без заголовка `x-admin: 1`), модулі `PublicSiteModule`, `AdminSiteModule` (експортує `Key<AdminSite>()` і `Key<AdminGuard>()`), `UsersPagesModule` (імпортує `AdminSiteModule`, `Pages.under<AdminSite>` зі сторінками `/` → «Dashboard», `/users` → «Users», `/users/:id` → «User <id>»), `HomePagesModule` (`Pages.under<PublicSite>`: `/` → «Home», `/about`). Тести у `sites_routing_test.dart` (клієнт `PagesApp.start([JasprModule(), PublicSiteModule(), AdminSiteModule(), HomePagesModule(), UsersPagesModule()])`):
  - `get('/')` → 200 «Home»; `get('/about')` → 200; `get('/admin/users', headers: {'x-admin': '1'})` → 200 «Users»; `get('/admin/users/7', …)` → тіло містить «User 7»; `get('/admin/users')` без заголовка → 401.
  - `get('/nope')` → 404 HTML публічного сайту (`notFound()`), `get('/admin/nope', admin)` → 404 HTML адмінки в `<main class="admin">`; `get('/admin/nope')` без заголовка → 401 (гість не бачить 404 адмінки).
  - `head('/about')` → 200 без тіла; `get('//about')` і `get('/about/')` → 200; `get('/ADMIN/users', admin)` → 404 (регістр); `get('/admin%2Fusers', admin)` не віддає сторінку адмінки.
  - Сторінка, що кидає `NotFoundException` у білдері → 404 `notFound()` сайту; сторінка, що кидає `StateError` у білдері → 500; компонент, що кидає під час рендеру, → 500.
  - Два сайти з різних модулів не змішуються: `/users` у публічному сайті не потрапляє в адмінку.
  `sites_di_test.dart`: білдер бачить сервіс модуля сторінок (`c<UsersService>()`); значення, поставлене хуком сайту (`c.set<CurrentUser>(…)`), читається в компоненті (`context.maybe<CurrentUser>()`); `Pages.under<AdminSite>` у модулі, що не імпортує `AdminSiteModule`, падає на старті помилкою графа (`isA<GraphError>()`: `MissingProviderError` або `ProviderNotVisibleError`, залежно від того, бачить модуль тип); `Pages.under` без `JasprModule` падає на старті `MissingProviderError` (бо `PageRenderer` відсутній); два `Pages.under<AdminSite>` в одному модулі — `DuplicateBindingError`.
- [ ] **Крок 2:** `dart test test/sites_routing_test.dart test/sites_di_test.dart` — FAIL. Якщо перевірка припущень (spread двох прив'язок, `dependsOn` з generic-`Key`, збір `PagesApi` через `all<HttpApi>`, експорт `Key<S>()`) показує, що задум не працює, зупинитися зі статусом BLOCKED і описом, не обходячи ядро.
- [ ] **Крок 3:** реалізувати `Pages`, `SiteApi`, `PagesApi`, `PageRegistry` (порожній), нову форму `JasprModule`; видалити `JasprPages`; мігрувати наявні тести й `example/grund_jaspr_example.dart`.
- [ ] **Крок 4:** `dart analyze && dart test` у `packages/grund_jaspr` — зелені; жоден файл `lib/` не перевищує 300 рядків.
- [ ] **Крок 5:** коміт `feat(jaspr)!: declare pages in modules with Pages.site and Pages.under`.

---

### Задача 5: Охоронці сайту й `skip`

**Файли:** створити `site/hook_resolver.dart`, `test/site_hooks_test.dart`; змінити `site/pages_api.dart`, `error/page_declaration_error.dart`.

**Інтерфейси:**
- `final class HookResolver { const HookResolver(); List<HookRef<HttpHook>> forPage({required PageSite site, required Page page, required String fullPath}); }` — повертає `site.use` без хуків, чий `hookType` точно дорівнює елементу `page.hooks.skip`, плюс `page.hooks.use`; кидає: `ForbiddenPageSkipError({path, type})`, якщо тип не входить до `site.skippableHooks`; `UnknownPageSkipError({path, type, siteHooks})` (повідомлення перелічує типи `site.use`), якщо типу немає в `site.use`; `AmbiguousPageSkipError({path, type})`, якщо тип зустрічається в `site.use` кілька разів. Логує через `Logger('grund.jaspr')`: `INFO` `page /admin/login skips AdminGuard (site /admin)` (`WARNING` для сторінки з `:param`).
- `PagesApi.routes` викликає `HookResolver.forPage` (помилка в геттері лишає стару таблицю).

- [ ] **Крок 1: тести** (`AdminSite.skippableHooks => [AdminGuard]`, сторінка `/login` з `PageHooks(skip: [AdminGuard])`): `get('/admin/login')` без заголовка → 200 і лише цей хук знято (другий хук сайту `AuditHook`, що ставить заголовок `x-audit`, спрацьовує — `r.headers['x-audit'] == 'on'`); `get('/admin/users')` без заголовка → 401; фолбек `/admin/nope` без заголовка → 401 (фолбек ігнорує `skip`); `skip: [HttpHook]` (базовий тип) → `UnknownPageSkipError`; тип не в `skippableHooks` → `ForbiddenPageSkipError`; сайт з двома `HookRef<AdminGuard>` → `AmbiguousPageSkipError`; помилка виникає при `PagesApp.start` (не при першому запиті); підтип не знімається (`skip: [BaseGuard]`, у сайті `ChildGuard extends BaseGuard` → `UnknownPageSkipError`); лог `INFO` перехоплений через `Logger.root.onRecord` містить `skips AdminGuard`.
- [ ] **Крок 2:** FAIL. **Крок 3:** реалізувати. **Крок 4:** `dart analyze && dart test` зелені.
- [ ] **Крок 5:** коміт `feat(jaspr): skip individual site hooks on a page`.

---

### Задача 6: Статика й запити не-сторінок

**Файли:** створити `site/static_api.dart`, `page/non_page_requests.dart`, `test/static_test.dart`, `test/non_page_requests_test.dart`; перемістити `static_files.dart` у `site/`; змінити `jaspr_module.dart` (прив'язки `StaticFiles`, `NonPageRequests`, `StaticApi`), `site/pages_api.dart`, `site/site_api.dart`, `error/page_declaration_error.dart` (+ `ReservedPagePathError({path, reason})`).

**Інтерфейси:**
- `final class StaticApi extends HttpApi`: `routes` = `Route.get('<staticPath>/*', serve)` + по `Route.get('/<file>', serve)` на елемент `config.rootFiles`; `serve` віддає файл із `StaticFiles` або кидає `NotFoundException(message: 'There is no file <path>.', code: 'file_not_found')`; без хуків сайтів.
- `final class NonPageRequests { NonPageRequests(this._config); bool isPageRequest(Uri uri); }` — `false`, коли останній сегмент має розширення (крапка) поза `config.pageSuffixes`; `Never notFound(Uri uri)` кидає `NotFoundException(..., code: 'file_not_found')`.
- Обробники сторінок і фолбек сайту: якщо `!isPageRequest` — `notFound` без виклику білдера.
- `PagesApi.routes` кидає `ReservedPagePathError`, якщо повний шлях сторінки дорівнює `staticPath`, лежить під ним або дорівнює `/<файл з rootFiles>`; `SiteApi`/`Pages.site` кидає `InvalidSitePathError`, якщо `site.path` дорівнює `staticPath` чи лежить під ним.

- [ ] **Крок 1: тести.** Тимчасовий каталог (`TempDir`) зі `styles.css`, `favicon.ico`, `sub/a.txt`; `JasprConfig(staticDirectory: dir.path, rootFiles: ['favicon.ico'])`: `get('/static/styles.css')` → 200 із правильним content-type; `get('/static/sub/a.txt')` → 200; `get('/favicon.ico')` → 200; `get('/static/../x')` і `/static/%2e%2e/x` → 404 `file_not_found`; `get('/static/missing.css')` → 404 JSON із `code == 'file_not_found'`; статика віддається гостю при сайті із `AdminGuard` (хуки сайту не діють). Сторінка `/:slug` у публічному сайті не проковтує `/static/styles.css` і `/favicon.ico`. Сторінка `/projects/:slug`: `get('/projects/x.png')` і `get('/projects/foo.md')` → 404 JSON `file_not_found`, а лічильник викликів білдера = 0; `get('/projects/alpha')` → 200; `get('/projects/a.html')` — сторінка (суфікс із `pageSuffixes`). Фолбек `/admin/logo.png` з заголовком → 404 JSON, не HTML. Сайт із `path => '/static'` → `InvalidSitePathError`; сторінка `/static/x` у публічному сайті і `/favicon.ico` при `rootFiles` → `ReservedPagePathError`.
- [ ] **Крок 2:** FAIL. **Крок 3:** реалізувати. **Крок 4:** `dart analyze && dart test` зелені (`static_files_test.dart` адаптувати до нових шляхів).
- [ ] **Крок 5:** коміт `feat(jaspr): static files under a static path, file requests never reach page builders`.

---

### Задача 7: Раннер `pages`, знімок і глобальні правила

**Файли:** створити `site/pages_runner.dart`, `site/site_validator.dart`, `test/pages_runner_test.dart`, `test/site_validation_test.dart`; змінити `site/page_registry.dart`, `jaspr_module.dart` (прив'язка `PagesRunner`), `error/site_declaration_error.dart`, `error/page_declaration_error.dart`.

**Інтерфейси:**
- `final class PagesRunner extends Runner { PagesRunner(this._registry, this._validator); String get name => 'pages'; Future<void> prepare(Injector injector); Future<ReassembleReport> reassemble(Injector injector); Future<void> start(Injector injector) async {}; Future<void> stop() async {}; }` — `prepare`/`reassemble` збирають `PageSnapshot` з `injector.all<SiteApi<PageSite>>()` і `injector.all<PagesApi<PageSite>>()`, викликають `SiteValidator.check(snapshot)` і лише після успіху `registry.replace(snapshot)`; `reassemble` повертає `ReassembleReport.none`.
- `final class SiteValidator { const SiteValidator(); void check(PageSnapshot snapshot); }` кидає: `DuplicateSiteError(siteType)` (два `SiteApi` з однаковим `siteType`; `siteType` береться з `S` — не з `runtimeType`), `MismatchedSiteTypeError({expected, actual})` (`site.runtimeType != S`), `DuplicateSitePathError(path)`, `NestedSitePathError({outer, inner})`, `MissingSiteIndexError(siteType)` (немає сторінки `/`), `MisplacedPagePathError({path, siteType, owner})` (повний шлях сторінки дорівнює шляху іншого сайту або лежить під ним). Класи — у `SiteDeclarationError`/`PageDeclarationError`.
- `PageRegistry.current` до першого `replace` — `null`.

- [ ] **Крок 1: тести.** `site_validation_test.dart`, кожна помилка з окремим застосунком: два модулі з `Pages.site<AdminSite>` → `DuplicateSiteError`; `AdminSite` і `OtherAdminSite` з `path => '/admin'` → `DuplicateSitePathError`; `/admin` і `/admin/reports` → `NestedSitePathError`; сайт без сторінки `/` → `MissingSiteIndexError`; сторінка `/admin/help` у публічному сайті → `MisplacedPagePathError`; підклас `SuperAdminSite extends AdminSite` не змішується з `AdminSite` (кожен має свій `SiteApi`, `Pages.under<AdminSite>` бере саме `AdminSite`). Усі помилки з `TestApp.start` (він викликає `prepare`, також з `only: {}`). `pages_runner_test.dart` (hot reload): запустити два застосунки A (сайт + сторінка `/x`) і B (A плюс сторінка `/y` та сайт `/blog`); `await runner.prepare(a.injector)`; `registry.current!.pages` містить `/x`; `await runner.reassemble(b.injector)` — знімок містить `/y` і `/blog`; невалідний B (`NestedSitePathError`) не замінює знімок A і кидає помилку. Запуск `PagesRunner` на порожньому графі (немає сайтів) проходить.
- [ ] **Крок 2:** FAIL. **Крок 3:** реалізувати. **Крок 4:** `dart analyze && dart test` зелені.
- [ ] **Крок 5:** коміт `feat(jaspr): validate sites at start and refresh the page snapshot on reload`.

---

### Задача 8: Каталог `PageCatalog`, навігація, `match`

**Файли:** створити `catalog/page_catalog.dart`, `catalog/nav_item.dart`, `page/page_matcher.dart`, `test/catalog_test.dart`, `test/page_matcher_test.dart`, `test/match_parity_test.dart`; змінити `jaspr_module.dart` (прив'язка і експорт `PageCatalog`), `error/page_runtime_error.dart` (+ `PageCatalogNotReadyError`).

**Інтерфейси:**
- `final class NavItem { const NavItem({required this.label, required this.path, required this.group, required this.order}); }`
- `final class PageCatalog { PageCatalog(this._registry, this._config); List<SitePage> pagesOf<S extends PageSite>(); List<NavItem> navOf<S extends PageSite>(); PageMatch? match(Uri uri); List<SitePage> pagesWith<T extends PageExtension>(); }`; обидва `…Of<S>` фільтрують за **точним** типом сайту (`siteType == S`); `registry.current == null` → `PageCatalogNotReadyError()`. Сортування: навігація — `order`, потім `label`, потім `path`; сторінки — за `path`. Пункт навігації лише з `meta.nav != null`, `label ?? meta.title`; сторінки з власним `hooks.use` без `PageSitemap(included: true)` у навігацію не входять.
- `final class PageMatcher` (внутрішній): `PageMatcher(List<SitePage> pages)`; `PageMatch? match(List<String> segments)` — пріоритет: літерал, потім `:param`, з поверненням назад; порожні сегменти відкидаються; відсотково декодує; регістр значущий.

- [ ] **Крок 1: тести.** Каталог: `navOf<PublicSite>()` повертає пункти у порядку `order`, потім `label`; сторінка без `nav` не входить; `pagesOf<AdminSite>()` не містить сторінок публічного сайту й `SuperAdminSite`; `pagesWith<MarkdownLike>()` повертає лише сторінки з таким розширенням; звернення до `PageCatalog` до `prepare` — `PageCatalogNotReadyError`. Матчер: `match(Uri.parse('/projects/alpha'))` → сторінка `/projects/:slug` і `params == {'slug': 'alpha'}`; літерал `/projects/new` перемагає `:slug`; `/` → індекс публічного сайту; `/admin/users/7` → сторінка адмінки; `//about`, `/about/`, `/ABOUT` (None), `/%61bout` → `about`; `/a%2Fb` лишається одним сегментом. `match_parity_test.dart`: для набору шляхів (`//`, `%2F`, `%61dmin`, кінцевий `/`, регістр, параметри) відповідь `TestClient` на запит і `catalog.match(uri)` вказують на одну й ту саму сторінку (за заголовком в тілі).
- [ ] **Крок 2:** FAIL. **Крок 3:** реалізувати. **Крок 4:** `dart analyze && dart test` зелені.
- [ ] **Крок 5:** коміт `feat(jaspr): page catalog with navigation and URL matching`.

---

### Задача 9: Модель sitemap: правила, писар, `sitemapOf`

**Файли:** створити `sitemap/sitemap_url.dart`, `sitemap/sitemap_writer.dart`, `test/sitemap_rules_test.dart`, `test/sitemap_writer_test.dart`, `test/sitemap_of_test.dart`; змінити `catalog/page_catalog.dart`, `site/pages_api.dart`, `site/site_api.dart`, `error/*` (+ `GuardedSiteSitemapError(siteType)`, `UndecidedPageSitemapError(path)`, `UnusedPageEntriesError(path)`, `PageEntriesMismatchError({path, expected, actual})`; `ReservedPagePathError` розширюється шляхами sitemap).

**Інтерфейси:**
- `final class SitemapUrl { const SitemapUrl({required this.location, this.lastModified, this.changeFrequency, this.priority}); final Uri location; … }`
- `PageCatalog.Stream<SitemapUrl> sitemapOf<S extends PageSite>()` — статичні сторінки (без `:param`, `sitemap.included`, без власних `hooks.use`, якщо не `included: true` явно) і адреси з `entries` порціями по `config.sitemapChunkSize` (підставляє `params` у шлях, значення відсотково кодує); локація — `sitemapBaseUrl.resolve(path)`; сайт без `sitemapBaseUrl` дає порожній потік; порядок — за шляхом.
- `final class SitemapWriter { static String urlSet(Iterable<SitemapUrl> urls); static String index(Iterable<Uri> sitemaps); }` — XML (`<?xml version="1.0" encoding="UTF-8"?>`, простір імен `http://www.sitemaps.org/schemas/sitemap/0.9`), екранує `& < > ' "` у `<loc>`, `lastmod` у ISO-8601 UTC, `changefreq` — ім'я enum, `priority` з однією цифрою після коми.
- Правила (кидаються в `PagesApi.routes`/`SiteApi.routes`): сайт із непорожнім `use` і `sitemapBaseUrl != null` → `GuardedSiteSitemapError`; сторінка з `:param` у сайті з `sitemapBaseUrl` без `entries` і без `PageSitemap(included: false)` → `UndecidedPageSitemapError`; `entries` на сторінці без `:param` → `UnusedPageEntriesError`; ключі `SitemapEntry.params` не збігаються з іменами `:param` → `PageEntriesMismatchError` (під час потоку); шляхи `<site>/sitemap.xml` і `<site>/sitemap/…` → `ReservedPagePathError`.

- [ ] **Крок 1: тести.** Писар: `urlSet` з `location: Uri.parse('https://x.test/a?b=1&c=2')` містить `&amp;` у `<loc>`, кирилиця `/проєкти/п` кодується відсотками, `index` перелічує всі файли; `sitemapOf<PublicSite>()` для сайту з `sitemapBaseUrl: Uri.parse('https://x.test')` повертає `/`, `/about`, а `/projects/:slug` з `entries.all` на два записи → `https://x.test/projects/alpha`, `…/beta`; сторінку з `included: false` пропускає; сторінку з власним `hooks.use` пропускає; `paged` з `count` 120 і `sitemapChunkSize: 50` викликає `load` з `(0,50)`, `(50,50)`, `(100,20)`; сайт без `sitemapBaseUrl` — порожньо. Правила: кожна з помилок вище на окремому застосунку (`TestApp.start` падає).
- [ ] **Крок 2:** FAIL. **Крок 3:** реалізувати. **Крок 4:** `dart analyze && dart test` зелені.
- [ ] **Крок 5:** коміт `feat(jaspr): sitemap model and rules derived from pages`.

---

### Задача 10: Ендпоїнти sitemap, порції, кеш

**Файли:** створити `sitemap/sitemap_handlers.dart`, `sitemap/sitemap_chunk_cache.dart`, `test/sitemap_endpoints_test.dart`, `test/sitemap_cache_test.dart`; змінити `site/site_api.dart` (роути sitemap), `catalog/page_catalog.dart` (`invalidateSitemap()`).

**Інтерфейси:**
- `SiteApi.routes` (лише коли `site.sitemapBaseUrl != null`) додає без хуків сайту `Route.get('/sitemap.xml', …)` і `Route.get('/sitemap/:chunk', …)`; відповідь `application/xml; charset=utf-8`. Один файл, коли адрес ≤ `sitemapChunkSize`; інакше `/sitemap.xml` — індекс на `<base>/sitemap/<n>.xml`; `chunk` розбирається з `<n>.xml` (1-based); некоректний або поза діапазоном → 404 `NotFoundException`.
- `final class SitemapChunkCache { SitemapChunkCache(this._lifetime, this._clock); Future<T> get<T>(String key, Future<T> Function() load); void clear(); }` — кеш на `lifetime`; значення кладеться лише після успіху; одночасні запити одного ключа діляться одним `load`; кількість ключів обмежена (найстаріші витісняються, максимум 64); `try/finally`, без `catch`.
- `PageCatalog.void invalidateSitemap()` очищає кеш.
- Помилка джерела `entries` → 500 на запит sitemap і `SEVERE` у логу; наступний запит після виправлення успішний (кеш не отруєний).

- [ ] **Крок 1: тести.** 0 адрес → `urlset` без `<url>`; рівно `sitemapChunkSize` адрес → один файл; `+1` → `/sitemap.xml` є індексом із двома `<sitemap>`, `/sitemap/1.xml` має `sitemapChunkSize` записів, `/sitemap/2.xml` один; `/sitemap/3.xml`, `/sitemap/x.xml`, `/sitemap/0.xml` → 404; `HEAD /sitemap.xml` → 200 без тіла; sitemap публічного сайту (без `use`) віддається без жодних заголовків (сайт із `use` і `sitemapBaseUrl` не стартує, Задача 9); кеш: два запити за `lifetime` викликають `count` один раз, після зміни годинника на `lifetime + 1 с` — вдруге; `invalidateSitemap()` скидає; джерело, що кидає, → 500, наступний успішний запит → 200 (джерело перемкнули); 20 одночасних запитів → `count` викликано один раз. Годинник у `SitemapChunkCache` підміняється в тесті (`DateTime Function() _clock`).
- [ ] **Крок 2:** FAIL. **Крок 3:** реалізувати. **Крок 4:** `dart analyze && dart test` зелені.
- [ ] **Крок 5:** коміт `feat(jaspr): serve chunked sitemaps with a short-lived cache`.

---

### Задача 11: Точки розширення `respond` і `claim`

**Файли:** змінити `site/pages_api.dart`, `site/site_api.dart`, `page/non_page_requests.dart`, тест `test/page_extension_test.dart`.

**Інтерфейси:**
- `PagesApi` обробник перед рендером HTML послідовно кличе `extension.respond(c, match)` кожного `page.extensions`; перша не-`null` відповідь повертається (після хуків сайту й сторінки — вони вже відпрацювали як `Route.use`).
- `NonPageRequests.Future<HttpResponse> answer(HttpCtx c, Iterable<PageExtension> extensions)` — для не-сторінкового запиту спершу `extension.claim(c, c.request.uri)` усіх розширень сторінок сайту (перша не-`null`), інакше JSON 404 `file_not_found`; обробники сторінок і фолбек користуються ним замість голого `notFound`. Розширення збираються зі знімка реєстру (`SitePage.page.extensions`) за сайтом.

- [ ] **Крок 1: тести** (тестове розширення `Recording extends PageExtension` з лічильниками): `respond` повертає `HttpResponse` для `Accept: text/markdown` → клієнт отримує її, білдер не викликається; `respond` → `null` → звичайна сторінка; на сайті з `AdminGuard` гість з `Accept: text/markdown` отримує 401 (розширення не викликалося); `claim` для `/projects/foo.md` повертає відповідь → 200; без `claim` → 404 JSON; `claim` не викликається для запиту сторінки (`/projects/alpha`).
- [ ] **Крок 2:** FAIL. **Крок 3:** реалізувати. **Крок 4:** `dart analyze && dart test` зелені.
- [ ] **Крок 5:** коміт `feat(jaspr): guarded page extension hooks for responses and file variants`.

---

### Задача 12: Споживачі — `example/`, шаблон `fullstack`, інтеграційний хелпер

**Файли:** змінити `example/lib/src/web/web_module.dart`, `tasks_site.dart`, `home_page.dart`, `login_page.dart`, `example/web/*` (посилання на `styles.css` → `/static/styles.css`), `example/test/web_e2e_test.dart`; `packages/grund_cli/lib/src/init/fullstack_template.dart`, `project_kind.dart`, `packages/grund_cli/test/init_fullstack_test.dart` (версія `grund_jaspr: ^0.2.0`), `packages/grund_cli/integration/helpers/site_sources.dart`, `packages/grund_cli/integration/dev_jaspr_test.dart`. Версія в `packages/grund_jaspr/pubspec.yaml` піднімається під час релізу (`docs/RELEASING.md`), тут не чіпати.

**Інтерфейси:** `example/`: `PublicSite`, `Pages.under<PublicSite>` у `WebModule` замість `JasprModule(app: TasksSite.new, imports: [tasks])`; сторінки входу/головна — окремі `Page`; приклад лишається «ті самі в анотаціях і явному API»: модуль веб-частини пишеться явно (анотацією сторінки не оголошуються). Шаблон `fullstack`: `AppModule` імпортує `JasprModule()`, `HomeSiteModule` з `Pages.site<PublicSite>` і `Pages.under<PublicSite>`.

- [ ] **Крок 1: тести спершу** — оновити `example/test/web_e2e_test.dart` (чотири сервери: `ModuleStyle × AdapterKind`): `GET /` → 200 з посиланням `/static/styles.css`; `GET /static/styles.css` → 200; вхід (POST sign-in same-origin) → 303 і cookie; `GET /nope` → 404 HTML; `packages/grund_cli/test/init_fullstack_test.dart` — `grund_jaspr: ^0.2.0` і шаблон містить `Pages.under<PublicSite>`; `dart test integration` у `grund_cli` (`dev_jaspr_test.dart`) очікує живе перезавантаження сторінки з правкою.
- [ ] **Крок 2:** запустити, FAIL.
- [ ] **Крок 3:** мігрувати код споживачів; `cd example && dart run grund_cli gen` (якщо змінилися анотації) і закомітити згенероване.
- [ ] **Крок 4:** `dart analyze` (корінь) чисто; `cd example && dart test`; `cd packages/grund_cli && dart test && dart test integration`.
- [ ] **Крок 5:** коміт `feat(cli,example): move the fullstack template and the example to sites`.

> Релізний порядок: шаблон називає `grund_jaspr ^0.2.0`, якого немає на pub.dev до релізу; публікація (вручну, за `docs/RELEASING.md`) — спершу `grund_jaspr`, потім `grund_cli`. Ця задача нічого не публікує.

---

### Задача 13: Документація й фінальні перевірки

**Файли:** змінити `docs/jaspr.md`, `packages/grund_jaspr/README.md`, `packages/grund_jaspr/CHANGELOG.md` (секція `## 0.2.0` зверху: перелік змін, **breaking** для `JasprModule(app:)`, статики в `/static`, нові `JasprConfig` поля), `packages/grund_cli/CHANGELOG.md` (шаблон `fullstack`), `CLAUDE.md` (опис `grund_jaspr`; зауваження, що `catch` лише `on NotFoundException`), `docs/superpowers/ROADMAP.md` (позначити pages-етап), `README.md`/`docs/faq.md`/`docs/getting-started.md` там, де згадується `JasprModule(app:)`.

- [ ] **Крок 1:** переписати `docs/jaspr.md` (розділи: A page, Sites, The module, Static files, Sitemap and navigation, Signing in, Testing, Hot reload, Things to know) під нові API, англійською; прибрати згадки `app:`.
- [ ] **Крок 2:** оновити README і CHANGELOG пакета; кожен публічний тип має `///`.
- [ ] **Крок 3: фінальні перевірки.** З кореня: `dart pub get`; `dart format --output=none --set-exit-if-changed packages example`; `dart analyze --fatal-infos`; `for dir in packages/*/ example/; do (cd "$dir" && dart test) || break; done`; `(cd packages/grund_cli && dart test integration)`; `(cd packages/grund_jaspr && dart pub publish --dry-run)` — «Package has 0 warnings.»; `wc -l` усіх змінених файлів `lib/` ≤300; `git diff --stat master -- packages/grund packages/grund_http` порожній.
- [ ] **Крок 4:** коміт `docs: grund_jaspr sites, pages and sitemap`.

---

## Самоперевірка плану (виконана)

- **Покриття spec:** §4.1 — Задачі 2, 4; §4.2 — 3, 4; §4.3 — 4, 6; §4.4 — 5; §4.5 — 8, 9, 10; §4.6 — помилки в задачах, що їх кидають (2, 5, 6, 7, 9); §4.7 — не змінюється (за spec); §4.8 — 11; §4.9 — огляд файлів; §4.10 — 7; §5 — розподілено по задачах; §6 — 12, 13; §9 (ризики-перевірки) — Задача 4, крок 2.
- **Відомі вибори поза spec (позначити у передачі):** `PageMeta.title` має типове `''` (spec уточнено); `JasprError` стає `abstract base class`; `PageExtension`, `SitePage` і `PageMatch` оголошені в Задачі 2 разом із `Page`, бо типи посилаються один на одного.
