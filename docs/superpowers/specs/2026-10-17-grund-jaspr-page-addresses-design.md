# grund_jaspr і grund_http: адреси сторінок, альтернативні подання й файли сайту — дизайн

Дата: 2026-10-17. Стан: чернетка на перегляд. Джерело: знахідки першого
споживача, портфоліо (`/home/genius/projects/portfolio`, лише читання), №1, 4,
5, 6, а також 7, 11 і 12 (§3, п. 9). Це самостійний крок G7b між фрагментами
й гідратацією. Він не залежить від гідратації і не змінює її (§9). Другий spec
цієї серії, `2026-10-17-grund-environment-design.md`, покриває №3 і 9.

## 1. Мета й межі

**Мета.** Кожна сторінка має одну адресну модель: одне канонічне написання URL
(зі слешем у кінці чи без), абсолютне, коли сайт знає своє публічне джерело.
Її використовує все, що фреймворк пише як URL: sitemap, навігація, редиректи,
заголовки `Link`. Альтернативні подання сторінки (Markdown для агентів)
оголошуються на самій сторінці, а згенеровані файли сайту (`robots.txt`,
`llms.txt`) — на сайті. Другий реєстр сторінок у портфоліо (`MachineApi`,
`MarkdownNegotiation`, `TrailingSlashRedirect`, власний sitemap, тест
синхронізації) стає оголошеннями.

**Цілі.**
- `grund_http`:
  - `AcceptHeader`;
  - `HttpResponse.withVary` і злиття `vary`/`link` у `mergeHeaders`;
  - `StatusCode.movedPermanently` (301) і `StatusCode.permanentRedirect` (308);
  - параметр маршруту з літеральним суфіксом (`:slug.md`);
  - `TestClient.head`.
- `grund_jaspr`:
  - `PageAlternate` із `Page.alternates` і `PageSite.requiredAlternates`;
  - `TrailingSlash` (`PageSite.trailingSlash`, редирект 308);
  - `PageSite.baseUrl` замість `sitemapBaseUrl`, з перевіркою;
  - `SiteFile` (`PageSite.files`);
  - `PageMatch.path`, `url`, `alternatePath`;
  - `NavItem.path` і `<loc>` sitemap за політикою слеша;
  - `PageExtension` вилучено.
- Приклад: Markdown-подання головної сторінки і `robots.txt`; e2e на обох
  адаптерах.
- Документація:
  - нові розділи в `docs/jaspr.md`;
  - пастка `<base href="/">` (№12);
  - рецепти тестів «кожна сторінка відповідає» (№11).

**Не цілі.**
- Перетворення HTML у Markdown і вбудовані генератори `llms.txt`/`robots.txt`.
  Вміст належить користувачеві, формати прості, а `llms.txt` — лише пропозиція
  (llmstxt.org).
- Альтернатива без власного URL (лише через `Accept`), відповідь `406`,
  заголовок `Content-Location`.
- Двійкові `SiteFile` і альтернативи для `SiteFile`: двійкові файли вже
  покривають статика й `rootFiles`.
- Політика слеша для маршрутів `HttpApi`: роутер і далі ігнорує порожні
  сегменти.
- `context.staticUrl` і відбитки в іменах статики (№8 відхилено, §3).
- Тестовий помічник «усі ресурси сторінки відповідають 200»: йому потрібен
  HTML-парсер. Натомість рецепт у документації.
- Окремий пакет «шару Markdown» із роадмапу: цей spec закриває той пункт
  інакше.
- Збірка клієнтського бандла (№2): уже є в поправці гідратації (коміт
  `9eb07b4`, `grund bundle --entry --output`). Тут не чіпається.

**Анти-цілі.**
- Мовчазне переписування URL, які написав користувач. Редирект отримують лише
  `GET`/`HEAD` оголошених сторінок і файлів сайту.
- Оракул існування: редирект іде після хуків і лише для маршруту, що
  збігся.
- Редирект на інше джерело: `Location` завжди шлях з одним `/` на початку.
- SEO-політика за спиною користувача (`noindex`, `canonical` у HTML).
- Будь-який другий реєстр сторінок.

## 2. Вхідні факти

**Портфоліо** (перевірено читанням):
- `lib/server/machine_api.dart` (71 рядок):
  - літеральні маршрути `.md`-двійників, `/llms.txt` (`x-robots-tag:
    noindex`), `/robots.txt` і `/sitemap.xml`;
  - помічник `_exact` віддає 404, коли `c.request.uri.path != path`, бо роутер
    ігнорує порожні сегменти.
- `lib/server/markdown_negotiation.dart` (49): middleware для `GET`/`HEAD`
  шляхів сторінок (останній сегмент без крапки). Віддає Markdown за
  `AcceptHeader.prefersMarkdown` і ставить `Vary: Accept` на кожну відповідь
  шляху сторінки. Middleware не знає маршрутів, тож тримає власний список.
- `lib/machine/accept_header.dart:23-27`:
  - Markdown, коли `text/markdown` названо з q > 0 і q ≥ названого
    `text/html`;
  - нічия дає Markdown, а вайлдкарти для HTML не рахуються;
  - зіпсований або нескінченний q дорівнює 0.
  `test/server/accept_matrix_test.dart:10-28` — 9 рядків «HTML» і 5 рядків
  «Markdown».
- `lib/server/markdown_responses.dart`: `text/markdown; charset=utf-8`,
  `x-robots-tag: noindex`, `link: <siteUrl+route>; rel="canonical"`.
- `lib/server/trailing_slash_redirect.dart` (41): лише `GET`/`HEAD`
  відомих маршрутів. Канонічна форма — непорожні сегменти плюс `/` (корінь
  `/`). Відповідь 308 зі збереженим query і `cache-control: public,
  max-age=3600`.
- `lib/shell/site_routes.dart`: кожна сторінка, крім головної, закінчується
  на `/` (`canonical(path)`). `lib/server/site_navigation_provider.dart`
  проганяє `navOf` через неї (№7).
- `lib/server/portfolio_site.dart:19-22`: `Document(base: null)` з
  коментарем, що `<base href="/">` перетворює якірне посилання «пропустити
  навігацію» на посилання на головну (№12). Сайт не має `sitemapBaseUrl`:
  власний sitemap зі слешами (№6).
- `test/server/page_registry_sync_test.dart` (82 рядки) звіряє сторінки з
  двійниками й маршрутами. `test/helpers/served_site.dart` робить `head`
  через `request('HEAD', …)` і тримає рукописний список маршрутів (№11).
