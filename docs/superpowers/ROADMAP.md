# dartnest — роадмап

Спека: `docs/superpowers/specs/2026-10-13-dartnest-design.md`.
Кожен етап — окремий план у `docs/superpowers/plans/`, який дає робоче й
протестоване ПЗ сам по собі. План наступного етапу пишеться після
завершення попереднього, на основі реального коду.

## v1.0 — ядро, HTTP, адаптери, генератор

| # | Етап | Пакети | Готово, коли |
|---|---|---|---|
| 1 | **Ядро DI** (план `2026-10-13-dartnest-core-di.md`) | `dartnest` | `Container.create(module)` з модулями, провайдерами, токенами, областями видимості, жадібною async-ініціалізацією; всі помилки графа — типізовані, з ланцюжком |
| 2 | **HTTP-конвеєр** | `dartnest` | `HttpRequest/HttpResponse`, radix-роутер, `ExecutionContext`, `Controller<T>`/`Route` на `HandlerSpec`, guards → interceptors → pipes → handler → filters, серіалізація, `Application.create`, `app.handle`, `TestClient`; e2e без сервера |
| 3 | **Адаптери** | `dartnest_io`, `dartnest_shelf` | Обидва проходять спільний conformance-набір на реальних сокетах; `shelfHandler(app)` вбудовується в shelf-пайплайн |
| 4 | **Анотації та генератор** | `dartnest_annotations`, `dartnest_generator` | `Collector` → `PackageModel` (з doc-коментарями, типами, `DtoModel`); `ModuleConstruct`, `ProviderConstruct`, `ControllerConstruct`; статична валідація з `path:line:col`; golden-тести; згенерований код проходить ті самі e2e, що явний |
| 5 | **CLI** | `dartnest_cli` | `gen`, `gen --watch`, `init`; analyzer-контекст у пам'яті; бенчмарк: інкремент < 1 с на 200 файлах, холодний старт < 10 с |
| 5b | **Hot reload / hot restart** | `dartnest` (`Container.reassemble`, extension), `dartnest_cli` (`dev`) | `dartnest_cli dev` перезбирає генерований код і робить hot reload зі збереженням стану провайдерів або hot restart; інтеграційний тест: PID не змінюється при reload, змінюється при restart (спека, розділ 10) |
| 6 | **build_runner-драйвер** | `dartnest_build` | Агрегуючий builder на `lib/$lib$` видає байт-у-байт той самий файл, що CLI |
| 7 | **Приклад і документація** | `example/`, README, pub.dev | Один застосунок у двох стилях, e2e на обох адаптерах у CI; README з quick start для обох стилів; публікація `0.1.0` |

Вимоги до ядра заради hot reload (спека, 10.1) діють з етапу 2: `Application.create`
приймає `Module Function()`, `close()` повторюваний, таблиця роутів
підміняється атомарно; `Container.reassemble` додається в етапі 5b, але
етап 1 не повинен ускладнювати його (екземпляри зберігаються за
`(moduleId, key)`).

Ризики v1 та де їх знімаємо:

- Виведення типів у `Provider((i) => X(i.get()))` — перевіряється першими
  тестами етапу 1; якщо Dart не виводить, API міняється до `Provider<X>`.
- Стабільність `analyzer` при власному watch-режимі (досвід Revali) —
  етап 5 пінить версію analyzer і має тест «зміна файлу без перезапуску».
- Швидкість генерації — бенчмарк етапу 5 входить у CI.

## v1.1 — документація API

| # | Етап | Пакети | Готово, коли |
|---|---|---|---|
| 8 | **OpenAPI** | `dartnest_openapi` | `OpenApiConstruct` будує OpenAPI 3.1 без додаткових анотацій; статичний `openapi.json` + `openApiModule(ui: ...)` зі Scalar/Swagger UI |
| 9 | **Lifecycle-хуки** | `dartnest` | `OnModuleInit`, `OnAppShutdown` на провайдерах; graceful shutdown через адаптер |

## v2.0 — GraphQL

| # | Етап | Пакети | Готово, коли |
|---|---|---|---|
| 10 | **Виконавець GraphQL** | `dartnest_graphql` | Парсер, валідація, виконання, інтроспекція за спеціфікацією GraphQL; власна реалізація без `graphql_server2`/`leto` |
| 11 | **Резолвери** | `dartnest_graphql` | `Resolver<T>`/`Field` на `HandlerSpec`, спільний конвеєр з HTTP, `GraphQLTransport` у `ExecutionContext`, `ResolverConstruct` для анотацій `@Resolver`/`@Query`/`@Mutation` |
| 12 | **Subscriptions** | `dartnest_graphql` + адаптери | WebSocket-транспорт в адаптерах (`graphql-transport-ws`) |

## Пізніше (без терміну)

Request-scoped провайдери, адаптер `relic`, мікросервісний транспорт,
scaffolding-CLI.
