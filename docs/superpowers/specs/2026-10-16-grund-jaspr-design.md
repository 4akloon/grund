# grund_jaspr: SSR-сторінки в одному процесі з API — дизайн

Дата: 2026-10-16. Стан: чернетка на перегляд (spec для етапу G7a, див. «Зміни
роадмапу»). Рамка: `2026-10-15-grund-platform-design.md` §6.7 (там `JasprModule`
описаний одним абзацом), ядро й HTTP: `2026-10-15-grund-core-design.md`.

## 1. Мета й межі

Мета: один процес `grund` віддає REST API і HTML-сторінки, відрендерені на
сервері Jaspr, з одним DI, одним життєвим циклом і спільною cookie-сесією.
Перший зріз — **лише SSR**: без гідратації (`@client`), без клієнтського JS-бандла,
без `jaspr_builder`/`build_runner` у проєкті користувача.

У зрізі:
- `grund_jaspr` (новий пакет): `JasprModule`, рендер сторінки на запит, віддача
  статичних файлів, доступ до DI і контексту виклику з компонентів.
- `grund_auth` (новий пакет, лише сесійна частина G4): `CurrentUser`, `Session`,
  `SessionStore` + `InMemorySessionStore`, `Sessions` (почати/закінчити сесію),
  `SessionHook`, `SameOriginHook`, серіалізація `Set-Cookie`.
- Шаблон `grund init` для fullstack (SSR-only) і сторінки в `example/` (за
  правилом роадмапу приклад покриває всі опубліковані модулі).
- Дрібна правка `grund_http`: злиття заголовків не губить `set-cookie` (див. 4.5).

Поза зрізом (лишається в G4/G7b): гідратація й dev-цикл `jaspr serve`, перевірка
облікових даних (пароль, OAuth), JWT, токени CSRF, ролі/дозволи
(`Authenticated`, `Roles`), WebSocket, сторінки помилок у HTML.

## 2. Вхідні факти (перевірено 2026-10-16)

- Jaspr `0.23.5` (2026-09-25), `sdk >=3.8.0`; рантайм працює на нашому флорі 3.8
  (залежності `shelf`, `html`, … мають сумісні версії; **не перевірено реальним
  `pub get` на 3.8** — перша задача плану, CI на 3.8.0 це підтвердить). Інструментарій
  гідратації (`jaspr_cli`, `build_web_compilers`) вимагає Dart 3.11–3.13, тому він
  поза зрізом. Jaspr до 1.0: мінорні версії ламають API → залежність
  `jaspr: '>=0.23.5 <0.24.0'`.
- Публічні входи Jaspr без власного сокета: `serveApp(...)` (shelf `Handler`) і
  `renderComponent(Component, {Request? request})` → запис
  `({int statusCode, Uint8List body, Map<String, List<String>> headers})`.
  `render` читає з `Request` лише `url`, `handlerPath` і `headersAll`; тіло не
  читається, тож вручну зібраний `shelf.Request` достатній.
- Пастки Jaspr: без `Jaspr.initializeApp` процес завершується через `exit(-1)`;
  стан процес-глобальний; шлях `web/` визначається через `Platform.script` і
  крихкий; dev-шлях `serveApp` викликає `hijack`, що кидає `StateError` на вручну
  зібраному `Request`. Звідси рішення не використовувати `serveApp`.
- grund: маршрут `Route.get('/*')` у `HttpApi` з порожнім `path` співіснує з
  API-маршрутами (пріоритет сегмента: літерал, `:param`, `*`); `/*` не збігається
  з `/`, тож потрібні `Route.get('/')` і `Route.get('/*')`. Хук кладе значення
  `c.set<T>(...)`, обробник читає `c<T>()`/`c.maybe<T>()`. Модульний `onInit`
  виконується раз на `App` і не повторюється на `reassemble`.

## 3. Підхід

Обрано підхід A: grund викликає Jaspr на кожен запит; Jaspr не володіє процесом.
Відкинуто B (Jaspr володіє процесом, grund як middleware: немає `close`, grund
втрачає життєвий цикл) і C (два процеси: суперечить меті).

## 4. Архітектура

```
запит → HttpServer → middleware → router ─┬─ API-маршрути (пріоритет)
                                          └─ JasprPages: GET / і GET /*
                                               ├─ файл у staticDirectory?  → байти
                                               └─ ні → renderComponent(GrundScope(app())) → HttpResponse
```

### 4.1 `grund_jaspr`

- `JasprModule({required Component Function() app, JasprConfig config})` —
  модуль, що імпортує `HttpModule` та віддає `HttpApi` з порожнім шляхом
  (`JasprPages`) і двома маршрутами: `GET /` та `GET /*`. Сторінки проходять той
  самий пайплайн (глобальні хуки, `ProblemResponder`, access log).
