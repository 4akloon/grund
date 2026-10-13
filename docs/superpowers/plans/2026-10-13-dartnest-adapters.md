# dartnest Adapters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Етап 3 роадмапу: адаптери `dartnest_io` (`IoAdapter` на `dart:io` `HttpServer`) і `dartnest_shelf` (`ShelfAdapter` і `shelfHandler(app)` для вбудовування в наявний shelf-пайплайн); обидва проходять один спільний conformance-набір на реальних сокетах.

**Architecture:** Чотири пакети робочого простору. `dartnest` (ядро) отримує нову бібліотеку `package:dartnest/adapter.dart`, яка відкриває адаптерам наявний `InFlightRequests`, і одну внутрішню зміну: `Application` не рахує запити, які доставив адаптер, — їх чекає `close()` адаптера (рішення 12); сигнатури ядра не змінюються. `dartnest_conformance` (непублікований, лише тестова підтримка) містить застосунок-фікстуру, сирий HTTP-клієнт і три групи тестів (`requests`, `bodies`, `lifecycle`), які адаптерний пакет запускає одним рядком `AdapterConformance.run(name, factory)`. `dartnest_io` — три класи: `IoRequestMapper` (запит `dart:io` → `HttpRequest`), `IoResponseWriter` (`HttpResponse` → відповідь `dart:io`: обрамлення, потоки без буферизації, HEAD) і `IoAdapter` (життєвий цикл сервера, лічильник запитів у польоті з `closeTimeout`, межі помилок). `dartnest_shelf` — `ShelfRequestMapper`/`ShelfResponseMapper`, `ShelfBridge` (shelf `Handler` над `RequestHandler`), `ShelfAdapter` (власний `HttpServer` + `shelf_io.handleRequest`) і функція `shelfHandler(app)`.

**Tech Stack:** Dart SDK ^3.8.0 (без dot shorthands, null-aware elements і primary constructors), `dart:io`, `package:shelf` ^1.4.2 (лише `dartnest_shelf`), `package:test` ^1.25.0, `package:lints` ^5.1.0 + strict-casts/inference/raw-types.

**Spec:** `docs/superpowers/specs/2026-10-13-dartnest-design.md` (розділи 2 «Структура пакетів і шари», 5 «HTTP-адаптер і Application», 8 «Тестування», 10.1 «Вимоги до ядра»); `docs/superpowers/ROADMAP.md`, етап 3.

## Рішення

1. **Conformance-набір живе в окремому непублікованому пакеті `packages/dartnest_conformance`** (dev_dependency обох адаптерів), бо це єдина копія, яку обидва пакети резолвлять через workspace без відносних імпортів між пакетами і без тестового коду в публікованих `lib/`.
2. **`InFlightRequests` відкривається через `package:dartnest/adapter.dart`.** `HttpServer.close()` не чекає активних з'єднань, а лічильник `Application` закінчив би запит, щойно `handle` повернув `HttpResponse`, — до того, як потокове тіло записано в сокет (і запитів адаптера він не рахує взагалі, рішення 12). Тому адаптер рахує власні запити (від прийому до закриття відповіді) і в `close()` чекає їх.
3. **Адаптери і `shelfHandler` мають необов'язковий `onError: ErrorLogger`** (розширення сигнатур зі специфікації `IoAdapter({SecurityContext?})`, `ShelfAdapter()`, `shelfHandler(app)`): сюди йдуть збої, які вже не можна перетворити на відповідь (тіло-потік упав посеред відповіді, клієнт пішов) і збій самого `handler` (можливий лише коли кидає логер застосунку). Типово — друк у stderr.
4. **Сервер шле рівно заголовки відповіді застосунку**: типові заголовки `dart:io` (`content-type: text/plain`, `x-frame-options`, `x-content-type-options`, `x-xss-protection`) очищаються, `x-powered-by` від shelf не додається.
5. **Обрамлення — справа адаптера**: `transfer-encoding` від застосунку відкидається; `BytesBody` → `content-length`; `StreamBody` → chunked, якщо застосунок не задав `content-length`; потоки пишуться без буферизації (кожен чанк іде клієнту, щойно емітований); `connection` від застосунку передається як є (`connection: close` закриває з'єднання); `transfer-encoding` запиту не передається (тіло вже розкодоване).
6. **HEAD**: заголовки ті самі, що в GET (включно з `content-length` для байтів), тіла немає, `StreamBody` скасовується непрочитаним (`dart:io` інакше дочитує потік до кінця, а нескінченний — ніколи).
7. **Шлях для роутингу**: `IoAdapter` бере лише request-target (`Uri.parse`, тож dot-сегменти прибрані), `Host` ігнорується, ціль `//x/y`, яку `dart:io` читає як authority `x`, повертається в шлях. `shelfHandler` бере `request.url` відносно `handlerPath` (застосунок можна змонтувати під префіксом). `ShelfAdapter` бере те саме, що й `shelf_io` (`requestedUri`, побудований з `Host` і цілі).
8. **Невалідне percent-кодування (`%FF`)**: `IoAdapter` віддає запит ядру, яке відповідає JSON 400; `shelf_io` сам відповідає 400 `text/plain` ще до адаптера. Conformance перевіряє лише статус 400.
9. **503 після `close()`** спостерігається лише через `shelfHandler` (сервер належить користувачеві й живе далі); адаптери після `close()` просто не приймають з'єднань (порт звільнено).
10. **Поза планом**: обмеження розміру тіла запиту (адаптери стрімлять тіло без ліміту; ліміт — middleware або пізніший етап), WebSocket/hijack, HTTP/2.
11. **Graceful close має таймаут: `closeTimeout` у конструкторах `IoAdapter` і `ShelfAdapter`** (тип `Duration?`, типово `defaultCloseTimeout` = 30 с, `null` — чекати без обмеження). Не в `HttpAdapter` і не в `Application.close({bool force})`: їхні сигнатури не змінюються, таймаут — властивість сервера, як `securityContext`. `close()` без `force` перестає приймати з'єднання і чекає запити в польоті (разом із відповідями, що ще пишуться); коли `closeTimeout` минув, адаптер робить з рештою з'єднань те саме, що `close(force: true)` (`HttpServer.close(force: true)` обриває їх; порт звільнено ще першим `server.close()`), і `close()` завершується нормально, без помилки. `close(force: true)` не чекає взагалі. Лічильник адаптера після таймауту не обнуляється й не «відпускається»: покинуті запити лишаються в ньому, доки їхній хендлер колись не завершиться (тоді запис в уже обірване з'єднання піде в `onError` межею відповіді), але `close()` на них більше не чекає. Типово 30 с, а не `null`: graceful close, що може висіти вічно (нескінченний потік, завислий хендлер), гірший дефолт — процес не завершиться сам, а оркестратор однаково вб'є його (Kubernetes типово дає 30 с `terminationGracePeriodSeconds`). `null`, а не `Duration.zero`, означає «без ліміту», бо нуль читається як «одразу force». Таймаут зроблено через `Future.timeout(onTimeout:)`, без нового `catch`, тож список меж `on Object` у `CLAUDE.md` не змінюється.
12. **`Application` не рахує запити, які доставив адаптер** (Task 1). Інакше `Application.close()` після `adapter.close()` чекав би свій лічильник, а хендлер, який адаптер покинув після `closeTimeout`, не завершиться ніколи, тож `app.close()` зависав би попри таймаут. `Application.listen` передає адаптеру не `handle`, а внутрішній `_handleForAdapter`: та сама відповідь (і 503 після `close`), але поза лічильником застосунку. Чекати доставлені запити — і так обов'язок `HttpAdapter.close` (без `force` він завершується після запису відповідей), тож лічильник застосунку лишається для прямих викликів `handle` (`TestClient`, `shelfHandler`), як і раніше. `HttpAdapter` змінюється лише в dartdoc контракту (адаптер може обмежити очікування таймаутом).

## Global Constraints

- Ядро `dartnest` лишається без `dart:io` і shelf: нова `lib/adapter.dart` лише експортує `src/app/in_flight_requests.dart` (залежить від `dart:async`). Решта ядра змінюється лише в Task 1: `Application` не рахує запити, доставлені адаптером (рішення 12), а dartdoc `HttpAdapter` дозволяє адаптеру обмежити graceful close таймаутом. Сигнатури `HttpAdapter`, `Application.close({bool force})` і решти публічного API ядра не змінюються.
- Пакети та залежності (специфікація, розділ 2): `dartnest_io` → `dartnest`; `dartnest_shelf` → `dartnest`, `shelf ^1.4.2`; `dartnest_conformance` → `dartnest`, `test`. Dev-залежності адаптерів: `dartnest_conformance`, `lints`, `test`. Інших залежностей немає. Усі пакети: `version: 0.1.0-dev`, `publish_to: none`, `sdk: ^3.8.0`, `resolution: workspace`; кожен додається в `workspace:` кореневого `pubspec.yaml` у задачі, що його створює.
- `package:test` імпортується лише в `test/` і в `dartnest_conformance/lib` (непублікована тестова підтримка; Task 2 фіксує це в `CLAUDE.md`). У `lib/` адаптерів — ніколи.
- `CLAUDE.md`: ≤ 300 рядків на файл у `lib/`, ≤ 500 на тестовий файл, ≤ 40 рядків на метод, ≤ 5 параметрів, ≤ 3 рівні вкладеності; один публічний клас на файл (виняток — функції, які специфікація робить публічним API: `shelfHandler`, `conformanceModule`); без `!`, `dynamic`, `late` без коментаря, `catch` без `on`. Кожна нова межа `on Object` у адаптерах додається до списку меж у `CLAUDE.md` у задачі, що її вводить (Task 5, Task 8).
- Публічний API, dartdoc, README і повідомлення комітів — англійською; кожен публічний клас і член має dartdoc.
- Тести не ходять у мережу: лише `127.0.0.1`/`localhost`, порт 0 (ефемерний), реальні сокети. TLS-тест використовує самопідписаний сертифікат із `packages/dartnest_io/test/fixtures/`.
- Hot reload не блокується: адаптер тримає лише замикання `RequestHandler` (`app.handle`), яке на кожен запит читає поточну таблицю роутів; адаптер нічого не кешує з застосунку.
- Перед кожним комітом: з кореня репо `dart analyze` — «No issues found!», `dart format --output=none --set-exit-if-changed packages` — 0 змінених файлів; `dart test` зелений у кожному пакеті, якого торкнулась задача.
- `dart` не завжди в `PATH`: `export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"`. Після зміни будь-якого `pubspec.yaml` — `dart pub get` з кореня.
- Відхилення від специфікації, зафіксовані планом: `onError` в адаптерах і `shelfHandler` (рішення 3); `closeTimeout` в обох адаптерах (рішення 11); геттер `port` в обох адаптерах (`HttpAdapter` не має способу повідомити порт, прив'язаний до `port: 0`); `ShelfAdapter` маршрутизує як `shelf_io` (рішення 7).

## Review Focus

1. Тіло-потік з дрібними чанками (server-sent events, прогрес): кожен чанк має дійти до клієнта, щойно потік його емітував, а не після 8 КіБ буфера `dart:io`. Закріплено в Task 4 (`flushes each chunk of a streamed response`) і в unit-тесті Task 7 (`streams a stream body without buffering`).
2. `HEAD` на роут, що повертає нескінченний потік: відповідь із заголовками приходить одразу, потік скасовується непрочитаним (`dart:io` інакше дочитує його вічно, а `close()` зависає). Закріплено в Task 4 (`cancels a streamed body for HEAD without reading it`).
3. Ціль `//users//1`: `dart:io` розбирає `//users` як authority; очікується 200 від `GET /users/:id` (порожні сегменти відкидає роутер), а не 404 на `/`. Закріплено в Task 3 через групу `requests` (`reads a target that starts with // as a path`).
4. Клієнт закриває сокет посеред потокової відповіді: адаптер не падає, потік скасовується, сервер обслуговує далі, лічильник у польоті повертається до нуля (наступний `close()` не зависає). Закріплено в Task 5 (`survives a client that leaves mid-response`).
5. Застосунок сам ставить `transfer-encoding: chunked` (скопійовано з проксі): тіло має прийти коректно обрамленим, без подвійного chunked-кодування (shelf вважає таке тіло вже закодованим). Закріплено в Task 4 (`frames the body itself despite an app transfer-encoding`) і в Task 7 (`drops transfer-encoding set by the application`).
6. Хендлер, що ніколи не завершується, і `app.close()` без `force`: після `closeTimeout` з'єднання обривається (клієнт бачить закрите з'єднання), порт вільний, і завершується не лише `close()` адаптера, а й `Application.close()` (не чекає свій лічильник на покинутому хендлері, рішення 12); хендлер, що встиг до таймауту, відповідає повністю; `closeTimeout: null` не діє як нуль. Закріплено в Task 1 (`does not wait for requests the adapter delivered`) і в Task 5 (`close gives up on a stuck handler after closeTimeout`, `close cuts a streaming response after closeTimeout`, `close lets a handler that finishes in time answer`, `close without a closeTimeout waits for a slow handler`).

---

## File Structure

```
pubspec.yaml                                     # workspace: + 3 packages (Tasks 2, 3, 7)
CLAUDE.md                                        # conformance note (Task 2), adapter boundaries (Tasks 5, 8)
docs/superpowers/ROADMAP.md                      # stage 3 row links this plan (Task 10)
packages/dartnest/
  lib/adapter.dart                               # NEW: exports InFlightRequests for adapter packages
  lib/src/app/application.dart                   # requests from the adapter are not counted (Task 1)
  lib/src/app/http_adapter.dart                  # dartdoc: close may be bounded by a timeout (Task 1)
  test/app/in_flight_requests_test.dart          # NEW
  test/app/application_lifecycle_test.dart       # + requests delivered by the adapter (Task 1)
  README.md                                      # last paragraph points to the adapters (Task 10)
packages/dartnest_conformance/                   # NEW, publish_to: none, test support only
  pubspec.yaml, analysis_options.yaml
  lib/dartnest_conformance.dart                  # barrel
  lib/src/adapter_conformance.dart               # AdapterConformance.run(name, factory)
  lib/src/adapter_under_test.dart                # AdapterFactory(onError, closeTimeout), AdapterUnderTest
  lib/src/conformance_probe.dart                 # ConformanceProbe: completers the fixture signals
  lib/src/conformance_data.dart                  # ConformanceData: deterministic payloads, checksum, endless stream
  lib/src/conformance_app.dart                   # conformanceModule(probe): users API + /probe/* routes
  lib/src/conformance_server.dart                # ConformanceServer: app + adapter on 127.0.0.1:0 + HttpClient
  lib/src/client_response.dart                   # ClientResponse: HttpClientResponse read to the end
  lib/src/raw_http.dart                          # RawHttp: raw socket requests (pipelining, '//' targets, aborts)
  lib/src/raw_response.dart                      # RawResponse: parses raw bytes, de-chunks, isComplete
  lib/src/groups/request_conformance.dart        # group 'requests' (Task 2)
  lib/src/groups/body_conformance.dart           # group 'bodies' (Task 4)
  lib/src/groups/lifecycle_conformance.dart      # group 'lifecycle' (Task 5)
  test/conformance_app_test.dart                 # fixture via TestClient, no sockets
  test/raw_http_test.dart                        # RawHttp against a bare dart:io server
packages/dartnest_io/                            # NEW
  pubspec.yaml, analysis_options.yaml, README.md
  lib/dartnest_io.dart                           # barrel: IoAdapter
  lib/src/io_request_mapper.dart                 # IoRequestMapper
  lib/src/io_response_writer.dart                # IoResponseWriter
  lib/src/io_adapter.dart                        # IoAdapter
  test/io_adapter_conformance_test.dart
  test/io_adapter_test.dart
  test/io_adapter_tls_test.dart
  test/fixtures/localhost_cert.pem, localhost_key.pem
packages/dartnest_shelf/                         # NEW
  pubspec.yaml, analysis_options.yaml, README.md
  lib/dartnest_shelf.dart                        # barrel: ShelfAdapter, shelfHandler
  lib/src/shelf_request_mapper.dart              # ShelfRequestMapper
  lib/src/shelf_response_mapper.dart             # ShelfResponseMapper
  lib/src/shelf_bridge.dart                      # ShelfBridge
  lib/src/shelf_adapter.dart                     # ShelfAdapter
  lib/src/shelf_handler.dart                     # shelfHandler(app)
  test/shelf_request_mapper_test.dart
  test/shelf_response_mapper_test.dart
  test/shelf_adapter_conformance_test.dart
  test/shelf_adapter_test.dart
  test/shelf_handler_test.dart
```

Залежності задач: 1 → 5, 8; 2 → 3 → 4 → 5 → 6; 2 → 7 → 8 → 9; 10 — останньою. Task 7 може йти паралельно з 3–6, але Task 8 вимагає групи `bodies` і `lifecycle` (Tasks 4, 5).

### Task 1: Ядро для адаптерів: `InFlightRequests` у `package:dartnest/adapter.dart` і запити адаптера поза лічильником `Application`

`InFlightRequests` (внутрішній клас ядра з етапу 2, `lib/src/app/in_flight_requests.dart`) уже рахує запити `Application`. Адаптерам потрібен такий самий лічильник для власного шару (відповідь у сокеті, рішення 2). Замість копії ядро відкриває його через окрему бібліотеку, яку застосункам імпортувати не потрібно; `package:dartnest/dartnest.dart` не змінюється. Сам клас не змінюється — задача додає точку входу і тести її контракту.

Друга частина (рішення 12): `Application._shutdown` після `adapter.close()` чекає `_inFlight.idle`, а `Application.listen` віддає адаптеру `handle`, тобто кожен доставлений запит рахується і тут. Коли адаптер після `closeTimeout` (Tasks 5, 8) покидає хендлер, що не завершується, `app.close()` зависав би на цьому лічильнику назавжди. Тому `listen` передає адаптеру `_handleForAdapter` — ту саму відповідь без лічильника; `handle` для прямих викликів рахується, як і раніше. Сигнатури не змінюються; dartdoc `HttpAdapter.close` і `Application.close` описує, хто що чекає.

**Files:**
- Create: `packages/dartnest/lib/adapter.dart`
- Modify: `packages/dartnest/lib/src/app/application.dart`
- Modify: `packages/dartnest/lib/src/app/http_adapter.dart` (лише dartdoc)
- Test: `packages/dartnest/test/app/in_flight_requests_test.dart`
- Test: `packages/dartnest/test/app/application_lifecycle_test.dart`

**Interfaces:**
- Consumes: `InFlightRequests` (етап 2, `packages/dartnest/lib/src/app/in_flight_requests.dart`, без змін); `FakeAdapter`, `waitingModule`, `requestFor`, `appModule` (тестові хелпери етапу 2).
- Produces: `package:dartnest/adapter.dart` експортує `final class InFlightRequests { int get count; Future<T> track<T>(Future<T> Function() handle); Future<void> get idle; }` (Tasks 5, 8). `Application.close()` не чекає запити, які доставив адаптер: їх чекає `HttpAdapter.close` (з `closeTimeout` у Tasks 5, 8), тож таймаут адаптера не підвішує `app.close()`.

- [ ] **Step 1: Write the failing test**

`packages/dartnest/test/app/in_flight_requests_test.dart`:

```dart
import 'dart:async';

import 'package:dartnest/adapter.dart';
import 'package:test/test.dart';

void main() {
  group('InFlightRequests', () {
    test('is idle at once when nothing is tracked', () async {
      final requests = InFlightRequests();

      await requests.idle;

      expect(requests.count, 0);
    });

    test('becomes idle when the last tracked operation ends', () async {
      final requests = InFlightRequests();
      final gate = Completer<void>();
      final tracked = requests.track(() => gate.future);
      var idle = false;
      unawaited(requests.idle.then((_) => idle = true));

      await Future<void>.delayed(Duration.zero);
      expect((requests.count, idle), (1, false));

      gate.complete();
      await tracked;
      await requests.idle;
      expect((requests.count, idle), (0, true));
    });

    test('stops counting an operation that fails', () async {
      final requests = InFlightRequests();

      await expectLater(
        requests.track<void>(() async => throw StateError('failed')),
        throwsStateError,
      );

      expect(requests.count, 0);
      await requests.idle;
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run from `packages/dartnest`: `dart test test/app/in_flight_requests_test.dart`
Expected: FAIL на компіляції — `package:dartnest/adapter.dart` не існує.

- [ ] **Step 3: Add the library**

`packages/dartnest/lib/adapter.dart`:

```dart
/// Building blocks for `HttpAdapter` implementations such as `dartnest_io`
/// and `dartnest_shelf`. Applications do not need this library.
library;

export 'src/app/in_flight_requests.dart';
```

- [ ] **Step 4: Run tests to verify they pass**

Run from `packages/dartnest`: `dart test`
Expected: `+239: All tests passed!` (236 наявних + 3 нові).

Run from repo root: `dart analyze && dart format --output=none --set-exit-if-changed packages`
Expected: `No issues found!`, `0 changed`.

- [ ] **Step 5: Commit**

```bash
git add packages/dartnest/lib/adapter.dart packages/dartnest/test/app/in_flight_requests_test.dart
git commit -m "feat(core): expose InFlightRequests to adapter packages"
```

- [ ] **Step 6: Write the failing tests for requests delivered by the adapter**

У `packages/dartnest/test/app/application_lifecycle_test.dart` замінити

```dart
      expect(app.container.isClosed, isTrue);
      gate.complete();
    });
  });
