# grund_jaspr: сторінки в модулях і сайти — дизайн

Дата: 2026-10-16 (рев'ю архітектури й неймінгу враховано 2026-10-17). Стан:
чернетка на перегляд. Замінює модель «один кореневий компонент» зі spec
`2026-10-16-grund-jaspr-design.md` §4.1 (решта того spec лишається чинною).
Походження: запит споживача (сайт-портфоліо) спростити реєстрацію сторінок;
рішення користувача зібрані в §3.

**Термінологія.** У коді й документації група сторінок із власним префіксом,
оболонкою, охоронцями й 404 називається **сайтом** (`PageSite`: публічний
сайт, адмінка). Слово «scope» лишається за DI (час життя: `Scope`,
`CallScope`), щоб два поняття не змішувалися.

## 1. Мета й межі

**Мета.** Сторінка оголошується у своєму модулі так само просто, як звичайний
роут, без центрального списку сторінок. Кілька сайтів (публічний, адмінка)
працюють паралельно в одному застосунку, кожен зі своїм префіксом, оболонкою,
охоронцями й сторінкою 404. Sitemap і навігація виводяться зі сторінок, а не
ведуться руками.

**Чому.** Зараз `JasprModule` приймає один компонент, а маршрутизацію між
сторінками робить застосунок. Споживач (портфоліо) для нової сторінки правив
близько восьми файлів, вів два паралельні реєстри (HTML і машинний), і
забутий реєстр не давав помилки.

**Цілі.**
- Сторінка в будь-якому модулі: шлях, компонент, метадані (заголовок, опис,
  навігація, sitemap, перелік адрес) в одному місці.
- Сайти паралельно; сторінки одного сайту додають різні модулі.
- Каталог сторінок (`PageCatalog`), з якого виводяться sitemap і навігація.
- Динамічні набори адрес (сторінка з параметром, перелік із живого джерела),
  зокрема великі: порціями, без повного набору в пам'яті.
- Точка розширення для окремого пакета (Markdown-двійники, `llms.txt`), яка
  чіпляється до тієї самої сторінки, а не веде другий реєстр.
- Жодних змін у `grund_http` і `grund` (ядро).

**Не цілі.**
- `.md`-двійники, `llms.txt`, `Accept: text/markdown`: окремий пакет (§4.8).
- Клієнтський бандл і гідратація (G7b; див. §8).
- Файловий роутинг, кодоген, анотації `@Page` (можливий цукор над цим API
  пізніше, за правилом «згенерований код = звичайний код на публічному API»;
  `Page` тоді конфліктуватиме з анотацією так само, як `Module`).
- Видимість пунктів навігації за ролями, типізовані посилання між
  сторінками.
- Зворотна сумісність з `JasprModule(app:)`: до 1.0 API ламається.

**Анти-цілі.** Другий реєстр поряд зі сторінками; мовчазне вгадування
(кожна неоднозначність або пропуск охорони: або явна декларація, або
помилка старту); новий механізм там, де вистачає наявного (`HttpApi`, хуки,
`Runner`, `Injector.all<T>()`).

## 2. Вхідні факти (перевірено в коді 2026-10-16/17)

- `JasprPages extends HttpApi` забирає `GET /` і `GET /*`; другий такий
  `HttpApi` дає `DuplicateRouteError`. `PageRenderer`, `JasprPages`,
  `StaticFiles` не експортуються. Твердження spec G7a, що `JasprModule`
  імпортує `HttpModule`, застаріле: код цього не робить.
- Роути збирає `HttpServer` з `injector.all<HttpApi>()`
  (`http_server.dart:147`, `route_table_builder.dart:27`): це кожен створений
  синглтон графа за типом прив'язки, незалежно від видимості й експорту.
  Дженерики реіфіковані й **коваріантні**: `all<SiteApi<PageSite>>()` знайде
  і `SiteApi<AdminSite>`, і `SiteApi<SuperAdminSite>`; точний тип треба
  фільтрувати самим.
- Запит виконується в call-scope **модуля, якому належить `HttpApi`**
  (`route_executor.dart:47`); хуки резолвляться на **підготовці** таблиці
  (`route_table_builder.dart:47`), тож хук, невидимий модулю, валить старт.
  Порядок хуків: глобальні, `api.use`, `route.use`. Тому хуки сайту йдуть у
  `Route.use` кожного роута сторінки (інакше `skip` неможливий).
- Таблиця роутів будується в `routes`-геттерах перед підміною (`_buildTable`
  читає їх до того, як `_table` замінюється): виняток у геттері лишає стару
  таблицю. Це єдине місце, де помилка гарантовано зупиняє підміну.
- Пріоритет сегментів: літерал, `:param`, `*`, з поверненням назад лише коли
  гілка не знайшла збігу: `/:slug` проковтне `/main.css` до того, як
  `GET /*` буде спробований. `*` лише останній і збігається з одним і більше
  сегментів, тож `/admin` потребує окремого роута; `/admin/*` перемагає `/*`.
  Сегмент не може змішувати літерал і `:param`/`*`. `Router` і `RoutePattern`
  не експортуються; диспетчер декодує відсотки, відкидає порожні сегменти
  (`//`, кінцевий `/`) і чутливий до регістру. `HEAD` іде на GET-роут.
- **Hot reload.** `Container._start` переносить кожен існуючий синглтон
  (`adopt`), не створюючи його знову (`container.dart:84`); його `Injector`
  (`ModuleView`) лишається прив'язаним до старого runtime, тож `all<T>()` з
  нього бачить старий набір синглтонів. Нові синглтони створюються зі свіжим
  injector. Свіжий корінь отримують лише раннери: `Runner.prepare(injector)`
  і `Runner.reassemble(injector)`. `prepare` викликається на **всіх** раннерах,
  також коли `only` їх не вибирає (`TestApp` стартує з `only: {}`), а раннери
  переприлаштовуються в порядку створення, тож порядок щодо `HttpServer` не
  гарантований.
- Хук `before` не може повернути відповідь, лише кинути `HttpException`;
  `onError` може відповісти (наприклад, редиректом).
- Два `JasprModule` зливаються в один (однакова ідентичність), перший виграє;
  інша конфігурація мовчки ігнорується. Два `Pages.under<S>` в одному модулі
  дають `DuplicateBindingError` (один ключ).
- Jaspr 0.23.5: виняток усередині компонента під час рендеру не пробивається
  назовні: Jaspr малює елемент помилки, ставить статус 500 і пише в stderr;
  `PageRenderer` уже перетворює це на `PageRenderError`.
- `grund_auth` не має охоронця «потрібен користувач»; `SessionHook` глобальний
  і анонімів не відсікає. Статичний шлях захищений від виходу з каталогу
  (`isWithin` у `static_files.dart`).
- Ресерч інших фреймворків (Angular, Next, SvelteKit, Nuxt, Remix, Laravel,
  Django, Phoenix, Rails, ASP.NET, NestJS, Astro, jaspr_router, shelf_router,
  dart_frog): ніхто в типізованому коді без файлових конвенцій не дає
  «модуль додає сторінку у спільний сайт» і виведений sitemap разом.
  Найближчі аналоги: Django `AdminSite`, Laravel/Astro, метадані біля
  сторінки (`metadata` Next, `handle` Remix). Для пропуску групових
  охоронців: Rails кидає помилку на невідомому імені, Laravel знімає й
  нащадків названого класу, ASP.NET `AllowAnonymous` знімає все, Django 404
  минає охоронця (оракул існування).

## 3. Ухвалені рішення

Користувача:
1. Сторінки оголошуються в різних модулях, центрального місця немає.
2. Сайти паралельні (приклад: адмінка поряд із публічним сайтом).
3. Сайт — клас у DI, який налаштовує свій модуль; сторінка називає його
   **типом** (`Pages.under<AdminSite>`). Назва групи: `PageSite`.
4. Markdown-двійники й `llms.txt` — окремий шар; sitemap і навігація — в
   `grund_jaspr`.
5. Набір адрес сторінки з параметром може бути динамічним і великим
   (порційний `entries`).
6. Зворотної сумісності немає (до 1.0).
7. Користувач не пише й не бачить `HttpApi`; зміни в `grund_http` не
   допускаються (відхилено варіант «роут із власним injector»).
8. Сторінка може пропустити окремі хуки сайту, а не всі.

Решта — мої рішення, зібрані в §8.

## 4. Архітектура

```
запит → HttpServer → router ─┬─ PagesApi<S> (у модулі сторінок): S.path + page.path, хуки S.use у Route.use
                             ├─ SiteApi<S>  (у модулі сайту):    <path>/*, sitemap
                             ├─ /*          кореневий сайт: claim → JSON 404 → notFound()
                             └─ StaticApi (у JasprModule): <staticPath>/*, rootFiles (поза сайтами)

PagesRunner (раннер 'pages'): на prepare/reassemble бере СВІЖИЙ injector, збирає
знімок усіх SiteApi/PagesApi, перевіряє глобальні правила, оновлює PageRegistry,
з якого читає PageCatalog.
```

### 4.1 Типи й прив'язки (`grund_jaspr`)

- `PageSite` — `abstract base class` (клас у DI). Конструктор приймає
  `Injector` модуля-власника. Віртуальні члени з замовчуваннями: `String get
  path => ''` (порожній або `/seg[/seg]`, без кінцевого `/`, лише літерали),
  `List<HookRef<HttpHook>> get use => const []`, `List<Type> get
  skippableHooks => const []` (типи хуків, які сторінка має право пропустити),
  `Component shell(Component content) => content`, `Component notFound()`
  (мінімальна сторінка «Not found»), `Uri? get sitemapBaseUrl => null`
  (абсолютна адреса сайту; `null`: sitemap сайту вимкнений).
- `Pages` — `abstract final class` зі статичними фабриками (внутрішні типи
  не експортуються, лише ці дві):
  - `Pages.site<S extends PageSite>(S Function(Injector) create)` повертає
    **два** звичайні прив'язки (`Singleton<S>` і внутрішній `SiteApi<S>`,
    що залежить від `S`), тож пишеться зі spread:
    `...Pages.site<AdminSite>(AdminSite.new)`. Модуль сайту експортує `S` і
    типи охоронців;
  - `Pages.under<S extends PageSite>(List<Page> Function(Injector) pages)`
    повертає `Singleton<PagesApi<S>>`, який залежить від `S` і `PageRenderer`
    (`dependsOn`) і бере сайт з DI за типом: відсутній сайт дає рідний
    `MissingProviderError` на старті, видимість працює за звичайними
    імпортами, точний тип гарантований. Роути виконуються в call-scope модуля
    сторінок, тож білдер бачить його провайдери, а значення від хуків
    доходять до компонентів.

  ```dart
  // модуль сайту (не імпортує модулі сторінок); гетери класу Module
  bindings => [...Pages.site<AdminSite>(AdminSite.new), /* охоронці */];
  exports => [Key<AdminSite>(), Key<AdminGuard>()];
  // будь-який модуль сторінок (імпортує модуль сайту)
  Pages.under<AdminSite>((injector) => [
    Page('/', build: (c) => DashboardPage()),
    Page('/users', build: (c) => UsersPage(c<UsersService>().all())),
    Page('/login', build: (_) => LoginPage(),
        hooks: PageHooks(skip: [AdminGuard])),
  ]),
  ```
