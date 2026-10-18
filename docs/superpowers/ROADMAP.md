# grund — роадмап

Рамка: `docs/superpowers/specs/2026-10-15-grund-platform-design.md`.
Загальний план по всіх репозиторіях: `docs/superpowers/PLATFORM-PLAN.md`.
Кожен етап — окремий spec у `docs/superpowers/specs/` і план у
`docs/superpowers/plans/`, що дає робоче й протестоване ПЗ сам по собі.
Spec і план наступного етапу пишуться після здачі попереднього, на основі
реального коду.

## Історія: dartnest v1.0 ✅

Етапи 1–7 (ядро DI, HTTP-конвеєр, адаптери, анотації та генератор, CLI, hot
reload, build_runner-драйвер, приклад і документація) завершені за spec-ом
`2026-10-13-dartnest-design.md`, плани в `docs/superpowers/plans/2026-10-1[34]-*`.
`0.1.0` не публікувався; перша публікація буде вже під назвою grund.
Попередні пункти v1.1/v2.0 (OpenAPI, lifecycle, GraphQL) поглинуті етапами
нижче.

## grund: віхи 0.x → 1.0

Випускаємо частинами: кожна віха дає робочу платформу з тим, що вже є, і
публікується на pub.dev. Обсяг 1.0 — увесь v1 з рамки (auth, realtime,
infra); 0.x — шлях до нього. До 1.0 несумісні зміни дозволені в мінорній
версії й позначаються `**Breaking:**` у CHANGELOG.

Версії пакетів незалежні (`docs/RELEASING.md`): реліз пакета — тег
`<package>-vX.Y.Z`, нову версію отримує лише змінений пакет (несумісна зміна —
мінорна, решта — патч), обмеження між членами workspace — найнижча версія, що
має потрібне залежному. Новий пакет починає з `0.1.0`; першу версію публікують
вручну. Віха закінчується однаковим кроком випуску: CHANGELOG кожного зміненого
пакета, README і quick start для того, що вже є, приклад покриває всі
опубліковані модулі, `publish --dry-run` без попереджень для всіх пакетів;
версії, теги й публікацію робить мейнтейнер вручну за `docs/RELEASING.md`.

| Віха | Етапи | Пакети, що додаються | Має бути опубліковано заздалегідь | Готово, коли |
|---|---|---|---|---|
| **REST** ✅ | G1 | `grund`, `grund_http`, `grund_io`, `grund_shelf`, `grund_generator`, `grund_http_generator`, `grund_cli`, `grund_build` (опубліковано `0.1.x`) | — | Здано |
| **Сторінки й сесії** | G7a | `grund_jaspr`, `grund_auth` (лише сесії); шаблон `grund init --template fullstack` | — | G7a здано; крок випуску (`grund_http` з `c.form()` і злиттям `set-cookie` — раніше за нові пакети й `grund_cli`) |
| **Контракт** | G2 | `grund_openapi` | — (typed_openapi T1–T2 потрібні лише контрактним тестам у неопублікованому `example/`) | G2 здано; крок випуску |
| **Дані** | G3 | `grund_basalt`, `grund_basalt_postgres`, `grund_basalt_sqlite` | basalt з B1–B3 | G3 здано; крок випуску |
| **Auth** | G4 | `grund_auth_oauth`; нові можливості `grund_auth` | basalt з B4; token_manager K1 | G4 здано; крок випуску |
| **Realtime** | G5 | `grund_sse`, `grund_redis`, `grund_pubsub` | typed_sse 0.1.0 (S1); typed_openapi з T4 | G5 здано; крок випуску |
| **Інфраструктура** | G6 | `grund_jobs`, `grund_cache`, `grund_storage`, `grund_storage_s3`, `grund_observability` | — (basalt B2 вийшов у віхі «Дані») | G6 здано; крок випуску |
| **WebSocket, гідратація, шаблони** | G7b | `grund_ws`; гідратація в `grund_jaspr`; решта шаблонів `grund_cli init` | — | Гідратація здана 2026-10-18 (гілка `jaspr-hydration`, випуск за мейнтейнером); відкрито: `grund_ws`, решта шаблонів `init` |
| **1.0.0** — стабілізація | G8 | — | typed_openapi 0.1.0 (T5) | Усі пакети `1.0.0`; публічний API заморожено, застарілі члени прибрано, сайт документації, гайд міграції з 0.x, відгуки з 0.x закриті або перенесені |

Етапи:

| # | Етап | Пакети цього репо | Залежить від інших репо | Готово, коли |
|---|---|---|---|---|
| G1 ✅ | **Ядро, HTTP, генератор** (spec `2026-10-15-grund-core-design.md`, вивід `2026-10-15-grund-generated-output-layout-design.md`; плани `2026-10-15-grund-g1-core-http-generator.md` і `...-g1-1-output-layout.md`; перейменування `dartnest*` → `grund*` зроблено) | `grund`, `grund_http`, `grund_generator`, `grund_http_generator`, `grund_cli`, `grund_build`, `grund_io`, `grund_shelf` (анотації: `package:grund/annotations.dart` і `package:grund_http/annotations.dart`) | — | Здано: приклад `tasks_api` у двох формах проходить ті самі e2e на обох адаптерах; `grund` без HTTP у залежностях; golden-фікстура `users_app` на новій моделі (плоский `X.g.dart`, `part` для `@Api`) |
| G7a | **Jaspr SSR і сесії** (spec `2026-10-16-grund-jaspr-design.md`; план `2026-10-16-grund-g7a-jaspr-ssr.md`) | `grund_jaspr`, `grund_auth` (сесії), `grund_http` (`c.form()`, злиття `set-cookie`), `grund_cli` (`init --template fullstack`, автооновлення сторінок у `dev`) | — | `example` віддає SSR-сторінку з даними з DI і вхід через сесію на обох адаптерах; шаблон fullstack проходить свої тести; CI зелений на 3.8.0 і stable; `publish --dry-run` без попереджень |
| G7a-pages | **Сайти й сторінки `grund_jaspr`** (spec `2026-10-16-grund-jaspr-pages-design.md`; план `2026-10-17-grund-jaspr-pages.md`) | `grund_jaspr` (`Pages.site`/`Pages.under`, `PageSite`, `Page`, `PageCatalog`, sitemap, статика в `/static`, `PageExtension`), `grund_cli` (шаблон `fullstack` на сайтах) | — | Здано й випущено 2026-10-17: `grund_jaspr` 0.2.0, `grund_cli` 0.1.3. Клієнтський бандл і гідратацію здано пізніше окремим кроком (G7b, див. нижче). Пакет шару Markdown закрито кроком адрес сторінок (spec `2026-10-17-grund-jaspr-page-addresses-design.md`): `PageAlternate`, `SiteFile`, `baseUrl`, `TrailingSlash`; `PageExtension` вилучено (`grund_jaspr` 0.3.0, `grund_http` 0.3.0, `grund_http_generator` 0.2.0, ще не випущено) |
| G2 | **OpenAPI** | `grund_openapi`; аналіз DTO і валідація полів у генераторі | typed_openapi T1–T2 (контрактний тест) | `GET /openapi.json` з `ETag`, Scalar UI, `export` для CI; RFC 9457 у схемах; контрактний тест: `typed_openapi check` без діагностик, згенерований клієнт проходить e2e прикладу |
| G3 | **Дані** | `grund_basalt`, `grund_basalt_postgres`, `grund_basalt_sqlite` | basalt B1–B3 | Кілька іменованих підключень; `transactionPerRequest`; health-check і метрики пулу; e2e прикладу на Postgres (контейнер у CI) і SQLite in-memory |
| G4 | **Auth** (сесії й cookie вже в G7a) | `grund_auth`, `grund_auth_oauth` | basalt B4; typed_openapi T3; token_manager K1 | JWT-стратегія, refresh-ротація з reuse detection, email+password (argon2id), Google, Apple; `Authenticated`/`Roles`; довговічне сховище сесій; хуки з `SecurityScheme`; Bearer і `httpOnly` cookie; e2e через згенерований клієнт із token_manager |
| G5 | **SSE, Redis, pub/sub** | `grund_sse`, `grund_redis`, `grund_pubsub` | typed_sse S1; typed_openapi T4 | `Stream<T>` з API як SSE з `Last-Event-ID`; fan-out між двома інстансами через Redis; `InMemoryBus`; клієнт typed_openapi читає стрім |
| G6 | **Jobs, cache, storage, observability** | `grund_jobs`, `grund_cache`, `grund_storage`, `grund_storage_s3`, `grund_observability` | basalt B2 (`QueryObserver`) | Redis Streams-черга з retry/DLQ/cron; кеш з тегами; S3 (RustFS у CI); один трейс від HTTP до SQL і джоба в OTLP; `DevExporter` через MCP і `tail` |
| G7b | **WebSocket, гідратація, шаблони** | `grund_ws`, `grund_jaspr` (гідратація, `@client`), шаблони `grund_cli init` | — | JSON-RPC 2.0 канали з AsyncAPI 3; гідратовані компоненти Jaspr у тому ж процесі; решта шаблонів `init` проходить свої тести; іде після кроку адрес сторінок (`Document(base:)` відсутній або `/`, сумісно з гідратацією) |
| G8 | **Стабілізація 1.0** | усі пакети, сайт документації | typed_openapi T5 | Див. рядок 1.0.0 вище |

Гідратація (G7b, spec `2026-10-17-grund-jaspr-hydration-design.md`) здано 2026-10-18 у гілці `jaspr-hydration`, випуск за мейнтейнером (`grund_jaspr` 0.3.1, `grund_cli` 0.3.0): реєстр `ClientComponents` (`client_components.dart`), `JasprConfig(clients:)`, `GrundClient.run` (`client.dart`), `grund bundle`, перезбірка бандла в `grund dev` (`--client-entry`), лічильник у шаблоні `fullstack` і в `example`. У G7b лишаються `grund_ws` і решта шаблонів `init`; політика генераторів (злиття `grund_http_generator` у `grund_generator` з першим новим конструктом) зафіксована в CLAUDE.md і spec §7.
G7b, окремий крок до гідратації: HTML-фрагменти для htmx (`Fragments.respond`) і кешування/стиснення статики в `grund_jaspr` здано; решта G7b не завершена.
Адреси сторінок (канонічний слеш, альтернативи Markdown за `Accept` і власним URL, файли сайту `robots.txt`/`llms.txt`) здано в гілці `jaspr-page-addresses`, випуск за мейнтейнером; це не змінює залишок G7b (`grund_ws`, шаблони; гідратацію здано).

## Після 1.0

`start` зі стеком (TUI, hot reload, підняття Postgres/Redis), GraphQL-адаптер
над typed_graphql (Q1 у роадмапі graphql_dart), 2FA/passkeys/magic links,
Dart WS-клієнт, адаптер `relic`.