```

на

```dart
      expect(app.container.isClosed, isTrue);
      gate.complete();
    });

    // Review Focus 6: an adapter that gave up on a request after its close
    // timeout must not leave Application.close waiting for it. FakeAdapter
    // closes at once, like an adapter whose timeout has expired.
    test('does not wait for requests the adapter delivered', () async {
      final gate = Completer<void>();
      final adapter = FakeAdapter();
      final app = await Application.create(
        () => waitingModule(gate),
        adapter: adapter,
      );
      await app.listen(port: 0);
      unawaited(adapter.send(requestFor('GET', '/wait')));
      await pumpEventQueue();

      await app.close().timeout(const Duration(seconds: 1));

      expect(app.container.isClosed, isTrue);
      gate.complete();
    });

    test('answers 503 to a request the adapter delivers after close', () async {
      final adapter = FakeAdapter();
      final app = await Application.create(appModule, adapter: adapter);
      await app.listen(port: 0);
      await app.close();

      final response = await adapter.send(requestFor('GET', '/users/1'));

      expect(response.status, 503);
    });
  });
```

- [ ] **Step 7: Run tests to verify they fail**

Run from `packages/dartnest`: `dart test test/app/application_lifecycle_test.dart`
Expected: FAIL — `does not wait for requests the adapter delivered` падає з `TimeoutException` (`close()` чекає лічильник застосунку на хендлері, що не завершується). `answers 503 to a request the adapter delivers after close` проходить уже зараз і стереже нову гілку `_handleForAdapter`.

- [ ] **Step 8: Leave requests delivered by the adapter to the adapter**

У `packages/dartnest/lib/src/app/application.dart` замінити

```dart
  Future<HttpResponse> handle(HttpRequest request) {
    if (isClosed) {
      return Future.value(
        _errors.respond(
          const ServiceUnavailableException(
            message: 'The application is shutting down.',
          ),
          StackTrace.current,
        ),
      );
    }
    final router = _router;
```

на

```dart
  Future<HttpResponse> handle(HttpRequest request) {
    if (isClosed) return _unavailable();
    final router = _router;
```

У тому ж файлі замінити

```dart
      await adapter.listen(handle, address: address, port: port);
```

на

```dart
      await adapter.listen(_handleForAdapter, address: address, port: port);
```

У тому ж файлі замінити

```dart
  /// Stops the application: the adapter stops accepting requests, new
  /// [handle] calls answer 503, in-flight requests finish (unless [force]),
  /// then the container closes. Every call returns the same future; [force]
  /// of later calls is ignored.
```

на

```dart
  /// Stops the application: the adapter stops accepting requests, new
  /// requests answer 503, in-flight requests finish (unless [force]), then
  /// the container closes. Every call returns the same future; [force] of
  /// later calls is ignored.
  ///
  /// The adapter's `close` waits for the requests it delivered and may give
  /// up on them after a timeout of its own; this method then waits for the
  /// [handle] calls made directly, e.g. by `TestClient`.
```

У тому ж файлі замінити

```dart
  Future<void> _shutdown({required bool force}) async {
```

на

```dart
  // Not counted in _inFlight: the adapter's close waits for the requests it
  // delivered and may abandon them after its timeout; counting them here as
  // well would leave close waiting for a handler the adapter gave up on.
  Future<HttpResponse> _handleForAdapter(HttpRequest request) {
    if (isClosed) return _unavailable();
    return _answer(request, _router, List.of(_middleware));
  }

  Future<HttpResponse> _unavailable() => Future.value(
    _errors.respond(
      const ServiceUnavailableException(
        message: 'The application is shutting down.',
      ),
      StackTrace.current,
    ),
  );

  Future<void> _shutdown({required bool force}) async {
```

У `packages/dartnest/lib/src/app/http_adapter.dart` замінити

```dart
/// - [close] stops accepting connections. With `force: false` it completes
///   after the responses in progress are written; with `force: true` it
///   drops open connections. It is idempotent and completes at once if
///   [listen] was never called. `Application.close` calls it before waiting
///   for in-flight requests.
```

на

```dart
/// - [close] stops accepting connections. With `force: false` it completes
///   after the responses in progress are written; an adapter may bound that
///   wait (e.g. a `closeTimeout`) and then drop the remaining connections
///   as `force: true` does. With `force: true` it drops open connections at
///   once. It is idempotent and completes at once if [listen] was never
///   called. `Application.close` calls it first and does not itself wait
///   for the requests the adapter delivered: that wait is the adapter's.
```

- [ ] **Step 9: Run tests to verify they pass**

Run from `packages/dartnest`: `dart test`
Expected: `+241: All tests passed!` (239 після Step 4 + 2 нові).

Run from repo root: `dart analyze && dart format --output=none --set-exit-if-changed packages`
Expected: `No issues found!`, `0 changed`.

- [ ] **Step 10: Commit**

```bash
git add packages/dartnest/lib/src/app packages/dartnest/test/app/application_lifecycle_test.dart
git commit -m "fix(app): leave requests delivered by an adapter to the adapter's close"
```

---

### Task 2: Пакет `dartnest_conformance`: фікстура, сирий HTTP, група `requests`

Спільний conformance-набір (рішення 1). Адаптерний пакет пише один тестовий файл:

```dart
void main() => AdapterConformance.run('IoAdapter', (onError, closeTimeout) {
  final adapter = IoAdapter(onError: onError, closeTimeout: closeTimeout);
  return AdapterUnderTest(adapter, boundPort: () => adapter.port);
});
```

Фабрика отримує `onError` адаптера і `closeTimeout` (рішення 11), який тест може задати в `ConformanceServer.start`; типово — `ConformanceServer.defaultCloseTimeout` (30 с, більше за будь-яке очікування тестів). Кожен тест групи створює свіжий `ConformanceServer`: `Application.create(() => conformanceModule(probe), adapter: ..., onError: ...)`, `app.listen(port: 0, address: InternetAddress.loopbackIPv4)`, `HttpClient` з `maxConnectionsPerHost = 1` (щоб повторне використання keep-alive з'єднання було видно за локальним портом) і записані помилки адаптера й застосунку. Фікстура — маленький users API (`GET /users/:id`, `POST /users` → 201 + `location`) і службові роути `/probe/*`: ехо запиту, сегмент, завантаження з контрольною сумою, потокове й in-memory скачування, потік на «воротах» `ConformanceProbe`, повільний хендлер, нескінченний потік, потік, що падає, кілька `set-cookie`, `transfer-encoding` і `connection: close` від застосунку, 204, хендлер, що кидає. `RawHttp` пише запити просто в сокет: конвеєрні запити, цілі `//users//1` і `%FF`, які `HttpClient` не відправить, обрив після перших байтів; `RawResponse` розбирає відповідь і розкодовує chunked, позначаючи обірвану.

У цій задачі `AdapterConformance.run` реєструє лише групу `requests`; `bodies` додає Task 4, `lifecycle` — Task 5. Групу `requests` уперше запускає адаптер у Task 3; тут вона лише компілюється. Власні тести пакета перевіряють фікстуру без сокетів (через `TestClient`) і `RawHttp` проти голого `dart:io`-сервера.

**Files:**
- Modify: `pubspec.yaml` (корінь, `workspace:`)
- Modify: `CLAUDE.md` (абзац **Tests.**)
- Create: `packages/dartnest_conformance/pubspec.yaml`
- Create: `packages/dartnest_conformance/analysis_options.yaml`
- Create: `packages/dartnest_conformance/lib/dartnest_conformance.dart`
- Create: `packages/dartnest_conformance/lib/src/adapter_under_test.dart`
- Create: `packages/dartnest_conformance/lib/src/conformance_probe.dart`
- Create: `packages/dartnest_conformance/lib/src/conformance_data.dart`
- Create: `packages/dartnest_conformance/lib/src/conformance_app.dart`
- Create: `packages/dartnest_conformance/lib/src/client_response.dart`
- Create: `packages/dartnest_conformance/lib/src/conformance_server.dart`
- Create: `packages/dartnest_conformance/lib/src/raw_response.dart`
- Create: `packages/dartnest_conformance/lib/src/raw_http.dart`
- Create: `packages/dartnest_conformance/lib/src/groups/request_conformance.dart`
- Create: `packages/dartnest_conformance/lib/src/adapter_conformance.dart`
- Test: `packages/dartnest_conformance/test/conformance_app_test.dart`
- Test: `packages/dartnest_conformance/test/raw_http_test.dart`

**Interfaces:**
- Consumes: `Application.create(Module Function(), {HttpAdapter? adapter, ErrorLogger? onError})`, `Application.listen({required int port, Object address})`, `Application.close({bool force})`, `HttpAdapter`, `ErrorLogger`, `Module`, `Controller`, `Route`, `HttpResponse`, `HeaderMap`, `TestClient` (етап 2).
- Produces (усе з `package:dartnest_conformance/dartnest_conformance.dart`):
  - `typedef AdapterFactory = AdapterUnderTest Function(ErrorLogger onError, Duration? closeTimeout);`
  - `final class AdapterUnderTest { const AdapterUnderTest(HttpAdapter adapter, {required int Function() boundPort}); }`
  - `abstract final class AdapterConformance { static void run(String name, AdapterFactory factory); }` — реєструє `group('$name conformance', ...)`.
  - `final class ConformanceServer { static const Duration defaultCloseTimeout; static Future<ConformanceServer> start(AdapterFactory factory, {ErrorLogger? applicationLogger, Duration? closeTimeout = defaultCloseTimeout}); Application app; int port; ConformanceProbe probe; HttpClient client; List<Object> adapterErrors; List<Object> applicationErrors; Future<Object> firstAdapterError; Uri uri(String target); Future<ClientResponse> send(String method, String target, {Map<String, String> headers, List<int>? body}); Future<void> close(); }`
  - `final class ConformanceProbe { Completer<void> entered, release, firstUploadChunk, endlessCancelled; }`
  - `abstract final class ConformanceData { static const chunkSize; static Uint8List bytes(int); static Stream<List<int>> chunks(int); static int checksum(Iterable<int>); static Stream<List<int>> endless(void Function() onCancel); }`
  - `Module conformanceModule(ConformanceProbe probe)`
  - `final class ClientResponse { static Future<ClientResponse> read(HttpClientResponse); int status; HttpHeaders headers; Uint8List bytes; int localPort; String text; Object? json; }`
  - `abstract final class RawHttp { static String head(String method, String target, {Map<String, String> headers = const {'Connection': 'close'}}); static Future<RawResponse> exchange(int port, String request); static Future<void> abortAfterFirstBytes(int port, String request); }`
  - `final class RawResponse { factory RawResponse.parse(Uint8List bytes); int status; HeaderMap headers; Uint8List bytes; Uint8List body; bool isComplete; String text; Object? json; }`

- [ ] **Step 1: Register the package in the workspace**

Корінь `pubspec.yaml`, список `workspace:`:

```yaml
workspace:
  - packages/dartnest
  - packages/dartnest_conformance
```

`packages/dartnest_conformance/pubspec.yaml`:

```yaml
name: dartnest_conformance
description: >-
  The shared conformance suite that every dartnest HTTP adapter runs on real
  loopback sockets. Test support only; not published.
version: 0.1.0-dev
publish_to: none
environment:
  sdk: ^3.8.0
resolution: workspace
dependencies:
  dartnest: ^0.1.0-dev
  test: ^1.25.0
dev_dependencies:
  lints: ^5.1.0
```

`packages/dartnest_conformance/analysis_options.yaml`:

```yaml
include: ../../analysis_options.yaml
```

Run from repo root: `dart pub get`
Expected: `Got dependencies!` (`dartnest` резолвиться з робочого простору).

- [ ] **Step 2: Write the failing tests**

`packages/dartnest_conformance/test/conformance_app_test.dart`:

```dart
import 'dart:convert';

import 'package:dartnest/dartnest.dart';
import 'package:dartnest/testing.dart';
import 'package:dartnest_conformance/dartnest_conformance.dart';
import 'package:test/test.dart';

void main() {
  group('conformanceModule', () {
    late ConformanceProbe probe; // Set in setUp before every test.
    late Application app; // Set in setUp before every test.
    late TestClient client; // Set in setUp before every test.

    setUp(() async {
      probe = ConformanceProbe();
      app = await Application.create(() => conformanceModule(probe));
      client = TestClient(app);
    });
    tearDown(() => app.close());

    test('serves the users API', () async {
      final created = await client.post('/users', json: {'name': 'cid'});

      expect((await client.get('/users/1')).json, {'id': 1, 'name': 'ann'});
      expect((created.status, created.headers['location']), (201, '/users/3'));
      expect((await client.get('/users/9')).status, 404);
    });

    test('echoes the request', () async {
      final response = await client.request(
        'PUT',
        '/probe/echo?b=%20x',
        body: 'hi',
        headers: {'X-Multi': 'a'},
      );

      expect(response.json, {
        'method': 'PUT',
        'path': '/probe/echo',
        'query': 'b=%20x',
        'headers': {
          'x-multi': ['a'],
        },
        'body': 'hi',
        'remoteAddress': null,
        'remotePort': null,
      });
    });

    test('streams an upload and reports its length and checksum', () async {
      final response = await client.send(
        HttpRequest(
          method: 'POST',
          uri: Uri.parse('/probe/upload'),
          body: RequestBody(ConformanceData.chunks(200000)),
        ),
      );

      expect(response.json, {
        'length': 200000,
        'checksum': ConformanceData.checksum(ConformanceData.bytes(200000)),
      });
      expect(probe.firstUploadChunk.isCompleted, isTrue);
    });

    test('downloads the payload streamed and in memory', () async {
      final streamed = await client.get('/probe/download?size=100000');
      final fixed = await client.get('/probe/download-fixed?size=100000');

      expect(streamed.bytes, ConformanceData.bytes(100000));
      expect(fixed.bytes, ConformanceData.bytes(100000));
    });

    test('holds the gated stream until the probe releases it', () async {
      final response = await app.handle(
        HttpRequest(method: 'GET', uri: Uri.parse('/probe/gated-stream')),
      );
      final body = response.body.readAll();

      await probe.entered.future;
      probe.release.complete();

      expect(utf8.decode(await body), 'first;last');
    });

    test('reports when the endless stream is cancelled', () async {
      final response = await app.handle(
        HttpRequest(method: 'GET', uri: Uri.parse('/probe/endless')),
      );
      final subscription = switch (response.body) {
        StreamBody(:final stream) => stream.listen(null),
        BytesBody() => fail('expected a stream body'),
      };

      await subscription.cancel();

      expect(probe.endlessCancelled.isCompleted, isTrue);
    });

    test('fails the broken stream after one chunk', () async {
      final response = await app.handle(
        HttpRequest(method: 'GET', uri: Uri.parse('/probe/broken-stream')),
      );

      await expectLater(response.body.readAll(), throwsStateError);
    });

    test('sends repeated headers and framing edge cases', () async {
      final cookies = await client.get('/probe/cookies');

      expect(cookies.headers.all('set-cookie'), ['a=1', 'b=2']);
      expect(cookies.headers.all('x-multi'), ['one', 'two']);
      expect(
        (await client.get('/probe/framing')).headers['transfer-encoding'],
        'chunked',
      );
      expect((await client.get('/probe/empty')).status, 204);
      expect((await client.get('/probe/fail')).status, 500);
    });
  });
}
```

`packages/dartnest_conformance/test/raw_http_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:dartnest_conformance/dartnest_conformance.dart';
import 'package:test/test.dart';

/// Serves [answer] with a bare `dart:io` server on a loopback port.
Future<HttpServer> serve(Future<void> Function(HttpRequest) answer) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(answer);
  addTearDown(() => server.close(force: true));
  return server;
}

void main() {
  group('RawHttp', () {
    test('builds a request head with Host and Connection: close', () {
      expect(
        RawHttp.head('GET', '/a?b'),
        'GET /a?b HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n',
      );
    });

    test('reads a content-length response', () async {
      // Written by hand: dart:io frames even a short body as chunked. A
      // second pipelined response follows, so only content-length tells
      // where the first body ends.
      final server = await serve((request) async {
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.write('HTTP/1.1 200 OK\r\ncontent-length: 5\r\n\r\nhello');
        socket.write('HTTP/1.1 200 OK\r\ncontent-length: 2\r\n\r\nno');
        await socket.flush();
        socket.destroy();
      });

      final response = await RawHttp.exchange(
        server.port,
        RawHttp.head('GET', '/'),
      );

      expect(response.status, 200);
      expect(response.headers['content-length'], '5');
      expect((response.text, response.isComplete), ('hello', true));
    });

    test('de-chunks a chunked response', () async {
      final server = await serve((request) async {
        request.response
          ..write('ab')
          ..write('cd');
        await request.response.close();
      });

      final response = await RawHttp.exchange(
        server.port,
        RawHttp.head('GET', '/'),
      );

      expect(response.headers['transfer-encoding'], 'chunked');
      expect((response.text, response.isComplete), ('abcd', true));
    });

    test('marks a chunked body cut short as incomplete', () async {
      final server = await serve((request) async {
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.write('HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\n\r\n');
        socket.write('4\r\nab');
        await socket.flush();
        socket.destroy();
      });

      final response = await RawHttp.exchange(
        server.port,
        RawHttp.head('GET', '/'),
      );

      expect((response.status, response.isComplete), (200, false));
    });

    test('marks a response without a complete head as incomplete', () {
      final response = RawResponse.parse(
        Uint8List.fromList('HTTP/1.1 200'.codeUnits),
      );

      expect((response.status, response.isComplete), (0, false));
    });
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run from `packages/dartnest_conformance`: `dart test`
Expected: FAIL на компіляції — `package:dartnest_conformance/dartnest_conformance.dart` не існує.

- [ ] **Step 4: Write the fixture and its support classes**

`packages/dartnest_conformance/lib/src/adapter_under_test.dart`:

```dart
import 'package:dartnest/dartnest.dart';

/// Creates the adapter under test; [onError] receives the failures the
/// adapter reports itself (a throwing handler, a failing body stream), and
/// [closeTimeout] is the adapter's limit for a graceful close (`null`: no
/// limit).
typedef AdapterFactory =
    AdapterUnderTest Function(ErrorLogger onError, Duration? closeTimeout);

/// An adapter for the conformance suite and how to read the port it bound;
/// the suite always listens on port 0.
final class AdapterUnderTest {
  /// Wraps [adapter]; [boundPort] is called after `listen` completed.
  const AdapterUnderTest(this.adapter, {required this.boundPort});

  /// The adapter passed to `Application.create`.
  final HttpAdapter adapter;

  /// The port the adapter listens on.
  final int Function() boundPort;
}
```

`packages/dartnest_conformance/lib/src/conformance_probe.dart`:

```dart
import 'dart:async';

/// Lets a test hold the fixture's slow handlers and observe its streams.
///
/// Created per test by `ConformanceServer.start`; every completer is used
/// at most once.
final class ConformanceProbe {
  /// Completes when `GET /probe/slow` or `GET /probe/gated-stream` starts
  /// waiting for [release].
  final Completer<void> entered = Completer<void>();

  /// Completed by the test to let the waiting handler or stream finish.
  final Completer<void> release = Completer<void>();

  /// Completes when `POST /probe/upload` received its first chunk.
  final Completer<void> firstUploadChunk = Completer<void>();

  /// Completes when the subscription to the `GET /probe/endless` stream is
  /// cancelled.
  final Completer<void> endlessCancelled = Completer<void>();
}
```

`packages/dartnest_conformance/lib/src/conformance_data.dart` (нескінченний потік — `StreamController`, а не `async*`: генератор, скасований до першого запуску, не доходить до `finally`, і тест HEAD не побачив би скасування):

```dart
import 'dart:async';
import 'dart:typed_data';

/// Deterministic payloads for body tests: byte `i` is `i % 251`, so a
/// shifted or lost chunk changes the checksum.
abstract final class ConformanceData {
  /// Size of the chunks [chunks] emits.
  static const chunkSize = 64 * 1024;

  /// The payload of [length] bytes.
  static Uint8List bytes(int length) =>
      Uint8List.fromList([for (var i = 0; i < length; i++) i % 251]);

  /// The payload of [length] bytes as a stream of [chunkSize] chunks.
  static Stream<List<int>> chunks(int length) async* {
    for (var start = 0; start < length; start += chunkSize) {
      final end = start + chunkSize < length ? start + chunkSize : length;
      yield Uint8List.fromList([for (var i = start; i < end; i++) i % 251]);
    }
  }

  /// Adler-style checksum of [bytes] (sum modulo 65521).
  static int checksum(Iterable<int> bytes) =>
      bytes.fold(0, (sum, byte) => (sum + byte) % 65521);

  /// A stream that emits 16 KiB chunks every millisecond until it is
  /// cancelled, then calls [onCancel]. A plain controller rather than an
  /// `async*` body: a generator cancelled before its first run never
  /// reaches its `finally`.
  static Stream<List<int>> endless(void Function() onCancel) {
    final chunk = Uint8List(16 * 1024);
    final controller = StreamController<List<int>>();
    Timer? timer;
    void start() => timer = Timer.periodic(
      const Duration(milliseconds: 1),
      (_) => controller.add(chunk),
    );
    void stop() => timer?.cancel();
    controller
      ..onListen = start
      ..onPause = stop
      ..onResume = start
      ..onCancel = () {
        stop();
        onCancel();
      };
    return controller.stream;
  }
}
```

`packages/dartnest_conformance/lib/src/conformance_app.dart` (`conformanceModule` — функція-фабрика модуля, дозволений виняток з правила «класи замість top-level функцій»):

```dart
import 'dart:async';
import 'dart:convert';

import 'package:dartnest/dartnest.dart';

import 'conformance_data.dart';
import 'conformance_probe.dart';

/// The application every adapter serves in the conformance suite: a small
/// users API plus `/probe` routes that expose what the adapter delivered.
///
/// - `GET /users/:id`, `POST /users` (`{"name"}` → 201 with `location`).
/// - `GET|POST|PUT|PATCH|DELETE /probe/echo`: method, path, raw query,
///   every header value, the body as text and the client address.
/// - `GET /probe/segments/:value`: the decoded path parameter.
/// - `POST /probe/upload`: streams the body; answers its length and
///   checksum.
/// - `GET /probe/download?size=n` (streamed) and
///   `GET /probe/download-fixed?size=n` (in memory): [ConformanceData].
/// - `GET /probe/gated-stream`, `GET /probe/slow`, `GET /probe/endless`:
///   wait for or report through the [ConformanceProbe].
/// - `GET /probe/broken-stream`: a body stream that fails after a chunk.
/// - `GET /probe/cookies`, `/probe/framing`, `/probe/close-connection`,
///   `/probe/empty`, `/probe/fail`: header and error edge cases.
Module conformanceModule(ConformanceProbe probe) => Module(
  id: 'conformance',
  providers: [Provider.value(probe), Provider((i) => ConformanceUsers())],
  controllers: [_usersController, _probeController],
);

/// In-memory users of the conformance application.
final class ConformanceUsers {
  final Map<int, String> _names = {1: 'ann', 2: 'bob'};

  /// The user with [id] as JSON; [NotFoundException] when absent.
  Map<String, Object?> find(int id) => switch (_names[id]) {
    final name? => {'id': id, 'name': name},
    null => throw NotFoundException(message: 'No user $id'),
  };

  /// Adds a user called [name] and returns it as JSON.
  Map<String, Object?> create(String name) {
    final id = _names.length + 1;
    _names[id] = name;
    return find(id);
  }
}

final _usersController = Controller<ConformanceUsers>(
  path: '/users',
  create: (i) => i.get(),
  routes: [
    Route.get('/:id', (users, ctx) async => users.find(await ctx.param('id'))),
    Route.post('/', (users, ctx) async {
      final name = await ctx.bodyAs(
        (json) => switch (json) {
          {'name': final String name} => name,
          _ => throw const FormatException('"name" must be a string'),
        },
      );
      final user = users.create(name);
      ctx.switchToHttp().response
        ..status = StatusCode.created
        ..headers.set('location', '/users/${user['id']}');
      return user;
    }),
  ],
);

final _probeController = Controller<ConformanceProbe>(
  path: '/probe',
  create: (i) => i.get(),
  routes: [
    Route.get('/echo', (_, ctx) => _ProbeHandlers.echo(ctx)),
    Route.post('/echo', (_, ctx) => _ProbeHandlers.echo(ctx)),
    Route.put('/echo', (_, ctx) => _ProbeHandlers.echo(ctx)),
    Route.patch('/echo', (_, ctx) => _ProbeHandlers.echo(ctx)),
    Route.delete('/echo', (_, ctx) => _ProbeHandlers.echo(ctx)),
    Route.get(
      '/segments/:value',
      (_, ctx) async => {'value': await ctx.param<String>('value')},
    ),
    Route.post('/upload', _ProbeHandlers.upload),
    Route.get(
      '/download',
      (_, ctx) async =>
          HttpResponse.stream(ConformanceData.chunks(await ctx.query('size'))),
    ),
    Route.get(
      '/download-fixed',
      (_, ctx) async =>
          HttpResponse.bytes(ConformanceData.bytes(await ctx.query('size'))),
    ),
    Route.get(
      '/gated-stream',
      (probe, _) => HttpResponse.stream(_ProbeHandlers.gated(probe)),
    ),
    Route.get('/slow', (probe, _) async {
      probe.entered.complete();
      await probe.release.future;
      return 'done';
    }),
    Route.get(
      '/endless',
      (probe, _) => HttpResponse.stream(
        ConformanceData.endless(probe.endlessCancelled.complete),
      ),
    ),
    Route.get(
      '/broken-stream',
      (_, _) => HttpResponse.stream(_ProbeHandlers.broken()),
    ),
    Route.get('/cookies', (_, _) => _ProbeHandlers.cookies()),
    Route.get(
      '/framing',
      (_, _) => HttpResponse.text(
        'framed',
        headers: HeaderMap.of({'transfer-encoding': 'chunked'}),
      ),
    ),
    Route.get(
      '/close-connection',
      (_, _) => HttpResponse.text(
        'bye',
        headers: HeaderMap.of({'connection': 'close'}),
      ),
    ),
    Route.get('/empty', (_, _) => null),
    Route.get('/fail', (_, _) => throw StateError('handler failure')),
  ],
);

/// Handlers of the probe routes that do not fit in one expression.
abstract final class _ProbeHandlers {
  static Future<Map<String, Object?>> echo(ExecutionContext ctx) async {
    final request = ctx.switchToHttp().request;
    return {
      'method': request.method,
      'path': request.uri.path,
      'query': request.uri.query,
      'headers': {
        for (final name in request.headers.names)
          name: request.headers.all(name),
      },
      'body': await request.body.text(),
      'remoteAddress': request.connectionInfo?.remoteAddress,
      'remotePort': request.connectionInfo?.remotePort,
    };
  }

  static Future<Map<String, Object?>> upload(
    ConformanceProbe probe,
    ExecutionContext ctx,
  ) async {
    var length = 0;
    var checksum = 0;
    await for (final chunk in ctx.body.stream) {
      if (!probe.firstUploadChunk.isCompleted) {
        probe.firstUploadChunk.complete();
      }
      length += chunk.length;
      checksum = (checksum + ConformanceData.checksum(chunk)) % 65521;
    }
    return {'length': length, 'checksum': checksum};
  }

  static Stream<List<int>> gated(ConformanceProbe probe) async* {
    yield utf8.encode('first;');
    probe.entered.complete();
    await probe.release.future;
    yield utf8.encode('last');
  }

  static Stream<List<int>> broken() async* {
    yield utf8.encode('partial');
    // Gives the adapter time to flush the first chunk before the failure.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    throw StateError('broken body stream');
  }

  static HttpResponse cookies() => HttpResponse.text(
    'cookies',
    headers: HeaderMap()
      ..add('set-cookie', 'a=1')
      ..add('set-cookie', 'b=2')
      ..add('x-multi', 'one')
      ..add('x-multi', 'two'),
  );
}
```

`packages/dartnest_conformance/lib/src/client_response.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A response received through `HttpClient`, with the whole body read.
final class ClientResponse {
  /// Creates the response.
  ClientResponse({
    required this.status,
    required this.headers,
    required this.bytes,
    required this.localPort,
  });

  /// Reads [response] to the end.
  static Future<ClientResponse> read(HttpClientResponse response) async {
    final body = BytesBuilder(copy: false);
    await response.forEach(body.add);
    return ClientResponse(
      status: response.statusCode,
      headers: response.headers,
      bytes: body.takeBytes(),
      localPort: response.connectionInfo?.localPort ?? 0,
    );
  }

  /// Status code.
  final int status;

  /// Response headers as `dart:io` parsed them.
  final HttpHeaders headers;

  /// The body.
  final Uint8List bytes;

  /// The client-side port of the connection the response came on.
  final int localPort;

  /// [bytes] decoded as UTF-8.
  String get text => utf8.decode(bytes);

  /// [text] decoded as JSON.
  Object? get json => jsonDecode(text);
}
```

`packages/dartnest_conformance/lib/src/conformance_server.dart` (`close()` закриває застосунок з `force: true` і відпускає «ворота», щоб тест, що впав посередині, не підвісив набір):

```dart
import 'dart:async';
import 'dart:io';

import 'package:dartnest/dartnest.dart';

import 'adapter_under_test.dart';
import 'client_response.dart';
import 'conformance_app.dart';
import 'conformance_probe.dart';

/// The conformance application served by one adapter on 127.0.0.1 and an
/// ephemeral port, with an `HttpClient` and the errors both sides
/// reported.
final class ConformanceServer {
  ConformanceServer._(this.app, this.port, this.probe, this._errors);

  /// The adapter's `closeTimeout` unless a test sets one: longer than any
  /// wait in the suite, so only the timeout tests reach it.
  static const defaultCloseTimeout = Duration(seconds: 30);

  /// Creates the application with the adapter from [factory] and listens.
  /// [applicationLogger] replaces the recording `onError` of the
  /// application (to test a logger that throws); [closeTimeout] goes to
  /// the adapter.
  static Future<ConformanceServer> start(
    AdapterFactory factory, {
    ErrorLogger? applicationLogger,
    Duration? closeTimeout = defaultCloseTimeout,
  }) async {
    final probe = ConformanceProbe();
    final errors = _ReportedErrors();
    final underTest = factory(errors.adapter, closeTimeout);
    final app = await Application.create(
      () => conformanceModule(probe),
      adapter: underTest.adapter,
      onError: applicationLogger ?? errors.application,
    );
    await app.listen(port: 0, address: InternetAddress.loopbackIPv4);
    return ConformanceServer._(app, underTest.boundPort(), probe, errors);
  }

  /// The served application.
  final Application app;

  /// The port the adapter bound.
  final int port;

  /// The probe of this server's fixture.
  final ConformanceProbe probe;

  final _ReportedErrors _errors;

  /// A client with at most one connection, so keep-alive reuse is visible.
  final HttpClient client = HttpClient()..maxConnectionsPerHost = 1;

  /// Errors the adapter reported through its `onError`.
  List<Object> get adapterErrors => _errors.fromAdapter;

  /// Errors the application logged (500 responses).
  List<Object> get applicationErrors => _errors.fromApplication;

  /// Completes with the first error the adapter reports.
  Future<Object> get firstAdapterError => _errors.firstFromAdapter.future;

  /// `http://127.0.0.1:port` + [target].
  Uri uri(String target) => Uri.parse('http://127.0.0.1:$port$target');

  /// Sends [method] to [target] with [headers] and [body]; reads the whole
  /// response.
  Future<ClientResponse> send(
    String method,
    String target, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    final request = await client.openUrl(method, uri(target));
    headers.forEach(request.headers.add);
    if (body != null) request.add(body);
    return ClientResponse.read(await request.close());
  }

  /// Closes the client and the application (forcefully, so a test that
  /// failed midway does not hang the suite) and releases waiting handlers.
  Future<void> close() async {
    if (!probe.release.isCompleted) probe.release.complete();
    client.close(force: true);
    await app.close(force: true);
  }
}

/// Collects what the adapter and the application report.
final class _ReportedErrors {
  final List<Object> fromAdapter = [];
  final List<Object> fromApplication = [];
  final Completer<Object> firstFromAdapter = Completer<Object>();

  void adapter(Object error, StackTrace _) {
    fromAdapter.add(error);
    if (!firstFromAdapter.isCompleted) firstFromAdapter.complete(error);
  }

  void application(Object error, StackTrace _) => fromApplication.add(error);
}
```

- [ ] **Step 5: Write the raw HTTP client**

`packages/dartnest_conformance/lib/src/raw_response.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartnest/dartnest.dart';

/// A response read byte for byte from a socket by `RawHttp`: what
/// `HttpClient` hides (the exact header lines, the bytes after a `HEAD`
/// response, a chunked body that never ended).
final class RawResponse {
  RawResponse._({
    required this.bytes,
    required this.status,
    required this.headers,
    required this.body,
    required this.isComplete,
  });

  /// Parses the first response in [bytes]. Without a complete head the
  /// status is 0 and the response is incomplete.
  factory RawResponse.parse(Uint8List bytes) {
    final headEnd = _indexOf(bytes, const [13, 10, 13, 10]);
    if (headEnd < 0) {
      return RawResponse._(
        bytes: bytes,
        status: 0,
        headers: HeaderMap(),
        body: Uint8List(0),
        isComplete: false,
      );
    }
    final lines = latin1.decode(bytes.sublist(0, headEnd)).split('\r\n');
    final headers = HeaderMap();
    for (final line in lines.skip(1)) {
      final colon = line.indexOf(':');
      headers.add(
        line.substring(0, colon).trim(),
        line.substring(colon + 1).trim(),
      );
    }
    final rest = bytes.sublist(headEnd + 4);
    final (body, isComplete) = _readBody(rest, headers);
    return RawResponse._(
      bytes: bytes,
      status: int.parse(lines.first.split(' ')[1]),
      headers: headers,
      body: body,
      isComplete: isComplete,
    );
  }

  /// Everything the server sent before closing the connection.
  final Uint8List bytes;

  /// Status code of the first response; 0 without a complete head.
  final int status;

  /// Header lines of the first response; a folded line is one value.
  final HeaderMap headers;

  /// The body after content-length or chunked decoding.
  final Uint8List body;

  /// Whether the body ended as its framing promised.
  final bool isComplete;

  /// [body] decoded as UTF-8.
  String get text => utf8.decode(body);

  /// [text] decoded as JSON.
  Object? get json => jsonDecode(text);

  static (Uint8List, bool) _readBody(Uint8List rest, HeaderMap headers) {
    if (headers['transfer-encoding'] == 'chunked') return _dechunk(rest);
    final length = int.tryParse(headers['content-length'] ?? '');
    if (length == null) return (rest, true);
    if (rest.length < length) return (rest, false);
    return (rest.sublist(0, length), true);
  }

  static (Uint8List, bool) _dechunk(Uint8List data) {
    final body = BytesBuilder(copy: false);
    var offset = 0;
    while (true) {
      final lineEnd = _indexOf(data, const [13, 10], offset);
      if (lineEnd < 0) return (body.takeBytes(), false);
      final sizeText = latin1.decode(data.sublist(offset, lineEnd));
      final size = int.parse(sizeText.split(';').first.trim(), radix: 16);
      if (size == 0) return (body.takeBytes(), true);
      final start = lineEnd + 2;
      if (data.length < start + size + 2) return (body.takeBytes(), false);
      body.add(data.sublist(start, start + size));
      offset = start + size + 2;
    }
  }

  static int _indexOf(Uint8List data, List<int> pattern, [int from = 0]) {
    for (var i = from; i <= data.length - pattern.length; i++) {
      var matches = true;
      for (var j = 0; j < pattern.length && matches; j++) {
        matches = data[i + j] == pattern[j];
      }
      if (matches) return i;
    }
    return -1;
  }
}
```

`packages/dartnest_conformance/lib/src/raw_http.dart` (читає до закриття з'єднання, тож запит, після якого сервер має закрити з'єднання, несе `Connection: close`; `SocketException` при читанні після обриву — не помилка тесту):

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'raw_response.dart';

/// HTTP/1.1 over a plain loopback socket, for requests `HttpClient` would
/// normalize (dot segments, a target starting with `//`, pipelining) and
/// for reading exactly what the server wrote.
abstract final class RawHttp {
  /// How long a raw exchange may take before the test fails.
  static const timeout = Duration(seconds: 10);

  /// The head of a request for [method] and [target] with `Host` and
  /// [headers]; add `Connection: close` to make [exchange] end.
  static String head(
    String method,
    String target, {
    Map<String, String> headers = const {'Connection': 'close'},
  }) {
    final lines = [
      '$method $target HTTP/1.1',
      'Host: 127.0.0.1',
      for (final MapEntry(:key, :value) in headers.entries) '$key: $value',
    ];
    return '${lines.join('\r\n')}\r\n\r\n';
  }

  /// Sends [request] (raw text, possibly several pipelined requests) to
  /// 127.0.0.1:[port] and reads until the server closes the connection.
  static Future<RawResponse> exchange(int port, String request) async {
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
    socket.add(latin1.encode(request));
    await socket.flush();
    final received = BytesBuilder(copy: false);
    // The server may reset the connection after a failed body; what was
    // received until then is the result.
    await socket
        .listen(received.add, cancelOnError: true)
        .asFuture<void>()
        .catchError((Object _) {}, test: (error) => error is SocketException)
        .timeout(timeout);
    socket.destroy();
    return RawResponse.parse(received.takeBytes());
  }

  /// Sends [request], waits for the first bytes of the response and
  /// closes the socket, like a client that goes away mid-response.
  static Future<void> abortAfterFirstBytes(int port, String request) async {
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
    socket.add(latin1.encode(request));
    await socket.flush();
    await socket.first.timeout(timeout);
    socket.destroy();
  }
}
```

- [ ] **Step 6: Write the `requests` group and the entry point**

`packages/dartnest_conformance/lib/src/groups/request_conformance.dart`:

```dart
import 'dart:convert';

import 'package:test/test.dart';

import '../adapter_under_test.dart';
import '../conformance_server.dart';
import '../raw_http.dart';

/// Requests reach the application as `HttpRequest`s that match what the
/// client sent: method, target, headers, body and connection details.
abstract final class RequestConformance {
  /// Registers the group for [factory].
  static void register(AdapterFactory factory) {
    group('requests', () {
      late ConformanceServer server; // Set in setUp before every test.

      setUp(() async => server = await ConformanceServer.start(factory));
      tearDown(() => server.close());

      test('serves the users app', () async {
        final found = await server.send('GET', '/users/1');
        final created = await server.send(
          'POST',
          '/users',
          headers: {'content-type': 'application/json'},
          body: utf8.encode(jsonEncode({'name': 'cid'})),
        );
        final missing = await server.send('GET', '/users/9');

        // Separate checks: a record compares a Map inside it by identity.
        expect(found.status, 200);
        expect(found.json, {'id': 1, 'name': 'ann'});
        expect(
          (created.status, created.headers.value('location')),
          (201, '/users/3'),
        );
        expect((missing.json as Map)['statusCode'], 404);
      });

      test('passes every method upper-cased', () async {
        for (final method in ['GET', 'POST', 'PUT', 'PATCH', 'DELETE']) {
          final response = await server.send(method, '/probe/echo');

          expect((response.json as Map)['method'], method);
        }
      });

      test('keeps the raw query', () async {
        final response = await server.send('GET', '/probe/echo?b=%20x&a=1&a=2');

        expect((response.json as Map)['query'], 'b=%20x&a=1&a=2');
      });

      test('removes dot segments from the target', () async {
        for (final target in ['/probe/../users/1', '/users/./1']) {
          final response = await RawHttp.exchange(
            server.port,
            RawHttp.head('GET', target),
          );

          expect(response.json, {'id': 1, 'name': 'ann'}, reason: target);
        }
      });

      // Review Focus 3: dart:io parses `//users` as an authority.
      test('reads a target that starts with // as a path', () async {
        final response = await RawHttp.exchange(
          server.port,
          RawHttp.head('GET', '//users//1'),
        );

        expect(response.json, {'id': 1, 'name': 'ann'});
      });

      test('keeps %2F inside one path segment', () async {
        final response = await server.send('GET', '/probe/segments/a%2Fb');

        expect(response.json, {'value': 'a/b'});
      });

      test('answers 400 to invalid percent-encoded UTF-8', () async {
        final response = await server.send('GET', '/probe/segments/%FF');

        expect(response.status, 400);
      });

      test('passes multi-valued headers case-insensitively', () async {
        final response = await RawHttp.exchange(
          server.port,
          RawHttp.head(
            'GET',
            '/probe/echo',
            headers: {
              'X-Multi': 'a',
              'x-multi': 'b',
              'X-CASE': 'Value',
              'Connection': 'close',
            },
          ),
        );
        final headers = (response.json as Map)['headers'] as Map;

        expect(headers['x-multi'], ['a', 'b']);
        expect(headers['x-case'], ['Value']);
      });

      test('sends every set-cookie and repeated header value', () async {
        final response = await RawHttp.exchange(
          server.port,
          RawHttp.head('GET', '/probe/cookies'),
        );

        expect(response.headers.all('set-cookie'), ['a=1', 'b=2']);
        expect(response.headers.all('x-multi').join(', '), 'one, two');
      });

      test('reports the client address and port', () async {
        final response = await server.send('GET', '/probe/echo');
        final echo = response.json as Map;

        expect(echo['remoteAddress'], '127.0.0.1');
        expect(echo['remotePort'], response.localPort);
      });

      test('reuses a keep-alive connection', () async {
        final ports = [
          for (var i = 0; i < 3; i++)
            (await server.send('GET', '/probe/echo')).localPort,
        ];

        expect(ports.toSet(), hasLength(1));
      });

      test('answers pipelined requests in order', () async {
        final response = await RawHttp.exchange(
          server.port,
          RawHttp.head('GET', '/probe/echo?n=1', headers: const {}) +
              RawHttp.head('GET', '/probe/echo?n=2'),
        );
        final text = latin1.decode(response.bytes);

        expect('HTTP/1.1 200'.allMatches(text), hasLength(2));
        expect(text.indexOf('n=1'), lessThan(text.indexOf('n=2')));
      });

      test('de-chunks the request body and drops transfer-encoding', () async {
        final head = RawHttp.head(
          'POST',
          '/probe/echo',
          headers: {'Transfer-Encoding': 'chunked', 'Connection': 'close'},
        );
        final response = await RawHttp.exchange(
          server.port,
          '${head}5\r\nhello\r\n0\r\n\r\n',
        );
        final echo = response.json as Map;

        expect(echo['body'], 'hello');
        expect(echo['headers'] as Map, isNot(contains('transfer-encoding')));
      });

      test('adds no default headers of the server library', () async {
        final response = await RawHttp.exchange(
          server.port,
          RawHttp.head('GET', '/probe/empty'),
        );

        expect(response.status, 204);
        expect(response.headers.contains('content-type'), isFalse);
        expect(response.headers.contains('x-frame-options'), isFalse);
        expect(response.headers.contains('x-powered-by'), isFalse);
      });
    });
  }
}
```

`packages/dartnest_conformance/lib/src/adapter_conformance.dart` (поки лише `requests`):

```dart
import 'package:test/test.dart';

import 'adapter_under_test.dart';
import 'groups/request_conformance.dart';

/// Entry point of the shared suite: an adapter package calls [run] from a
/// test file.
///
/// ```dart
/// void main() => AdapterConformance.run(
///   'IoAdapter',
///   (onError, closeTimeout) {
///     final adapter = IoAdapter(
///       onError: onError,
///       closeTimeout: closeTimeout,
///     );
///     return AdapterUnderTest(adapter, boundPort: () => adapter.port);
///   },
/// );
/// ```
abstract final class AdapterConformance {
  /// Registers every conformance group for the adapters [factory] creates,
  /// inside a group called [name].
  static void run(String name, AdapterFactory factory) {
    group('$name conformance', () {
      RequestConformance.register(factory);
    });
  }
}
```

`packages/dartnest_conformance/lib/dartnest_conformance.dart`:

```dart
/// The shared conformance suite for dartnest `HttpAdapter`s: one users
/// application served on a loopback ephemeral port, run by every adapter
/// package from its own tests. Test support only: it imports
/// `package:test`.
library;

export 'src/adapter_conformance.dart';
export 'src/adapter_under_test.dart';
export 'src/client_response.dart';
export 'src/conformance_app.dart';
export 'src/conformance_data.dart';
export 'src/conformance_probe.dart';
export 'src/conformance_server.dart';
export 'src/raw_http.dart';
export 'src/raw_response.dart';
```

- [ ] **Step 7: Run tests to verify they pass**

Run from `packages/dartnest_conformance`: `dart test`
Expected: `+13: All tests passed!` (8 у `conformance_app_test.dart`, 5 у `raw_http_test.dart`).

- [ ] **Step 8: Record the test-support exception in `CLAUDE.md`**

У `CLAUDE.md`, абзац **Tests.**, замінити

```
than about 5 lines repeated becomes a helper.
```

на

```
than about 5 lines repeated becomes a helper. `packages/dartnest_conformance`
is unpublished test support for the adapter packages: its `lib/` may import
`package:test`, and the `register` methods of its test groups are held to the
test-file limits, not to the 40-line method limit.
```

Run from repo root: `dart analyze && dart format --output=none --set-exit-if-changed packages`
Expected: `No issues found!`, `0 changed`.

- [ ] **Step 9: Commit**

```bash
git add pubspec.yaml CLAUDE.md packages/dartnest_conformance
git commit -m "test(conformance): add the shared adapter conformance package with the requests group"
```

---

### Task 3: `dartnest_io`: `IoAdapter`, відображення запиту і група `requests`

Перший адаптер, мінімальний: `IoAdapter.listen` прив'язує `HttpServer`, очищає типові заголовки `dart:io` (рішення 4) і на кожен запит викликає `handler(IoRequestMapper.map(request))`, а потім `IoResponseWriter.write`. Відображення запиту: метод, ціль (рішення 7: `Uri.parse` уже прибрав dot-сегменти, `//users//1` повертається з authority в шлях, `Host` не використовується), кожне значення кожного заголовка, крім `transfer-encoding` (тіло вже розкодоване), непрочитаний потік тіла, адреса й порт клієнта. `%2F` лишається всередині сегмента, бо `Uri(path: ...)` зберігає кодування, а роутер ядра декодує вже розділені сегменти; `%FF` дає 400 від ядра. Писач поки простий: статус, усі заголовки, `content-length` + байти або `addStream`. Потоки без буфера і HEAD — Task 4; `onError`, межі помилок і очікування запитів у польоті — Task 5; HTTPS — Task 6.

`port` — геттер поза контрактом `HttpAdapter`: після `listen(port: 0)` повертає прив'язаний порт, до `listen` і після `close()` кидає `StateError`. `listen` дозволений один раз; `close()` повторюваний (той самий `Future`) і до `listen` просто забороняє подальший `listen`.

**Files:**
- Modify: `pubspec.yaml` (корінь, `workspace:`)
- Create: `packages/dartnest_io/pubspec.yaml`
- Create: `packages/dartnest_io/analysis_options.yaml`
- Create: `packages/dartnest_io/lib/dartnest_io.dart`
- Create: `packages/dartnest_io/lib/src/io_request_mapper.dart`
- Create: `packages/dartnest_io/lib/src/io_response_writer.dart`
- Create: `packages/dartnest_io/lib/src/io_adapter.dart`
- Test: `packages/dartnest_io/test/io_adapter_conformance_test.dart`
- Test: `packages/dartnest_io/test/io_adapter_test.dart`

**Interfaces:**
- Consumes: `HttpAdapter`, `RequestHandler`, `HttpRequest`, `HttpResponse`, `BytesBody`, `StreamBody`, `HeaderMap`, `RequestBody`, `ConnectionInfo` (етап 2); `AdapterConformance.run`, `AdapterUnderTest` (Task 2).
- Produces:
  - `final class IoAdapter implements HttpAdapter { IoAdapter(); int get port; Future<void> listen(RequestHandler handler, {required Object address, required int port}); Future<void> close({bool force = false}); }` (конструктор розширюють Task 5 `onError` і Task 6 `securityContext`).
  - `abstract final class IoRequestMapper { static HttpRequest map(io.HttpRequest native); static Uri target(Uri parsed); }`
  - `abstract final class IoResponseWriter { static Future<void> write(HttpResponse response, io.HttpResponse native); }` (Task 4 додає `{required bool isHead}`).

- [ ] **Step 1: Create the package**

Корінь `pubspec.yaml`, список `workspace:`:

```yaml
workspace:
  - packages/dartnest
  - packages/dartnest_conformance
  - packages/dartnest_io
```

`packages/dartnest_io/pubspec.yaml`:

```yaml
name: dartnest_io
description: dart:io HttpServer adapter for dartnest applications.
version: 0.1.0-dev
publish_to: none
environment:
  sdk: ^3.8.0
resolution: workspace
dependencies:
  dartnest: ^0.1.0-dev
dev_dependencies:
  dartnest_conformance: ^0.1.0-dev
  lints: ^5.1.0
  test: ^1.25.0
```

`packages/dartnest_io/analysis_options.yaml`:

```yaml
include: ../../analysis_options.yaml
```

Run from repo root: `dart pub get`
Expected: `Got dependencies!`

- [ ] **Step 2: Write the failing tests**

`packages/dartnest_io/test/io_adapter_conformance_test.dart` (поки без `onError` і `closeTimeout`: їх додає Task 5):

```dart
import 'package:dartnest_conformance/dartnest_conformance.dart';
import 'package:dartnest_io/dartnest_io.dart';

void main() => AdapterConformance.run('IoAdapter', (_, _) {
  final adapter = IoAdapter();
  return AdapterUnderTest(adapter, boundPort: () => adapter.port);
});
```

`packages/dartnest_io/test/io_adapter_test.dart`:

```dart
import 'dart:io' as io;

import 'package:dartnest/dartnest.dart';
import 'package:dartnest_io/dartnest_io.dart';
import 'package:test/test.dart';

/// Answers every request with `ok`.
Future<HttpResponse> answerOk(HttpRequest request) async =>
    HttpResponse.text('ok');

void main() {
  group('IoAdapter', () {
    test('has no port before listen', () {
      expect(() => IoAdapter().port, throwsStateError);
    });

    test('serves on the bound ephemeral port', () async {
      final adapter = IoAdapter();
      await adapter.listen(
        answerOk,
        address: io.InternetAddress.loopbackIPv4,
        port: 0,
      );
      addTearDown(adapter.close);
      final client = io.HttpClient();
      addTearDown(client.close);

      final request = await client.get('127.0.0.1', adapter.port, '/');
      final response = await request.close();

      expect(response.statusCode, 200);
      expect(await response.map(String.fromCharCodes).join(), 'ok');
    });

    test('listens only once', () async {
      final adapter = IoAdapter();
      await adapter.listen(
        answerOk,
        address: io.InternetAddress.loopbackIPv4,
        port: 0,
      );
      addTearDown(adapter.close);

      await expectLater(
        adapter.listen(
          answerOk,
          address: io.InternetAddress.loopbackIPv4,
          port: 0,
        ),
        throwsStateError,
      );
    });

    test('close before listen completes and blocks a later listen', () async {
      final adapter = IoAdapter();

      await adapter.close();

      await expectLater(
        adapter.listen(
          answerOk,
          address: io.InternetAddress.loopbackIPv4,
          port: 0,
        ),
        throwsStateError,
      );
    });

    test('close is idempotent and forgets the port', () async {
      final adapter = IoAdapter();
      await adapter.listen(
        answerOk,
        address: io.InternetAddress.loopbackIPv4,
        port: 0,
      );

      expect(identical(adapter.close(), adapter.close()), isTrue);
      await adapter.close();
      expect(() => adapter.port, throwsStateError);
    });
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run from `packages/dartnest_io`: `dart test`
Expected: FAIL на компіляції — `package:dartnest_io/dartnest_io.dart` не існує.

- [ ] **Step 4: Map the request**

`packages/dartnest_io/lib/src/io_request_mapper.dart`:

```dart
import 'dart:io' as io;

import 'package:dartnest/dartnest.dart';

/// Builds the dartnest [HttpRequest] for a `dart:io` request.
abstract final class IoRequestMapper {
  /// The request for [native]: its method, its target as a path with the
  /// raw query, every header value except `transfer-encoding` (the body
  /// is already de-chunked), the unread body stream and the client
  /// address.
  static HttpRequest map(io.HttpRequest native) {
    final headers = HeaderMap();
    native.headers.forEach((name, values) {
      if (name == io.HttpHeaders.transferEncodingHeader) return;
      for (final value in values) {
        headers.add(name, value);
      }
    });
    final connection = native.connectionInfo;
    return HttpRequest(
      method: native.method,
      uri: target(native.uri),
      headers: headers,
      body: RequestBody(native),
      connectionInfo: connection == null
          ? null
          : ConnectionInfo(
              remoteAddress: connection.remoteAddress.address,
              remotePort: connection.remotePort,
            ),
    );
  }

  /// The path and raw query of [parsed], the target as `dart:io` parsed it
  /// (`Uri.parse`, so dot segments are already removed). An origin-form
  /// target that starts with `//` comes back with its first segment as
  /// the authority; it is put back into the path. `Host` is not used, so
  /// it cannot change the routed path.
  static Uri target(Uri parsed) {
    final path = parsed.hasAuthority && !parsed.hasScheme
        ? '//${parsed.authority}${parsed.path}'
        : parsed.path;
    return Uri(
      path: path.isEmpty ? '/' : path,
      query: parsed.hasQuery ? parsed.query : null,
    );
  }
}
```

- [ ] **Step 5: Write the response**

`packages/dartnest_io/lib/src/io_response_writer.dart`:

```dart
import 'dart:io' as io;

import 'package:dartnest/dartnest.dart';

/// Writes a dartnest [HttpResponse] to a `dart:io` response.
abstract final class IoResponseWriter {
  /// Writes [response] to [native] and closes it: status, every header
  /// value, then the bytes (with `content-length`) or the stream.
  static Future<void> write(
    HttpResponse response,
    io.HttpResponse native,
  ) async {
    native.statusCode = response.status;
    for (final name in response.headers.names) {
      native.headers.set(name, response.headers.all(name));
    }
    switch (response.body) {
      case BytesBody(:final bytes):
        native.contentLength = bytes.length;
        native.add(bytes);
      case StreamBody(:final stream):
        await native.addStream(stream);
    }
    await native.close();
  }
}
```

- [ ] **Step 6: Write the adapter and the barrel**

`packages/dartnest_io/lib/src/io_adapter.dart`:

```dart
import 'dart:async';
import 'dart:io' as io;

import 'package:dartnest/dartnest.dart';

import 'io_request_mapper.dart';
import 'io_response_writer.dart';

/// Serves a dartnest application on a `dart:io` [io.HttpServer].
///
/// ```dart
/// final adapter = IoAdapter();
/// final app = await Application.create(appModule, adapter: adapter);
/// await app.listen(port: 3000);
/// print('listening on ${adapter.port}');
/// ```
///
/// The server sends exactly the headers of the application's response
/// (the `dart:io` defaults such as `x-frame-options` are cleared; add them
/// with middleware). Requests are routed on their target only, never on
/// `Host`.
final class IoAdapter implements HttpAdapter {
  /// Creates the adapter.
  IoAdapter();

  io.HttpServer? _server;
  Future<void>? _closing;

  /// The bound port, useful after listening on port 0; a [StateError]
  /// before `listen` completed or after `close`.
  int get port => switch (_server) {
    final server? when _closing == null => server.port,
    _ => throw StateError('IoAdapter is not listening.'),
  };

  @override
  Future<void> listen(
    RequestHandler handler, {
    required Object address,
    required int port,
  }) async {
    if (_server != null || _closing != null) {
      throw StateError('IoAdapter.listen can be called only once.');
    }
    final server = await io.HttpServer.bind(address, port);
    server.defaultResponseHeaders.clear();
    _server = server;
    server.listen((request) => unawaited(_serve(request, handler)));
  }

  @override
  Future<void> close({bool force = false}) =>
      _closing ??= _shutdown(force: force);

  Future<void> _shutdown({required bool force}) async {
    final server = _server;
    if (server == null) return;
    await server.close(force: force);
  }

  Future<void> _serve(io.HttpRequest native, RequestHandler handler) async {
    final response = await handler(IoRequestMapper.map(native));
    await IoResponseWriter.write(response, native.response);
  }
}
```

`packages/dartnest_io/lib/dartnest_io.dart`:

```dart
/// Serves dartnest applications on a `dart:io` `HttpServer`.
library;

export 'src/io_adapter.dart';
```

- [ ] **Step 7: Run tests to verify they pass**

Run from `packages/dartnest_io`: `dart test`
Expected: `+19: All tests passed!` (14 у групі `IoAdapter conformance requests`, 5 у `io_adapter_test.dart`). Тест `reads a target that starts with // as a path` (Review Focus 3) без `IoRequestMapper.target` дає 404: перевірте це, тимчасово замінивши `uri: target(native.uri)` на `uri: native.uri`, і поверніть.

Run from repo root: `dart analyze && dart format --output=none --set-exit-if-changed packages`
Expected: `No issues found!`, `0 changed`.

- [ ] **Step 8: Commit**

```bash
git add pubspec.yaml packages/dartnest_io
git commit -m "feat(io): add IoAdapter on dart:io HttpServer"
```

---

### Task 4: Тіла: потоки без буфера, HEAD, обрамлення (група `bodies`)

Група `bodies` перевіряє: велике chunked-завантаження (8 МіБ) доходить до хендлера цілим і хендлер отримує перший чанк до кінця завантаження; велике потокове скачування — chunked, in-memory — з `content-length`; кожен чанк потоку доходить до клієнта окремо (Review Focus 1); HEAD має заголовки GET і жодного байта тіла; HEAD на нескінченний потік скасовує його (Review Focus 2); `transfer-encoding` від застосунку не ламає обрамлення (Review Focus 5); `connection: close` від застосунку закриває з'єднання після відповіді.

Причини в `dart:io`: `bufferOutput` (типово `true`) тримає чанки до 8 КіБ у буфері; для HEAD сервер ставить `ignoreBody`, але `addStream` дочитує потік до кінця; заголовок `transfer-encoding: chunked`, скопійований у відповідь, конфліктує з власним обрамленням. Тому `IoResponseWriter.write` отримує `isHead`, пропускає `transfer-encoding`, для HEAD не пише байти (а `content-length` лишає) і скасовує потік, а для потоку вимикає `bufferOutput`.

**Files:**
- Create: `packages/dartnest_conformance/lib/src/groups/body_conformance.dart`
- Modify: `packages/dartnest_conformance/lib/src/adapter_conformance.dart`
- Modify: `packages/dartnest_io/lib/src/io_response_writer.dart`
- Modify: `packages/dartnest_io/lib/src/io_adapter.dart` (`_serve`)

**Interfaces:**
- Consumes: `ConformanceServer`, `ConformanceData`, `RawHttp`, `RawResponse` (Task 2); `IoAdapter`, `IoResponseWriter` (Task 3).
- Produces: `static void BodyConformance.register(AdapterFactory factory)` (група `bodies`); `IoResponseWriter.write(HttpResponse response, io.HttpResponse native, {required bool isHead})`.

- [ ] **Step 1: Write the `bodies` group**

`packages/dartnest_conformance/lib/src/groups/body_conformance.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';

import '../adapter_under_test.dart';
import '../client_response.dart';
import '../conformance_data.dart';
import '../conformance_server.dart';
import '../raw_http.dart';
import '../raw_response.dart';

/// Bodies stream in both directions without being buffered whole, use
/// `content-length` or chunked framing as appropriate, and `HEAD` sends
/// headers only.
abstract final class BodyConformance {
  /// Bytes in a "large" body: far above any socket or adapter buffer.
  static const largeSize = 8 * 1024 * 1024;

  /// How long a test waits for a step the adapter must make on its own.
  static const stepTimeout = Duration(seconds: 5);

  /// Registers the group for [factory].
  static void register(AdapterFactory factory) {
    group('bodies', () {
      late ConformanceServer server; // Set in setUp before every test.

      setUp(() async => server = await ConformanceServer.start(factory));
      tearDown(() => server.close());

      test('streams a large chunked upload to the handler', () async {
        final request = await server.client.post(
          '127.0.0.1',
          server.port,
          '/probe/upload',
        );
        await request.addStream(ConformanceData.chunks(largeSize));
        final response = await ClientResponse.read(await request.close());

        expect(response.json, {
          'length': largeSize,
          'checksum': ConformanceData.checksum(
            ConformanceData.bytes(largeSize),
          ),
        });
      });

      test('hands the upload to the handler before it ends', () async {
        final request = await server.client.post(
          '127.0.0.1',
          server.port,
          '/probe/upload',
        );
        request.bufferOutput = false;
        request.add(ConformanceData.bytes(1024));
        await request.flush();
        await server.probe.firstUploadChunk.future.timeout(stepTimeout);
        request.add(ConformanceData.bytes(1024));
        final response = await ClientResponse.read(await request.close());

        expect((response.json as Map)['length'], 2048);
      });

      test('streams a large download with chunked framing', () async {
        final response = await server.send(
          'GET',
          '/probe/download?size=$largeSize',
        );

        expect(response.headers.chunkedTransferEncoding, isTrue);
        expect(response.headers.contentLength, -1);
        expect(response.bytes.length, largeSize);
        expect(
          ConformanceData.checksum(response.bytes),
          ConformanceData.checksum(ConformanceData.bytes(largeSize)),
        );
      });

      test('sends content-length for an in-memory body', () async {
        const size = 1024 * 1024;
        final response = await server.send(
          'GET',
          '/probe/download-fixed?size=$size',
        );

        expect(response.headers.contentLength, size);
        expect(response.headers.chunkedTransferEncoding, isFalse);
        expect(response.bytes, ConformanceData.bytes(size));
      });

      // Review Focus 1: server-sent events need unbuffered chunks.
      test('flushes each chunk of a streamed response', () async {
        final request = await server.client.get(
          '127.0.0.1',
          server.port,
          '/probe/gated-stream',
        );
        final response = await request.close().timeout(stepTimeout);
        final chunks = StreamIterator(response);

        expect(await chunks.moveNext().timeout(stepTimeout), isTrue);
        expect(utf8.decode(chunks.current), 'first;');
        server.probe.release.complete();
        final rest = <int>[];
        while (await chunks.moveNext()) {
          rest.addAll(chunks.current);
        }
        expect(utf8.decode(rest), 'last');
      });

      test('answers HEAD with the GET headers and no body', () async {
        final get = await server.send('GET', '/users/1');
        final head = await RawHttp.exchange(
          server.port,
          RawHttp.head('HEAD', '/users/1'),
        );

        expect(head.status, 200);
        expect(head.headers['content-length'], '${get.bytes.length}');
        expect(head.headers['content-type'], get.headers.value('content-type'));
        expect(head.bytes.length, _headLength(head));
      });

      // Review Focus 2: dart:io drains a HEAD body to its end.
      test('cancels a streamed body for HEAD without reading it', () async {
        final head = await RawHttp.exchange(
          server.port,
          RawHttp.head('HEAD', '/probe/endless'),
        );

        expect(head.status, 200);
        expect(head.bytes.length, _headLength(head));
        await server.probe.endlessCancelled.future.timeout(stepTimeout);
      });

      // Review Focus 5: shelf treats such a body as already chunked.
      test('frames the body itself despite an app transfer-encoding', () async {
        final response = await RawHttp.exchange(
          server.port,
          RawHttp.head('GET', '/probe/framing'),
        );

        expect((response.isComplete, response.text), (true, 'framed'));
      });

      test(
        'closes the connection when the app sends connection: close',
        () async {
          final response = await RawHttp.exchange(
            server.port,
            RawHttp.head('GET', '/probe/close-connection', headers: const {}) +
                RawHttp.head('GET', '/probe/echo'),
          );

          expect(response.text, 'bye');
          expect(
            'HTTP/1.1 '.allMatches(latin1.decode(response.bytes)),
            hasLength(1),
          );
        },
      );
    });
  }

  /// Length of the status line and headers of [response], including the
  /// blank line: all a body-less response may contain.
  static int _headLength(RawResponse response) =>
      latin1.decode(response.bytes).indexOf('\r\n\r\n') + 4;
}
```

`packages/dartnest_conformance/lib/src/adapter_conformance.dart`:

```dart
import 'package:test/test.dart';

import 'adapter_under_test.dart';
import 'groups/body_conformance.dart';
import 'groups/request_conformance.dart';

/// Entry point of the shared suite: an adapter package calls [run] from a
/// test file.
///
/// ```dart
/// void main() => AdapterConformance.run(
///   'IoAdapter',
///   (onError, closeTimeout) {
///     final adapter = IoAdapter(
///       onError: onError,
///       closeTimeout: closeTimeout,
///     );
///     return AdapterUnderTest(adapter, boundPort: () => adapter.port);
///   },
/// );
/// ```
abstract final class AdapterConformance {
  /// Registers every conformance group for the adapters [factory] creates,
  /// inside a group called [name].
  static void run(String name, AdapterFactory factory) {
    group('$name conformance', () {
      RequestConformance.register(factory);
      BodyConformance.register(factory);
    });
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run from `packages/dartnest_io`: `dart test`
Expected: FAIL. Напевно падають `flushes each chunk of a streamed response` (перший чанк не приходить, поки ворота закриті) і `cancels a streamed body for HEAD without reading it` (скасування не настає за 5 с); `frames the body itself despite an app transfer-encoding` може впасти або пройти залежно від того, як `dart:io` поєднує заголовок зі своїм обрамленням. Решта груп `requests` і `IoAdapter` зелені.

- [ ] **Step 3: Frame, flush and answer HEAD in the writer**

`packages/dartnest_io/lib/src/io_response_writer.dart`:

```dart
import 'dart:async';
import 'dart:io' as io;

import 'package:dartnest/dartnest.dart';

/// Writes a dartnest [HttpResponse] to a `dart:io` response.
abstract final class IoResponseWriter {
  /// Writes [response] to [native] and closes it.
  ///
  /// - Every header value is copied except `transfer-encoding`: framing
  ///   is the writer's job (`content-length` for bytes, chunked for a
  ///   stream without `content-length`).
  /// - A stream is written chunk by chunk, unbuffered, so each chunk
  ///   reaches the client when the stream emits it.
  /// - For `HEAD` ([isHead]) no body is written and a stream is cancelled
  ///   unread; the headers stay those of the `GET` response.
  ///
  /// Fails when the body stream fails or the connection breaks; the caller
  /// reports it, `dart:io` has already dropped the connection.
  static Future<void> write(
    HttpResponse response,
    io.HttpResponse native, {
    required bool isHead,
  }) async {
    native.statusCode = response.status;
    for (final name in response.headers.names) {
      if (name == io.HttpHeaders.transferEncodingHeader) continue;
      native.headers.set(name, response.headers.all(name));
    }
    switch (response.body) {
      case BytesBody(:final bytes):
        native.contentLength = bytes.length;
        if (!isHead) native.add(bytes);
      case StreamBody(:final stream) when isHead:
        await stream.listen(null).cancel();
      case StreamBody(:final stream):
        native.bufferOutput = false;
        await native.addStream(stream);
    }
    await native.close();
  }
}
```

- [ ] **Step 4: Pass `isHead` from the adapter**

`packages/dartnest_io/lib/src/io_adapter.dart`:

```dart
import 'dart:async';
import 'dart:io' as io;

import 'package:dartnest/dartnest.dart';

import 'io_request_mapper.dart';
import 'io_response_writer.dart';

/// Serves a dartnest application on a `dart:io` [io.HttpServer].
///
/// ```dart
/// final adapter = IoAdapter();
/// final app = await Application.create(appModule, adapter: adapter);
/// await app.listen(port: 3000);
/// print('listening on ${adapter.port}');
/// ```
///
/// The server sends exactly the headers of the application's response
/// (the `dart:io` defaults such as `x-frame-options` are cleared; add them
/// with middleware). Requests are routed on their target only, never on
/// `Host`.
final class IoAdapter implements HttpAdapter {
  /// Creates the adapter.
  IoAdapter();

  io.HttpServer? _server;
  Future<void>? _closing;

  /// The bound port, useful after listening on port 0; a [StateError]
  /// before `listen` completed or after `close`.
  int get port => switch (_server) {
    final server? when _closing == null => server.port,
    _ => throw StateError('IoAdapter is not listening.'),
  };

  @override
  Future<void> listen(
    RequestHandler handler, {
    required Object address,
    required int port,
  }) async {
    if (_server != null || _closing != null) {
      throw StateError('IoAdapter.listen can be called only once.');
    }
    final server = await io.HttpServer.bind(address, port);
    server.defaultResponseHeaders.clear();
    _server = server;
    server.listen((request) => unawaited(_serve(request, handler)));
  }

  @override
  Future<void> close({bool force = false}) =>
      _closing ??= _shutdown(force: force);

  Future<void> _shutdown({required bool force}) async {
    final server = _server;
    if (server == null) return;
    await server.close(force: force);
  }

  Future<void> _serve(io.HttpRequest native, RequestHandler handler) async {
    final response = await handler(IoRequestMapper.map(native));
    await IoResponseWriter.write(
      response,
      native.response,
      isHead: native.method == 'HEAD',
    );
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run from `packages/dartnest_io`: `dart test`
Expected: `+28: All tests passed!` (14 `requests`, 9 `bodies`, 5 `IoAdapter`).

Run from `packages/dartnest_conformance`: `dart test`
Expected: `+13: All tests passed!`

Run from repo root: `dart analyze && dart format --output=none --set-exit-if-changed packages`
Expected: `No issues found!`, `0 changed`.

- [ ] **Step 6: Commit**

```bash
git add packages/dartnest_conformance/lib/src packages/dartnest_io/lib/src
git commit -m "feat(io): stream bodies unbuffered and answer HEAD without a body"
```

---

### Task 5: Життєвий цикл: `close`, запити в польоті, межі помилок (група `lifecycle`)

Група `lifecycle`: `close()` чекає відповідь, що ще стрімиться, і повільний хендлер; після `close()` нові з'єднання відхиляються, а порт можна прив'язати знову; `close(force: true)` обриває запит у польоті; якщо логер застосунку кидає, адаптер відповідає 500 без тіла і працює далі; потік, що падає посеред відповіді, обриває з'єднання (клієнт бачить незавершене chunked-тіло), а збій іде в `onError`; клієнт, що пішов посеред відповіді, не валить сервер і не підвішує `close()` (Review Focus 4); `closeTimeout` (рішення 11, Review Focus 6): завислий хендлер і потік, що ще пишеться, обриваються після таймауту, `app.close()` завершується, порт вільний; хендлер, що встиг, відповідає повністю; `null` чекає без ліміту.

`HttpServer.close()` повертається, не чекаючи активних з'єднань, а `Application` не рахує запити, які доставив адаптер (Task 1). Тому `IoAdapter` обгортає кожен запит у `InFlightRequests.track` (Task 1) і в `close()` після `server.close()` чекає `idle` (крім `force`) не довше за `closeTimeout`: `Future.timeout` з `onTimeout: () => server.close(force: true)` обриває решту з'єднань, і `close()` завершується без помилки. Нового `catch` немає. Межі `on Object`:
- **запиту** (`_answer`): `handler` кидає лише тоді, коли кидає логер застосунку; адаптер віддає збій в `onError` і відповідає 500 без тіла;
- **відповіді** (`_serve`): запис тіла (код користувача) або сокет падає; `dart:io` вже обірвав з'єднання, тож лишається повідомити `onError`.

Без меж такий збій — необроблена асинхронна помилка, яка в тестах валить тест, а в застосунку — ізолят.

**Files:**
- Create: `packages/dartnest_conformance/lib/src/groups/lifecycle_conformance.dart`
- Modify: `packages/dartnest_conformance/lib/src/adapter_conformance.dart`
- Modify: `packages/dartnest_io/lib/src/io_adapter.dart`
- Modify: `packages/dartnest_io/test/io_adapter_conformance_test.dart`
- Modify: `packages/dartnest_io/test/io_adapter_test.dart`
- Modify: `CLAUDE.md` (список меж помилок)

**Interfaces:**
- Consumes: `InFlightRequests` з `package:dartnest/adapter.dart` і `Application`, що не рахує запити адаптера (Task 1); `ConformanceServer.firstAdapterError`, `adapterErrors`, `applicationErrors`, `start(..., applicationLogger:, closeTimeout:)`, `RawHttp.exchange`, `RawHttp.abortAfterFirstBytes` (Task 2); `IoResponseWriter.write(..., isHead:)` (Task 4).
- Produces: `static void LifecycleConformance.register(AdapterFactory factory)` (група `lifecycle`); `IoAdapter({Duration? closeTimeout = IoAdapter.defaultCloseTimeout, ErrorLogger? onError})`, `static const Duration IoAdapter.defaultCloseTimeout` (30 с), `final Duration? closeTimeout`, `final ErrorLogger onError`, `static void IoAdapter.printError(Object error, StackTrace stackTrace)`.

- [ ] **Step 1: Write the `lifecycle` group**

`packages/dartnest_conformance/lib/src/groups/lifecycle_conformance.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../adapter_under_test.dart';
import '../conformance_server.dart';
import '../raw_http.dart';

/// Closing, failures and misbehaving clients: the adapter finishes or
/// drops in-flight work as asked, releases its port, and keeps serving
/// after anything a single request does.
abstract final class LifecycleConformance {
  /// How long a test waits for a step the adapter must make on its own.
  static const stepTimeout = Duration(seconds: 5);

  /// How long a test watches that something does not happen.
  static const settle = Duration(milliseconds: 200);

  /// The adapter's `closeTimeout` in the tests that let it expire.
  static const shortCloseTimeout = Duration(milliseconds: 250);

  /// Registers the group for [factory].
  static void register(AdapterFactory factory) {
    group('lifecycle', () {
      late ConformanceServer server; // Set in setUp before every test.

      setUp(() async => server = await ConformanceServer.start(factory));
      tearDown(() => server.close());

      test('close waits for a response that is still streaming', () async {
        final request = await server.client.get(
          '127.0.0.1',
          server.port,
          '/probe/gated-stream',
        );
        final response = await request.close().timeout(stepTimeout);
        final body = utf8.decoder.bind(response).join();
        await server.probe.entered.future.timeout(stepTimeout);
        var closed = false;
        final closing = server.app.close().then((_) => closed = true);

        await Future<void>.delayed(settle);
        expect(closed, isFalse);
        server.probe.release.complete();
        expect(await body, 'first;last');
        await closing.timeout(stepTimeout);
      });

      test('close waits for a slow handler', () async {
        final response = server.send('GET', '/probe/slow');
        await server.probe.entered.future.timeout(stepTimeout);
        var closed = false;
        final closing = server.app.close().then((_) => closed = true);

        await Future<void>.delayed(settle);
        expect(closed, isFalse);
        server.probe.release.complete();
        expect((await response).text, 'done');
        await closing.timeout(stepTimeout);
      });

      test('close refuses new connections and releases the port', () async {
        await server.app.close().timeout(stepTimeout);

        await expectLater(
          Socket.connect(InternetAddress.loopbackIPv4, server.port),
          throwsA(isA<SocketException>()),
        );
        final rebound = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          server.port,
        );
        await rebound.close();
      });

      test('force close drops a request in flight', () async {
        final response = server.send('GET', '/probe/slow');
        await server.probe.entered.future.timeout(stepTimeout);

        await server.app.close(force: true).timeout(stepTimeout);

        await expectLater(response, throwsA(isA<IOException>()));
      });

      // Review Focus 6: the adapter drops the connection after the timeout
      // and Application.close does not wait for the abandoned handler.
      test('close gives up on a stuck handler after closeTimeout', () async {
        await server.close();
        server = await ConformanceServer.start(
          factory,
          closeTimeout: shortCloseTimeout,
        );
        final response = server.send('GET', '/probe/slow');
        await server.probe.entered.future.timeout(stepTimeout);
        final stopwatch = Stopwatch()..start();

        await server.app.close().timeout(stepTimeout);

        expect(stopwatch.elapsed, greaterThan(shortCloseTimeout ~/ 2));
        await expectLater(response, throwsA(isA<IOException>()));
        final rebound = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          server.port,
        );
        await rebound.close();
      });

      test('close cuts a streaming response after closeTimeout', () async {
        await server.close();
        server = await ConformanceServer.start(
          factory,
          closeTimeout: shortCloseTimeout,
        );
        final streamed = RawHttp.exchange(
          server.port,
          RawHttp.head('GET', '/probe/gated-stream'),
        );
        await server.probe.entered.future.timeout(stepTimeout);

        await server.app.close().timeout(stepTimeout);

        final response = await streamed;
        expect((response.status, response.isComplete), (200, false));
      });

      test('close lets a handler that finishes in time answer', () async {
        await server.close();
        server = await ConformanceServer.start(
          factory,
          closeTimeout: shortCloseTimeout,
        );
        final response = server.send('GET', '/probe/slow');
        await server.probe.entered.future.timeout(stepTimeout);
        final closing = server.app.close();

        server.probe.release.complete();

        expect((await response).text, 'done');
        await closing.timeout(stepTimeout);
      });

      test('close without a closeTimeout waits for a slow handler', () async {
        await server.close();
        server = await ConformanceServer.start(factory, closeTimeout: null);
        final response = server.send('GET', '/probe/slow');
        await server.probe.entered.future.timeout(stepTimeout);
        var closed = false;
        final closing = server.app.close().then((_) => closed = true);

        await Future<void>.delayed(settle);
        expect(closed, isFalse);
        server.probe.release.complete();
        expect((await response).text, 'done');
        await closing.timeout(stepTimeout);
      });

      test('answers 500 without a body when the app logger throws', () async {
        await server.close();
        server = await ConformanceServer.start(
          factory,
          applicationLogger: (error, _) => throw StateError('logger failed'),
        );

        final failed = await server.send('GET', '/probe/fail');
        final next = await server.send('GET', '/users/1');

        expect(failed.status, 500);
        expect(failed.bytes, isEmpty);
        expect(
          await server.firstAdapterError.timeout(stepTimeout),
          isA<StateError>(),
        );
        expect(next.status, 200);
      });

      test('aborts the connection when the body stream fails', () async {
        final broken = await RawHttp.exchange(
          server.port,
          RawHttp.head('GET', '/probe/broken-stream'),
        );
        final next = await server.send('GET', '/users/1');

        expect(broken.isComplete, isFalse);
        expect(
          await server.firstAdapterError.timeout(stepTimeout),
          isA<StateError>(),
        );
        expect(next.status, 200);
      });

      // Review Focus 4: the stream is cancelled and close is not stuck.
      test('survives a client that leaves mid-response', () async {
        await RawHttp.abortAfterFirstBytes(
          server.port,
          RawHttp.head('GET', '/probe/endless'),
        );

        await server.probe.endlessCancelled.future.timeout(stepTimeout);
        expect((await server.send('GET', '/users/1')).status, 200);
        await server.app.close().timeout(stepTimeout);
      });
    });
  }
}
```

`packages/dartnest_conformance/lib/src/adapter_conformance.dart`:

```dart
import 'package:test/test.dart';

import 'adapter_under_test.dart';
import 'groups/body_conformance.dart';
import 'groups/lifecycle_conformance.dart';
import 'groups/request_conformance.dart';

/// Entry point of the shared suite: an adapter package calls [run] from a
/// test file.
///
/// ```dart
/// void main() => AdapterConformance.run(
///   'IoAdapter',
///   (onError, closeTimeout) {
///     final adapter = IoAdapter(
///       onError: onError,
///       closeTimeout: closeTimeout,
///     );
///     return AdapterUnderTest(adapter, boundPort: () => adapter.port);
///   },
/// );
/// ```
abstract final class AdapterConformance {
  /// Registers every conformance group for the adapters [factory] creates,
  /// inside a group called [name].
  static void run(String name, AdapterFactory factory) {
    group('$name conformance', () {
      RequestConformance.register(factory);
      BodyConformance.register(factory);
      LifecycleConformance.register(factory);
    });
  }
}
```

- [ ] **Step 2: Pass `onError` and `closeTimeout` to the adapter in the tests**

`packages/dartnest_io/test/io_adapter_conformance_test.dart`:

```dart
import 'package:dartnest_conformance/dartnest_conformance.dart';
import 'package:dartnest_io/dartnest_io.dart';

void main() => AdapterConformance.run('IoAdapter', (onError, closeTimeout) {
  final adapter = IoAdapter(onError: onError, closeTimeout: closeTimeout);
  return AdapterUnderTest(adapter, boundPort: () => adapter.port);
});
```

У `packages/dartnest_io/test/io_adapter_test.dart` додати в кінець групи `IoAdapter` (після `close is idempotent and forgets the port`):

```dart
    test('answers 500 without a body when the handler throws', () async {
      final errors = <Object>[];
      final adapter = IoAdapter(onError: (error, _) => errors.add(error));
      await adapter.listen(
        (request) async => throw StateError('handler failed'),
        address: io.InternetAddress.loopbackIPv4,
        port: 0,
      );
      addTearDown(adapter.close);
      final client = io.HttpClient();
      addTearDown(client.close);

      final response = await (await client.get(
        '127.0.0.1',
        adapter.port,
        '/',
      )).close();

      expect(response.statusCode, 500);
      expect(await response.fold<int>(0, (n, chunk) => n + chunk.length), 0);
      expect(errors, [isA<StateError>()]);
    });
```

- [ ] **Step 3: Run tests to verify they fail**

Run from `packages/dartnest_io`: `dart test`
Expected: FAIL на компіляції — `IoAdapter` не має параметрів `onError` і `closeTimeout`. Після Step 4 без очікування `InFlightRequests` (перевірка: тимчасово замінити все після `if (force) return;` у `_shutdown` на `return;`) падає `close waits for a response that is still streaming`; без меж падають `answers 500 without a body when the app logger throws` і `aborts the connection when the body stream fails`; без таймауту (тимчасово `return _inFlight.idle;` замість `return _inFlight.idle.timeout(...)`) падають з `TimeoutException` `close gives up on a stuck handler after closeTimeout` і `close cuts a streaming response after closeTimeout`; якщо `null` діяв би як нуль (тимчасово `if (limit == null) return;`), падає `close without a closeTimeout waits for a slow handler`.

- [ ] **Step 4: Track requests, bound the wait and add the error boundaries**

`packages/dartnest_io/lib/src/io_adapter.dart`:

```dart
import 'dart:async';
import 'dart:io' as io;

import 'package:dartnest/adapter.dart';
import 'package:dartnest/dartnest.dart';

import 'io_request_mapper.dart';
import 'io_response_writer.dart';

/// Serves a dartnest application on a `dart:io` [io.HttpServer].
///
/// ```dart
/// final adapter = IoAdapter();
/// final app = await Application.create(appModule, adapter: adapter);
/// await app.listen(port: 3000);
/// print('listening on ${adapter.port}');
/// ```
///
/// The server sends exactly the headers of the application's response
/// (the `dart:io` defaults such as `x-frame-options` are cleared; add them
/// with middleware). Requests are routed on their target only, never on
/// `Host`. Each request runs in its own `Future`; a failure in one never
/// stops the server.
final class IoAdapter implements HttpAdapter {
  /// Creates the adapter. [closeTimeout] bounds how long a graceful
  /// `close` waits for the requests in flight. [onError] receives failures
  /// the adapter cannot turn into a response (a handler that throws, a body
  /// stream that fails mid-response, a broken connection); it defaults to
  /// [printError] and must not throw.
  IoAdapter({this.closeTimeout = defaultCloseTimeout, ErrorLogger? onError})
    : onError = onError ?? printError;

  /// The default [closeTimeout].
  static const defaultCloseTimeout = Duration(seconds: 30);

  /// How long `close()` without `force` waits for the requests in flight,
  /// responses still being written included; then it drops the remaining
  /// connections as `close(force: true)` does and completes normally.
  /// `null` waits without a limit.
  final Duration? closeTimeout;

  /// Where the adapter reports failures.
  final ErrorLogger onError;

  final InFlightRequests _inFlight = InFlightRequests();
  io.HttpServer? _server;
  Future<void>? _closing;

  /// The bound port, useful after listening on port 0; a [StateError]
  /// before `listen` completed or after `close`.
  int get port => switch (_server) {
    final server? when _closing == null => server.port,
    _ => throw StateError('IoAdapter is not listening.'),
  };

  @override
  Future<void> listen(
    RequestHandler handler, {
    required Object address,
    required int port,
  }) async {
    if (_server != null || _closing != null) {
      throw StateError('IoAdapter.listen can be called only once.');
    }
    final server = await io.HttpServer.bind(address, port);
    server.defaultResponseHeaders.clear();
    _server = server;
    server.listen(
      (request) => unawaited(_inFlight.track(() => _serve(request, handler))),
    );
  }

  @override
  Future<void> close({bool force = false}) =>
      _closing ??= _shutdown(force: force);

  /// The default [onError]: prints the error and stack trace to stderr.
  static void printError(Object error, StackTrace stackTrace) {
    io.stderr.writeln('dartnest_io: $error\n$stackTrace');
  }

  Future<void> _shutdown({required bool force}) async {
    final server = _server;
    if (server == null) return;
    await server.close(force: force);
    if (force) return;
    final limit = closeTimeout;
    if (limit == null) return _inFlight.idle;
    // Past the limit, drop the remaining connections as force does; their
    // requests stay counted, but nothing waits for them any more.
    return _inFlight.idle.timeout(
      limit,
      onTimeout: () => server.close(force: true),
    );
  }

  Future<void> _serve(io.HttpRequest native, RequestHandler handler) async {
    final response = await _answer(native, handler);
    // Response boundary: the body stream is user code and the client can
    // go away; dart:io has already dropped the connection, so report it.
    try {
      await IoResponseWriter.write(
        response,
        native.response,
        isHead: native.method == 'HEAD',
      );
    } on Object catch (error, stackTrace) {
      onError(error, stackTrace);
    }
  }

  Future<HttpResponse> _answer(
    io.HttpRequest native,
    RequestHandler handler,
  ) async {
    // Request boundary: Application.handle only fails when the
    // application's own error logger throws; answer 500 without a body
    // and keep serving.
    try {
      return await handler(IoRequestMapper.map(native));
    } on Object catch (error, stackTrace) {
      onError(error, stackTrace);
      return HttpResponse(StatusCode.internalServerError);
    }
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run from `packages/dartnest_io`: `dart test`
Expected: `+40: All tests passed!` (14 `requests`, 9 `bodies`, 11 `lifecycle`, 6 `IoAdapter`).

- [ ] **Step 6: Add the adapter boundaries to `CLAUDE.md`**

У `CLAUDE.md`, список меж помилок (розділ про `catch`), замінити кінець останнього пункту

```
  body without them, so the last-resort 500 is always produced.
```

на

```
  body without them, so the last-resort 500 is always produced;
- adapter boundaries (added by the adapters work): `IoAdapter` reports a
  failure of the request handler (only possible when the application's own
  error logger throws) to its `onError` and answers 500 without a body, and
  reports a failure while writing the response (a failing body stream, a
  client that went away) to its `onError`; the connection is already
  dropped, and the adapter keeps serving.
```

Run from repo root: `dart analyze && dart format --output=none --set-exit-if-changed packages`
Expected: `No issues found!`, `0 changed`.

- [ ] **Step 7: Commit**

```bash
git add CLAUDE.md packages/dartnest_conformance/lib/src packages/dartnest_io
git commit -m "feat(io): wait for responses on close with a timeout and report failures"
```

---

### Task 6: HTTPS через `SecurityContext`

Специфікація: `IoAdapter({SecurityContext?})`. З контекстом адаптер викликає `HttpServer.bindSecure`; решта поведінки та сама. Тест піднімає HTTPS на `127.0.0.1:0` із самопідписаним сертифікатом для `localhost`/`127.0.0.1` і довіряє лише йому (`SecurityContext(withTrustedRoots: false)`). Сертифікат і ключ — тестові фікстури в репозиторії, ніде більше не використовуються.

**Files:**
- Create: `packages/dartnest_io/test/fixtures/localhost_cert.pem`
- Create: `packages/dartnest_io/test/fixtures/localhost_key.pem`
- Modify: `packages/dartnest_io/lib/src/io_adapter.dart`
- Test: `packages/dartnest_io/test/io_adapter_tls_test.dart`

**Interfaces:**
- Consumes: `IoAdapter` (Task 5).
- Produces: `IoAdapter({io.SecurityContext? securityContext, Duration? closeTimeout = IoAdapter.defaultCloseTimeout, ErrorLogger? onError})`, `final io.SecurityContext? securityContext`.

- [ ] **Step 1: Generate the test certificate**

Run from `packages/dartnest_io`:

```bash
mkdir -p test/fixtures
openssl req -x509 -newkey rsa:2048 -nodes -days 36500 \
  -subj '/CN=localhost' \
  -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1' \
  -keyout test/fixtures/localhost_key.pem \
  -out test/fixtures/localhost_cert.pem
```

Expected: два PEM-файли (`-----BEGIN CERTIFICATE-----`, `-----BEGIN PRIVATE KEY-----`).

- [ ] **Step 2: Write the failing test**

`packages/dartnest_io/test/io_adapter_tls_test.dart`:

```dart
import 'dart:io' as io;

import 'package:dartnest/dartnest.dart';
import 'package:dartnest_io/dartnest_io.dart';
import 'package:test/test.dart';

/// A self-signed certificate for `localhost` and `127.0.0.1`, test only.
const certificate = 'test/fixtures/localhost_cert.pem';

/// The private key of [certificate].
const privateKey = 'test/fixtures/localhost_key.pem';

void main() {
  test('IoAdapter serves HTTPS with a security context', () async {
    final adapter = IoAdapter(
      securityContext: io.SecurityContext()
        ..useCertificateChain(certificate)
        ..usePrivateKey(privateKey),
    );
    await adapter.listen(
      (request) async => HttpResponse.text('secure'),
      address: io.InternetAddress.loopbackIPv4,
      port: 0,
    );
    addTearDown(adapter.close);
    final client = io.HttpClient(
      context: io.SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificates(certificate),
    );
    addTearDown(client.close);

    final response = await (await client.getUrl(
      Uri.parse('https://localhost:${adapter.port}/'),
    )).close();

    expect(response.statusCode, 200);
    expect(await response.map(String.fromCharCodes).join(), 'secure');
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run from `packages/dartnest_io`: `dart test test/io_adapter_tls_test.dart`
Expected: FAIL на компіляції — `IoAdapter` не має параметра `securityContext`.

- [ ] **Step 4: Bind a secure server when a context is given**

`packages/dartnest_io/lib/src/io_adapter.dart`:

```dart
import 'dart:async';
import 'dart:io' as io;

import 'package:dartnest/adapter.dart';
import 'package:dartnest/dartnest.dart';

import 'io_request_mapper.dart';
import 'io_response_writer.dart';

/// Serves a dartnest application on a `dart:io` [io.HttpServer].
///
/// ```dart
/// final adapter = IoAdapter();
/// final app = await Application.create(appModule, adapter: adapter);
/// await app.listen(port: 3000);
/// print('listening on ${adapter.port}');
/// ```
///
/// The server sends exactly the headers of the application's response
/// (the `dart:io` defaults such as `x-frame-options` are cleared; add them
/// with middleware). Requests are routed on their target only, never on
/// `Host`. Each request runs in its own `Future`; a failure in one never
/// stops the server.
final class IoAdapter implements HttpAdapter {
  /// Creates the adapter; with [securityContext] it serves HTTPS.
  /// [closeTimeout] bounds how long a graceful `close` waits for the
  /// requests in flight. [onError] receives failures the adapter cannot
  /// turn into a response (a handler that throws, a body stream that fails
  /// mid-response, a broken connection); it defaults to [printError] and
  /// must not throw.
  IoAdapter({
    this.securityContext,
    this.closeTimeout = defaultCloseTimeout,
    ErrorLogger? onError,
  }) : onError = onError ?? printError;

  /// The default [closeTimeout].
  static const defaultCloseTimeout = Duration(seconds: 30);

  /// TLS configuration; `null` serves plain HTTP.
  final io.SecurityContext? securityContext;

  /// How long `close()` without `force` waits for the requests in flight,
  /// responses still being written included; then it drops the remaining
  /// connections as `close(force: true)` does and completes normally.
  /// `null` waits without a limit.
  final Duration? closeTimeout;

  /// Where the adapter reports failures.
  final ErrorLogger onError;

  final InFlightRequests _inFlight = InFlightRequests();
  io.HttpServer? _server;
  Future<void>? _closing;

  /// The bound port, useful after listening on port 0; a [StateError]
  /// before `listen` completed or after `close`.
  int get port => switch (_server) {
    final server? when _closing == null => server.port,
    _ => throw StateError('IoAdapter is not listening.'),
  };

  @override
  Future<void> listen(
    RequestHandler handler, {
    required Object address,
    required int port,
  }) async {
    if (_server != null || _closing != null) {
      throw StateError('IoAdapter.listen can be called only once.');
    }
    final context = securityContext;
    final server = context == null
        ? await io.HttpServer.bind(address, port)
        : await io.HttpServer.bindSecure(address, port, context);
    server.defaultResponseHeaders.clear();
    _server = server;
    server.listen(
      (request) => unawaited(_inFlight.track(() => _serve(request, handler))),
    );
  }

  @override
  Future<void> close({bool force = false}) =>
      _closing ??= _shutdown(force: force);

  /// The default [onError]: prints the error and stack trace to stderr.
  static void printError(Object error, StackTrace stackTrace) {
    io.stderr.writeln('dartnest_io: $error\n$stackTrace');
  }

  Future<void> _shutdown({required bool force}) async {
    final server = _server;
    if (server == null) return;
    await server.close(force: force);
    if (force) return;
    final limit = closeTimeout;
    if (limit == null) return _inFlight.idle;
    // Past the limit, drop the remaining connections as force does; their
    // requests stay counted, but nothing waits for them any more.
    return _inFlight.idle.timeout(
      limit,
      onTimeout: () => server.close(force: true),
    );
  }

  Future<void> _serve(io.HttpRequest native, RequestHandler handler) async {
    final response = await _answer(native, handler);
    // Response boundary: the body stream is user code and the client can
    // go away; dart:io has already dropped the connection, so report it.
    try {
      await IoResponseWriter.write(
        response,
        native.response,
        isHead: native.method == 'HEAD',
      );
    } on Object catch (error, stackTrace) {
      onError(error, stackTrace);
    }
  }

  Future<HttpResponse> _answer(
    io.HttpRequest native,
    RequestHandler handler,
  ) async {
    // Request boundary: Application.handle only fails when the
    // application's own error logger throws; answer 500 without a body
    // and keep serving.
    try {
      return await handler(IoRequestMapper.map(native));
    } on Object catch (error, stackTrace) {
      onError(error, stackTrace);
      return HttpResponse(StatusCode.internalServerError);
    }
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run from `packages/dartnest_io`: `dart test`
Expected: `+41: All tests passed!`

Run from repo root: `dart analyze && dart format --output=none --set-exit-if-changed packages`
Expected: `No issues found!`, `0 changed`.

- [ ] **Step 6: Commit**

```bash
git add packages/dartnest_io
git commit -m "feat(io): serve HTTPS with a SecurityContext"
```

---

### Task 7: `dartnest_shelf`: відображення запиту й відповіді

Два чисті перетворювачі без сервера. `ShelfRequestMapper.map`: метод, шлях `'/${request.url.path}'` (відносно `handlerPath`, тож застосунок, змонтований під `/api/`, бачить `/users/1`) із сирим query, кожне значення кожного заголовка (`headersAll`), непрочитане тіло (`request.read()`), адреса клієнта з контексту `shelf.io.connection_info`, якщо запит прийшов через `shelf_io`. `%2F` лишається в сегменті, бо `url.path` зберігає кодування. `ShelfResponseMapper.map`: відкидає `transfer-encoding` (shelf вважав би тіло вже закодованим, Review Focus 5); байти — тіло з `content-length`; потік — тіло з контекстом `shelf.io.buffer_output: false` (Review Focus 1); HEAD — порожнє тіло, явний `content-length` для байтів, потік скасовується непрочитаним.

**Files:**
- Modify: `pubspec.yaml` (корінь, `workspace:`)
- Create: `packages/dartnest_shelf/pubspec.yaml`
- Create: `packages/dartnest_shelf/analysis_options.yaml`
- Create: `packages/dartnest_shelf/lib/src/shelf_request_mapper.dart`
- Create: `packages/dartnest_shelf/lib/src/shelf_response_mapper.dart`
- Test: `packages/dartnest_shelf/test/shelf_request_mapper_test.dart`
- Test: `packages/dartnest_shelf/test/shelf_response_mapper_test.dart`

**Interfaces:**
- Consumes: `HttpRequest`, `HttpResponse`, `BytesBody`, `StreamBody`, `HeaderMap`, `RequestBody`, `ConnectionInfo` (етап 2); `shelf.Request`, `shelf.Response`.
- Produces:
  - `abstract final class ShelfRequestMapper { static const connectionInfoKey = 'shelf.io.connection_info'; static HttpRequest map(shelf.Request request); }`
  - `abstract final class ShelfResponseMapper { static const bufferOutputKey = 'shelf.io.buffer_output'; static shelf.Response map(HttpResponse response, {required bool isHead}); }`

- [ ] **Step 1: Create the package**

Корінь `pubspec.yaml` (повністю; додано останній рядок `workspace:`):

```yaml
name: dartnest_workspace
publish_to: none
environment:
  sdk: ^3.8.0
workspace:
  - packages/dartnest
  - packages/dartnest_conformance
  - packages/dartnest_io
  - packages/dartnest_shelf
```

`packages/dartnest_shelf/pubspec.yaml`:

```yaml
name: dartnest_shelf
description: shelf adapter for dartnest applications, and a shelf Handler to embed one in an existing shelf pipeline.
version: 0.1.0-dev
publish_to: none
environment:
  sdk: ^3.8.0
resolution: workspace
dependencies:
  dartnest: ^0.1.0-dev
  shelf: ^1.4.2
dev_dependencies:
  dartnest_conformance: ^0.1.0-dev
  lints: ^5.1.0
  test: ^1.25.0
```

`packages/dartnest_shelf/analysis_options.yaml`:

```yaml
include: ../../analysis_options.yaml
```

Run from repo root: `dart pub get`
Expected: `Got dependencies!` (`shelf` 1.4.x із pub).

- [ ] **Step 2: Write the failing tests**

`packages/dartnest_shelf/test/shelf_request_mapper_test.dart`:

```dart
import 'dart:io' as io;

import 'package:dartnest_shelf/src/shelf_request_mapper.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

/// Connection details as `shelf_io` stores them in the request context.
final class FakeConnectionInfo implements io.HttpConnectionInfo {
  @override
  final io.InternetAddress remoteAddress = io.InternetAddress.loopbackIPv4;

  @override
  final int remotePort = 50123;

  @override
  final int localPort = 8080;
}

void main() {
  group('ShelfRequestMapper', () {
    test('keeps the method, the path and the raw query', () {
      final request = ShelfRequestMapper.map(
        shelf.Request('get', Uri.parse('http://localhost/users/1?b=%20x&a=1')),
      );

      expect(request.method, 'GET');
      expect(request.uri.path, '/users/1');
      expect(request.uri.query, 'b=%20x&a=1');
    });

    test('uses the path relative to the handler path', () {
      final request = ShelfRequestMapper.map(
        shelf.Request(
          'GET',
          Uri.parse('http://localhost/api/users/1'),
          handlerPath: '/api/',
        ),
      );

      expect(request.uri.path, '/users/1');
    });

    test('keeps %2F inside one segment', () {
      final request = ShelfRequestMapper.map(
        shelf.Request('GET', Uri.parse('http://localhost/files/a%2Fb')),
      );

      expect(request.uri.pathSegments, ['files', 'a/b']);
    });

    test('copies every header value case-insensitively', () {
      final request = ShelfRequestMapper.map(
        shelf.Request(
          'GET',
          Uri.parse('http://localhost/'),
          headers: {
            'X-Multi': ['a', 'b'],
            'X-Case': 'Value',
          },
        ),
      );

      expect(request.headers.all('x-multi'), ['a', 'b']);
      expect(request.headers['X-CASE'], 'Value');
    });

    test('passes the body unread', () async {
      final request = ShelfRequestMapper.map(
        shelf.Request(
          'POST',
          Uri.parse('http://localhost/'),
          body: Stream.fromIterable([
            [1, 2],
            [3],
          ]),
        ),
      );

      expect(await request.body.bytes(), [1, 2, 3]);
    });

    test('reads the client address from the shelf_io context', () {
      final served = ShelfRequestMapper.map(
        shelf.Request(
          'GET',
          Uri.parse('http://localhost/'),
          context: {ShelfRequestMapper.connectionInfoKey: FakeConnectionInfo()},
        ),
      );
      final embedded = ShelfRequestMapper.map(
        shelf.Request('GET', Uri.parse('http://localhost/')),
      );

      expect(served.connectionInfo?.remoteAddress, '127.0.0.1');
      expect(served.connectionInfo?.remotePort, 50123);
      expect(embedded.connectionInfo, isNull);
    });
  });
}
```

`packages/dartnest_shelf/test/shelf_response_mapper_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:dartnest/dartnest.dart';
import 'package:dartnest_shelf/src/shelf_response_mapper.dart';
import 'package:test/test.dart';

void main() {
  group('ShelfResponseMapper', () {
    test('copies status, every header value and the bytes', () async {
      final response = ShelfResponseMapper.map(
        HttpResponse.text(
          'hello',
          status: 201,
          headers: HeaderMap()
            ..add('set-cookie', 'a=1')
            ..add('set-cookie', 'b=2'),
        ),
        isHead: false,
      );

      expect(response.statusCode, 201);
      expect(response.headersAll['set-cookie'], ['a=1', 'b=2']);
      expect(response.headers['content-length'], '5');
      expect(await response.readAsString(), 'hello');
    });

    // Review Focus 5.
    test('drops transfer-encoding set by the application', () async {
      final response = ShelfResponseMapper.map(
        HttpResponse.text(
          'framed',
          headers: HeaderMap.of({'transfer-encoding': 'chunked'}),
        ),
        isHead: false,
      );

      expect(response.headers.containsKey('transfer-encoding'), isFalse);
      expect(await response.readAsString(), 'framed');
    });

    test('streams a stream body without buffering', () async {
      final response = ShelfResponseMapper.map(
        HttpResponse.stream(Stream.value(utf8.encode('chunk'))),
        isHead: false,
      );

      expect(response.contentLength, isNull);
      expect(response.context[ShelfResponseMapper.bufferOutputKey], isFalse);
      expect(await response.readAsString(), 'chunk');
    });

    test('HEAD keeps the content-length of bytes and sends none', () async {
      final response = ShelfResponseMapper.map(
        HttpResponse.text('hello'),
        isHead: true,
      );

      expect(response.headers['content-length'], '5');
      expect(await response.readAsString(), isEmpty);
    });

    test('HEAD cancels a stream body unread', () async {
      final cancelled = Completer<void>();
      final source = StreamController<List<int>>(onCancel: cancelled.complete);

      final response = ShelfResponseMapper.map(
        HttpResponse.stream(source.stream),
        isHead: true,
      );

      await cancelled.future;
      expect(await response.readAsString(), isEmpty);
    });
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run from `packages/dartnest_shelf`: `dart test`
Expected: FAIL на компіляції — `shelf_request_mapper.dart` і `shelf_response_mapper.dart` не існують.

- [ ] **Step 4: Write the mappers**

`packages/dartnest_shelf/lib/src/shelf_request_mapper.dart`:

```dart
import 'dart:io' as io;

import 'package:dartnest/dartnest.dart';
import 'package:shelf/shelf.dart' as shelf;

/// Builds the dartnest [HttpRequest] for a shelf request.
abstract final class ShelfRequestMapper {
  /// The context key under which `shelf_io` stores the connection details.
  static const connectionInfoKey = 'shelf.io.connection_info';

  /// The request for [request]: its method; its path relative to the
  /// shelf `handlerPath` (so a mounted application sees its own paths)
  /// with the raw query; every header value; the unread body; the client
  /// address when `shelf_io` serves it.
  static HttpRequest map(shelf.Request request) {
    final headers = HeaderMap();
    for (final MapEntry(:key, :value) in request.headersAll.entries) {
      for (final single in value) {
        headers.add(key, single);
      }
    }
    final url = request.url;
    return HttpRequest(
      method: request.method,
      uri: Uri(path: '/${url.path}', query: url.hasQuery ? url.query : null),
      headers: headers,
      body: RequestBody(request.read()),
      connectionInfo: switch (request.context[connectionInfoKey]) {
        final io.HttpConnectionInfo info => ConnectionInfo(
          remoteAddress: info.remoteAddress.address,
          remotePort: info.remotePort,
        ),
        _ => null,
      },
    );
  }
}
```

`packages/dartnest_shelf/lib/src/shelf_response_mapper.dart`:

```dart
import 'dart:async';

import 'package:dartnest/dartnest.dart';
import 'package:shelf/shelf.dart' as shelf;

/// Builds the shelf response for a dartnest [HttpResponse].
abstract final class ShelfResponseMapper {
  /// The context key that tells `shelf_io` whether to buffer the body.
  static const bufferOutputKey = 'shelf.io.buffer_output';

  /// The shelf response for [response].
  ///
  /// - Every header value is copied except `transfer-encoding`: shelf
  ///   would treat the body as already chunk-encoded.
  /// - Bytes get `content-length`; a stream is chunked unless the
  ///   application set `content-length`, and is not buffered by
  ///   `shelf_io`, so each chunk reaches the client when it is emitted.
  /// - For `HEAD` ([isHead]) the body is empty, `content-length` of a bytes
  ///   body is kept, and a stream is cancelled unread.
  static shelf.Response map(HttpResponse response, {required bool isHead}) {
    final headers = <String, Object>{
      for (final name in response.headers.names)
        if (name != 'transfer-encoding') name: response.headers.all(name),
    };
    switch (response.body) {
      case BytesBody(:final bytes) when isHead:
        headers['content-length'] = '${bytes.length}';
        return shelf.Response(response.status, headers: headers);
      case BytesBody(:final bytes):
        return shelf.Response(response.status, body: bytes, headers: headers);
      case StreamBody(:final stream) when isHead:
        unawaited(stream.listen(null).cancel());
        return shelf.Response(
          response.status,
          body: const Stream<List<int>>.empty(),
          headers: headers,
        );
      case StreamBody(:final stream):
        return shelf.Response(
          response.status,
          body: stream,
          headers: headers,
          context: {bufferOutputKey: false},
        );
    }
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run from `packages/dartnest_shelf`: `dart test`
Expected: `+11: All tests passed!` (6 + 5).

Run from repo root: `dart analyze && dart format --output=none --set-exit-if-changed packages`
Expected: `No issues found!`, `0 changed`.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml packages/dartnest_shelf
git commit -m "feat(shelf): map shelf requests and responses to dartnest"
```

---

### Task 8: `ShelfAdapter` і conformance для shelf

`ShelfBridge` — shelf `Handler` над `RequestHandler`: відображає запит, викликає `handler`, відображає відповідь (з `isHead`). Межа запиту: якщо `handler` кидає (лише коли кидає логер застосунку), збій іде в `onError`, відповідь — 500 без тіла. `ShelfAdapter` сам прив'язує `HttpServer` (а не `shelf_io.serve`), щоб очистити типові заголовки `dart:io`, тримати порт і рахувати запити в `InFlightRequests`, і на кожен запит викликає `shelf_io.handleRequest(request, bridge, poweredByHeader: null)`. Межа відповіді: збій `handleRequest` під час запису тіла йде в `onError`. Семантика `listen`/`close`/`port` і `closeTimeout` (рішення 11) така сама, як в `IoAdapter`: той самий `_shutdown` з `Future.timeout`, після таймауту `server.close(force: true)` обриває з'єднання, на яких `shelf_io.handleRequest` ще чекає хендлер або пише тіло. Адаптер проходить увесь conformance-набір; відмінності від `IoAdapter` лише ті, що набір дозволяє: `%FF` отримує 400 від самого `shelf_io` (рішення 8), маршрутизація — за `requestedUri` (рішення 7).

**Files:**
- Create: `packages/dartnest_shelf/lib/src/shelf_bridge.dart`
- Create: `packages/dartnest_shelf/lib/src/shelf_adapter.dart`
- Create: `packages/dartnest_shelf/lib/dartnest_shelf.dart`
- Modify: `CLAUDE.md` (список меж помилок)
- Test: `packages/dartnest_shelf/test/shelf_adapter_conformance_test.dart`
- Test: `packages/dartnest_shelf/test/shelf_adapter_test.dart`

**Interfaces:**
- Consumes: `InFlightRequests` і `Application`, що не рахує запити адаптера (Task 1); `AdapterConformance.run`, `AdapterUnderTest` з усіма трьома групами (Tasks 2, 4, 5); `ShelfRequestMapper`, `ShelfResponseMapper` (Task 7).
- Produces:
  - `final class ShelfBridge { ShelfBridge(RequestHandler handler, {required ErrorLogger onError}); Future<shelf.Response> call(shelf.Request request); }`
  - `final class ShelfAdapter implements HttpAdapter { ShelfAdapter({Duration? closeTimeout = ShelfAdapter.defaultCloseTimeout, ErrorLogger? onError}); static const Duration defaultCloseTimeout; final Duration? closeTimeout; final ErrorLogger onError; int get port; Future<void> listen(RequestHandler handler, {required Object address, required int port}); Future<void> close({bool force = false}); static void printError(Object error, StackTrace stackTrace); }`

- [ ] **Step 1: Write the failing tests**

`packages/dartnest_shelf/test/shelf_adapter_conformance_test.dart`:

```dart
import 'package:dartnest_conformance/dartnest_conformance.dart';
import 'package:dartnest_shelf/dartnest_shelf.dart';

void main() => AdapterConformance.run('ShelfAdapter', (onError, closeTimeout) {
  final adapter = ShelfAdapter(onError: onError, closeTimeout: closeTimeout);
  return AdapterUnderTest(adapter, boundPort: () => adapter.port);
});
```

`packages/dartnest_shelf/test/shelf_adapter_test.dart`:

```dart
import 'dart:io' as io;

import 'package:dartnest/dartnest.dart';
import 'package:dartnest_shelf/dartnest_shelf.dart';
import 'package:test/test.dart';

/// Answers every request with `ok`.
Future<HttpResponse> answerOk(HttpRequest request) async =>
    HttpResponse.text('ok');

void main() {
  group('ShelfAdapter', () {
    test('has no port before listen', () {
      expect(() => ShelfAdapter().port, throwsStateError);
    });

    test('serves on the bound ephemeral port', () async {
      final adapter = ShelfAdapter();
      await adapter.listen(
        answerOk,
        address: io.InternetAddress.loopbackIPv4,
        port: 0,
      );
      addTearDown(adapter.close);
      final client = io.HttpClient();
      addTearDown(client.close);

      final response = await (await client.get(
        '127.0.0.1',
        adapter.port,
        '/',
      )).close();

      expect(response.statusCode, 200);
      expect(await response.map(String.fromCharCodes).join(), 'ok');
    });

    test('listens only once', () async {
      final adapter = ShelfAdapter();
      await adapter.listen(
        answerOk,
        address: io.InternetAddress.loopbackIPv4,
        port: 0,
      );
      addTearDown(adapter.close);

      await expectLater(
        adapter.listen(
          answerOk,
          address: io.InternetAddress.loopbackIPv4,
          port: 0,
        ),
        throwsStateError,
      );
    });

    test('close before listen completes and blocks a later listen', () async {
      final adapter = ShelfAdapter();

      await adapter.close();

      await expectLater(
        adapter.listen(
          answerOk,
          address: io.InternetAddress.loopbackIPv4,
          port: 0,
        ),
        throwsStateError,
      );
    });

    test('close is idempotent and forgets the port', () async {
      final adapter = ShelfAdapter();
      await adapter.listen(
        answerOk,
        address: io.InternetAddress.loopbackIPv4,
        port: 0,
      );

      expect(identical(adapter.close(), adapter.close()), isTrue);
      await adapter.close();
      expect(() => adapter.port, throwsStateError);
    });

    test('answers 500 without a body when the handler throws', () async {
      final errors = <Object>[];
      final adapter = ShelfAdapter(onError: (error, _) => errors.add(error));
      await adapter.listen(
        (request) async => throw StateError('handler failed'),
        address: io.InternetAddress.loopbackIPv4,
        port: 0,
      );
      addTearDown(adapter.close);
      final client = io.HttpClient();
      addTearDown(client.close);

      final response = await (await client.get(
        '127.0.0.1',
        adapter.port,
        '/',
      )).close();

      expect(response.statusCode, 500);
      expect(await response.fold<int>(0, (n, chunk) => n + chunk.length), 0);
      expect(errors, [isA<StateError>()]);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run from `packages/dartnest_shelf`: `dart test`
Expected: FAIL на компіляції — `package:dartnest_shelf/dartnest_shelf.dart` не існує.

- [ ] **Step 3: Write the bridge**

`packages/dartnest_shelf/lib/src/shelf_bridge.dart`:

```dart
import 'package:dartnest/dartnest.dart';
import 'package:shelf/shelf.dart' as shelf;

import 'shelf_request_mapper.dart';
import 'shelf_response_mapper.dart';

/// A shelf handler that answers through a dartnest [RequestHandler].
final class ShelfBridge {
  /// Bridges to [handler]; [onError] receives a failure of [handler].
  ShelfBridge(this.handler, {required this.onError});

  /// Answers the mapped requests (usually `Application.handle`).
  final RequestHandler handler;

  /// Where a failure of [handler] is reported.
  final ErrorLogger onError;

  /// Answers [request]; never throws.
  Future<shelf.Response> call(shelf.Request request) async =>
      ShelfResponseMapper.map(
        await _answer(request),
        isHead: request.method == 'HEAD',
      );

  Future<HttpResponse> _answer(shelf.Request request) async {
    // Request boundary: Application.handle only fails when the
    // application's own error logger throws; answer 500 without a body.
    try {
      return await handler(ShelfRequestMapper.map(request));
    } on Object catch (error, stackTrace) {
      onError(error, stackTrace);
      return HttpResponse(StatusCode.internalServerError);
    }
  }
}
```

- [ ] **Step 4: Write the adapter and the barrel**

`packages/dartnest_shelf/lib/src/shelf_adapter.dart`:

```dart
import 'dart:async';
import 'dart:io' as io;

import 'package:dartnest/adapter.dart';
import 'package:dartnest/dartnest.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'shelf_bridge.dart';

/// Serves a dartnest application through shelf on a `dart:io` server.
///
/// ```dart
/// final adapter = ShelfAdapter();
/// final app = await Application.create(appModule, adapter: adapter);
/// await app.listen(port: 3000);
/// ```
///
/// Use it to run shelf on the wire; to put an application into a shelf
/// pipeline you already have, use `shelfHandler(app)` instead. Like
/// `shelf_io`, it routes on the requested URI that shelf builds from
/// `Host` and the target. The server sends exactly the headers of the
/// application's response: no `x-powered-by`, and the `dart:io` defaults
/// are cleared.
final class ShelfAdapter implements HttpAdapter {
  /// Creates the adapter. [closeTimeout] bounds how long a graceful
  /// `close` waits for the requests in flight. [onError] receives failures
  /// the adapter cannot turn into a response (a handler that throws, a body
  /// stream that fails mid-response); it defaults to [printError] and must
  /// not throw.
  ShelfAdapter({this.closeTimeout = defaultCloseTimeout, ErrorLogger? onError})
    : onError = onError ?? printError;

  /// The default [closeTimeout].
  static const defaultCloseTimeout = Duration(seconds: 30);

  /// How long `close()` without `force` waits for the requests in flight,
  /// responses still being written included; then it drops the remaining
  /// connections as `close(force: true)` does and completes normally.
  /// `null` waits without a limit.
  final Duration? closeTimeout;

  /// Where the adapter reports failures.
  final ErrorLogger onError;

  final InFlightRequests _inFlight = InFlightRequests();
  io.HttpServer? _server;
  Future<void>? _closing;

  /// The bound port, useful after listening on port 0; a [StateError]
  /// before `listen` completed or after `close`.
  int get port => switch (_server) {
    final server? when _closing == null => server.port,
    _ => throw StateError('ShelfAdapter is not listening.'),
  };

  @override
  Future<void> listen(
    RequestHandler handler, {
    required Object address,
    required int port,
  }) async {
    if (_server != null || _closing != null) {
      throw StateError('ShelfAdapter.listen can be called only once.');
    }
    final server = await io.HttpServer.bind(address, port);
    server.defaultResponseHeaders.clear();
    _server = server;
    final shelfHandler = ShelfBridge(handler, onError: onError).call;
    server.listen(
      (request) =>
          unawaited(_inFlight.track(() => _serve(request, shelfHandler))),
    );
  }

  @override
  Future<void> close({bool force = false}) =>
      _closing ??= _shutdown(force: force);

  /// The default [onError]: prints the error and stack trace to stderr.
  static void printError(Object error, StackTrace stackTrace) {
    io.stderr.writeln('dartnest_shelf: $error\n$stackTrace');
  }

  Future<void> _shutdown({required bool force}) async {
    final server = _server;
    if (server == null) return;
    await server.close(force: force);
    if (force) return;
    final limit = closeTimeout;
    if (limit == null) return _inFlight.idle;
    // Past the limit, drop the remaining connections as force does; their
    // requests stay counted, but nothing waits for them any more.
    return _inFlight.idle.timeout(
      limit,
      onTimeout: () => server.close(force: true),
    );
  }

  Future<void> _serve(io.HttpRequest request, shelf.Handler handler) async {
    // Response boundary: shelf_io writes the body stream (user code) to a
    // socket that can fail; the connection is already dropped, so report.
    try {
      await shelf_io.handleRequest(request, handler, poweredByHeader: null);
    } on Object catch (error, stackTrace) {
      onError(error, stackTrace);
    }
  }
}
```

`packages/dartnest_shelf/lib/dartnest_shelf.dart` (`shelfHandler` додає Task 9):

```dart
/// Serves dartnest applications through shelf with [ShelfAdapter].
library;

export 'src/shelf_adapter.dart';
```

- [ ] **Step 5: Run tests to verify they pass**

Run from `packages/dartnest_shelf`: `dart test`
Expected: `+51: All tests passed!` (34 conformance: 14 `requests`, 9 `bodies`, 11 `lifecycle`; 6 `ShelfAdapter`; 11 mappers). `shelf_io` друкує в stderr `ERROR` на тест `%FF` — це його власний лог відмови, не збій.

- [ ] **Step 6: Add the shelf boundaries to `CLAUDE.md`**

У `CLAUDE.md`, список меж помилок, замінити кінець пункту `IoAdapter` (Task 5)

```
  dropped, and the adapter keeps serving.
```

на

```
  dropped, and the adapter keeps serving;
- `ShelfBridge` and `ShelfAdapter` (added by the adapters work) do the same
  for shelf: `ShelfBridge` reports a failure of the request handler to its
  `onError` and answers 500 without a body; `ShelfAdapter` reports a failure
  of `shelf_io.handleRequest` while writing the response to its `onError`.
```

Run from repo root: `dart analyze && dart format --output=none --set-exit-if-changed packages`
Expected: `No issues found!`, `0 changed`.

- [ ] **Step 7: Commit**

```bash
git add CLAUDE.md packages/dartnest_shelf
git commit -m "feat(shelf): add ShelfAdapter passing the adapter conformance suite"
```

---

### Task 9: `shelfHandler(app)` — вбудовування в shelf-пайплайн

`shelfHandler(app)` — той самий `ShelfBridge` над `app.handle`. Пайплайн лишається користувачевим (`CLAUDE.md`: «The user's HTTP stack is not ours»): функція нічого не додає довкола, застосунок бачить шлях відносно `handlerPath`, тож монтується під префіксом (`request.change(path: 'api')` у `Cascade`, `Router.mount` з `shelf_router`). Застосунок не закривається разом із сервером; після `app.close()` хендлер відповідає 503 (рішення 9). Тести запускають справжній `shelf_io.serve` на `127.0.0.1:0` з middleware користувача і монтуванням під `/api/`.

**Files:**
- Create: `packages/dartnest_shelf/lib/src/shelf_handler.dart`
- Modify: `packages/dartnest_shelf/lib/dartnest_shelf.dart`
- Test: `packages/dartnest_shelf/test/shelf_handler_test.dart`

**Interfaces:**
- Consumes: `ShelfBridge`, `ShelfAdapter.printError` (Task 8); `Application.handle`, `Application.close` (етап 2).
- Produces: `shelf.Handler shelfHandler(Application app, {ErrorLogger? onError})` з `package:dartnest_shelf/dartnest_shelf.dart`.

- [ ] **Step 1: Write the failing test**

`packages/dartnest_shelf/test/shelf_handler_test.dart`:

```dart
import 'dart:convert';
import 'dart:io' as io;

import 'package:dartnest/dartnest.dart';
import 'package:dartnest_conformance/dartnest_conformance.dart';
import 'package:dartnest_shelf/dartnest_shelf.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

/// The user's own shelf stack: a middleware that tags every response, an
/// own route, and the dartnest application mounted under `/api/`.
shelf.Handler userPipeline(shelf.Handler api) => const shelf.Pipeline()
    .addMiddleware(
      (inner) =>
          (request) async =>
              (await inner(request)).change(headers: {'x-user-stack': 'yes'}),
    )
    .addHandler(
      shelf.Cascade()
          .add(
            (request) => request.url.path == 'health'
                ? shelf.Response.ok('healthy')
                : shelf.Response.notFound(null),
          )
          .add(
            (request) => request.url.path.startsWith('api/')
                ? api(request.change(path: 'api'))
                : shelf.Response.notFound(null),
          )
          .handler,
    );

void main() {
  group('shelfHandler', () {
    late Application app; // Set in setUp before every test.

    setUp(() async {
      app = await Application.create(
        () => conformanceModule(ConformanceProbe()),
      );
    });
    tearDown(() => app.close());

    test('answers inside a user pipeline, mounted under a prefix', () async {
      final server = await shelf_io.serve(
        userPipeline(shelfHandler(app)),
        io.InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(server.close);
      final client = io.HttpClient();
      addTearDown(client.close);

      Future<(int, String?, String)> get(String path) async {
        final response = await (await client.get(
          '127.0.0.1',
          server.port,
          path,
        )).close();
        return (
          response.statusCode,
          response.headers.value('x-user-stack'),
          await utf8.decoder.bind(response).join(),
        );
      }

      expect(await get('/api/users/1'), (
        200,
        'yes',
        jsonEncode({'id': 1, 'name': 'ann'}),
      ));
      expect(await get('/health'), (200, 'yes', 'healthy'));
    });

    test('answers 503 after the application is closed', () async {
      final handler = shelfHandler(app);
      await app.close();

      final response = await handler(
        shelf.Request('GET', Uri.parse('http://localhost/users/1')),
      );

      expect(response.statusCode, 503);
    });

    test('answers 500 without a body when the app logger throws', () async {
      final failing = await Application.create(
        () => conformanceModule(ConformanceProbe()),
        onError: (error, _) => throw StateError('logger failed'),
      );
      addTearDown(failing.close);
      final errors = <Object>[];

      final response = await shelfHandler(
        failing,
        onError: (error, _) => errors.add(error),
      )(shelf.Request('GET', Uri.parse('http://localhost/probe/fail')));

      expect(response.statusCode, 500);
      expect(await response.readAsString(), isEmpty);
      expect(errors, [isA<StateError>()]);
    });

    test('drops the body of a HEAD response', () async {
      final response = await shelfHandler(app)(
        shelf.Request('HEAD', Uri.parse('http://localhost/users/1')),
      );

      expect(response.statusCode, 200);
      expect(
        response.headers['content-length'],
        '${jsonEncode({'id': 1, 'name': 'ann'}).length}',
      );
      expect(await response.readAsString(), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run from `packages/dartnest_shelf`: `dart test test/shelf_handler_test.dart`
Expected: FAIL на компіляції — `shelfHandler` не визначено.

- [ ] **Step 3: Write `shelfHandler` and export it**

`packages/dartnest_shelf/lib/src/shelf_handler.dart` (публічна функція зі специфікації — дозволений виняток з правила «класи замість top-level функцій»):

```dart
import 'package:dartnest/dartnest.dart';
import 'package:shelf/shelf.dart' as shelf;

import 'shelf_adapter.dart';
import 'shelf_bridge.dart';

/// A shelf [shelf.Handler] that answers through [app], for embedding a
/// dartnest application in an existing shelf pipeline.
///
/// The pipeline stays the user's: the handler changes nothing around it.
/// The application sees paths relative to the shelf `handlerPath`, so it
/// can be mounted under a prefix. [app] is not closed with the server;
/// after `app.close()` the handler answers 503. [onError] receives a
/// failure of `app.handle` (only possible when the application's own error
/// logger throws), answered with a 500 without a body; it defaults to
/// [ShelfAdapter.printError] and must not throw.
///
/// ```dart
/// final handler = const shelf.Pipeline()
///     .addMiddleware(shelf.logRequests())
///     .addHandler(shelfHandler(app));
/// await shelf_io.serve(handler, 'localhost', 8080);
/// ```
shelf.Handler shelfHandler(Application app, {ErrorLogger? onError}) =>
    ShelfBridge(app.handle, onError: onError ?? ShelfAdapter.printError).call;
```

`packages/dartnest_shelf/lib/dartnest_shelf.dart`:

```dart
/// Serves dartnest applications through shelf: [ShelfAdapter] runs a
/// server, [shelfHandler] embeds an application in an existing shelf
/// pipeline.
library;

export 'src/shelf_adapter.dart';
export 'src/shelf_handler.dart';
```

- [ ] **Step 4: Run tests to verify they pass**

Run from `packages/dartnest_shelf`: `dart test`
Expected: `+55: All tests passed!`

Run from repo root: `dart analyze && dart format --output=none --set-exit-if-changed packages`
Expected: `No issues found!`, `0 changed`.

- [ ] **Step 5: Commit**

```bash
git add packages/dartnest_shelf
git commit -m "feat(shelf): add shelfHandler to embed an application in a shelf pipeline"
```

---

### Task 10: Документація: quick start адаптерів і роадмап

README обох адаптерів (quick start і правила, які користувач має знати: заголовки, обрамлення, HEAD, `close` і `closeTimeout`, `onError`, відсутність ліміту тіла), останній абзац README ядра (він каже, що адаптери «planned in later milestones») і рядок етапу 3 у роадмапі з посиланням на цей план, як у етапів 1 і 2. Коду немає; перевірка — повний прогін усіх пакетів.

**Files:**
- Create: `packages/dartnest_io/README.md`
- Create: `packages/dartnest_shelf/README.md`
- Modify: `packages/dartnest/README.md` (останній абзац)
- Modify: `docs/superpowers/ROADMAP.md` (рядок етапу 3)

**Interfaces:**
- Consumes: `IoAdapter({SecurityContext? securityContext, Duration? closeTimeout, ErrorLogger? onError})`, `IoAdapter.port`, `IoAdapter.defaultCloseTimeout` (Tasks 3–6); `ShelfAdapter({Duration? closeTimeout, ErrorLogger? onError})`, `shelfHandler(Application app, {ErrorLogger? onError})` (Tasks 8, 9).
- Produces: нічого для інших задач.

- [ ] **Step 1: Write the `dartnest_io` README**

`packages/dartnest_io/README.md`:

````markdown
# dartnest_io

Serves a dartnest application on a `dart:io` `HttpServer`.

```dart
import 'package:dartnest/dartnest.dart';
import 'package:dartnest_io/dartnest_io.dart';

Future<void> main() async {
  final adapter = IoAdapter();
  // appModule: your root module, `Module appModule() => Module(...)`.
  final app = await Application.create(appModule, adapter: adapter);
  await app.listen(port: 8080);
  print('Listening on http://localhost:${adapter.port}');
}
```

For HTTPS pass a context:
`IoAdapter(securityContext: SecurityContext()..useCertificateChain('cert.pem')..usePrivateKey('key.pem'))`.

Rules:

- The response carries exactly the application's headers. The `dart:io`
  defaults (`content-type: text/plain`, `x-frame-options`,
  `x-content-type-options`, `x-xss-protection`) are cleared; add security
  headers with middleware.
- Bodies stream both ways. A byte body is sent with `content-length`; a
  stream is chunked unless the application set `content-length`, and each
  chunk is sent as soon as the stream emits it. A `transfer-encoding`
  header from the application is ignored; `connection: close` closes the
  connection after the response.
- `HEAD` gets the headers of `GET` and no body; a stream body is cancelled
  unread.
- Routing uses the request target only, never `Host`. Dot segments are
  removed, `%2F` stays inside one path segment, and invalid percent-encoding
  is a 400.
- `app.close()` stops accepting connections, waits for the responses being
  written (streams included) and then closes the application;
  `app.close(force: true)` drops them at once. The wait is bounded by
  `IoAdapter(closeTimeout: ...)`, 30 seconds by default: when it expires,
  the remaining connections are dropped as with `force: true` and
  `app.close()` still completes normally. `closeTimeout: null` waits
  without a limit (an endless stream then keeps `close` waiting).
- Failures that can no longer become a response (a body stream that fails
  mid-response, a client that goes away) go to `IoAdapter(onError: ...)`;
  the default prints them to stderr.
- There is no request body size limit: the handler reads the body as a
  stream and decides how much to accept.
````

- [ ] **Step 2: Write the `dartnest_shelf` README**

`packages/dartnest_shelf/README.md`:

````markdown
# dartnest_shelf

Serves a dartnest application through [shelf](https://pub.dev/packages/shelf),
or embeds it in a shelf pipeline you already have.

Let dartnest run shelf on the wire:

```dart
import 'package:dartnest/dartnest.dart';
import 'package:dartnest_shelf/dartnest_shelf.dart';

Future<void> main() async {
  // appModule: your root module, `Module appModule() => Module(...)`.
  final app = await Application.create(appModule, adapter: ShelfAdapter());
  await app.listen(port: 8080);
}
```

Or keep your own server and middleware:

```dart
import 'package:dartnest/dartnest.dart';
import 'package:dartnest_shelf/dartnest_shelf.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final app = await Application.create(appModule);
  final handler = const shelf.Pipeline()
      .addMiddleware(shelf.logRequests())
      .addHandler(shelfHandler(app));
  await shelf_io.serve(handler, 'localhost', 8080);
}
```

Rules:

- `shelfHandler(app)` changes nothing around it. The application sees the
  path relative to the shelf `handlerPath`, so it can be mounted under a
  prefix. The application is not closed with your server; after
  `app.close()` the handler answers 503.
- `ShelfAdapter` behaves like `IoAdapter` from `dartnest_io`: exactly the
  application's headers (no `x-powered-by`, no `dart:io` defaults), byte
  bodies with `content-length`, streams chunked and unbuffered, `HEAD`
  without a body, and `app.close()` waits for the responses being written,
  for at most `ShelfAdapter(closeTimeout: ...)` (30 seconds by default;
  `null` waits without a limit) before it drops the remaining connections.
  It routes on the URI `shelf_io` builds from `Host` and the target, and
  `shelf_io` itself answers 400 to invalid percent-encoding.
- Failures that can no longer become a response go to the `onError` of
  `ShelfAdapter` or `shelfHandler`; the default prints them to stderr.
- There is no request body size limit: the handler reads the body as a
  stream and decides how much to accept.
````

- [ ] **Step 3: Point the core README to the adapters**

У `packages/dartnest/README.md` замінити останній абзац

```
This package has no server: `app.handle(request)` answers an `HttpRequest`
directly and `TestClient` wraps it for tests. Annotations, an analyzer-based
generator and HTTP adapters (`dart:io`, shelf) are planned in later
milestones; see the repository's `docs/` directory for the roadmap.
```

на

```
This package has no server of its own: `app.handle(request)` answers an
`HttpRequest` directly and `TestClient` wraps it for tests. To serve over
HTTP, pass an adapter to `Application.create`: `IoAdapter` from
`dartnest_io` (a `dart:io` `HttpServer`) or `ShelfAdapter` from
`dartnest_shelf`; `shelfHandler(app)` from `dartnest_shelf` embeds an
application in an existing shelf pipeline. Annotations and an
analyzer-based generator are planned in later milestones; see the
repository's `docs/` directory for the roadmap.
```

- [ ] **Step 4: Link this plan from the roadmap**

У `docs/superpowers/ROADMAP.md`, таблиця v1.0, замінити

```
| 3 | **Адаптери** | `dartnest_io`, `dartnest_shelf` |
```

на

```
| 3 | **Адаптери** (план `2026-10-13-dartnest-adapters.md`) | `dartnest_io`, `dartnest_shelf` |
```

(решта рядка без змін).

- [ ] **Step 5: Run everything**

Run from repo root: `dart analyze && dart format --output=none --set-exit-if-changed packages`
Expected: `No issues found!`, `0 changed`.

Run from each package directory: `dart test`
Expected: `packages/dartnest` — `+241`, `packages/dartnest_conformance` — `+13`, `packages/dartnest_io` — `+41`, `packages/dartnest_shelf` — `+55`; усі `All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add packages/dartnest_io/README.md packages/dartnest_shelf/README.md packages/dartnest/README.md docs/superpowers/ROADMAP.md
git commit -m "docs: add adapter quick starts and link the stage 3 plan"
```

---

## Самоперевірка

**Покриття специфікації.**

| Вимога | Задача |
|---|---|
| 2: окремі пакети `dartnest_io` (→ `dartnest`) і `dartnest_shelf` (→ `dartnest`, `shelf`); ядро без `dart:io` і shelf | 1, 3, 7 |
| 5: `HttpAdapter.listen(RequestHandler, {address, port})` і `close({force})` в обох адаптерах | 3, 5, 8 |
| 5: `IoAdapter({SecurityContext?})` | 6 |
| 5: `ShelfAdapter()` і `shelfHandler(app)` для вбудовування в наявний shelf-пайплайн без змін | 8, 9 |
| 5, 8: спільний conformance-набір на реальних сокетах і ефемерному порту, запускається для обох адаптерів | 2, 4, 5 (групи); 3, 8 (запуск) |
| conformance: методи, заголовки (мультизначення, регістр, кілька `set-cookie`, повтори), keep-alive і конвеєрні запити, адреса клієнта | 2 (`requests`) |
| conformance: ціль запиту як у `TestClient`, dot-сегменти, `//`, `%2F` у сегменті, `%FF` → 400 | 2, 3 |
| conformance: потокові тіла в обидва боки без буферизації, великі тіла, `content-length` vs chunked, HEAD без тіла, `transfer-encoding`/`connection` | 4 (`bodies`), 7 |
| conformance: коректне закриття (не приймає нових, чекає запити в польоті, `force`, порт звільнено), 503 після `close` | 5 (`lifecycle`), 9 |
| рішення автора: graceful close з `closeTimeout` в обох адаптерах; `Application.close` не зависає на покинутому хендлері | 1, 5, 6, 8 |
| збої: логер застосунку кидає → 500 і сервер працює далі; потік падає; клієнт пішов — без падіння і без зависання лічильника | 5, 8, 9 |
| 10.1: hot reload не блокується (адаптер тримає лише `RequestHandler`) | Global Constraints, 3 |
| роадмап, етап 3 «Готово, коли» | 3–9, 10 |

Поза планом (рішення 10): ліміт розміру тіла запиту, WebSocket/hijack, HTTP/2.

**Плейсхолдери.** Пошук `TBD`, `TODO`, «similar to Task», «add error handling», «implement later» — нічого. Кожен крок з кодом містить повний файл; зміни `CLAUDE.md`, кореневого `pubspec.yaml`, README, роадмапу і наявних файлів ядра (`application.dart`, `http_adapter.dart`, `application_lifecycle_test.dart` у Task 1) дано точним «було → стало». Проміжні версії файлів, які змінюються кількома задачами (`adapter_conformance.dart` у Tasks 2/4/5, `io_adapter.dart` у Tasks 3/4/5/6, `io_response_writer.dart` у Tasks 3/4, `dartnest_shelf.dart` у Tasks 8/9), наведено повністю в кожній задачі.

**Узгодженість типів.** Імена між задачами звірено з кодом: `InFlightRequests.track/idle/count`; `AdapterFactory(onError, closeTimeout)`, `AdapterUnderTest(adapter, boundPort:)`, `AdapterConformance.run`, `RequestConformance/BodyConformance/LifecycleConformance.register`; `ConformanceServer.start(..., applicationLogger:, closeTimeout:)/defaultCloseTimeout/send/uri/close/firstAdapterError/adapterErrors/applicationErrors`; `ConformanceProbe.entered/release/firstUploadChunk/endlessCancelled`; `ConformanceData.bytes/chunks/checksum/endless`; `conformanceModule`; `RawHttp.head/exchange/abortAfterFirstBytes`; `RawResponse.parse/isComplete`; `IoRequestMapper.map/target`; `IoResponseWriter.write(..., isHead:)`; `IoAdapter({securityContext, closeTimeout, onError}).port/printError/defaultCloseTimeout`; `ShelfRequestMapper.map`, `ShelfResponseMapper.map(..., isHead:)`; `ShelfBridge(handler, onError:).call`; `ShelfAdapter({closeTimeout, onError}).port/printError/defaultCloseTimeout`; `shelfHandler(app, {onError})`. З ядра використано лише наявні `Application.create/listen/close/handle` (Task 1 змінює лише внутрішню поведінку `listen`/`close` і dartdoc `HttpAdapter`), `HttpAdapter`, `RequestHandler`, `ErrorLogger`, `HttpRequest`, `HttpResponse`, `BytesBody`, `StreamBody`, `RequestBody`, `HeaderMap`, `ConnectionInfo`, `StatusCode`, `TestClient`.

**Перевірка.** Код кожної задачі зібрано в чистій копії `master` (d1e7dc3) у стані після Tasks 3, 4, 5, 7, 8 і після останньої: `dart pub get --offline`, `dart analyze` — «No issues found!», `dart format` — 0 змінених файлів. Тести під час написання плану не запускались (лише компіляція й аналіз); кількості в кроках «Expected» пораховано з коду. Якщо при виконанні кількість або стан тесту в кроці «verify it fails» не збігається, це сигнал перевірити задачу, а не підганяти число. Після додавання `closeTimeout` (рішення 11, 12) код знову зібрано так само (стан після Tasks 3, 5 і після останньої; Task 1 — накладанням «було → стало» на `master`) і цього разу тести запущено: нові тести Task 1 і групи `lifecycle` проходять для обох адаптерів (група `lifecycle` — 5 прогонів поспіль без флейків) і падають без відповідного коду так, як описано в кроках «verify it fails» Tasks 1 і 5; кількості `+241`/`+40`/`+41`/`+55` збіглися. Той самий прогін показав два дефекти тестів, не пов'язані з таймаутом; їх виправлено: `serves the users app` (група `requests`) порівнював запис `(status, json)`, а `Map` усередині запису порівнюється за ідентичністю — тепер статус і JSON перевіряються окремо; `RawHttp reads a content-length response` (`raw_http_test.dart`) чекав `content-length: 5` від голого `dart:io`-сервера, який для `write('hello')` шле chunked — тепер відповідь пишеться вручну в сокет (`content-length: 5` + друга конвеєрна відповідь), тож тест падає, якщо `RawResponse` ігнорує `content-length`. Після виправлення в чистій копії (стан після Task 3) `dart test` у `dartnest_conformance` дає `+13`, у `dartnest_io` — `+19`, `dart analyze` і `dart format` чисті; інших записів із `Map`/`List` в `expect` у плані немає. Найбільший файл у `lib/` — `conformance_app.dart` (189 рядків), у `test/` — `conformance_app_test.dart` (121 рядок).

**Review Focus.** Кожен пункт закріплено тестом із коментарем `// Review Focus N`: 1 → Task 4 (`bodies`) і Task 7; 2 → Task 4; 3 → Task 2/3 (`requests`, уперше запускається в Task 3); 4 → Task 5 (`lifecycle`); 5 → Task 4 і Task 7; 6 → Task 1 і Task 5 (`lifecycle`).

## Відкриті питання для автора

1. **Маршрутизація `ShelfAdapter` за `Host`.** `ShelfAdapter` бере шлях з `requestedUri`, як `shelf_io` (рішення 7), а `IoAdapter` ігнорує `Host`. Вирівняти `ShelfAdapter` на ціль запиту (власний розбір, як в `IoAdapter`) чи лишити поведінку shelf?
2. **`onError` адаптера vs логер застосунку.** Адаптер має власний `onError` (типово stderr), окремий від `Application.create(onError:)`. Чи варто, щоб `Application.listen` передавав свій логер адаптеру (зміна контракту `HttpAdapter`), щоб користувач налаштовував логування в одному місці?