- `Page(String path, {required PageBuilder build, PageMeta meta, PageHooks
  hooks, List<PageExtension> extensions})`. Шлях сторінки: літерали й
  `:param`; `*` у сторінках заборонений; кожен сайт мусить мати сторінку
  `/` (індекс).
  `typedef PageBuilder = FutureOr<Component> Function(HttpCtx c)`: параметри
  шляху читаються як у звичайному роуті (`c.path.string('slug')`), дані
  завантажуються тут, а компонент отримує їх аргументами. `NotFoundException`,
  кинутий **білдером** (єдиний новий `catch`, `on NotFoundException`),
  перетворюється на `site.notFound()` зі статусом 404; виняток усередині
  компонента Jaspr робить 500.
- `PageHooks({List<Type> skip = const [], List<HookRef<HttpHook>> use =
  const []})`: що пропустити з хуків сайту (за типом) і що додати після них.
- `PageMeta({String title = '', String? description, PageNav? nav,
  PageSitemap sitemap})` (`title` має типове порожнє значення, щоб `Page('/',
  build: ...)` без метаданих працювало, як у прикладах); `PageNav({String? label, String group = 'main', int
  order = 0})` (`label` за замовчуванням дорівнює `title`);
  `PageSitemap({bool included = true, DateTime? lastModified,
  SitemapChangeFrequency? changeFrequency, double? priority, SitemapEntries?
  entries})`.