- `app()` викликається **на кожен запит** і будує кореневий компонент
  користувача; маршрутизацію між сторінками користувач робить сам (наприклад,
  `jaspr_router`, на нього пакет не залежить).
- Кореневу обгортку додає пакет: `GrundScope` (`InheritedComponent`) тримає
  `HttpCtx` поточного виклику. Для компонентів — розширення `BuildContext`:
  `context.injector`, `context.call<T>()`, `context.maybe<T>()` (ті самі
  семантики, що в `HttpCtx`). Через це `grund_jaspr` **не залежить від
  `grund_auth`**: `CurrentUser` читається як `context.maybe<CurrentUser>()`.
- Рендер: `HttpCtx` → `shelf.Request(method, uri, headers, handlerPath: '/')`;
  відповідь → `HttpResponse.bytes(status, body, headers)` з усіма заголовками,
  включно з кількома `set-cookie`. Якщо `content-type` відсутній або без charset,
  виставляється `text/html; charset=utf-8`. Якщо компонент не задав
  `cache-control`, ставиться `private, no-cache` (сторінка залежить від сесії).
  `HEAD` обслуговується через `GET` самим router-ом.
- Ініціалізація: `Jaspr.initializeApp()` у `onInit` модуля, **ідемпотентно**
  (статичний прапорець; кілька `App`/`TestApp` в одному процесі; у `onShutdown`
  не скасовується). `useIsolates: false`.
- Статичні файли: `JasprConfig.staticDirectory` (за замовчуванням `web`, шлях
  відносно кореня пакета застосунку, не `Platform.script`). Файл віддається, якщо
  шлях після нормалізації лишається всередині каталогу (захист від `..` і
  відсотково закодованих обходів) і це звичайний файл; тип за невеликою вбудованою
  таблицею розширень; `cache-control: no-cache`. Інакше — рендер сторінки.
  Шлях з розширенням, якого рендер не дозволяє (`allowedPathSuffixes` Jaspr), дає 404.

### 4.2 `grund_auth` (сесії)

- `CurrentUser(String id, {Map<String, Object?> claims})` — значення в контексті
  виклику.
- `SessionStore` (інтерфейс): `create`, `read(id)`, `delete(id)`;
  `InMemorySessionStore` з простроченням. Довговічне сховище — G3/G4.
- `Session(id, userId, createdAt, expiresAt)`; ідентифікатор — непрозорий
  випадковий токен (32 байти з `Random.secure`, base64url). Cookie містить лише
  його; підписувати нічого, ключів немає (узгоджено з G4: «непрозорий токен»).
- `Sessions` (сервіс): `start(HttpCtx, userId)` створює **нову** сесію (старий
  токен видаляється: захист від фіксації сесії) і додає `set-cookie`;
  `end(HttpCtx)` видаляє сесію й надсилає протермінований cookie.
- `SessionHook` (глобальний): у `before` читає cookie, шукає сесію, і якщо вона
  жива — `c.set<CurrentUser>(...)`. Відсутня, невідома чи прострочена сесія — не
  помилка: просто немає `CurrentUser`.
- Cookie: назва `grund_sid` (налаштовується), `HttpOnly`, `SameSite=Lax`,
  `Path=/`, `Secure` (за замовчуванням увімкнено; шаблон `init` вимикає у dev),
  `Max-Age` 7 діб абсолютно. `SetCookie` — власний серіалізатор (у grund_http
  немає): значення проходить перевірку на допустимі символи, атрибути збираються
  детерміновано.
- `SameOriginHook` (глобальний, вмикається в `SessionConfig`): небезпечні методи
  (не `GET/HEAD/OPTIONS`) з `Sec-Fetch-Site` не `same-origin`/`none` або з `Origin`,
  що не збігається з `Host`, відхиляються `ForbiddenException`. Без заголовків
  (клієнт не браузер) запит проходить. Токени CSRF — G4.

### 4.3 Шаблон `grund init` і приклад

Шаблон `fullstack`: `bin/main.dart`, `lib/src/app_module.dart`, сторінки
(головна, вхід), `web/` зі стилем, `pubspec.yaml` із `grund`, `grund_http`,
`grund_io`, `grund_jaspr`, `grund_auth`, `jaspr`. Генерований проєкт має
проходити власні тести (`TestApp`: `GET /` дає 200 і HTML, вхід ставить cookie).
`example/` отримує SSR-сторінки та вхід через сесію.

### 4.4 Потік входу (приклад)

`POST /login` (звичайний `HttpApi` користувача) перевіряє облікові дані **сам**
(у зрізі пароль не наш), викликає `sessions.start(c, user.id)` і повертає
`HttpResponse.redirect('/')`. Наступний `GET /` проходить `SessionHook`, і
компонент бачить `context.maybe<CurrentUser>()`.