- Spec портфоліо (`docs/superpowers/specs/2026-10-17-portfolio-grund-pages-design.md:39-40,
  62-63`) відхилив `PageExtension`: `claim` бачить лише файлові запити після
  хуків, а `/sitemap.xml` до нього не доходить.

**`grund_jaspr`** (перевірено читанням):
- `lib/src/page/page_extension.dart` (24): `respond(c, match)` і `claim(c,
  uri)`. Користувачів у репозиторії немає; grep знаходить лише
  `test/page_extension_test.dart`, `test/catalog_test.dart`,
  `test/helpers/catalog_app.dart`, README і `docs/jaspr.md:558-569`.
- `lib/src/site/pages_api.dart`:
  - `:37-48`: маршрут сторінки `Route.get(page.path, …, use:
    HookResolver().forPage(…))`;
  - `:105-125`, `_serve`: файловий запит іде в ланцюжок `claim` усіх
    розширень сайту (`SiteExtensions` виключає лише сторінки з власним
    `hooks.use`), і то після хуків маршруту, який його зловив;
  - тож сторінка зі `skip` може дати `claim` чужого розширення без хука сайту.
    Ця діра зникає разом із вилученням.
- `lib/src/page/non_page_requests.dart:19-24`: `xml` — суфікс сторінки, тож
  `/sitemap.xml` вважається запитом сторінки, і `claim` його не бачить.
- `lib/src/catalog/sitemap_source.dart:197-221`: `<loc>` = `base.resolve('/seg/…')`,
  без кінцевого слеша (№6).
  - `resolve` з абсолютним шляхом відкидає шлях бази (проба Dart:
    `https://x.test/app/` + `/projects` → `https://x.test/projects`).
  - `sitemapBaseUrl` (`lib/src/site/page_site.dart:29`) ніде не
    перевіряється (grep), тож база зі шляхом мовчки ігнорується.
- `lib/src/catalog/navigation_builder.dart:34-43`: `NavItem.path` =
  `SitePage.path` (без слеша).
- `lib/src/page/page_path.dart:62-77`: ім'я параметра лише непорожнє й без
  `:`, тож `:slug.md` проходить як ім'я `slug.md`, а потім його відкидає
  `RoutePattern`.
- `lib/src/jaspr_response.dart:43-44`: сторінка без `cache-control`
  отримує `private, no-cache`.
- Jaspr 0.23.5, `lib/src/components/document/document_server.dart:15, 112`:
  `Document.base` за замовчуванням `'/'`, а `null` не рендерить `<base>`.
  Spec гідратації (`2026-10-17-grund-jaspr-hydration-design.md:71-75, 228`)
  вимагає, щоб `<base>` не було або щоб він був `/`. Отже, `base: null`
  сумісний.

**`grund_http`** (перевірено читанням):
- Маршрутизація:
  - `lib/src/routing/route_pattern.dart:52-71`: параметр і вайлдкард —
    лише цілий сегмент;
  - `router.dart:93-115`: у кожному сегменті спершу літерал, потім `:param`,
    потім `*`, з поверненням назад;
  - `server/request_dispatcher.dart:25-27, 67-75`: декодовані непорожні
    сегменти, тож `/users/` = `/users`.
- `lib/src/http/status_code.dart:5-47`: константи 200…503, без 301/307/308;
  `reasonPhrase` їх знає (`:55-60`).
- `lib/src/http/http_response.dart`:
  - `:60-66`: `redirect` (302 за замовчуванням);
  - `:83-103`, `mergeHeaders`: для імені, яке відповідь уже має, виграють її
    значення (окрім `set-cookie`). Тож `vary: cookie` чи `link`, поставлені
    хуком у `c.response`, губляться, щойно відповідь ставить свої.
- `lib/src/testing/test_client.dart:31-66`: `get`/`delete`/`post`/`put`/`patch`,
  без `head`. За `:69-73` відповідь на `HEAD` зберігає тіло.
- Адаптери кладуть ціль `//x` назад у шлях
  (`grund_io/lib/src/io_request_mapper.dart:37-49`,
  `grund_shelf/lib/src/target_request.dart:20-33`). Проба Dart:
  `Uri(path: '//x')` друкується як `////x`, а `Uri(path:
  '/a%2Fb/caf%C3%A9/')` зберігає екранування.
- Розбору `Accept` у `grund_http` немає (grep).