- `SitemapEntries` — `abstract interface class` з двома конструкторами:
  `SitemapEntries.all(Future<List<SitemapEntry>> Function(Injector))` для
  малих наборів (читається цілком) і `SitemapEntries.paged({required
  Future<int> Function(Injector) count, required Future<List<SitemapEntry>>
  Function(Injector, int offset, int limit) load})` для великих: порції віддає
  саме джерело (SQL `LIMIT/OFFSET` тощо). `Injector` тут — injector модуля,
  не call-scope. `SitemapEntry({required Map<String, String> params,
  DateTime? lastModified})`; ключі `params` мусять дорівнювати іменам
  `:param` шляху сторінки. Записи живлять лише sitemap: у навігацію вони не
  потрапляють.
- `PageExtension` — `abstract base class` з двома необов'язковими
  охоронюваними точками з типовими порожніми тілами (§4.8); сторінка тримає
  список розширень, нічого про них не знаючи.

### 4.2 `JasprModule`

`JasprModule({JasprConfig config})` без `app` і без `imports`: бібліотеки
**не імпортують** `JasprModule`, лише застосунок (так само виправляється
`AdminModule` у spec адмінки §5.5). Один на застосунок; `global => true`,
експортує `PageRenderer`, `PageCatalog` і внутрішні `StaticFiles`/
`NonPageRequests`. Прив'язує також `PagesRunner` (§4.10) і `StaticApi`
(§4.3), який не залежить від сайтів. Живе перезавантаження,
`Jaspr.initializeApp` лишаються як є; `JasprConfig` отримує `staticPath` і
`rootFiles` (§4.3).