### 4.5 Зміна в `grund_http`

`HttpResponse.mergeHeaders` зараз не додає заголовок, якщо відповідь уже має
заголовок з таким іменем; тому `set-cookie` з `c.response.headers` губиться, коли
відповідь несе власний. Для багатозначних заголовків (`set-cookie`) злиття має
**додавати**. Окрема правка з тестом (відповідь із власним і з доданим хуком cookie
повертає обидва).

## 5. Помилки

Помилки рендеру й хуків ідуть звичайним шляхом `ProblemResponder` (RFC 9457,
`application/problem+json`; для HTML-сторінки це відомий компроміс, сторінки
помилок у HTML — поза зрізом). Нічого не вгадується мовчки: невалідне
налаштування cookie (порожня назва, `SameSite=None` без `Secure`, значення з
недозволеними символами) — типізована помилка при старті модуля, до запуску
сервера. Відсутній `staticDirectory` — не помилка (статики просто немає).

## 6. Тести

- `grund_auth`: серіалізація `Set-Cookie` (атрибути, порядок, відхилення
  недопустимих значень); `InMemorySessionStore` (створення, читання, прострочення,
  видалення); `Sessions.start` ротує токен; `SessionHook` (жива/невідома/
  прострочена/підроблена сесія); `SameOriginHook` (усі гілки, включно з відсутніми
  заголовками).
- `grund_jaspr`: відображення відповіді (статус, кілька `set-cookie`, charset,
  `cache-control`); API-маршрути не затінюються `/*`; `/` обслуговується окремим
  маршрутом; `HEAD`; статика (обхід `..`, `%2e%2e`, каталог замість файлу, тип);
  `Jaspr.initializeApp` ідемпотентний для кількох `App`; `context.call/maybe`.
- `grund_http`: злиття `set-cookie` (4.5).
- e2e в `example/` на обох адаптерах (`grund_io`, `grund_shelf`): сторінка,
  вхід → cookie з `HttpOnly; SameSite=Lax`, захищена сторінка бачить користувача,
  вихід; а також перевірка шаблону `init` у `grund_cli` (генерується, `pub get` у
  робочому просторі, тести проєкту зелені).
- CI на Dart 3.8.0 і stable підтверджує сумісність рантайму Jaspr із флором.

## 7. Зміни роадмапу

- G7 розділяється: **G7a** (цей spec: `grund_jaspr`, `grund_auth` лише сесії,
  шаблон fullstack SSR-only) іде раніше; **G7b** (`grund_ws`, решта шаблонів,
  гідратація) лишається на місці.
- З G4 «сесії + cookie» переходить у G7a; G4 далі додає облікові дані, JWT, OAuth,
  `Authenticated`/`Roles`, довговічне сховище.
- Опубліковано 0.1.0 з вісьмох пакетів G1; `grund_openapi` (G2) і нові пакети
  отримують версію свого релізу за правилом lockstep. Нумерацію релізів
  (0.2.0…) у таблиці роадмапу оновити окремою задачею плану.

## 8. Рішення, що чекають вашого перегляду

1. `CurrentUser` у `grund_auth` — мінімальний `(id, claims)`; існуючий
   `CurrentUser(Role)` в `example/` лишається окремим типом (імпорт з префіксом до G4).
2. Захист від CSRF у зрізі — `SameSite=Lax` + `SameOriginHook` за заголовками
   Fetch Metadata/Origin, без токенів.
3. Сесія — непрозорий токен у пам'яті, абсолютний строк 7 діб, без ковзного.
4. Статика входить у зріз (інакше сторінки без стилю й favicon непрактичні).
5. `Secure` увімкнено за замовчуванням; dev-шаблон вимикає.
6. Помилки сторінок — problem+json, HTML-сторінки помилок пізніше.

## 9. Ризики

- Jaspr 0.x: API зміниться; ізольовано в `grund_jaspr`, версія закріплена.
- Крихкість `web/` у Jaspr обійдено власною віддачею статики.
- `exit(-1)` без ініціалізації: ініціалізація в `onInit` до першого запиту; тест
  на `TestApp` без `App.start`.
- Сумісність із флором 3.8 доводиться лише CI.

## 10. Готово, коли

`example` віддає SSR-сторінку з даними з DI та вхід через сесію на обох
адаптерах; `grund init --template fullstack` створює проєкт, що проходить свої
тести; CI зелений на 3.8.0 і stable; `publish --dry-run` без попереджень для
`grund_jaspr` і `grund_auth`; документація (`docs/jaspr.md`, README, CHANGELOG)
і роадмап оновлені.