**Попередній досвід** (веб, 2026-10-17):
- llmstxt.org: Markdown-версія лежить на тому самому URL із доданим `.md`
  (`page.html.md`) або із заміненим розширенням (`page.md`). URL без імені
  файла отримує `index.html.md` або `index.md`. Формат `llms.txt`:
  - H1 (обов'язковий);
  - цитата;
  - секції;
  - H2-списки посилань;
  - секція `Optional`.
- Google Search Central, «Consolidate duplicate URLs»: `rel="canonical"` у
  HTTP-заголовку `Link` підтримується, з абсолютними URL. `noindex` для
  вибору канонічної сторінки не рекомендовано, кращий спосіб — canonical.
- Cloudflare, «Markdown for Agents»: `text/markdown` серед варіантів `Accept`
  дає Markdown, відповідь несе `Vary: Accept`. Claude Code і OpenCode такі
  заголовки шлють; точні значення не наведено.
- Типові політики слеша, з пам'яті (§8):
  - Next.js (`trailingSlash: false`, 308 на `/x`);
  - SvelteKit (`never`);
  - Astro (`ignore`);
  - Express (нестрогий роутинг);
  - Django (`APPEND_SLASH`).

## 3. Рішення

1. **Одна адресна модель.** Усі URL, які фреймворк пише або на які
   переадресовує, будує один внутрішній клас `PageAddress` (§4.5).
2. **Альтернатива — частина оголошення сторінки** (`Page.alternates`), а не
   точка розширення. `PageExtension` вилучається: користувачів немає, а
   першому споживачеві вона не підійшла (§2). Пункт роадмапу «пакет шару
   Markdown» закривається цим spec (Для автора, п. 2).
3. **URL альтернативи сторінки з параметром — звичайний маршрут
   `grund_http`** із суфіксом у сегменті параметра (`/projects/:slug.md`). Він
   має хуки сторінки, а `c.path.string('slug')` дає `grund`, а не
   `grund.md`.
4. **Узгодження на URL сторінки.** Типово віддається HTML. Альтернатива
   віддається, лише коли `Accept` називає її тип явно і з якістю, не нижчою
   за якість `text/html` (§4.7). Це не правило RFC «нічию вирішує сервер»:
   агенти називають `text/markdown` явно, браузери — ніколи.
5. **Слеш у кінці** визначає політика сайту `TrailingSlash`; за
   замовчуванням `never` (Для автора, п. 1). Неканонічне написання отримує
   308.
6. **`baseUrl`** — публічне джерело сайту (схема, хост, порт). Його
   перевіряють на старті. Як і раніше, він вмикає sitemap, а також дає
   абсолютні URL (`PageMatch.url`, canonical `Link`).
7. **Файли сайту** (`PageSite.files`) — літеральні маршрути з хуками сайту.
8. **Без SEO-політики за замовчуванням.** Відповідь альтернативи на власному
   URL несе `Link: <сторінка>; rel="canonical"` (лише з `baseUrl`), але не
   `X-Robots-Tag` (Для автора, п. 3).
9. **Відхилені й понижені знахідки:**
   - №8 (`context.staticUrl`) відхилено. Портфоліо вже тримає префікс в
     одній константі й передає її в `JasprConfig(staticPath:)`; помічник дав
     би лише `'${config.staticPath}/$file'`. Документація радить цю константу.
   - №10 (модуль лише для одного `HttpApi`) відхилено: це звичайний модуль, а
     після цього spec портфоліо `MachineApi` уже не потрібен.
   - №7 закривається тим, що `NavItem.path` підкоряється політиці слеша (§4.5).
   - №11 — `TestClient.head` плюс рецепти в документації (§4.11).
   - №12 — лише документація: фреймворк не володіє `Document`, а `base: null`
     правильний і сумісний із гідратацією.
   - №9 переходить до spec середовища (документація).
   - №2 тут не розглядається.

**Відхилені альтернативи.**
- *Лишити `PageExtension` і зробити на ньому пакет Markdown.* `claim` іде
  після хуків довільного маршруту, `/sitemap.xml` — запит сторінки, а
  `respond` не може додати `Vary` до HTML.
- *Узгодження в middleware (як у портфоліо).* Middleware іде до
  маршрутизації, не знає, що таке сторінка, і потребує другого списку
  маршрутів.
- *Маршрут сторінки сам обрізає суфікс* (`/projects/grund.md` → slug
  `grund.md`). У будівнику `c.path.string('slug')` поверне `grund.md`, і це
  пастка.
- *Каталогова форма* (`/projects/grund/index.md`). Роутер лишається
  незмінним, але така форма розходиться з поширеною конвенцією «дописати
  `.md`» і з URL портфоліо.
- *Нічия на користь порядку сервера (RFC 9110 §12.5.1).* Агент із `Accept:
  text/markdown, text/html` отримав би HTML.
- *301 замість 308.* 301 дозволяє клієнтові змінити метод. 308 — пара до
  307, і так робить Next.js. Константу 301 додано лише для документованих
  застарілих випадків.
- *Відносний canonical без `baseUrl` чи хост із заголовка `Host`.* Google
  просить абсолютні URL, а `Host` контролює клієнт. Без `baseUrl` canonical
  `Link` немає.

## 4. Дизайн

### 4.1 `grund_http`: `AcceptHeader`

Новий файл `lib/src/http/accept_header.dart`, експортований із
`grund_http.dart`:

```dart
/// The media ranges of an `Accept` request header with their qualities
/// (RFC 9110 §12.5.1). Reading never throws.
final class AcceptHeader {
  /// Reads [value], every `Accept` field of the request joined with `,`.
  /// `null`, empty or blank means the header is absent.
  factory AcceptHeader.parse(String? value);

  /// The quality of [mediaType] (`type/subtype`, case-insensitive): that of
  /// the most specific range matching it (`type/subtype`, then `type/*`,
  /// then `*/*`); 0 when none matches; 1 when the header is absent.
  double qualityOf(String mediaType);

  /// Whether the header names [mediaType] itself (not through a wildcard)
  /// with a quality above 0.
  bool names(String mediaType);
}
```

Правила розбору:
- **Елементи.** Значення ділиться за `,`. Діапазон — `*/*`, `type/*` або
  `type/subtype` із символів `tchar` (RFC 9110 §5.6.2), без урахування
  регістру. Елемент іншої форми (`*/x`, порожній, сміття) пропускається.
- **Вага `q`.** Ім'я параметра — без урахування регістру. Значення має
  відповідати `^(0(\.\d{0,3})?|1(\.0{0,3})?)$`; інакше якість діапазону 0
  (зіпсована вага ніколи не виграє). Інші параметри й `accept-ext`
  ігноруються.
- **Повтори.** Діапазон, що повторюється, має найвищу зі своїх якостей.
- **Відсутній заголовок проти порожнього списку.** Без заголовка (`null`,
  порожній, пробіли) будь-який тип має якість 1, а `names` — `false`.
  Заголовок, у якому немає жодного розібраного діапазону (`,,;;,q=`), дає 0
  для всього.

### 4.2 `grund_http`: `Vary`, `Link`, статуси редиректу

- `HttpResponse.withVary(String header)` — копія, у якій `vary` називає
  `header` (порівняння без урахування регістру). Результат — **один рядок
  `vary`** з токенами через `, ` (наявні спершу, `header` останнім; моє
  рішення, §10.15), тож `response.headers['vary']` бачить усі токени.
  Повертає ту саму відповідь, якщо `header` уже названо або `vary` дорівнює
  `*`.
- `HttpResponse.mergeHeaders(extra)` — нове правило для трьох імен, решта без
  змін (свої значення виграють):
  - `set-cookie` (як зараз) і `link`: спершу значення `extra`, потім свої,
    обидва зберігаються;
  - `vary`: спершу свої токени, потім токени `extra`, яких ще немає (без
    урахування регістру), і знову **один рядок** `vary`. `*` у будь-якому з
    них дає єдиний `vary: *`.
  `///` методу описує всі три.
- `StatusCode.movedPermanently = 301` і `StatusCode.permanentRedirect = 308`
  з `///`. Документований вибір: 308 для постійних редиректів, 301 лише для
  клієнтів, що не знають 308. `HttpResponse.redirect` лишає 302 за
  замовчуванням.

### 4.3 `grund_http`: параметр із суфіксом

`RoutePattern` приймає сегмент `:name<suffix>`:
- `name` відповідає `[A-Za-z_][A-Za-z0-9_]*`, а `suffix` — `(\.[A-Za-z0-9_~-]+)+`;
- приклади: `:slug.md`, `:name.tar.gz`;
- будь-що інше з `:` усередині сегмента лишається `InvalidRoutePatternError`
  з тим самим текстом про змішування.
- **Модель.** `ParamSegment` отримує поле `suffix` (порожнє для звичайного
  параметра), `toString` дає `:slug.md`, а `parameterNames` — `slug`.
- **Збіг.** Суфікс порівнюється з декодованим сегментом із урахуванням
  регістру, як літерал. Значення параметра — сегмент без суфікса, щонайменше
  один символ (тож `.md` не збігається з `:slug.md`).
- **Пріоритет у сегменті:**
  1. літерал;
  2. параметр із суфіксом, від довшого суфікса до коротшого (однакові
     суфікси — один вузол);
  3. звичайний параметр;
  4. `*`.
  Повернення назад, як зараз.
- **Дублікати.** `/a/:x.md` і `/a/:y.md` дають той самий вузол, отже
  `DuplicateRouteError`. `/a/:x.md` і `/a/:x` співіснують.
- **Генератор** (`grund_http_generator/lib/src/construct/route_paths.dart`):
  `parameters` бере ім'я до першої крапки, `shape` дає `:` плюс суфікс.
  Тож `@Get('/:id.json')` з `@Path() int id` працює так само, як явний
  маршрут.

Зміна не ламає наявний код: такий сегмент досі був помилкою.

### 4.4 `grund_http`: `TestClient.head`

`Future<TestResponse> head(String target, {Map<String, String> headers =
const {}})` = `request('HEAD', target, headers: headers)`. Тіло, як і раніше
для `HEAD`, зберігається (документовано), щоб тест міг порівняти його з `GET`.

### 4.5 `grund_jaspr`: адреса сторінки

```dart
/// How a site spells the end of its page URLs.
enum TrailingSlash {
  /// Both spellings are served as is; links and the sitemap use the
  /// declared path (no slash). The behaviour of 0.2.0.
  ignore,
  /// No slash at the end; `/about/` redirects to `/about` (308).
  never,
  /// A slash at the end of every page URL except one whose last segment has
  /// an extension; `/about` redirects to `/about/` (308).
  always,
}
```

Нові члени `PageSite` (разом 10 членів після змін: було 7, +4 нових, −`sitemapBaseUrl`):

```dart
/// The public origin of the site (`https://example.com`), for the sitemap
/// and absolute URLs; no sitemap and no absolute URLs when `null`.
Uri? get baseUrl => null;

/// How page URLs end; see [TrailingSlash].
TrailingSlash get trailingSlash => TrailingSlash.never;

/// Generated files served at fixed paths of the site, such as `/robots.txt`.
List<SiteFile> get files => const [];

/// Media types every page of the site must offer as an alternate.
List<String> get requiredAlternates => const [];
```

`sitemapBaseUrl` вилучено (**breaking**).

**Перевірка `baseUrl`** у конструкторі `SiteApi`, через `SiteDeclarationCheck`
(§4.12). Порушення дає `InvalidSiteBaseUrlError`. Вимоги:
- схема `http` або `https`;
- хост є;
- шлях порожній або `/`;
- без query, фрагмента й userinfo.
`GuardedSiteSitemapError` (хуки плюс `baseUrl`) лишається, змінюється лише
текст.

**`PageAddress`** (внутрішній, `lib/src/page/page_address.dart`):
- `static String pathOf(String pattern, Map<String, String> params,
  TrailingSlash policy)` — конкретний шлях сторінки за повним шаблоном
  (шлях сайту включно):
  - кожен сегмент через `Uri.encodeComponent`, параметр — його значенням (так
    sitemap робить зараз); **відсутній параметр, порожнє значення, `.` чи `..`
    кидають `ArgumentError`** з іменем параметра (моє рішення, §10.16: це
    помилка коду, що будує `PageMatch(page:, params:)`, а не стартова
    декларація; ті самі значення sitemap відхиляє раніше за `PageEntryValueError`,
    тож до `pathOf` вони не доходять);
  - корінь — `/`;
  - за `always` до шляху, відмінного від `/`, додається `/`, якщо його
    останній сегмент не має розширення (`p.extension`);
  - **виняток (рішення №19).** Якщо останній сегмент без слеша був би
    файловим запитом (розширення, якого немає серед `pageSuffixes`, наприклад
    `v1.2`), слеш лишається за будь-якої політики. Перевірка та сама, що в
    `NonPageRequests` (`NonPageRequests.isFileSegment`); `pathOf` отримує
    `pageSuffixes` іменованим параметром, а `SitePage` несе їх з конфігурації.
    Це стосується `PageMatch.path`/`url`, навігації, sitemap і `Link`;
    `alternatePathOf` слеша не має ніколи.
- `static String alternatePathOf(String pagePath, String suffix, {required
  bool isSiteRoot})` — URL альтернативи:
  - для кореня сайту — `<шлях сайту>/index<suffix>` (`/index.md`,
    `/docs/index.md`);
  - для решти — шлях сторінки без кінцевого `/` плюс суфікс (`/projects.md`,
    `/projects/grund.md`, і так само за `always`).
  Корінь сайту має бути всередині префікса сайту, інакше маршрут не належить
  його `HttpApi` і може зіткнутися з чужою територією.
- `static String alternatePatternOf(String pattern, String suffix, {required
  bool isSiteRoot})` — той самий шаблон для маршрутизатора. Останній літерал
  отримує суфікс (`projects.md`), останній параметр стає `:slug.md`, корінь
  дає `index<suffix>`.

**`PageMatch`** отримує три обчислювані члени (дані беруться з
`page.site`):

```dart
/// The canonical path of the matched page with its parameter values:
/// percent-encoded segments, spelled by the site's [TrailingSlash].
String get path;

/// [path] on the site's `baseUrl`; `null` when the site has none.
Uri? get url;

/// The path of the page's alternate of [mediaType]; `null` when the page
/// declares none.
String? alternatePath(String mediaType);
```

`PageMatch(page:, params:)` лишається публічним конструктором, тож
користувач будує адресу будь-якої сторінки з будь-якими параметрами
(наприклад, для `llms.txt`).

**Навігація і sitemap.**
- `NavigationBuilder` ставить `NavItem.path = PageAddress.pathOf(…, policy)`.
- `SitemapSource._urlOf` ставить `baseUrl.resolve(PageAddress.pathOf(…,
  policy))`, а `_encodedPath` переходить у `PageAddress`.
- За `never` і `ignore` результат не змінюється, за `always` URL отримують
  слеш (№6, №7).

### 4.6 `grund_jaspr`: канонічні редиректи

Внутрішній `CanonicalRedirect` (`lib/src/site/canonical_redirect.dart`)
працює за `never` і `always` (за `ignore` нічого не робить).

```dart
static HttpResponse? forPage(Uri uri, TrailingSlash policy,
    {required List<String> pageSuffixes, required bool isGuarded});
static HttpResponse? forFile(Uri uri, TrailingSlash policy,
    {required bool isGuarded});
```

- **Канонічна форма** будується з сирого `uri.path`: непорожні сегменти без
  декодування й перекодування. Порожньому списку відповідає `/`.
  - `forPage`: за `always` додається `/`, якщо останній сегмент без
    розширення.
  - `forPage` не знімає слеш з останнього сегмента, який без нього був би
    файловим запитом (№19): `/v1.2/` віддається (200) за будь-якої політики,
    а не переадресовується на `/v1.2` (404 `file_not_found`).
  - `forFile` (альтернативи, файли сайту, sitemap): слеша в кінці немає
    ніколи.
  - Якщо форма збігається з `uri.path`, відповідь `null`.
- **Відповідь** — 308, `location` = `Uri(path: канонічна, query: uri.hasQuery
  ? uri.query : null)`, `cache-control: max-age=3600`. Година обмежує
  помилку політики, яку браузер інакше закешував би назавжди. Якщо маршрут має
  хуки (непорожній `use`), значення `private, max-age=3600` (№20): спільний
  кеш не віддасть редирект клієнтові, якого хуки не перевіряли.
- **Безпека.** Канонічна форма ніколи не починається з `//`, бо порожні
  сегменти відкинуто, тож ціль `//evil.test/x` дає `/evil.test/x` на тому
  самому джерелі. `location` не має ні схеми, ні хоста, бо `Uri(path:)` їх не
  отримує.
- **Де викликається.** Першим кроком хендлера маршрутів сторінки,
  альтернативи, файла сайту й sitemap (`/sitemap.xml`, `/sitemap/:chunk`),
  тобто після хуків. Ні фолбек `/*`, ні файловий запит (`/x.png/` отримує 404
  як зараз) не переадресовуються. Сторінка з параметром переадресовується до
  виклику будівника, тож невідомий `slug` іде на 404 після одного редиректу.

### 4.7 `grund_jaspr`: альтернативні подання

```dart
/// Builds the text of an alternate representation of the page [match].
typedef AlternateBuilder =
    FutureOr<String> Function(HttpCtx c, PageMatch match);

/// Another representation of a page, such as Markdown for agents.
final class PageAlternate {
  /// Creates the alternate of [mediaType] served at the page URL plus
  /// [suffix].
  const PageAlternate({
    required this.mediaType,
    required this.suffix,
    required this.build,
  });

  /// Markdown (`text/markdown`) at the page URL plus `.md`.
  const PageAlternate.markdown(AlternateBuilder build)
    : this(mediaType: 'text/markdown', suffix: '.md', build: build);

  /// The media type, `type/subtype` in lower case.
  final String mediaType;

  /// What the page URL gets at its end, such as `.md`.
  final String suffix;

  /// Builds the text; throws `NotFoundException` for an unknown parameter.
  final AlternateBuilder build;
}
```

`Page` отримує `this.alternates = const []` (`List<PageAlternate>`) замість
`extensions`.

**Маршрути.** `PagesApi` для кожної альтернативи сторінки реєструє
`Route.get(PageAddress.alternatePatternOf(…), …, use: <ті самі хуки, що й у
сторінки>, name: 'GET <шаблон>')`. Хуки обчислюються один раз на сторінку,
тож попередження `HookResolver` про `skip` не дублюються.

**Хендлер альтернативи на її URL:**
1. `CanonicalRedirect.forFile`;
2. `PageMatch` з `c.path`;
3. `await alternate.build(c, match)`;
4. `HttpResponse.text` із заголовками:
   - `content-type: <mediaType>; charset=utf-8`;
   - `cache-control: private, no-cache`, якщо `c.response.headers` не має
     `cache-control`. **Це подібне, але не те саме правило, що в сторінок:**
     сторінка дивиться на заголовки, які поставив компонент Jaspr
     (`jaspr_response.dart:43-44`), тож `cache-control` хука на HTML-сторінці
     програє типовому `private, no-cache` (`mergeHeaders`: свої значення
     виграють), а на альтернативі й файлі сайту виграє (§10.11);
   - `link: <match.url>; rel="canonical"`, лише з `baseUrl`.

`NotFoundException` будівника не перехоплюється: це межа запиту, вона дає
problem+json 404, як файловий запит.

**Хендлер URL сторінки:**
1. Файловий запит (`isPageRequest == false`) дає 404 `file_not_found`, як
   зараз, але без ланцюжка `claim`.
2. `CanonicalRedirect.forPage`.
3. Якщо альтернатив немає, сторінка рендериться як у 0.2.0.
4. Якщо вони є, `AlternateNegotiation.choose(AcceptHeader.parse(<усі
   accept через ", ">), page.alternates)` (внутрішній) обирає серед
   альтернатив, для яких `accept.names(m)` і `accept.qualityOf(m) >=
   accept.qualityOf('text/html')`, найвищу якість; нічию вирішує порядок
   оголошення.
   - Якщо альтернативу обрано, будується вона. Відповідь як на її URL, але
     без canonical `Link`. Її `NotFoundException` дає сторінку 404 сайту, як у
     будівника сторінки (розширена межа сторінки, §7).
   - Якщо ні, рендериться HTML, і відповідь отримує по одному `link:
     <alternatePath або абсолютний з baseUrl>; rel="alternate";
     type="<mediaType>"` на альтернативу.
   - 404 сторінки не несе `link rel="alternate"` (сторінки, що її описувала б
     альтернатива, немає; моє рішення, §10.17).
   - Будь-яка відповідь цього кроку (HTML, альтернатива, 404 сторінки)
     отримує `withVary('accept')`. Редирект і відповіді хуків його не
     отримують, бо від `Accept` не залежать.

Таблиця прийому (порт рядків портфоліо, `accept_matrix_test.dart:10-28`), для
сторінки з `PageAlternate.markdown`:

| `Accept` | Відповідь |
| --- | --- |
| відсутній, `''`, `*/*`, `text/*`, `application/json`, браузерний (`text/html,…,*/*;q=0.8`), `,,;;,q=` | HTML |
| `text/markdown;q=0`, `text/markdown;q=abc`, `text/markdown;q=0.5, text/html`, `text/markdown;q=0.1, */*` | HTML |
| `text/markdown`, `TEXT/MARKDOWN`, `text/markdown;charset=utf-8` | Markdown |
| `text/markdown, text/html;q=0.9`, `text/html, text/markdown` (нічия), `text/markdown;q=0.5, */*;q=0.5` | Markdown |

Відмінність від портфоліо: `text/markdown;q=0.1, */*` дає HTML, бо `*/*`
дає HTML якість 1. Портфоліо вайлдкарти не рахувало.

**`requiredAlternates`.** На старті, коли будується таблиця маршрутів,
кожна сторінка сайту має мати альтернативу кожного переліченого типу,
інакше `MissingPageAlternateError`. Виключень у першій версії немає: сайт зі
сторінками без альтернатив цей список не задає. Це замінює тест
синхронізації портфоліо.

**Перевірки альтернатив** (`PageDeclarationCheck`, §4.12). Кожне порушення дає
`InvalidPageAlternateError` із причиною:
- `mediaType` не `type/subtype` з `tchar` у нижньому регістрі, має
  параметри, `*` або дорівнює `text/html`;
- `suffix` не відповідає `^(\.[a-z0-9]+)+$`;
- останнє розширення суфікса входить до `JasprConfig.pageSuffixes`;
- дві альтернативи сторінки мають той самий тип або суфікс;
- URL альтернативи зарезервовано (`staticPath`, sitemap, `rootFiles`; ті
  самі причини, що й для сторінок).
Зіткнення з іншим маршрутом (наприклад, сторінка `/index` і корінь сайту, які
обидві дають `/index.md`) ловить роутер як `DuplicateRouteError`.

**`PagePath`** тепер вимагає, щоб ім'я параметра сторінки відповідало
`[A-Za-z_][A-Za-z0-9_]*` (`InvalidPagePathError`). Сторінка не може
оголосити `:slug.md`: суфікси належать альтернативам.

### 4.8 `grund_jaspr`: файли сайту

```dart
/// Builds the text of a site file.
typedef SiteFileBuilder = FutureOr<String> Function(HttpCtx c);

/// A generated text file at a fixed path of a site, such as `/robots.txt`.
final class SiteFile {
  /// Creates the file served at [path] (relative to the site) as
  /// [mediaType] in UTF-8.
  const SiteFile(this.path, {required this.mediaType, required this.build});
  // fields path, mediaType, build with ///
}
```

- **Маршрути.** `SiteApi` реєструє `Route.get(file.path, …, use: site.use)`
  до фолбеку `/*`.
- **Хендлер:**
  1. `CanonicalRedirect.forFile`;
  2. `await file.build(c)`;
  3. `content-type: <mediaType>; charset=utf-8`;
  4. те саме правило `cache-control`, що й в альтернатив.
- **Перевірки** у конструкторі `SiteApi` дають `InvalidSiteFileError`:
  - шлях починається з `/`, складається з літералів, не `/`, без порожніх
    сегментів, `:` і `*`;
  - `mediaType` має форму `type/subtype` (будь-який тип, і `text/html` теж:
    так роблять файли підтвердження власника сайту);
  - шлях не зарезервовано.
  Дубль шляху ловить роутер.
- **Територія** (моє рішення, §10.14). Повний шлях файла (шлях сайту плюс
  `file.path`) не може лежати під префіксом іншого сайту: файл кореневого
  сайту `/admin/x.txt` інакше мовчки перекрив би `/admin/*` фолбека сайту
  `/admin`. `SiteValidator._checkTerritories` (`site/site_validator.dart`)
  перевіряє й повні шляхи файлів і кидає наявну `MisplacedPagePathError`
  (її текст говорить про шлях сторінки чи файла); нового класу помилки
  немає.
- `Sitemap:`-рядок у `robots.txt` користувач пише сам із `baseUrl`, як у
  прикладі документації: `baseUrl!.resolve('/sitemap.xml')`.

### 4.9 Вилучення `PageExtension`

Вилучаються:
- `lib/src/page/page_extension.dart`;
- `Page.extensions`;
- `PageCatalog.pagesWith`;
- `lib/src/site/site_extensions.dart`;
- `SiteServices.extensions`;
- прив'язка й експорт `SiteExtensions` у `JasprModule`;
- `NonPageRequests.answer`. Хендлери кличуть `nonPage.notFound(uri)`
  напряму.

Експорт із `grund_jaspr.dart` прибирається. `test/page_extension_test.dart`
вилучається, частини `catalog_test.dart` і `helpers/catalog_app.dart` про
`pagesWith` теж; `test/page_values_test.dart:19` (`expect(page.extensions,
isEmpty)`) стає перевіркою `page.alternates`.

### 4.10 Приклад

`example/lib/src/web/public_site.dart` (явний API, спільний для обох стилів
модулів):
- `files: [SiteFile('/robots.txt', mediaType: 'text/plain', build: (_) =>
  'User-agent: *\nAllow: /\n')]`;
- головна сторінка (`web_module.dart` або там, де оголошено `Page('/')`)
  отримує `PageAlternate.markdown`, який перелічує назви задач тим самим
  сервісом, що й HTML.

Новий `example/test/web_addresses_test.dart` на обох адаптерах:
- `GET /index.md` дає 200 `text/markdown`, а `HEAD` (через `client.head`)
  дає 200;
- `GET /` з `accept: text/markdown` дає Markdown і `vary: accept`;
- браузерний `GET /` дає HTML, `link` з `rel="alternate"` і `vary`;
- `GET /login/` дає 308 і `location: /login`;
- `GET /robots.txt` дає 200 `text/plain`.

### 4.11 Документація (англійською)

- **`docs/jaspr.md`:**
  - таблиця `PageSite` (`:133`) без `sitemapBaseUrl`, з
    `baseUrl`/`trailingSlash`/`files`/`requiredAlternates`;
  - новий розділ «Addresses: base URL and trailing slash», перед «Sitemap and
    navigation»;
  - «Sitemap and navigation» (`:371-427`) переходить на `baseUrl`;
  - новий розділ «Alternate representations», де Markdown для агентів — з
    `llms.txt` як `SiteFile`, зібраним через `PageCatalog.pagesOf` і
    `PageMatch.alternatePath`. Там же: чому немає `noindex` і як його додати
    (`c.response.headers.set('x-robots-tag', 'noindex')` у будівнику), а
    також кеші/CDN і `Vary: Accept`;
  - новий розділ «Site files»;
  - у «Testing» (`:482-502`) — `client.head` і рецепт «кожна сторінка
    відповідає 200». Конкретні URL дають `PageCatalog.pagesOf<S>()` і
    `PageMatch(page:, params:).path`, для параметричних сторінок —
    `sitemapOf<S>()`. Перевірку ресурсів сторінки з `package:html` у
    `dev_dependencies` користувача наведено як рецепт, не як API;
  - у «Things to know» (`:542-569`): абзац про `PageExtension` прибирається,
    додається `<base href="/">` (типовий у Jaspr `Document`; якірні
    посилання `#x` ведуть на головну; `Document(base: null)`; сумісно з
    гідратацією, якій потрібен `<base>` відсутній або `/`).
- **`docs/http-and-hooks.md`:**
  - параметр із суфіксом;
  - `AcceptHeader`;
  - `withVary` і правила `mergeHeaders`;
  - `StatusCode.permanentRedirect`/`movedPermanently`.
- **`docs/testing.md`:** `head`.
- **README `grund_jaspr`:** без `PageExtension`, з альтернативами й файлами
  сайту.
- **CHANGELOG:**
  - `grund_http` 0.3.0;
  - `grund_http_generator` 0.2.0;
  - `grund_jaspr` 0.3.0 з `**Breaking:**` для вилучення, перейменування,
    типового `never` і суворіших імен параметрів.
- **`CLAUDE.md`:**
  - опис `grund_jaspr` у «Project»;
  - межа сторінки в «Code rules» (§7).
- **`ROADMAP.md`:** рядок G7a-pages («пакет шару Markdown» закрито цим
  кроком) і рядок G7b.

### 4.12 Розкладка коду `grund_jaspr`

Щоб `pages_api.dart` (131 рядок) і `site_api.dart` (72) не росли за межі,
перевірки й видача виносяться в колаборатори. Усі вони внутрішні, у барелі
їх немає.

| Колаборатор | Що робить |
| --- | --- |
| `site/reserved_paths.dart` (`ReservedPaths.reasonFor(path, site, config)`) | причина резерву або `null` (з `_checkNotReserved`) |
| `site/page_declaration_check.dart` | резерв, sitemap, альтернативи, `requiredAlternates` однієї сторінки |
| `site/site_declaration_check.dart` | шлях сайту, `baseUrl`, guarded sitemap, файли (з конструктора `SiteApi`) |
| `site/page_responder.dart` | хендлери URL сторінки й альтернативи (§4.6–4.7) |
| `site/alternate_negotiation.dart` | вибір альтернативи |
| `site/canonical_redirect.dart` | §4.6 |
| `page/page_address.dart` | §4.5 |

Публічні нові файли:
- `page/page_alternate.dart`;
- `site/trailing_slash.dart`;
- `site/site_file.dart`.

## 5. Помилки

| Клас (стабільний код) | Родина | Коли |
| --- | --- | --- |
| `InvalidPageAlternateError(path, mediaType, reason)` | `PageDeclarationError` | §4.7, перевірки альтернатив |
| `MissingPageAlternateError(path, mediaType)` | `PageDeclarationError` | сторінка без типу з `requiredAlternates` |
| `InvalidSiteFileError(siteType, path, reason)` | `SiteDeclarationError` | §4.8 |
| `InvalidSiteBaseUrlError(siteType, url, reason)` | `SiteDeclarationError` | §4.5 |
| `InvalidPagePathError` (наявна) | `PageDeclarationError` | ім'я параметра не ідентифікатор |
| `InvalidRoutePatternError` (наявна) | `RoutingError` | зіпсований `:name<suffix>` |
| `GuardedSiteSitemapError` (наявна) | `SiteDeclarationError` | текст про `baseUrl` |

Усі помилки виникають на старті, до прослуховування. Повідомлення мають
форму «проблема + суб'єкт + підказка», як у наявних. Нових помилок часу
виконання немає: `NotFoundException` будівника дає 404 (§4.7). Зіпсований
`Accept` — не помилка, а HTML.

## 6. Тестування

- **`grund_http`:**
  - `test/http/accept_header_test.dart`: граматика `q`, вайлдкарти,
    специфічність, регістр, повтори, відсутній проти сміттєвого заголовка;
  - `withVary` (додає, не дублює, `*`);
  - `mergeHeaders`: `vary` об'єднується, `link` і `set-cookie` зберігають
    обидва значення, решта — свої;
  - маршрутизація: пріоритет літерал > суфікс > параметр > `*`, довший
    суфікс першим, порожнє значення не збігається, `DuplicateRouteError`,
    зіпсовані шаблони, декодований сегмент (`grund%2Emd`);
  - `TestClient.head`.
- **`grund_http_generator`:** `RoutePaths` для `:id.json`; один кейс
  `http_cases_app` з `@Get('/:id.json')`, якщо фікстура це дозволяє без
  зміни golden-файлів `users_app` (§8).
- **`grund_jaspr`:** нові файли тестів, кожен ≤ 500 рядків.
  - `alternates_test.dart`:
    - URL кореня й префіксного сайту;
    - параметрична сторінка (`c.path` дає значення без суфікса);
    - хуки сторінки на альтернативі, зокрема `skip`;
    - canonical `Link` з `baseUrl` і без;
    - `cache-control`;
    - `NotFoundException` на URL альтернативи (problem 404) і через
      узгодження (сторінка 404).
  - `negotiation_test.dart`: таблиця §4.7, `vary`, `link` alternate,
    `HEAD`.
  - `trailing_slash_test.dart`:
    - `never`/`always`/`ignore` для сторінки, кореня, префіксного кореня,
      параметра, розширення;
    - query зберігається;
    - `//evil.test/x`;
    - файли й sitemap;
    - хуки до редиректу;
    - 404 і файлові запити без редиректу.
  - `site_files_test.dart`.
  - `page_addresses_test.dart`: `PageMatch.path/url/alternatePath`,
    `NavItem.path`, `<loc>` за `always`.
  - `alternate_rules_test.dart`: усі причини §4.7 і §4.8, `baseUrl`,
    `requiredAlternates`.
  - Наявні тести sitemap переходять на `baseUrl`.
- **Приклад:** §4.10 на обох адаптерах.
- **Прийом:**
  - `dart analyze` чистий;
  - `dart test` усіх змінених пакетів і прикладу;
  - `publish --dry-run` без попереджень для `grund_http`,
    `grund_http_generator` і `grund_jaspr`.

## 7. Відхилення від CLAUDE.md і релізи

- **Нових винятків немає.** Межа сторінки (`CLAUDE.md`, «the page boundary»)
  розширюється, не з'являється нова: `on NotFoundException` тепер оточує і
  будівник альтернативи, обраної узгодженням на URL сторінки. На власному
  URL альтернативи він не ловиться. Текст `CLAUDE.md` оновлюється в задачі
  документації.
- **Нових залежностей немає.** `grund_jaspr` уже має `path`.
- **Версії:**
  - `grund_http` 0.3.0: нове API; поведінкова зміна злиття `vary`/`link` у
    CHANGELOG;
  - `grund_http_generator` 0.2.0;
  - `grund_jaspr` 0.3.0, **breaking**.
  Секції CHANGELOG уже є.
- **Обмеження на мейнтейнера, під час випуску:**
  - `grund_jaspr` має залежати від `grund_http: ^0.3.0`, бо використовує
    `AcceptHeader`, суфікси й `permanentRedirect`;
  - тег `grund_http` пушиться раніше за `grund_jaspr` (RELEASING.md).
  План не змінює ні `version:`, ні обмежень у pubspec.

## 8. Не перевірено (перші перевірки плану)

1. Типові політики Next.js/SvelteKit/Astro/Django у §2 взято з пам'яті, не з
   джерел. На рішення впливає лише Для автора, п. 1.
2. Точний `Accept` Claude Code. Cloudflare лише каже, що агенти шлють
   `text/markdown`. Таблиця §4.7 покриває обидві ймовірні форми (з
   `text/html` і без).
3. Чи `public_member_api_docs` приймає `const PageAlternate.markdown(…) :
   this(…)` і typedef-и без додаткових правил (очікувано так).
4. Чи `http_cases_app` може отримати маршрут `/:id.json` без зміни
   golden-файлів `users_app`. Якщо ні — лише юніт-тест `RoutePaths`.
5. Чи `PageCatalog.match(Uri)` правильно матчить `/projects/` (кінцевий
   слеш). Поза цим spec, але `context.pageMatch` за `always` від цього
   залежить. Перевірка в Задачі 5 плану; якщо ні, виправлення йде туди.
6. Поведінка CDN із `Vary: Accept` (фрагментація кешу) не вимірювалася.
   Документація попереджає.

## 9. Узгодження з гідратацією

Spec і план гідратації не змінюються. Перетини:
- `CHANGELOG.md` `grund_jaspr` 0.3.0, `docs/jaspr.md` («Things to know»,
  «Testing») і `jaspr_module.dart` (тут лише вилучення `SiteExtensions`).
  Хто зливається другим, той робить rebase.
- Абзац про `<base>` (§4.11) збігається з вимогою гідратації («`<base>`
  відсутній або `/`») і на неї посилається.

## 10. Рішення, прийняті без користувача

1. URL альтернативи не залежить від політики слеша. Для кореня сайту це
   `<шлях сайту>/index<suffix>`, для решти — шлях без кінцевого `/` плюс
   суфікс (§4.5). Збігається з URL портфоліо (`/projects/` → `/projects.md`)
   і з формою «замінене розширення» llmstxt.
2. Нічия між названою альтернативою і HTML дає альтернативу. Альтернатива,
   досяжна лише вайлдкардом, не виграє ніколи (§4.7).
3. Зіпсована вага `q` дає якість 0; відсутній і порожній заголовок
   рівнозначні (§4.1).
4. `406` немає: HTML — завжди доступний варіант (RFC 9110 дозволяє ігнорувати
   `Accept`).
5. Редирект після хуків, до будівника; лише відомі маршрути; `cache-control:
   max-age=3600`; `location` без хоста (§4.6).
6. За `always` слеш не додається до сегмента з розширенням (§4.5).
7. canonical `Link` лише з `baseUrl`, абсолютний; на HTML — лише `link`
   alternate. Canonical HTML лишається справою оболонки (`PageMatch.url`).
8. `baseUrl` вмикає і sitemap, і абсолютні URL. Окремого прапорця sitemap
   немає; guarded-сайт не має `baseUrl`.
9. `requiredAlternates` без механізму виключення (§4.7).
10. `SiteFile` — лише текст UTF-8, будь-який тип, хуки сайту (§4.8).
11. Правило `cache-control` («типовий `private, no-cache`, коли відповідь його
    не має») поширено на альтернативи й файли сайту, але читає
    `c.response.headers`, а не заголовки компонента (§4.7).
12. `mergeHeaders` зливає `vary` і `link` (§4.2). Інакше `Vary: Accept`
    сторінки стер би `Vary`, який поставив хук.
13. Синтаксис суфікса — крапкові розширення з `[A-Za-z0-9_~-]` (§4.3). Інші
    роздільники (`:from-:to`) поза межами.
14. Перевірка території охоплює файли сайту (§4.8): наявна
    `MisplacedPagePathError`, без нового класу. Ціна помилки: хибне
    спрацювання на файлі, що навмисно лежить під чужим префіксом (його немає
    чим дозволити; такий файл оголошується сайтом-власником).
15. `withVary` і `mergeHeaders` лишають один рядок `vary` (§4.2).
16. `PageAddress.pathOf` кидає `ArgumentError` на відсутній параметр і
    значення «порожнє / `.` / `..`», а не типізовану помилку (§4.5). Ціна
    помилки: менш єдиний вигляд помилок; перехід на типізовану помилку не
    ламає нічого, бо `pathOf` внутрішній.
17. 404 сторінки на URL з `Accept` альтернативи не несе `link
    rel="alternate"` (§4.7).
18. №8 і №10 відхилено, №12 — лише документація (§3).
19. Канонічна адреса ніколи не веде на файловий запит; сторінки з крапкою в
    параметрі (`v1.2`) мають канонічну адресу зі слешем за будь-якої політики
    (§4.5, §4.6). Ціна помилки: канонічний URL такої сторінки містить слеш
    навіть за `never`.
20. Редирект маршруту з хуками має `cache-control: private, max-age=3600`,
    інакше `max-age=3600` (§4.6). Ціна помилки: редиректи захищених сторінок
    не кешуються спільними кешами.

## 11. Для автора

1. **Типова політика слеша.** Рекомендую `TrailingSlash.never`: оголошені
   шляхи вже без слеша, і так роблять Next.js і SvelteKit. Альтернатива —
   `ignore`, поведінка 0.2.0 без редиректів. Якщо обрати `ignore`, у §4.5
   змінюється одне значення за замовчуванням; приклад і тест
   `/login/` → 308 явно ставлять `never`.
2. **Вилучити `PageExtension` і не робити окремий пакет Markdown.**
   Рекомендую так: користувачів немає, а альтернативи покривають єдиний
   задуманий випадок. Альтернатива — лишити його поруч, але тоді діра
   `claim`/`skip` (§2) лишається і потребує окремого виправлення.
3. **Без `X-Robots-Tag: noindex` за замовчуванням.** Рекомендую так: Google
   радить canonical, а не `noindex`, і canonical `Link` іде з `baseUrl`.
   Портфоліо зараз ставить обидва. Хто хоче `noindex`, ставить його одним
   рядком у будівнику.
4. **Синтаксис `:name.ext` у роутері `grund_http`.** Рекомендую так: це
   загальна можливість (`/users/:id.json`) і єдиний спосіб дати альтернативі
   параметричної сторінки чисті `c.path`. Альтернатива — каталогова форма
   `/projects/grund/index.md` без змін роутера (§3).

**Рішення автора (2026-10-17, відповідь «Все»):** усі рекомендації цього
розділу прийнято, spec і його план схвалено до виконання.