Рендер: компонент сторінки обгортається `site.shell(...)` і
`GrundScope(httpContext: c, ...)`; `context.call<T>()` працює в call-scope
модуля сторінки. Фреймворк **не володіє** `Document` (мова, скрипти, стилі
лишаються за оболонкою користувача): `GrundScope` несе знайдену сторінку
(`PageMatch`), у компонентах це `context.pageMatch`, звідки оболонка бере
`page.meta.title`, `page.meta.description` і підсвічує активний пункт
навігації; `context.call<PageCatalog>()` дає навігацію. Для 404
`context.pageMatch` має синтетичну сторінку із заголовком «Not found».
Заголовок динамічної сторінки (за записом) ставить сама сторінка.

### 4.3 Фолбек, 404, статика

Для кожного сайту `SiteApi` реєструє `GET <path>/*` (індекс `<path>/` дає
обов'язкова сторінка `/`): фолбек віддає `site.notFound()` у `site.shell` зі
статусом 404 **через усі хуки сайту** (гість не дізнається, які сторінки є в
адмінці) і ігнорує `skip`. 404 для невідомого значення параметра
(`/projects/nope`) вирішує сторінка, кинувши `NotFoundException` у білдері.

**Не-сторінкові запити.** Правило `NonPageRequests` (один клас, спільний для
фолбека й обробників сторінок): якщо останній сегмент шляху має розширення
поза `JasprConfig.pageSuffixes`, запит не є запитом сторінки, і сторінка не
викликає білдер, а відповідає ланцюжком `PageExtension.claim` сторінок сайту,
далі JSON 404 `file_not_found`. Так `/projects/x.png` і `/projects/foo.md`, що
їх перехопив би `/projects/:slug`, не потрапляють у білдер. Значення параметра
з крапкою в останньому сегменті (`/projects/node.js`) через це не
підтримується: задокументовано.

Кореневий сайт володіє єдиним `GET /*` застосунку: те саме правило, далі
`notFound()`. Без кореневого сайту невідомі `GET` лишаються стандартним
`route_not_found`.

**Статика** (як `STATIC_URL` у Django) не належить жодному сайту. `StaticApi`
у `JasprModule` віддає файли з `JasprConfig.staticDirectory` під
`JasprConfig.staticPath` (за замовчуванням `/static`, роут `GET <staticPath>/*`)
і окремими літеральними роутами файли зі списку `JasprConfig.rootFiles`
(`favicon.ico`, `robots.txt`, ...; за замовчуванням порожній). Це публічні
файли без хуків сайту. Літеральні роути перемагають `:param`, тож сторінка
`/:slug` їх не проковтне. Існуючого файлу немає: JSON 404 `file_not_found`.
Шлях сайту й повний шлях сторінки не можуть збігатися зі `staticPath` або
лежати під ним, ні збігатися з елементом `rootFiles` (`InvalidSitePathError`,
`ReservedPagePathError`). Статика для сайту (адмінка в G7b) — підкаталог:
`/static/admin/...`. Sitemap віддається **без** хуків сайту (§4.5). Шляхи
`<path>/sitemap.xml` і `<path>/sitemap/*` у сайті зарезервовані
(`ReservedPagePathError`).

### 4.4 Охоронці й `skip`

`site.use` — звичайні `HttpHook`; роут сторінки отримує їх у `Route.use`
(перед хуками сторінки), тож вони резолвляться на підготовці таблиці й на
кожен запит у call-scope модуля сторінок: модуль сторінок мусить бачити типи
охоронців, тому модуль сайту їх **експортує**, а модуль сторінок його
імпортує. Модуль сайту сторінкових модулів не імпортує (інакше цикл
`CircularModuleImportError`): зверху все збирає кореневий модуль застосунку.
Редирект гостя робить `onError` хука (відповідь `303`), нового механізму
немає; охоронець «потрібен користувач» у `grund_auth` з'явиться в G4.

`PageHooks.skip` знімає з однієї сторінки названі хуки сайту. Правила (за
дослідженням Laravel, Rails, ASP.NET, Django, OWASP):
- збіг лише за **точним** `HookRef.hookType` (не підтип): називання базового
  класу не знімає нащадків; хуки з `HookRef.instance` у нетипізованому списку
  мають тип `HttpHook`, тож їх слід оголошувати типізовано
  (`HookRef<AdminGuard>.instance(...)`);
- пропустити можна лише типи з `site.skippableHooks` (охоронець вирішує, а не
  автор сторінки): інакше `ForbiddenPageSkipError`; назва типу, якого немає в
  `site.use`: `UnknownPageSkipError` (повідомлення перелічує типи сайту); тип,
  що зустрічається в `site.use` кілька разів: `AmbiguousPageSkipError`;
- `skip` стосується однієї сторінки; фолбек сайту, sitemap і всі
  невідповідні шляхи його ігнорують; глобальні хуки застосунку пропустити
  неможливо;
- порядок решти хуків зберігається, хуки сторінки йдуть після хуків сайту;
  кожен пропуск пишеться в лог при старті (`INFO`, логер `grund.jaspr`:
  `page /admin/login skips AdminGuard (site /admin)`; при hot reload `FINE`),
  пропуск на сторінці з `:param` — `WARNING`.

### 4.5 Каталог (`PageCatalog`)

Інжектований провайдер, що читає **знімок** (`PageSnapshot`: усі `SiteApi` і
`PagesApi`, незмінний) із `PageRegistry`; знімок кладе `PagesRunner` (§4.10),
тож каталог не застаріває після hot reload, навіть будучи перенесеним
синглтоном. До першого знімка (до `prepare`) звернення дає
`PageCatalogNotReadyError`. Усе сортується детерміновано: навігація —
`order`, потім `label`, потім шлях; sitemap — за шляхом.
- `pagesOf<S>()` → `List<SitePage>` (`SitePage`: сайт, `Page`, повний шлях);
  фільтр за **точним** `S`;
- `navOf<S>()` → `List<NavItem>` (`NavItem`: `label`, `path`, `group`,
  `order`; з `meta.nav`; записи `entries` у навігацію не потрапляють);
- `sitemapOf<S>()` → `Stream<SitemapUrl>`: статичні сторінки плюс адреси з
  `entries`, порціями, без повного набору в пам'яті (`SitemapUrl`: абсолютна
  адреса, `lastModified`, `changeFrequency`, `priority`);
