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

## grund: релізи 0.x → 1.0

Випускаємо частинами: кожен реліз дає робочу платформу з тим, що вже є, і
публікується на pub.dev. Обсяг 1.0 — увесь v1 з рамки (auth, realtime,
infra); 0.x — шлях до нього. До 1.0 несумісні зміни дозволені в мінорній
версії й позначаються `**Breaking:**` у CHANGELOG.

Кожен реліз закінчується однаковим кроком випуску: CHANGELOG усіх пакетів,
README і quick start для того, що вже є, приклад покриває всі опубліковані
модулі, `publish --dry-run` без попереджень; публікацію й теги робить
мейнтейнер вручну за `docs/RELEASING.md`. Версія lockstep: усі `grund_*`
мають одну версію; новий пакет зʼявляється з версією свого релізу.

| Реліз | Етапи | Пакети, що додаються | Має бути опубліковано заздалегідь | Готово, коли |
|---|---|---|---|---|
| **0.1.0** — REST з контрактом | G1, G2 | `grund`, `grund_annotations`, `grund_generator`, `grund_build`, `grund_cli`, `grund_http`, `grund_io`, `grund_shelf`, `grund_openapi` | — (typed_openapi T1–T2 потрібні лише контрактним тестам у неопублікованому `example/`) | Етапи G1 і G2 здані; крок випуску |
| **0.2.0** — дані | G3 | `grund_basalt`, `grund_basalt_postgres`, `grund_basalt_sqlite` | basalt з B1–B3 | G3 здано; крок випуску |
| **0.3.0** — auth | G4 | `grund_auth`, `grund_auth_oauth` | basalt з B4; token_manager K1 | G4 здано; крок випуску |
| **0.4.0** — realtime | G5 | `grund_sse`, `grund_redis`, `grund_pubsub` | typed_sse 0.1.0 (S1); typed_openapi з T4 | G5 здано; крок випуску |
| **0.5.0** — інфраструктура | G6 | `grund_jobs`, `grund_cache`, `grund_storage`, `grund_storage_s3`, `grund_observability` | — (basalt B2 вийшов у 0.2.0) | G6 здано; крок випуску |
| **0.6.0** — WebSocket, Jaspr, init | G7 | `grund_ws`, `grund_jaspr`, шаблони `grund_cli init` | — | G7 здано; крок випуску |
| **1.0.0** — стабілізація | G8 | — | typed_openapi 0.1.0 (T5) | Публічний API заморожено, застарілі члени прибрано, сайт документації, гайд міграції з 0.x, відгуки з 0.x закриті або перенесені |

Етапи:

| # | Етап | Пакети цього репо | Залежить від інших репо | Готово, коли |
|---|---|---|---|---|
| G1 | **Ядро, HTTP, генератор** (spec `2026-10-15-grund-core-design.md`; перейменування `dartnest*` → `grund*` уже зроблено) | `grund`, `grund_http`, `grund_generator`, `grund_annotations`, `grund_cli`, `grund_build`, `grund_io`, `grund_shelf` | — | Приклад `tasks_api` у двох формах проходить ті самі e2e на обох адаптерах; `grund` без HTTP у залежностях; golden-фікстура на новій моделі |
| G2 | **OpenAPI** | `grund_openapi`; аналіз DTO і валідація полів у генераторі | typed_openapi T1–T2 (контрактний тест) | `GET /openapi.json` з `ETag`, Scalar UI, `export` для CI; RFC 9457 у схемах; контрактний тест: `typed_openapi check` без діагностик, згенерований клієнт проходить e2e прикладу |
| G3 | **Дані** | `grund_basalt`, `grund_basalt_postgres`, `grund_basalt_sqlite` | basalt B1–B3 | Кілька іменованих підключень; `transactionPerRequest`; health-check і метрики пулу; e2e прикладу на Postgres (контейнер у CI) і SQLite in-memory |
| G4 | **Auth** | `grund_auth`, `grund_auth_oauth` | basalt B4; typed_openapi T3; token_manager K1 | Сесії + JWT-стратегія, refresh-ротація з reuse detection, email+password (argon2id), Google, Apple; хуки з `SecurityScheme`; Bearer і `httpOnly` cookie; e2e через згенерований клієнт із token_manager |
| G5 | **SSE, Redis, pub/sub** | `grund_sse`, `grund_redis`, `grund_pubsub` | typed_sse S1; typed_openapi T4 | `Stream<T>` з API як SSE з `Last-Event-ID`; fan-out між двома інстансами через Redis; `InMemoryBus`; клієнт typed_openapi читає стрім |
| G6 | **Jobs, cache, storage, observability** | `grund_jobs`, `grund_cache`, `grund_storage`, `grund_storage_s3`, `grund_observability` | basalt B2 (`QueryObserver`) | Redis Streams-черга з retry/DLQ/cron; кеш з тегами; S3 (RustFS у CI); один трейс від HTTP до SQL і джоба в OTLP; `DevExporter` через MCP і `tail` |
| G7 | **WebSocket, Jaspr, init** | `grund_ws`, `grund_jaspr`, шаблони `grund_cli init` | — | JSON-RPC 2.0 канали з AsyncAPI 3; Jaspr SSR у тому ж процесі з cookie-сесією; `init` створює api- і fullstack-проєкт, що проходить свої тести |
| G8 | **Стабілізація 1.0** | усі пакети, сайт документації | typed_openapi T5 | Див. рядок 1.0.0 вище |

## Після 1.0

`start` зі стеком (TUI, hot reload, підняття Postgres/Redis), GraphQL-адаптер
над typed_graphql (Q1 у роадмапі graphql_dart), 2FA/passkeys/magic links,
Dart WS-клієнт, адаптер `relic`.
