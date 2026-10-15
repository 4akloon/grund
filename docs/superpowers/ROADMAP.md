# dartnest — роадмап

Спека: `docs/superpowers/specs/2026-10-13-dartnest-design.md`.
Кожен етап — окремий план у `docs/superpowers/plans/`, який дає робоче й
протестоване ПЗ сам по собі. План наступного етапу пишеться після
завершення попереднього, на основі реального коду.

## v1.0 — ядро, HTTP, адаптери, генератор

| # | Етап | Пакети | Готово, коли |
|---|---|---|---|
| 1 | **Ядро DI** (план `2026-10-13-dartnest-core-di.md`) ✅ | `dartnest` | `Container.create(module)` з модулями, провайдерами, токенами, областями видимості, жадібною async-ініціалізацією; всі помилки графа — типізовані, з ланцюжком |
| 2 | **HTTP-конвеєр** (план `2026-10-13-dartnest-http-pipeline.md`) ✅ | `dartnest` | `HttpRequest/HttpResponse`, radix-роутер, `ExecutionContext`, `Controller<T>`/`Route` на `HandlerSpec`, guards → interceptors → pipes → handler → filters, серіалізація, `Application.create`, `app.handle`, `TestClient`; e2e без сервера |
| 3 | **Адаптери** (план `2026-10-13-dartnest-adapters.md`) ✅ | `dartnest_io`, `dartnest_shelf` | Обидва проходять спільний conformance-набір на реальних сокетах; `shelfHandler(app)` вбудовується в shelf-пайплайн |
| 4 | **Анотації та генератор** (план `2026-10-13-dartnest-annotations-generator.md`) ✅ | `dartnest_annotations`, `dartnest_generator` | `Collector` → `PackageModel` (з doc-коментарями, типами, `DtoModel`); `ModuleConstruct`, `ProviderConstruct`, `ControllerConstruct`; статична валідація з `path:line:col`; golden-тести; згенерований код проходить ті самі e2e, що явний |
| 5 | **CLI** (план `2026-10-14-dartnest-cli.md`) ✅ | `dartnest_cli` | `gen`, `gen --watch`, `init`; analyzer-контекст у пам'яті; бенчмарк: інкремент < 1 с на 200 файлах, холодний старт < 10 с |
| 5b | **Hot reload / hot restart** (план `2026-10-14-dartnest-hot-reload.md`) ✅ | `dartnest` (`Container.reassemble`, extension), `dartnest_cli` (`dev`) | `dartnest_cli dev` перезбирає генерований код і робить hot reload зі збереженням стану провайдерів або hot restart; інтеграційний тест: PID не змінюється при reload, змінюється при restart (спека, розділ 10) |
| 6 | **build_runner-драйвер** (план `2026-10-14-dartnest-build-runner.md`) ✅ | `dartnest_build` | Агрегуючий builder на `lib/$lib$` видає байт-у-байт той самий файл, що CLI |
| 7 | **Приклад, документація, готовність до випуску** (план `2026-10-14-dartnest-example-docs-release.md`) ✅ | `example/`, `README.md`, `docs/`, усі пакети | Один застосунок у двох стилях, e2e на обох адаптерах у CI; README з quick start для обох стилів; кожен публікований пакет проходить `dart pub publish --dry-run` без попереджень. Сама публікація `0.1.0` — ручні кроки мейнтейнера за `docs/RELEASING.md` |

Вимоги до ядра заради hot reload (спека, 10.1) діють з етапу 2: `Application.create`
приймає `Module Function()`, `close()` повторюваний, таблиця роутів
підміняється атомарно; `Container.reassemble` додається в етапі 5b, але
етап 1 не повинен ускладнювати його (екземпляри зберігаються за
`(moduleId, key)`).

Ризики v1 та де їх знімаємо:

- Виведення типів у `Provider((i) => X(i.get()))` — перевіряється першими
  тестами етапу 1; якщо Dart не виводить, API міняється до `Provider<X>`.
- Стабільність `analyzer` при власному watch-режимі (досвід Revali) —
  етап 5 тримає той самий діапазон analyzer, що й генератор
  (`'>=8.1.1 <15.0.0'`, обидва краї перевірено), і має тест «зміна файлу
  без перезапуску» (`packages/dartnest_cli/test/gen_watch_test.dart`).
- Швидкість генерації — бенчмарк етапу 5
  (`cd packages/dartnest_cli && dart test benchmark`) входить у CI.

## v1.1 — документація API

| # | Етап | Пакети | Готово, коли |
|---|---|---|---|
| 8 | **OpenAPI** | `dartnest_openapi` | `OpenApiConstruct` будує OpenAPI 3.1 без додаткових анотацій; статичний `openapi.json` + `openApiModule(ui: ...)` зі Scalar/Swagger UI |
| 9 | **Lifecycle-хуки** | `dartnest` | `OnModuleInit`, `OnAppShutdown` на провайдерах; graceful shutdown через адаптер |

## v2.0 — GraphQL

| # | Етап | Пакети | Готово, коли |
|---|---|---|---|
| 10 | **Адаптер над typed_graphql** | `dartnest_graphql` | Виконавець GraphQL не пишемо: беремо окремий проєкт `typed_graphql` (`typed_graphql_server`). Пакет `dartnest_graphql` — тонкий адаптер: HTTP-маршрут у звичайному контролері перетворює `HttpRequest` на `HttpRequestData`, викликає обробник `typed_graphql_server` і повертає `HttpResponse`; guards/interceptors/filters працюють як для будь-якого маршруту. Обмеження читання тіла (`bodyAs` без ліміту). SDK-поріг пакета `^3.13.0` (поріг `typed_graphql`) — перевірити змішані пороги в workspace |
| 11 | **Контекст і помилки** | `dartnest_graphql` | Guard кладе користувача в `ExecutionContext.items`, фабрика GraphQL-контексту копіює його; сервіси DI доступні резолверам через контекст (резолвери — замикання, бібліотека не інстанціює їх); хук `onError` до маскування помилок; `CancelSignal` з закриття застосунку/таймауту; відповідь на збіг імен `Token`/`@Query` (`as`/`hide`, документація) |
| 12 | **Subscriptions** | `dartnest_graphql` + `typed_graphql_shelf` | WebSocket (`graphql-ws`) монтується з `typed_graphql_shelf` поруч із `shelfHandler(app)` в одному shelf-роутері (в `HttpAdapter` немає апґрейду); автентифікація в `connection_init`; `Transport` розширюємо лише якщо знадобиться конвеєр на рівні полів |

## Пізніше (без терміну)

Request-scoped провайдери, адаптер `relic`, мікросервісний транспорт,
scaffolding-CLI.