- `match(Uri)` → `PageMatch?` (`SitePage` і параметри) власним `PageMatcher` з
  тими ж правилами, що й router (пріоритет літерал, `:param`; відсоткове
  декодування; порожні сегменти відкидаються; регістр); паритет з реальним
  router перевіряє тест (`//`, `%2F`, `%61dmin`, кінцевий `/`); суфікси на
  кшталт `.md` каталог не знімає;
- `pagesWith<T extends PageExtension>()` → `List<SitePage>`: сторінки, що
  несуть розширення `T`;
- `invalidateSitemap()` скидає кеш sitemap (нижче).

**Sitemap.** Віддає `SiteApi` сайту з `sitemapBaseUrl`, без хуків сайту, тому
сайт із непорожнім `use` і `sitemapBaseUrl` дає `GuardedSiteSitemapError`
(грубо, але безпечно). У sitemap та навігацію не потрапляє сторінка з
власними `hooks.use`, якщо вона явно не вказала `PageSitemap(included:
true)`. Параметрична сторінка в сайті з `sitemapBaseUrl` мусить мати
`entries` або `PageSitemap(included: false)`, інакше
`UndecidedPageSitemapError` (нічого не вгадується мовчки); `entries` у
сторінці без `:param`: `UnusedPageEntriesError`.

`GET <path>/sitemap.xml` — один файл, коли адрес не більше
`JasprConfig.sitemapChunkSize` (за замовчуванням 50 000, ліміт протоколу; 50 МБ
на файл теж ліміт), інакше індекс на `<path>/sitemap/<n>.xml`
(`GET <path>/sitemap/:chunk`, `n` розбирає обробник, поза діапазоном — 404);
порція запитує в `entries` лише свій діапазон і будується в пам'яті (до
50 000 записів), `<loc>` екранується й відсотково кодується. Кешуються число
адрес і готові порції (`JasprConfig.sitemapCacheLifetime`, за замовчуванням
60 с; кількість порцій обмежена); запис у кеш лише після успіху (`try/finally`,
без `catch`); одночасні перші заповнення зливаються в одне; `HEAD`
виконує повний обробник. Помилка `entries` (виняток або ключі `params` не
збігаються зі шляхом, `PageEntriesMismatchError`) дає 500 на запит sitemap і
`SEVERE` у логу; перевірка на старті неможлива без виклику джерела, і це
задокументовано. Структура сторінок не кешується (її бере знімок).

### 4.6 Помилки

Родина `JasprError extends GrundError` (`abstract base class`; ім'я класу —
стабільний ідентифікатор) із трьома запечатаними підродинами, кожна у своєму
файлі; назви за зразком наявних (`DuplicateRouteError`,
`InvalidRoutePatternError`: проблема, потім предмет).
- `SiteDeclarationError`: `InvalidSitePathError` (також шлях під `staticPath`), `DuplicateSitePathError`,
  `NestedSitePathError` (`/admin` і `/admin/reports`: внутрішній сайт обходив
  би охоронців зовнішнього), `DuplicateSiteError` (один тип сайту прив'язаний
  у двох модулях), `MismatchedSiteTypeError` (`create` повернув не `S`),
  `MissingSiteIndexError` (немає сторінки `/`), `GuardedSiteSitemapError`;
- `PageDeclarationError`: `InvalidPagePathError`, `ReservedPagePathError` (sitemap, `staticPath`, `rootFiles`),
  `MisplacedPagePathError` (шлях сторінки потрапляє під префікс іншого сайту:
  літерал `/admin/help` у кореневому сайті обійшов би охоронців `/admin`),
  `UnusedPageEntriesError`, `UndecidedPageSitemapError`,
  `ForbiddenPageSkipError`, `UnknownPageSkipError`, `AmbiguousPageSkipError`;
- `PageRuntimeError`: `PageCatalogNotReadyError`, `PageEntriesMismatchError`.

Відсутній сайт: рідний `MissingProviderError`. Дубль `(сайт, шлях)`: наявний
`DuplicateRouteError`. Де перевіряється:
- **локально**, у `routes`-геттері `SiteApi`/`PagesApi` або в їхніх
  фабриках: шляхи, зарезервовані шляхи, `skip`, `entries`, рішення про
  sitemap, `GuardedSiteSitemapError`. Виняток тут лишає стару таблицю
  (hot reload) і валить старт;
- **глобально**, у `PagesRunner.prepare/reassemble` над свіжим знімком:
  `DuplicateSiteError`, `MismatchedSiteTypeError` (порівнює тип сайту з `S`
  у знімку; конструктор `SiteApi` цього не бачить без обгортки
  `ProviderCreationError`), `DuplicateSitePathError`, `NestedSitePathError`,
  `MissingSiteIndexError`, `MisplacedPagePathError`. На старті це зупиняє
  застосунок до першого запиту; при hot reload `HttpServer` міг уже підмінити
  таблицю (порядок раннерів не гарантований), тож помилка лише повідомляється,
  а нова таблиця діє до виправлення. Це dev-режим; задокументовано.

### 4.7 Адмінка

`2026-10-16-grund-admin-design.md` описує `AdminModule(path: '/admin')`, що
збирає `AdminPage` через `Injector.all<T>()`. Дизайн сумісний: адмінка стає
`AdminSite` (`path => '/admin'`, охоронці над `AdminPolicy`, оболонка
адмінки), її сторінки — `Pages.under<AdminSite>`. Spec адмінки тут не
змінюється; до узгодження в G7b: `AdminModule` не імпортує `JasprModule`;
невідомий `GET /admin/api/x` потрапляє у HTML-фолбек сайту, а не в JSON 404;
статика адмінки лежить у підкаталозі `/static/admin/...` (§4.3).

### 4.8 Межа з Markdown-пакетом (окремий spec і план)

Пакет-шар (назва відкрита, умовно `grund_jaspr_markdown`) вмикає `.md`-двійники,
`llms.txt` і `Accept: text/markdown`. Від `grund_jaspr` йому потрібно: список
`Page.extensions` (він оголошує `MarkdownTwin extends PageExtension`),
`PageCatalog.match/pagesWith/sitemapOf` і дві **охоронювані** точки:
`PageExtension.respond(HttpCtx, PageMatch)` (викликається перед рендером HTML
на роуті сторінки, після хуків сайту й сторінки; так працює
`Accept: text/markdown`) і `PageExtension.claim(HttpCtx, Uri)` (викликається
правилом `NonPageRequests` для варіантів з суфіксом на кшталт `/about.md`,
після хуків **сайту**). `claim` не має `PageMatch`, тож фреймворк не може
застосувати хуки сторінки, на яку вказує варіант: розширення сторінок із
власними `hooks.use` у ланцюжок `claim` не входять (варіант охоронюваної
сторінки не віддається взагалі; шар віддає його через `respond` на роуті самої
сторінки).
Шар ніколи не віддає вміст глобальним хуком чи middleware, бо вони
виконуються до охоронців сайту. Режим «суворо» пакета-шару на старті вимагає
від кожної сторінки або `MarkdownTwin`, або явного `NoMarkdown`, тож забутий
двійник — помилка старту.

### 4.9 Поділ на файли й класи (ліміти CLAUDE.md)

Один публічний клас (або запечатана родина) на файл, ≤300 рядків, методи
≤40. Каталоги `lib/src/page/`, `lib/src/site/`, `lib/src/sitemap/`.
- Публічні: `PageSite`, `Pages`, `Page`, `PageHooks`, `PageMeta`, `PageNav`,
  `PageSitemap`, `SitemapEntries`, `SitemapEntry`, `SitemapChangeFrequency`,
  `PageExtension`, `PageMatch`, `SitePage`, `NavItem`, `SitemapUrl`,
  `PageCatalog`, `PageBuilder`, `JasprError` та три підродини.
- Внутрішні (не в barrel): `SiteApi`, `PagesApi`, `PagesRunner`,
  `PageRegistry`/`PageSnapshot`, `SiteValidator` (глобальні правила),
  `HookResolver` (site.use + skip), `NonPageRequests`, `StaticFiles`,
  `PageRenderer`, `PageMatcher`, `SitemapHandlers`, `SitemapWriter`,
  `SitemapChunkCache`, `StaticApi`. `StaticFiles` шукає файл на диску, `StaticApi`
  віддає його роутом.
- `Page`, `PageMeta`, `PageHooks`, `PageSitemap` — декларативні значення в
  межах 5 параметрів. Файли помилок — плоскі каталоги; якщо файл > 300 рядків,
  це зазначено в doc-коментарі бібліотеки.

### 4.10 Hot reload і `PagesRunner`

Раннер `pages` (внутрішній, прив'язаний `JasprModule`) нічого не слухає:
`prepare(injector)` і `reassemble(injector)` беруть свіжий корінь, збирають
знімок через `all<SiteApi>()`/`all<PagesApi>()` (фільтр за точним
`siteType`), викликають `SiteValidator` і кладуть знімок у `PageRegistry`;
`start/stop` порожні. Що діє при hot reload без перезапуску: тіла білдерів,
компоненти, метадані, нові сторінки в наявному `Pages.under` (геттер заново
викликає `pages`), нові сайти й нові `Pages.under` (нові синглтони зі свіжим
injector). Зміна `path` наявного сайту й видалення сайту або `Pages.under`
вимагають перезапуску, якщо сторінки ще посилаються на старий синглтон
(перенесені синглтони лишаються); це задокументовано, перевіряється тестом.

## 5. Тести

- Роутинг: `/admin/*` проти `/*`; літерал, параметр, фолбек; два сайти, кілька
  модулів у сайті; `HEAD`; `//`, `%2F`, `%61dmin`, кінцевий `/`, `.html` на
  охоронюваному сайті; `/projects/x.png` і `/projects/foo.md` не доходять до
  білдера `/projects/:slug`; `/static/x.css` і `rootFiles` віддаються поза
  хуками сайту, сторінка `/:slug` їх не проковтує; сайт під `/static` —
  помилка.
- Сайти: хуки на сторінках і фолбеку; 404 сайту не розкриває сторінок гостю;
  оболонка; редирект охоронця через `onError`; вкладені префікси;
  `MisplacedPagePathError` (`/admin/help` у кореневому сайті);
  `MissingSiteIndexError`; точний тип сайту
  (`SuperAdminSite` не змішується з `AdminSite`); `DuplicateSiteError`.
- `skip`: сторінка входу пропускає лише названий хук; `Unknown`, `Forbidden`,
  `Ambiguous`; фолбек ігнорує `skip`; лог пропуску.
- DI: компонент і білдер бачать прив'язки модуля сторінок; значення від
  `SessionHook` доходять до сторінки (`context.maybe<CurrentUser>()`); хук зі
  Scoped-залежністю працює; модуль сторінок без імпорту модуля сайту падає
  `MissingProviderError`; `Pages.under` без `JasprModule` падає на старті;
  модуль сайту не імпортує модулі сторінок.
- Сторінки: `NotFoundException` з білдера (404 сайту) і з компонента (500),
  `FutureOr`-білдер, `context.pageMatch`.
- Каталог: nav (групи, порядок, сортування), sitemap (статичні, `entries`,
  виключені, `Undecided`, власні `hooks.use`), порції (індекс при
  > `sitemapChunkSize`, діапазон поза межами = 404), екранування XML, злиття
  одночасного заповнення, помилка `entries` без отруєння кешу,
  `PageCatalogNotReadyError`, паритет `match(Uri)` з реальним router.
- Hot reload: новий сайт і нова сторінка з'являються в каталозі й роутах;
  видалена сторінка зникає з каталогу; помилка локального правила лишає стару
  таблицю; помилка глобального правила на `reassemble` повідомляється.
- `TestApp` (`only: {}`) все одно виконує `prepare` раннера і ловить глобальні
  помилки.
- Живе перезавантаження, правило розширень, захист від виходу з каталогу
  статики: наявні тести переносяться з урахуванням `staticPath`. `example/` переходить на новий спосіб (e2e на обох адаптерах).

## 6. Пакети, версії, документація

`grund_jaspr` 0.2.0 (ламка зміна); `grund_http` і `grund` не змінюються.
`grund_cli` (шаблон fullstack) переходить на сайти, а посилання на файли з
`web/` отримують префікс `/static/`; `example/`,
`docs/jaspr.md`, README, CHANGELOG, CLAUDE.md (межі `catch`: новий лише `on
NotFoundException`) оновлюються. Портфоліо мігрує окремою роботою після
релізу.

## 7. Зміни роадмапу

Нового етапу не додаємо: це розвиток G7a. Markdown-пакет — окремий spec і
план після ядра. Клієнтський бандл — G7b.

## 8. Рішення, що чекають вашого перегляду

Мої рішення (крім назви `PageSite`, яку ви вибрали):
- прив'язки `Pages.site`/`Pages.under` замість класу-нащадка; `Pages.site`
  повертає дві прив'язки (spread); сайт береться в `Pages.under` з DI за типом
  (рідна помилка, видимість, точний тип), а не пошуком `all<>`;
- внутрішні `HttpApi` у модулі сторінок і сайту (запит у call-scope свого
  модуля); хуки сайту в `Route.use`;
- `PagesRunner` для свіжого injector, знімка й глобальної валідації; помилки
  глобальних правил при hot reload лише повідомляються;
- кожен сайт мусить мати сторінку `/`; шляхи сторінок без `*`;
- статика поза сайтами, як `STATIC_URL` у Django: `JasprConfig.staticPath`
  (`/static`) і `rootFiles`; статика ніколи не проходить через хуки сайту;
- правило не-сторінкових запитів у всіх обробниках сторінок (`claim`, JSON 404);
  параметр з крапкою в останньому сегменті не підтримується;
- `skip` лише за точним типом, лише з `skippableHooks`, фолбек його ігнорує;
- `entries` перенесені в `PageSitemap` і перейменовані в `SitemapEntries`/
  `SitemapEntry` (без `title`); не додають пункти навігації;
- параметрична сторінка без `entries` у сайті з `sitemapBaseUrl` — помилка;
  `sitemapBaseUrl` вмикає sitemap і виключає сайти з `use`; шляхи
  `/sitemap.xml` і `/sitemap/*` зарезервовані;
- кеш sitemap 60 с, порції по 50 000 через `offset/limit`;
- імена: `path` замість `prefix`, `skippableHooks`, `lastModified`,
  `changeFrequency`, `pagesWith`, `NavItem`, `context.pageMatch`, помилки за
  зразком «проблема + предмет», три запечатані підродини;
- фреймворк не володіє `Document`; білдер `FutureOr`, 404 лише з білдера;
  `JasprModule` глобальний, без `imports`, бібліотеки його не імпортують;
  `match(Uri)` власний матчер із тестом-паритетом; охоронювані точки
  `respond/claim` для Markdown-шару.

Відкрите для користувача: клієнтський бандл (друге питання споживача) —
пропоную розв'язати в G7b разом із гідратацією, не тут; назва Markdown-пакета.

## 9. Ризики

- `dependsOn` приймає `Key`-и (`[Key<S>(), Key<PageRenderer>()]`, не `const`), а
  `exports` — `Key`-и власних прив'язок; spread із двох прив'язок `Pages.site`
  перевіряє перша наскрізна задача плану.
- Паритет `PageMatcher` з router: `Router` не експортується, тож тест
  реєструє ті самі шаблони в справжньому сервері.
- Порядок раннерів не гарантований: при hot reload глобальна помилка
  повідомляється вже після підміни таблиці (§4.6); для старту порядок не
  важливий, бо `prepare` викликається на всіх до першого `start`.
- Перенесені синглтони тримають старий injector: нові Scoped/Transient
  провайдери, додані при hot reload, невидимі старим call-scope (загальне
  обмеження ядра, не цього дизайну).
- Кеш `entries` показує застарілий sitemap до 60 с; порції через `OFFSET` на
  мільйонах рядків повільні на великих зсувах: відповідальність джерела.
- Jaspr до 1.0 ламає мінорні версії (залежність `>=0.23.5 <0.24.0`).
- Не перевірено: `jaspr_content` (імовірний сусід Markdown-пакета) експортує
  власний `Page`; конфлікт імен вирішує префікс імпорту.

## 10. Готово, коли

Сторінки двох сайтів з різних модулів працюють на обох адаптерах; sitemap і
навігація виводяться з каталогу; `example/` і шаблон fullstack переведені;
`dart analyze`, тести, форматування й dry-run `grund_jaspr` чисті; документація
й CHANGELOG оновлені; `grund_http` і `grund` без змін.
