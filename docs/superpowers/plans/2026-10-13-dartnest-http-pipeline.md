# dartnest HTTP Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Етап 2 роадмапу: HTTP-конвеєр у пакеті `dartnest` без жодного сервера — `HttpRequest`/`HttpResponse`, роутер на дереві сегментів, `ExecutionContext`, `Controller<T>`/`Route` на `HandlerSpec`, guards → interceptors → pipes → handler → filters, серіалізація, `Application.create`, `app.handle`, `TestClient` і e2e-тест без сокетів.

**Architecture:** Чотири шари, кожен залежить лише від попередніх. `http/` — незмінні значення запиту й відповіді. `routing/` — розбір шаблонів і `Router<V>` (generic, нічого не знає про контролери). `pipeline/` + `controller/` — контракти компонентів, `ExecutionContext`, опис контролерів як значень і `Pipeline.run`, що виконує один ендпоінт. `app/` — `RouteTableBuilder` (на старті: перевірка роутів до запуску провайдерів, потім створення контролерів через `Container.injectorFor` і заповнення `Router<Endpoint>`), `RequestDispatcher` (один запит: роутинг, 404/405, конвеєр, серіалізація, межа помилок) і `Application` (middleware, атомарна підміна таблиці роутів, `listen` через `HttpAdapter`, повторюваний `close`). `ModuleInjector` і `ModuleGraph` лишаються внутрішніми; публічний API розширюється лише новими типами та `Module.controllers`, `Container.close`.

**Tech Stack:** Dart SDK ^3.8.0 (без dot shorthands, null-aware elements і primary constructors), `package:meta`, `package:test`, `package:lints` + strict-casts/inference/raw-types. Жодного `dart:io` і shelf у `dartnest`.

**Spec:** `docs/superpowers/specs/2026-10-13-dartnest-design.md` (розділи 4 «Контролери, роути, конвеєр», 5 «HTTP-адаптер і Application», 7 «Помилки», 8 «Тестування», 10.1 «Вимоги до ядра»).

## Global Constraints

- Пакет `dartnest` залежить лише від Dart SDK і `package:meta`. Ні `dart:io` (включно з `HttpHeaders`, `HttpStatus`), ні shelf: адаптери — етап 3. `TestClient` викликає `app.handle` напряму.
- Публічний API, dartdoc і повідомлення комітів — англійською; кожен публічний клас і член має dartdoc.
- `CLAUDE.md`: ≤ 300 рядків на файл у `lib/`, ≤ 500 на тестовий файл, ≤ 40 рядків на метод, ≤ 5 параметрів, ≤ 3 рівні вкладеності; один публічний клас або sealed-родина на файл; без `!`, `dynamic`, `late` без коментаря, `catch` без `on`; `Error` не ловиться, окрім задокументованих меж (Task 7 оновлює `CLAUDE.md`).
- Перед кожним комітом: `dart analyze` (корінь репо) — «No issues found!», `dart format --output=none --set-exit-if-changed packages` — 0 змінених файлів, `dart test` у `packages/dartnest` — усе зелене.
- Помилки мають стабільні поля (тести перевіряють поля, а не лише текст). `InjectionError` не розширюється; нові родини: `RoutingError` (`DuplicateRouteError`, `InvalidRoutePatternError`), `PipelineError` (`UnsupportedConversionError`, `UnknownRouteParameterError`, `SerializationError`), `ApplicationError` (`ControllerCreationError`, `InvalidComponentError`, `ApplicationStateError`). Усі sealed, наслідують `DartnestError`.
- Hot reload (специфікація 10.1) не реалізується, але не блокується: `Application.create` приймає `Module Function()`, `close()` повторюваний, таблиця роутів підміняється одним присвоєнням (`@internal replaceRoutes`), контролери створюються з `Container.injectorFor`. `Container.reassemble` у цьому плані не додається.
- Відхилення від специфікації, зафіксовані цим планом:
  - `ctx.param<T>()`, `ctx.query<T>()` і новий `ctx.bodyAs<T>(fromJson)` повертають `Future<T>` (pipes — `FutureOr`): `await ctx.param<int>('id')`.
  - Списки `guards/interceptors/pipes/filters` передаються одним об'єктом `Enhancers(...)` у `Controller`, `Route` і `Application.create` (правило ≤ 5 параметрів).
  - `ExceptionFilter<E>` — абстрактний клас (`extends`), бо `catches(error)` перевіряє `E` під час виконання; решта контрактів — `interface`. Усі компоненти реалізують маркер `PipelineComponent`.
  - Окремого `HttpTransport` немає: `HttpContext extends Transport`. `HttpRequest.body` — обгортка `RequestBody` (`bytes/text/json/stream` з кешуванням), а не голий `Stream`.
  - `Application.create(Module Function())` і `Application.fromModule(Module)` замість одного методу з union-параметром. `Module` отримує шостий параметр `controllers` (його вимагає специфікація).
  - `HttpException` реалізує `Exception` і не наслідує `DartnestError`. 404/405 роутера відповідає типовий `HttpErrorResponder`, користувацькі фільтри їх не бачать (специфікація: фільтри — кроки 5–8); змінити їх можна middleware.
  - `List<int>` серіалізується як JSON-масив; байтами є лише `Uint8List` і `Stream<List<int>>`.
  - Модульного рівня enhancers немає (лише app → controller → route, як у специфікації). App-рівневі `Use<T>` резолвляться через кореневий модуль.

## Review Focus

1. Хендлер повертає `List<int>` (наприклад, `[1, 2, 3]`): очікується JSON-масив з `application/json`, а не тіло з байтами. Закріплено в Task 9 (`List<int> is a JSON array, not a byte body`).
2. Зламаний JSON, JSON-масив замість об'єкта або `FormatException` з `fromJson` у `ctx.bodyAs`: очікується 400 з повідомленням, а не 500. Закріплено в Task 6 (група `bodyAs`: `malformed JSON is a 400`, `a JSON array where an object is expected is a 400`, `FormatException from fromJson is a 400`).
3. Перекриття `/users/me` і `/users/:id/posts`: `GET /users/me/posts` має повернутися зі статичної гілки `me` і збігтися з `/users/:id/posts` (`id = me`), а `DELETE /users/me` — з `DELETE /users/:id`. Закріплено в Task 4 (`backtracks from a static branch to a parameter branch`).
4. `/users/`, `/users//2`, `/files/a%20b`, `/files/raw/x/y%2Fz`: порожні сегменти відкидаються, сегменти декодуються до роутингу, `*` захоплює решту шляху, з'єднану через `/` (тому `%2F` після wildcard не відрізняється від `/`). Закріплено в Task 10 (`trailing and repeated slashes, percent-decoding, wildcard`).
5. `close()` під час запиту в польоті та повторний `close()`: той самий `Future`, адаптер закривається один раз, запит у польоті завершується до закриття контейнера, новий `handle` отримує 503. Закріплено в Task 11 (`is idempotent and closes the adapter and container once`, `waits for in-flight requests, new ones get 503`).

---

## File Structure

```
packages/dartnest/
  lib/dartnest.dart                         # barrel: + http, routing errors, pipeline, controller, app
  lib/testing.dart                          # TestClient, TestResponse
  lib/src/http/
    header_map.dart                         # HeaderMap: case-insensitive multimap
    connection_info.dart                    # ConnectionInfo
    status_code.dart                        # StatusCode constants + reason phrases
    http_exception.dart                     # HttpException family
    request_body.dart                       # RequestBody: read once, cached bytes/text/json
    http_request.dart                       # HttpRequest
    response_body.dart                      # ResponseBody: BytesBody | StreamBody
    http_response.dart                      # HttpResponse + factories
    response_head.dart                      # ResponseHead: status/headers set by handlers
  lib/src/routing/
    routing_error.dart                      # RoutingError family
    pattern_segment.dart                    # internal: Static/Param/Wildcard segments
    route_pattern.dart                      # internal: RoutePattern.join + validation
    route_match.dart                        # internal: RouteFound | RouteMethodNotAllowed | RouteNotFound
    router.dart                             # internal: Router<V> segment trie
  lib/src/pipeline/
    pipeline_component.dart                 # PipelineComponent marker
    use.dart                                # Use<T>: resolve from the module injector
    enhancers.dart                          # Enhancers parameter object
    guard.dart, interceptor.dart, pipe.dart, exception_filter.dart
    argument_source.dart, argument_meta.dart
    transport.dart                          # Transport, HttpContext
    execution_context.dart                  # ExecutionContext
    pipeline_error.dart                     # PipelineError family
    value_converter.dart                    # internal: String -> int/double/num/bool/DateTime
    argument_resolver.dart                  # internal: pipes + conversion
    enum_pipe.dart                          # EnumPipe
    handler_spec.dart                       # HandlerSpec (shared with GraphQL in v2)
    resolved_enhancers.dart                 # internal: Use resolved, kinds checked, levels chained
    endpoint.dart                           # internal: one routed handler
    pipeline.dart                           # internal: Pipeline.run
    serializer_registry.dart                # SerializerRegistry
    response_serializer.dart                # internal: result -> HttpResponse
    http_error_responder.dart               # internal: error -> JSON response (exports ErrorLogger)
  lib/src/controller/
    route.dart                              # Route<T>
    controller.dart                         # ControllerSpec, Controller<T>
  lib/src/app/
    application_error.dart                  # ApplicationError family
    route_table_builder.dart                # internal: validate + build Router<Endpoint>
    request_dispatcher.dart                 # internal: one request without middleware
    http_adapter.dart                       # HttpAdapter, RequestHandler
    middleware.dart                         # Middleware typedef
    in_flight_requests.dart                 # internal: counter for graceful close
    application.dart                        # Application
  lib/src/testing/
    test_client.dart, test_response.dart
  lib/src/di/module.dart                    # modified: controllers
  lib/src/di/module_graph.dart              # modified: shape includes controller types
  lib/src/di/container.dart                 # modified: close(), isClosed
  test/helpers/{http,pipeline,app}_fixtures.dart, fake_adapter.dart
  test/{http,routing,pipeline,controller,app,e2e}/*_test.dart
```

Межі відповідальності: `routing/` не знає про контролери; `pipeline/` не знає про роутер; лише `app/` поєднує контейнер, роутер і конвеєр. Файли з позначкою internal не експортуються з barrel.

Передумова для кожної задачі: Dart SDK ≥ 3.8 на PATH (`dart --version`). Команди `dart test` запускаються з `packages/dartnest`, `dart analyze` і `dart format` — з кореня репо.

Barrel: у кожній задачі нові `export`-рядки додаються в `packages/dartnest/lib/dartnest.dart` так, щоб усі `export`-рядки лишалися в алфавітному порядку.

---

### Task 1: HTTP-примітиви: `HeaderMap`, `StatusCode`, `HttpException`

Незмінні будівельні блоки HTTP без `dart:io`: регістронезалежна мультимапа заголовків, коди статусу з reason phrase і відкрита ієрархія `HttpException`. `HttpException` реалізує `Exception` і **не** наслідує `DartnestError`: це очікувана відповідь клієнту, а не дефект застосунку, і користувачі можуть наслідувати її без `base`. Підкласи лежать в одному файлі як задокументоване відхилення від правила «один публічний клас на файл» (це одна родина).

**Files:**
- Create: `packages/dartnest/lib/src/http/header_map.dart`
- Create: `packages/dartnest/lib/src/http/connection_info.dart`
- Create: `packages/dartnest/lib/src/http/status_code.dart`
- Create: `packages/dartnest/lib/src/http/http_exception.dart`
- Modify: `packages/dartnest/lib/dartnest.dart`
- Test: `packages/dartnest/test/http/header_map_test.dart`
- Test: `packages/dartnest/test/http/http_exception_test.dart`

**Interfaces:**
- Consumes: nothing new (only `dart:convert`).
- Produces:
  - `final class HeaderMap { HeaderMap(); HeaderMap.of(Map<String, String>); HeaderMap.copy(HeaderMap); HeaderMap.unmodifiable(HeaderMap); String? operator [](String); List<String> all(String); bool contains(String); Iterable<String> get names; bool get isReadOnly; void add/set(String, String); void setAll(HeaderMap); void remove(String); Map<String, List<String>> toMap(); }` — names lower-cased.
  - `final class ConnectionInfo { const ConnectionInfo({required String remoteAddress, required int remotePort}); }`
  - `abstract final class StatusCode { static const ok, created, noContent, found, badRequest, unauthorized, forbidden, notFound, methodNotAllowed, conflict, unprocessableContent, internalServerError, serviceUnavailable; static String reasonPhrase(int code); }`
  - `class HttpException implements Exception { const HttpException(int status, {String? message, Object? details, Map<String, String> headers}); int status; String get message; Object? details; Map<String, String> headers; }` and subclasses `BadRequestException`, `UnauthorizedException` (with `headers`), `ForbiddenException`, `NotFoundException`, `MethodNotAllowedException(List<String> allowed)` (sets `allow`), `ServiceUnavailableException`.

- [ ] **Step 1: Write the failing tests**

`packages/dartnest/test/http/header_map_test.dart`:

```dart
import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

void main() {
  group('HeaderMap', () {
    test('lookups ignore the case of the name', () {
      final headers = HeaderMap.of({'Content-Type': 'application/json'});

      expect(headers['content-type'], 'application/json');
      expect(headers['CONTENT-TYPE'], 'application/json');
      expect(headers.contains('Content-type'), isTrue);
      expect(headers.names, ['content-type']);
    });

    test('add keeps every value of a name in order', () {
      final headers = HeaderMap()
        ..add('Set-Cookie', 'a=1')
        ..add('set-cookie', 'b=2');

      expect(headers.all('SET-COOKIE'), ['a=1', 'b=2']);
      expect(headers['set-cookie'], 'a=1');
    });

    test('set replaces, remove deletes, absent names read as empty', () {
      final headers = HeaderMap()
        ..add('x-a', '1')
        ..add('x-a', '2')
        ..set('X-A', '3');
      expect(headers.all('x-a'), ['3']);

      headers.remove('x-A');
      expect(headers['x-a'], isNull);
      expect(headers.all('x-a'), isEmpty);
    });

    test('setAll overrides only the names present in the other map', () {
      final headers = HeaderMap.of({'a': '1', 'b': '2'})
        ..setAll(HeaderMap.of({'B': '3', 'c': '4'}));

      expect(headers.toMap(), {
        'a': ['1'],
        'b': ['3'],
        'c': ['4'],
      });
    });

    test('unmodifiable copies reject changes and do not track the source', () {
      final source = HeaderMap.of({'a': '1'});
      final frozen = HeaderMap.unmodifiable(source);
      source.add('a', '2');

      expect(frozen.isReadOnly, isTrue);
      expect(frozen.all('a'), ['1']);
      expect(() => frozen.add('a', '3'), throwsUnsupportedError);
      expect(() => frozen.set('a', '3'), throwsUnsupportedError);
      expect(() => frozen.remove('a'), throwsUnsupportedError);
      expect(HeaderMap.copy(frozen).isReadOnly, isFalse);
    });
  });
}
```

`packages/dartnest/test/http/http_exception_test.dart`:

```dart
import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

class PaymentRequiredException extends HttpException {
  const PaymentRequiredException() : super(402, message: 'Pay first');
}

void main() {
  group('HttpException', () {
    test('message defaults to the reason phrase', () {
      expect(const HttpException(404).message, 'Not Found');
      expect(const HttpException(499).message, 'Unknown Status');
      expect(const HttpException(409, message: 'Taken').message, 'Taken');
    });

    test('built-in subclasses carry their status', () {
      expect(const BadRequestException().status, 400);
      expect(const UnauthorizedException().status, 401);
      expect(const ForbiddenException().status, 403);
      expect(const NotFoundException().status, 404);
      expect(MethodNotAllowedException(const ['GET']).status, 405);
      expect(const ServiceUnavailableException().status, 503);
    });

    test('405 lists the allowed methods in the allow header', () {
      final error = MethodNotAllowedException(const ['GET', 'HEAD', 'POST']);

      expect(error.allowed, ['GET', 'HEAD', 'POST']);
      expect(error.headers, {'allow': 'GET, HEAD, POST'});
    });

    test('applications can extend it and keep details', () {
      const error = PaymentRequiredException();
      const withDetails = BadRequestException(details: {'field': 'name'});

      expect(error.status, 402);
      expect(error.toString(), 'PaymentRequiredException(402): Pay first');
      expect(withDetails.details, {'field': 'name'});
    });
  });

  group('StatusCode', () {
    test('knows reason phrases of common codes', () {
      expect(StatusCode.reasonPhrase(StatusCode.ok), 'OK');
      expect(
        StatusCode.reasonPhrase(StatusCode.methodNotAllowed),
        'Method Not Allowed',
      );
      expect(
        StatusCode.reasonPhrase(StatusCode.serviceUnavailable),
        'Service Unavailable',
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run from `packages/dartnest`: `dart test test/http/header_map_test.dart test/http/http_exception_test.dart`
Expected: FAIL at compile time, first error: `Error: Undefined name 'HeaderMap'.`

- [ ] **Step 3: Implement**

`packages/dartnest/lib/src/http/header_map.dart`:

````dart
/// Case-insensitive multimap of HTTP header names to values.
///
/// Names are stored lower-cased; each name keeps its values in the order they
/// were added. A map made with [HeaderMap.unmodifiable] rejects changes,
/// which is how `HttpRequest` and `HttpResponse` stay immutable.
///
/// ```dart
/// final headers = HeaderMap.of({'Content-Type': 'application/json'});
/// headers['content-type']; // 'application/json'
/// headers.add('Set-Cookie', 'a=1');
/// headers.add('set-cookie', 'b=2');
/// headers.all('SET-COOKIE'); // ['a=1', 'b=2']
/// ```
final class HeaderMap {
  /// Creates an empty, modifiable map.
  HeaderMap() : this._({}, isReadOnly: false);

  /// Creates a modifiable map with one value per entry of [headers].
  factory HeaderMap.of(Map<String, String> headers) {
    final map = HeaderMap();
    headers.forEach(map.add);
    return map;
  }

  /// Creates a modifiable copy of [source].
  HeaderMap.copy(HeaderMap source)
    : this._(_copyValues(source._values), isReadOnly: false);

  /// Creates a read-only copy of [source].
  HeaderMap.unmodifiable(HeaderMap source)
    : this._(_copyValues(source._values), isReadOnly: true);

  HeaderMap._(this._values, {required this.isReadOnly});

  final Map<String, List<String>> _values;

  /// Whether changes are rejected with [UnsupportedError].
  final bool isReadOnly;

  /// The first value of [name], or `null` when the header is absent.
  String? operator [](String name) => _values[name.toLowerCase()]?.first;

  /// Every value of [name] in insertion order; empty when absent.
  List<String> all(String name) =>
      List.unmodifiable(_values[name.toLowerCase()] ?? const <String>[]);

  /// Whether [name] has at least one value.
  bool contains(String name) => _values.containsKey(name.toLowerCase());

  /// Lower-cased header names in insertion order.
  Iterable<String> get names => _values.keys;

  /// Appends [value] to the values of [name].
  void add(String name, String value) {
    _checkWritable();
    _values.putIfAbsent(name.toLowerCase(), () => []).add(value);
  }

  /// Replaces every value of [name] with [value].
  void set(String name, String value) {
    _checkWritable();
    _values[name.toLowerCase()] = [value];
  }

  /// Replaces the values of every name present in [other] with its values.
  void setAll(HeaderMap other) {
    _checkWritable();
    for (final MapEntry(:key, :value) in other._values.entries) {
      _values[key] = List.of(value);
    }
  }

  /// Removes every value of [name].
  void remove(String name) {
    _checkWritable();
    _values.remove(name.toLowerCase());
  }

  /// A read-only snapshot keyed by lower-cased name, for adapters that copy
  /// headers into their native response.
  Map<String, List<String>> toMap() => Map.unmodifiable({
    for (final MapEntry(:key, :value) in _values.entries)
      key: List<String>.unmodifiable(value),
  });

  void _checkWritable() {
    if (isReadOnly) {
      throw UnsupportedError('These headers are read-only; copy them first.');
    }
  }

  static Map<String, List<String>> _copyValues(
    Map<String, List<String>> source,
  ) => {
    for (final MapEntry(:key, :value) in source.entries) key: List.of(value),
  };
}
````

`packages/dartnest/lib/src/http/connection_info.dart`:

```dart
/// Network details of the connection a request arrived on, as reported by
/// the `HttpAdapter`.
final class ConnectionInfo {
  /// Creates connection details.
  const ConnectionInfo({required this.remoteAddress, required this.remotePort});

  /// Address of the client (an IP address in text form).
  final String remoteAddress;

  /// Port of the client.
  final int remotePort;
}
```

`packages/dartnest/lib/src/http/status_code.dart`:

```dart
/// HTTP status codes that dartnest itself produces or documents, and their
/// reason phrases. A flat catalog.
abstract final class StatusCode {
  /// 200 OK.
  static const ok = 200;

  /// 201 Created.
  static const created = 201;

  /// 204 No Content.
  static const noContent = 204;

  /// 302 Found.
  static const found = 302;

  /// 400 Bad Request.
  static const badRequest = 400;

  /// 401 Unauthorized.
  static const unauthorized = 401;

  /// 403 Forbidden.
  static const forbidden = 403;

  /// 404 Not Found.
  static const notFound = 404;

  /// 405 Method Not Allowed.
  static const methodNotAllowed = 405;

  /// 409 Conflict.
  static const conflict = 409;

  /// 422 Unprocessable Content.
  static const unprocessableContent = 422;

  /// 500 Internal Server Error.
  static const internalServerError = 500;

  /// 503 Service Unavailable.
  static const serviceUnavailable = 503;

  /// The reason phrase of [code], or `'Unknown Status'`.
  static String reasonPhrase(int code) => switch (code) {
    200 => 'OK',
    201 => 'Created',
    202 => 'Accepted',
    204 => 'No Content',
    301 => 'Moved Permanently',
    302 => 'Found',
    303 => 'See Other',
    304 => 'Not Modified',
    307 => 'Temporary Redirect',
    308 => 'Permanent Redirect',
    400 => 'Bad Request',
    401 => 'Unauthorized',
    403 => 'Forbidden',
    404 => 'Not Found',
    405 => 'Method Not Allowed',
    409 => 'Conflict',
    410 => 'Gone',
    413 => 'Content Too Large',
    415 => 'Unsupported Media Type',
    422 => 'Unprocessable Content',
    429 => 'Too Many Requests',
    500 => 'Internal Server Error',
    501 => 'Not Implemented',
    502 => 'Bad Gateway',
    503 => 'Service Unavailable',
    504 => 'Gateway Timeout',
    _ => 'Unknown Status',
  };
}
```

`packages/dartnest/lib/src/http/http_exception.dart`:

````dart
/// [HttpException] and the built-in subclasses the framework throws itself.
///
/// The subclasses are one family with their base and share this file, like
/// the error families in `errors.dart`; the base stays open (not sealed) so
/// that applications can add their own statuses.
library;

import 'status_code.dart';

/// An error that the default exception filter turns into an HTTP error
/// response: `{"statusCode": status, "error": reason phrase,
/// "message": message}`, plus `"details"` when given.
///
/// Throw it from guards, interceptors, pipes, handlers and filters. Extend it
/// for statuses that have no built-in subclass:
///
/// ```dart
/// class PaymentRequiredException extends HttpException {
///   const PaymentRequiredException() : super(402);
/// }
/// ```
class HttpException implements Exception {
  /// Creates an exception for [status]; [message] defaults to the reason
  /// phrase of [status].
  const HttpException(
    this.status, {
    String? message,
    this.details,
    this.headers = const {},
  }) : _message = message;

  /// HTTP status code of the response.
  final int status;

  final String? _message;

  /// Human-readable message sent to the client.
  String get message => _message ?? StatusCode.reasonPhrase(status);

  /// Extra data sent as `"details"`: a JSON value (`Map`, `List`, `String`,
  /// `num`, `bool`); any other object is sent as its `toString()`.
  final Object? details;

  /// Headers added to the error response (for example `allow` or
  /// `www-authenticate`).
  final Map<String, String> headers;

  @override
  String toString() => '$runtimeType($status): $message';
}

/// 400: the request is malformed (bad JSON, a parameter of the wrong type).
class BadRequestException extends HttpException {
  /// Creates the exception.
  const BadRequestException({super.message, super.details})
    : super(StatusCode.badRequest);
}

/// 401: the request lacks valid credentials.
class UnauthorizedException extends HttpException {
  /// Creates the exception.
  const UnauthorizedException({super.message, super.details, super.headers})
    : super(StatusCode.unauthorized);
}

/// 403: the credentials are valid but not sufficient; also thrown when a
/// guard returns `false`.
class ForbiddenException extends HttpException {
  /// Creates the exception.
  const ForbiddenException({super.message, super.details})
    : super(StatusCode.forbidden);
}

/// 404: no route matches the path, or the requested entity does not exist.
class NotFoundException extends HttpException {
  /// Creates the exception.
  const NotFoundException({super.message, super.details})
    : super(StatusCode.notFound);
}

/// 405: a route matches the path but not the method; [allowed] is sent in
/// the `allow` header.
class MethodNotAllowedException extends HttpException {
  /// Creates the exception for the [allowed] methods.
  MethodNotAllowedException(this.allowed, {super.message})
    : super(
        StatusCode.methodNotAllowed,
        headers: {'allow': allowed.join(', ')},
      );

  /// Methods the matched path accepts, sorted.
  final List<String> allowed;
}

/// 503: the application is shutting down or temporarily unable to serve.
class ServiceUnavailableException extends HttpException {
  /// Creates the exception.
  const ServiceUnavailableException({super.message, super.details})
    : super(StatusCode.serviceUnavailable);
}
````

- [ ] **Step 4: Export the public types**

Add to `packages/dartnest/lib/dartnest.dart`, keeping all `export` lines sorted:

```dart
export 'src/http/connection_info.dart';
export 'src/http/header_map.dart';
export 'src/http/http_exception.dart';
export 'src/http/status_code.dart';
```

- [ ] **Step 5: Run the tests to verify they pass**

Run from `packages/dartnest`: `dart test test/http/header_map_test.dart test/http/http_exception_test.dart`
Expected: `+10: All tests passed!`

Run from `packages/dartnest`: `dart test`
Expected: `+84: All tests passed!`

- [ ] **Step 6: Analyze, format and commit**

Run from repo root: `dart analyze && dart format --output=none --set-exit-if-changed packages`
Expected: `No issues found!` and `Formatted N files (0 changed)`.

```bash
git add \
  packages/dartnest/lib/src/http/header_map.dart \
  packages/dartnest/lib/src/http/connection_info.dart \
  packages/dartnest/lib/src/http/status_code.dart \
  packages/dartnest/lib/src/http/http_exception.dart \
  packages/dartnest/test/http/header_map_test.dart \
  packages/dartnest/test/http/http_exception_test.dart \
  packages/dartnest/lib/dartnest.dart
git commit -m "feat(http): add HeaderMap, StatusCode and the HttpException family"
```

---

### Task 2: `HttpRequest`, `HttpResponse` і тіла

`HttpRequest` і `HttpResponse` незмінні; адаптери (етап 3) і `TestClient` будують їх напряму. `RequestBody` читає джерело один раз і кешує `bytes()`/`text()`/`json()`; порожнє чи зламане JSON-тіло та неправильний UTF-8 дають `BadRequestException`. `ResponseBody` закритий (`BytesBody` | `StreamBody`). `ResponseHead` (змінні `status` і `headers`) — це «response builder» зі специфікації, через який хендлер задає статус і заголовки, повертаючи звичайне значення.

**Files:**
- Create: `packages/dartnest/lib/src/http/request_body.dart`
- Create: `packages/dartnest/lib/src/http/http_request.dart`
- Create: `packages/dartnest/lib/src/http/response_body.dart`
- Create: `packages/dartnest/lib/src/http/http_response.dart`
- Create: `packages/dartnest/lib/src/http/response_head.dart`
- Modify: `packages/dartnest/lib/dartnest.dart`
- Test: `packages/dartnest/test/http/http_request_test.dart`
- Test: `packages/dartnest/test/http/http_response_test.dart`

**Interfaces:**
- Consumes: `HeaderMap`, `ConnectionInfo`, `StatusCode`, `BadRequestException` (Task 1).
- Produces:
  - `final class RequestBody { RequestBody(Stream<List<int>>); RequestBody.bytes(List<int>); RequestBody.empty(); Future<Uint8List> bytes(); Future<String> text(); Future<Object?> json(); Stream<List<int>> get stream; }`
  - `final class HttpRequest { HttpRequest({required String method, required Uri uri, HeaderMap? headers, RequestBody? body, ConnectionInfo? connectionInfo}); String method; Uri uri; HeaderMap headers /* read-only */; RequestBody body; ConnectionInfo? connectionInfo; }`
  - `sealed class ResponseBody { Future<Uint8List> readAll(); }` with `BytesBody(List<int>)` and `StreamBody(Stream<List<int>>)`.
  - `final class HttpResponse { HttpResponse(int status, {HeaderMap? headers, ResponseBody? body}); factory .text/.json/.bytes/.stream/.redirect/.empty; int status; HeaderMap headers; ResponseBody body; HttpResponse mergeHeaders(HeaderMap extra); }`
  - `final class ResponseHead { int? status; final HeaderMap headers; }`

- [ ] **Step 1: Write the failing tests**

`packages/dartnest/test/http/http_request_test.dart`:

```dart
import 'dart:convert';

import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

RequestBody streamed(List<String> chunks) =>
    RequestBody(Stream.fromIterable(chunks.map(utf8.encode)));

void main() {
  group('HttpRequest', () {
    test('upper-cases the method and freezes the headers', () {
      final headers = HeaderMap.of({'X-Id': '1'});
      final request = HttpRequest(
        method: 'get',
        uri: Uri.parse('/users?page=2'),
        headers: headers,
      );
      headers.set('x-id', '2');

      expect(request.method, 'GET');
      expect(request.uri.path, '/users');
      expect(request.uri.queryParameters, {'page': '2'});
      expect(request.headers['x-id'], '1');
      expect(() => request.headers.add('a', 'b'), throwsUnsupportedError);
    });

    test('defaults to an empty body and no connection info', () async {
      final request = HttpRequest(method: 'GET', uri: Uri.parse('/'));

      expect(await request.body.bytes(), isEmpty);
      expect(request.connectionInfo, isNull);
    });
  });

  group('RequestBody', () {
    test('reads a chunked stream once and caches it', () async {
      final body = streamed(['{"a":', '1}']);

      expect(await body.text(), '{"a":1}');
      expect(await body.json(), {'a': 1});
      expect(await body.json(), {'a': 1});
      expect(await body.bytes(), utf8.encode('{"a":1}'));
    });

    test('malformed JSON is a 400, not a crash', () async {
      await expectLater(
        RequestBody.bytes(utf8.encode('{"a":')).json(),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.message,
            'message',
            startsWith('Request body is not valid JSON'),
          ),
        ),
      );
    });

    test('an empty body is a 400 when JSON is expected', () async {
      await expectLater(
        RequestBody.empty().json(),
        throwsA(isA<BadRequestException>()),
      );
    });

    test('malformed UTF-8 is a 400', () async {
      await expectLater(
        RequestBody.bytes(const [0xff, 0xfe]).text(),
        throwsA(isA<BadRequestException>()),
      );
    });

    test('the raw stream can be taken once, then readers fail', () async {
      final body = streamed(['abc']);
      final chunks = await body.stream.toList();

      expect(utf8.decode(chunks.expand((c) => c).toList()), 'abc');
      expect(() => body.stream, throwsStateError);
      expect(() => body.bytes(), throwsStateError);
    });

    test('after a cached read, stream replays the cached bytes', () async {
      final body = streamed(['abc']);
      await body.bytes();

      expect(await body.stream.toList(), [utf8.encode('abc')]);
    });
  });
}
```

`packages/dartnest/test/http/http_response_test.dart`:

```dart
import 'dart:convert';

import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

class Point {
  Point(this.x);
  final int x;
  Map<String, Object?> toJson() => {'x': x};
}

Future<String> bodyText(HttpResponse response) async =>
    utf8.decode(await response.body.readAll());

void main() {
  group('HttpResponse factories', () {
    test('text sets the content type and encodes UTF-8', () async {
      final response = HttpResponse.text('привіт', status: 201);

      expect(response.status, 201);
      expect(response.headers['content-type'], 'text/plain; charset=utf-8');
      expect(await bodyText(response), 'привіт');
    });

    test('json encodes maps and toJson objects', () async {
      final response = HttpResponse.json({'p': Point(1)});

      expect(response.status, 200);
      expect(
        response.headers['content-type'],
        'application/json; charset=utf-8',
      );
      expect(await bodyText(response), '{"p":{"x":1}}');
    });

    test('explicit content-type is kept', () {
      final response = HttpResponse.text(
        '<b>hi</b>',
        headers: HeaderMap.of({'Content-Type': 'text/html'}),
      );

      expect(response.headers['content-type'], 'text/html');
    });

    test('bytes, stream, redirect and empty', () async {
      expect(
        HttpResponse.bytes(const [1, 2]).headers['content-type'],
        'application/octet-stream',
      );
      final streamed = HttpResponse.stream(
        Stream.fromIterable([
          [1],
          [2, 3],
        ]),
        contentType: 'text/csv',
      );
      expect(await streamed.body.readAll(), [1, 2, 3]);
      expect(streamed.headers['content-type'], 'text/csv');

      final redirect = HttpResponse.redirect(Uri.parse('/login'));
      expect(redirect.status, 302);
      expect(redirect.headers['location'], '/login');
      expect(HttpResponse.empty().status, 204);
    });

    test('status outside 100-599 is rejected', () {
      expect(() => HttpResponse(42), throwsRangeError);
      expect(() => HttpResponse(600), throwsRangeError);
    });

    test('headers are read-only', () {
      expect(
        () => HttpResponse.text('x').headers.add('a', 'b'),
        throwsUnsupportedError,
      );
    });
  });

  group('HttpResponse.mergeHeaders', () {
    test('adds missing names and keeps the response values', () {
      final response = HttpResponse.text('x').mergeHeaders(
        HeaderMap.of({'content-type': 'text/html', 'x-trace': '7'}),
      );

      expect(response.headers['content-type'], 'text/plain; charset=utf-8');
      expect(response.headers['x-trace'], '7');
    });

    test('returns the same response when nothing is missing', () {
      final response = HttpResponse.text('x');

      expect(response.mergeHeaders(HeaderMap()), same(response));
    });
  });

  group('ResponseHead', () {
    test('starts without a status and with writable headers', () {
      final head = ResponseHead()..headers.set('x-a', '1');

      expect(head.status, isNull);
      expect(head.headers['x-a'], '1');
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run from `packages/dartnest`: `dart test test/http/http_request_test.dart test/http/http_response_test.dart`
Expected: FAIL at compile time, first error: `Error: Type 'RequestBody' not found.`

- [ ] **Step 3: Implement**

`packages/dartnest/lib/src/http/request_body.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'http_exception.dart';

/// The body of an `HttpRequest`: a byte stream that is read at most once.
///
/// [bytes], [text] and [json] read the whole stream on first use and cache
/// the result, so a guard and a handler can both call `json()`. [stream]
/// hands out the raw stream for large uploads; after that the cached
/// readers fail with a [StateError], and vice versa only the cached bytes
/// are streamed.
final class RequestBody {
  /// Wraps a body stream supplied by an adapter.
  RequestBody(Stream<List<int>> source) : _source = source;

  /// A body whose content is already in memory (tests, middleware).
  RequestBody.bytes(List<int> bytes)
    : _source = null,
      _bytes = Future.value(Uint8List.fromList(bytes));

  /// A body with no content.
  RequestBody.empty() : this.bytes(const []);

  Stream<List<int>>? _source;
  Future<Uint8List>? _bytes;
  Future<Object?>? _json;
  bool _streamTaken = false;

  /// The whole body; read once and cached.
  Future<Uint8List> bytes() {
    if (_streamTaken) {
      throw StateError('The request body was already taken by `stream`.');
    }
    return _bytes ??= _collect();
  }

  /// The body decoded as UTF-8; malformed UTF-8 throws
  /// [BadRequestException].
  Future<String> text() async {
    final data = await bytes();
    try {
      return utf8.decode(data);
    } on FormatException catch (error) {
      throw BadRequestException(
        message: 'Request body is not valid UTF-8: ${error.message}',
      );
    }
  }

  /// The body decoded as JSON and cached. An empty or malformed body throws
  /// [BadRequestException].
  Future<Object?> json() => _json ??= _decodeJson();

  /// The raw body stream; can be taken once, and not after [bytes] started
  /// reading (then the cached bytes are streamed instead).
  Stream<List<int>> get stream {
    final cached = _bytes;
    if (cached != null) return Stream.fromFuture(cached);
    final source = _source;
    if (source == null || _streamTaken) {
      throw StateError('The request body stream can be taken only once.');
    }
    _streamTaken = true;
    return source;
  }

  Future<Object?> _decodeJson() async {
    final source = await text();
    if (source.trim().isEmpty) {
      throw const BadRequestException(
        message: 'Request body is empty; expected JSON.',
      );
    }
    try {
      return jsonDecode(source);
    } on FormatException catch (error) {
      throw BadRequestException(
        message: 'Request body is not valid JSON: ${error.message}',
      );
    }
  }

  Future<Uint8List> _collect() async {
    final source = _source;
    _source = null;
    if (source == null) return Uint8List(0);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in source) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}
```

`packages/dartnest/lib/src/http/http_request.dart`:

```dart
import 'connection_info.dart';
import 'header_map.dart';
import 'request_body.dart';

/// An incoming HTTP request, independent of any server library.
///
/// Adapters build it from their native request; tests build it directly or
/// through `TestClient`. It is immutable: [headers] is read-only and
/// [method] is upper-cased.
final class HttpRequest {
  /// Creates a request. [uri] is the request target: a path with an
  /// optional query (`/users?page=2`); an absolute URI also works.
  HttpRequest({
    required String method,
    required this.uri,
    HeaderMap? headers,
    RequestBody? body,
    this.connectionInfo,
  }) : method = method.toUpperCase(),
       headers = HeaderMap.unmodifiable(headers ?? HeaderMap()),
       body = body ?? RequestBody.empty();

  /// Upper-cased method, for example `GET`.
  final String method;

  /// Request target: path (percent-decoded via [Uri.pathSegments]) and query.
  final Uri uri;

  /// Read-only request headers.
  final HeaderMap headers;

  /// The body, read lazily.
  final RequestBody body;

  /// Client connection details, when the adapter provides them.
  final ConnectionInfo? connectionInfo;

  @override
  String toString() => 'HttpRequest($method $uri)';
}
```

`packages/dartnest/lib/src/http/response_body.dart`:

```dart
import 'dart:typed_data';

/// The body of an `HttpResponse`: bytes in memory or a stream.
sealed class ResponseBody {
  /// Creates a body.
  const ResponseBody();

  /// Collects the whole body (for tests and small responses).
  Future<Uint8List> readAll() async {
    switch (this) {
      case BytesBody(:final bytes):
        return bytes;
      case StreamBody(:final stream):
        final builder = BytesBuilder(copy: false);
        await for (final chunk in stream) {
          builder.add(chunk);
        }
        return builder.takeBytes();
    }
  }
}

/// A body held in memory.
final class BytesBody extends ResponseBody {
  /// Wraps [bytes]; copies them unless they already are a [Uint8List].
  BytesBody(List<int> bytes)
    : bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

  /// The content.
  final Uint8List bytes;
}

/// A body written chunk by chunk as the stream emits.
final class StreamBody extends ResponseBody {
  /// Wraps [stream]; it is listened to once, by the adapter.
  const StreamBody(this.stream);

  /// The content.
  final Stream<List<int>> stream;
}
```

`packages/dartnest/lib/src/http/http_response.dart`:

```dart
import 'dart:convert';

import 'header_map.dart';
import 'response_body.dart';
import 'status_code.dart';

/// An outgoing HTTP response, independent of any server library.
///
/// Immutable: [headers] is read-only. Return it from a handler to control
/// the response completely, or return a plain value and let dartnest
/// serialize it.
final class HttpResponse {
  /// Creates a response; [status] must be within 100–599.
  HttpResponse(int status, {HeaderMap? headers, ResponseBody? body})
    : status = RangeError.checkValueInInterval(status, 100, 599, 'status'),
      headers = HeaderMap.unmodifiable(headers ?? HeaderMap()),
      body = body ?? BytesBody(const []);

  /// A `text/plain; charset=utf-8` response.
  factory HttpResponse.text(
    String text, {
    int status = StatusCode.ok,
    HeaderMap? headers,
  }) => _typed(
    status,
    headers,
    'text/plain; charset=utf-8',
    BytesBody(utf8.encode(text)),
  );

  /// An `application/json; charset=utf-8` response with [value] encoded by
  /// `jsonEncode` (so objects with `toJson()` work).
  factory HttpResponse.json(
    Object? value, {
    int status = StatusCode.ok,
    HeaderMap? headers,
  }) => _typed(
    status,
    headers,
    'application/json; charset=utf-8',
    BytesBody(utf8.encode(jsonEncode(value))),
  );

  /// An `application/octet-stream` response.
  factory HttpResponse.bytes(
    List<int> bytes, {
    int status = StatusCode.ok,
    HeaderMap? headers,
  }) => _typed(status, headers, 'application/octet-stream', BytesBody(bytes));

  /// A streamed response of [contentType].
  factory HttpResponse.stream(
    Stream<List<int>> stream, {
    int status = StatusCode.ok,
    HeaderMap? headers,
    String contentType = 'application/octet-stream',
  }) => _typed(status, headers, contentType, StreamBody(stream));

  /// A redirect to [location] (302 unless [status] says otherwise).
  factory HttpResponse.redirect(
    Uri location, {
    int status = StatusCode.found,
  }) => HttpResponse(
    status,
    headers: HeaderMap.of({'location': location.toString()}),
  );

  /// A response without a body (204 unless [status] says otherwise).
  factory HttpResponse.empty({
    int status = StatusCode.noContent,
    HeaderMap? headers,
  }) => HttpResponse(status, headers: headers);

  /// Status code.
  final int status;

  /// Read-only headers.
  final HeaderMap headers;

  /// The body.
  final ResponseBody body;

  /// A copy that also carries every header of [extra] whose name this
  /// response does not set; the response's own values win.
  HttpResponse mergeHeaders(HeaderMap extra) {
    final missing = [
      for (final name in extra.names)
        if (!headers.contains(name)) name,
    ];
    if (missing.isEmpty) return this;
    final merged = HeaderMap.copy(headers);
    for (final name in missing) {
      for (final value in extra.all(name)) {
        merged.add(name, value);
      }
    }
    return HttpResponse(status, headers: merged, body: body);
  }

  static HttpResponse _typed(
    int status,
    HeaderMap? headers,
    String contentType,
    ResponseBody body,
  ) {
    final all = HeaderMap.copy(headers ?? HeaderMap());
    if (!all.contains('content-type')) all.set('content-type', contentType);
    return HttpResponse(status, headers: all, body: body);
  }

  @override
  String toString() => 'HttpResponse($status)';
}
```

`packages/dartnest/lib/src/http/response_head.dart`:

```dart
import 'header_map.dart';

/// Status and headers that a guard, interceptor or handler sets for the
/// response dartnest builds from the handler's result.
///
/// Reach it through `context.switchToHttp().response`.
///
/// - [status] replaces the default status of a serialized result (200, or
///   204 for `null`). It is ignored when the handler returns an
///   `HttpResponse`.
/// - [headers] are added to every response of the request, error responses
///   included. For a serialized result they replace the defaults (so a
///   handler can set `content-type`); a returned `HttpResponse` keeps its own
///   values for names it sets.
final class ResponseHead {
  /// Creates an empty head.
  ResponseHead();

  /// Status for a serialized result; `null` keeps the default.
  int? status;

  /// Headers for the response.
  final HeaderMap headers = HeaderMap();
}
```

- [ ] **Step 4: Export the public types**

Add to `packages/dartnest/lib/dartnest.dart`, keeping all `export` lines sorted:

```dart
export 'src/http/http_request.dart';
export 'src/http/http_response.dart';
export 'src/http/request_body.dart';
export 'src/http/response_body.dart';
export 'src/http/response_head.dart';
```

- [ ] **Step 5: Run the tests to verify they pass**

Run from `packages/dartnest`: `dart test test/http/http_request_test.dart test/http/http_response_test.dart`
Expected: `+17: All tests passed!`

Run from `packages/dartnest`: `dart test`
Expected: `+101: All tests passed!`

- [ ] **Step 6: Analyze, format and commit**

Run from repo root: `dart analyze && dart format --output=none --set-exit-if-changed packages`
Expected: `No issues found!` and `Formatted N files (0 changed)`.

```bash
git add \
  packages/dartnest/lib/src/http/request_body.dart \
  packages/dartnest/lib/src/http/http_request.dart \
  packages/dartnest/lib/src/http/response_body.dart \
  packages/dartnest/lib/src/http/http_response.dart \
  packages/dartnest/lib/src/http/response_head.dart \
  packages/dartnest/test/http/http_request_test.dart \
  packages/dartnest/test/http/http_response_test.dart \
  packages/dartnest/lib/dartnest.dart
git commit -m "feat(http): add immutable HttpRequest and HttpResponse with bodies"
```

---

### Task 3: `RoutePattern` і помилки роутингу

Шаблон шляху розбирається один раз при побудові таблиці роутів. `RoutePattern.join(prefix, path)` склеює шлях контролера й роуту та відкидає порожні сегменти, тому `/users/` і `users` еквівалентні. Сегменти: статичний, `:name` (ім'я відповідає `[A-Za-z_][A-Za-z0-9_]*`) і `*` лише в кінці (один або більше сегментів, у параметрах під ключем `*`). Усі порушення — `InvalidRoutePatternError`; родина `RoutingError` (sealed, наслідує `DartnestError`) також містить `DuplicateRouteError` для Task 4.

**Files:**
- Create: `packages/dartnest/lib/src/routing/routing_error.dart`
- Create: `packages/dartnest/lib/src/routing/pattern_segment.dart`
- Create: `packages/dartnest/lib/src/routing/route_pattern.dart`
- Modify: `packages/dartnest/lib/dartnest.dart`
- Test: `packages/dartnest/test/routing/route_pattern_test.dart`

**Interfaces:**
- Consumes: `DartnestError` (`lib/src/di/errors.dart`).
- Produces:
  - `sealed class RoutingError extends DartnestError` with `DuplicateRouteError({method, path, existing, duplicate})` and `InvalidRoutePatternError({pattern, reason})`.
  - `sealed class PatternSegment` with `StaticSegment(String value)`, `ParamSegment(String name)`, `WildcardSegment()` (`WildcardSegment.parameterName == '*'`); internal, not exported.
  - `final class RoutePattern { static RoutePattern join(String prefix, String path); List<PatternSegment> segments; List<String> get parameterNames; String toString() /* '/users/:id' */; }`; internal.

- [ ] **Step 1: Write the failing tests**

`packages/dartnest/test/routing/route_pattern_test.dart`:

```dart
import 'package:dartnest/dartnest.dart';
import 'package:dartnest/src/routing/pattern_segment.dart';
import 'package:dartnest/src/routing/route_pattern.dart';
import 'package:test/test.dart';

Matcher invalidPattern(String pattern, String reasonPart) => throwsA(
  isA<InvalidRoutePatternError>()
      .having((e) => e.pattern, 'pattern', pattern)
      .having((e) => e.reason, 'reason', contains(reasonPart)),
);

void main() {
  group('RoutePattern.join', () {
    test('joins prefix and path and normalizes slashes', () {
      expect(RoutePattern.join('/users', '/:id').toString(), '/users/:id');
      expect(RoutePattern.join('users/', 'posts/').toString(), '/users/posts');
      expect(RoutePattern.join('', '//a//b').toString(), '/a/b');
      expect(RoutePattern.join('', '/').toString(), '/');
      expect(RoutePattern.join('', '').segments, isEmpty);
    });

    test('classifies segments', () {
      final pattern = RoutePattern.join('/files', ':owner/*');

      expect(pattern.segments, [
        isA<StaticSegment>().having((s) => s.value, 'value', 'files'),
        isA<ParamSegment>().having((s) => s.name, 'name', 'owner'),
        isA<WildcardSegment>(),
      ]);
      expect(pattern.parameterNames, ['owner', '*']);
    });

    test('wildcard must be last', () {
      expect(
        () => RoutePattern.join('/files/*', '/:id'),
        invalidPattern('/files/*/:id', 'must be the last segment'),
      );
    });

    test('parameter names must be identifiers', () {
      expect(
        () => RoutePattern.join('', '/:'),
        invalidPattern('/:', 'parameter name ""'),
      );
      expect(
        () => RoutePattern.join('', '/:user-id'),
        invalidPattern('/:user-id', 'parameter name "user-id"'),
      );
    });

    test('partial parameters and wildcards are rejected', () {
      expect(
        () => RoutePattern.join('', '/file.*'),
        invalidPattern('/file.*', 'mixes literal text'),
      );
      expect(
        () => RoutePattern.join('', '/a:b'),
        invalidPattern('/a:b', 'mixes literal text'),
      );
    });

    test('a parameter name may appear only once', () {
      expect(
        () => RoutePattern.join('/users/:id', '/posts/:id'),
        invalidPattern('/users/:id/posts/:id', 'appears twice'),
      );
    });
  });

  group('DuplicateRouteError', () {
    test('names both handlers', () {
      const error = DuplicateRouteError(
        method: 'GET',
        path: '/users/:id',
        existing: 'A.one (module "a")',
        duplicate: 'B.two (module "b")',
      );

      expect(
        error.message,
        'Route GET /users/:id is declared twice: by A.one (module "a") and by '
        'B.two (module "b"). Parameter names do not distinguish routes.',
      );
      expect(error, isA<DartnestError>());
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run from `packages/dartnest`: `dart test test/routing/route_pattern_test.dart`
Expected: FAIL at compile time, first error: `Error: Error when reading 'lib/src/routing/pattern_segment.dart': No such file or directory`

- [ ] **Step 3: Implement**

`packages/dartnest/lib/src/routing/routing_error.dart`:

```dart
import '../di/errors.dart';

/// Errors in the declared routes, raised by `Application.create` before any
/// provider is created.
sealed class RoutingError extends DartnestError {
  /// Creates a routing error.
  const RoutingError();
}

/// Two handlers are declared for the same method and path.
final class DuplicateRouteError extends RoutingError {
  /// Creates the error.
  const DuplicateRouteError({
    required this.method,
    required this.path,
    required this.existing,
    required this.duplicate,
  });

  /// The upper-cased method.
  final String method;

  /// The normalized path pattern, for example `/users/:id`.
  final String path;

  /// The handler declared first, as `Controller.handler (module "id")`.
  final String existing;

  /// The handler declared second, in the same format.
  final String duplicate;

  @override
  String get message =>
      'Route $method $path is declared twice: by $existing and by $duplicate. '
      'Parameter names do not distinguish routes.';
}

/// A route path cannot be parsed.
final class InvalidRoutePatternError extends RoutingError {
  /// Creates the error.
  const InvalidRoutePatternError({required this.pattern, required this.reason});

  /// The normalized pattern (controller path joined with the route path).
  final String pattern;

  /// What is wrong with it.
  final String reason;

  @override
  String get message => 'Invalid route pattern "$pattern": $reason.';
}
```

`packages/dartnest/lib/src/routing/pattern_segment.dart`:

```dart
/// One `/`-separated segment of a `RoutePattern`.
sealed class PatternSegment {
  /// Creates a segment.
  const PatternSegment();
}

/// A literal segment, matched exactly (case-sensitive).
final class StaticSegment extends PatternSegment {
  /// Creates a literal segment.
  const StaticSegment(this.value);

  /// The literal text.
  final String value;

  @override
  String toString() => value;
}

/// A `:name` segment that matches any single segment.
final class ParamSegment extends PatternSegment {
  /// Creates a parameter segment.
  const ParamSegment(this.name);

  /// Parameter name, without the colon.
  final String name;

  @override
  String toString() => ':$name';
}

/// A trailing `*` that matches one or more remaining segments; the match is
/// available as parameter `*`.
final class WildcardSegment extends PatternSegment {
  /// Creates the wildcard.
  const WildcardSegment();

  /// Name under which the matched rest of the path is captured.
  static const parameterName = '*';

  @override
  String toString() => '*';
}
```

`packages/dartnest/lib/src/routing/route_pattern.dart`:

```dart
import 'pattern_segment.dart';
import 'routing_error.dart';

/// A parsed route path: static segments, `:name` parameters and an optional
/// trailing `*` wildcard.
///
/// Empty segments are dropped, so `/users/`, `users` and `//users` are the
/// same pattern `/users`. A parameter or wildcard must be a whole segment.
final class RoutePattern {
  RoutePattern._(this.segments);

  /// The segments in order.
  final List<PatternSegment> segments;

  static final _parameterName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  /// Parses [path] relative to the controller [prefix]; throws
  /// [InvalidRoutePatternError].
  static RoutePattern join(String prefix, String path) {
    final parts = '$prefix/$path'
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    final display = '/${parts.join('/')}';
    final segments = <PatternSegment>[
      for (var i = 0; i < parts.length; i++)
        _segment(parts[i], isLast: i == parts.length - 1, pattern: display),
    ];
    _checkUniqueNames(segments, display);
    return RoutePattern._(List.unmodifiable(segments));
  }

  /// Parameter names in order; the wildcard contributes `*`.
  List<String> get parameterNames => [
    for (final segment in segments)
      if (segment case ParamSegment(:final name))
        name
      else if (segment is WildcardSegment)
        WildcardSegment.parameterName,
  ];

  static PatternSegment _segment(
    String part, {
    required bool isLast,
    required String pattern,
  }) {
    if (part == '*') {
      if (isLast) return const WildcardSegment();
      _fail(pattern, 'the wildcard "*" must be the last segment');
    }
    if (part.startsWith(':')) {
      final name = part.substring(1);
      if (_parameterName.hasMatch(name)) return ParamSegment(name);
      _fail(
        pattern,
        'parameter name "$name" must match [A-Za-z_][A-Za-z0-9_]*',
      );
    }
    if (part.contains(':') || part.contains('*')) {
      _fail(
        pattern,
        'segment "$part" mixes literal text with ":" or "*"; parameters and '
        'wildcards must be whole segments',
      );
    }
    return StaticSegment(part);
  }

  static void _checkUniqueNames(List<PatternSegment> segments, String pattern) {
    final seen = <String>{};
    for (final segment in segments) {
      if (segment is ParamSegment && !seen.add(segment.name)) {
        _fail(pattern, 'parameter ":${segment.name}" appears twice');
      }
    }
  }

  static Never _fail(String pattern, String reason) =>
      throw InvalidRoutePatternError(pattern: pattern, reason: reason);

  @override
  String toString() => '/${segments.join('/')}';
}
```

- [ ] **Step 4: Export the public types**

Add to `packages/dartnest/lib/dartnest.dart`, keeping all `export` lines sorted:

```dart
export 'src/routing/routing_error.dart';
```

- [ ] **Step 5: Run the tests to verify they pass**

Run from `packages/dartnest`: `dart test test/routing/route_pattern_test.dart`
Expected: `+7: All tests passed!`

Run from `packages/dartnest`: `dart test`
Expected: `+108: All tests passed!`

- [ ] **Step 6: Analyze, format and commit**

Run from repo root: `dart analyze && dart format --output=none --set-exit-if-changed packages`
Expected: `No issues found!` and `Formatted N files (0 changed)`.

```bash
git add \
  packages/dartnest/lib/src/routing/routing_error.dart \
  packages/dartnest/lib/src/routing/pattern_segment.dart \
  packages/dartnest/lib/src/routing/route_pattern.dart \
  packages/dartnest/test/routing/route_pattern_test.dart \
  packages/dartnest/lib/dartnest.dart
git commit -m "feat(routing): parse and validate route patterns"
```

---

### Task 4: Роутер: префіксне дерево сегментів, 404/405, HEAD

`Router<V>` — дерево сегментів з пріоритетом static > param > wildcard і поверненням назад (backtracking): якщо статична гілка не дала збігу, пробується параметрична. 405 повертається, коли шлях збігся хоч з одним роутом, але не з методом; `allow` — відсортоване об'єднання методів (з `HEAD`, якщо є `GET`). `HEAD` без власного роуту обслуговується `GET`-роутом (адаптер відкидає тіло). Дублікат (той самий метод і форма шляху, імена параметрів не враховуються) — `DuplicateRouteError` з обома джерелами.

**Files:**
- Create: `packages/dartnest/lib/src/routing/route_match.dart`
- Create: `packages/dartnest/lib/src/routing/router.dart`
- Test: `packages/dartnest/test/routing/router_test.dart`

**Interfaces:**
- Consumes: `RoutePattern`, `PatternSegment`, `DuplicateRouteError` (Task 3).
- Produces:
  - `sealed class RouteMatch<V>` with `RouteFound<V>(V value, Map<String, String> parameters)`, `RouteMethodNotAllowed<V>(List<String> allowed)`, `RouteNotFound<V>()`; internal.
  - `final class Router<V> { void add(String method, RoutePattern pattern, V value, {required String source}); RouteMatch<V> match(String method, List<String> segments); }`; internal.

- [ ] **Step 1: Write the failing tests**

`packages/dartnest/test/routing/router_test.dart`:

```dart
import 'package:dartnest/dartnest.dart';
import 'package:dartnest/src/routing/route_match.dart';
import 'package:dartnest/src/routing/route_pattern.dart';
import 'package:dartnest/src/routing/router.dart';
import 'package:test/test.dart';

Router<String> routerOf(List<(String, String)> routes) {
  final router = Router<String>();
  for (final (method, path) in routes) {
    router.add(
      method,
      RoutePattern.join('', path),
      '$method $path',
      source: '$method $path',
    );
  }
  return router;
}

List<String> split(String path) =>
    path.split('/').where((s) => s.isNotEmpty).toList();

RouteMatch<String> match(Router<String> router, String method, String path) =>
    router.match(method, split(path));

Matcher found(String value, [Map<String, String> parameters = const {}]) =>
    isA<RouteFound<String>>()
        .having((m) => m.value, 'value', value)
        .having((m) => m.parameters, 'parameters', parameters);

void main() {
  group('Router.match', () {
    test('static, parameter and root routes', () {
      final router = routerOf([
        ('GET', '/'),
        ('GET', '/users'),
        ('GET', '/users/:id'),
        ('GET', '/users/:id/posts/:postId'),
      ]);

      expect(match(router, 'GET', '/'), found('GET /'));
      expect(match(router, 'GET', '/users'), found('GET /users'));
      expect(
        match(router, 'GET', '/users/7'),
        found('GET /users/:id', {'id': '7'}),
      );
      expect(
        match(router, 'GET', '/users/7/posts/9'),
        found('GET /users/:id/posts/:postId', {'id': '7', 'postId': '9'}),
      );
    });

    test('static beats parameter beats wildcard', () {
      final router = routerOf([
        ('GET', '/files/readme'),
        ('GET', '/files/:name'),
        ('GET', '/files/*'),
      ]);

      expect(match(router, 'GET', '/files/readme'), found('GET /files/readme'));
      expect(
        match(router, 'GET', '/files/a'),
        found('GET /files/:name', {'name': 'a'}),
      );
      expect(
        match(router, 'GET', '/files/a/b/c'),
        found('GET /files/*', {'*': 'a/b/c'}),
      );
    });

    test('wildcard needs at least one segment', () {
      final router = routerOf([('GET', '/static/*')]);

      expect(match(router, 'GET', '/static'), isA<RouteNotFound<String>>());
    });

    // Review Focus 3: overlapping static and parameter routes.
    test('backtracks from a static branch to a parameter branch', () {
      final router = routerOf([
        ('GET', '/users/me'),
        ('GET', '/users/:id/posts'),
        ('DELETE', '/users/:id'),
      ]);

      expect(
        match(router, 'GET', '/users/me/posts'),
        found('GET /users/:id/posts', {'id': 'me'}),
      );
      expect(
        match(router, 'DELETE', '/users/me'),
        found('DELETE /users/:id', {'id': 'me'}),
      );
      expect(match(router, 'GET', '/users/me'), found('GET /users/me'));
    });

    test('unknown path is not found', () {
      final router = routerOf([('GET', '/users')]);

      expect(match(router, 'GET', '/posts'), isA<RouteNotFound<String>>());
      expect(match(router, 'GET', '/users/1'), isA<RouteNotFound<String>>());
    });

    test('known path with another method is 405 with sorted methods', () {
      final router = routerOf([
        ('POST', '/users/:id'),
        ('GET', '/users/me'),
        ('PUT', '/users/:id'),
      ]);

      expect(
        match(router, 'PATCH', '/users/me'),
        isA<RouteMethodNotAllowed<String>>().having(
          (m) => m.allowed,
          'allowed',
          ['GET', 'HEAD', 'POST', 'PUT'],
        ),
      );
    });

    test('HEAD falls back to GET, an explicit HEAD wins', () {
      final router = routerOf([('GET', '/a'), ('GET', '/b'), ('HEAD', '/b')]);

      expect(match(router, 'HEAD', '/a'), found('GET /a'));
      expect(match(router, 'HEAD', '/b'), found('HEAD /b'));
    });

    test('methods are case-insensitive', () {
      final router = routerOf([('get', '/a')]);

      expect(match(router, 'GET', '/a'), found('get /a'));
    });

    test('result does not depend on insertion order', () {
      final routes = [('GET', '/x/:id'), ('GET', '/x/new'), ('GET', '/x/*')];
      final forward = routerOf(routes);
      final backward = routerOf(routes.reversed.toList());

      for (final path in ['/x/new', '/x/7', '/x/7/8']) {
        final a = match(forward, 'GET', path) as RouteFound<String>;
        final b = match(backward, 'GET', path) as RouteFound<String>;
        expect(a.value, b.value, reason: path);
      }
    });
  });

  group('Router.add', () {
    test('same method and shape is a duplicate even with other names', () {
      final router = Router<String>()
        ..add('GET', RoutePattern.join('/users', ':id'), 'a', source: 'A.one');

      expect(
        () => router.add(
          'get',
          RoutePattern.join('/users', ':userId'),
          'b',
          source: 'B.two',
        ),
        throwsA(
          isA<DuplicateRouteError>()
              .having((e) => e.method, 'method', 'GET')
              .having((e) => e.path, 'path', '/users/:userId')
              .having((e) => e.existing, 'existing', 'A.one')
              .having((e) => e.duplicate, 'duplicate', 'B.two'),
        ),
      );
    });

    test('same path with another method is not a duplicate', () {
      final router = routerOf([('GET', '/a'), ('POST', '/a')]);

      expect(match(router, 'POST', '/a'), found('POST /a'));
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run from `packages/dartnest`: `dart test test/routing/router_test.dart`
Expected: FAIL at compile time, first error: `Error: Error when reading 'lib/src/routing/route_match.dart': No such file or directory`

- [ ] **Step 3: Implement**

`packages/dartnest/lib/src/routing/route_match.dart`:

```dart
/// Result of `Router.match`.
sealed class RouteMatch<V> {
  /// Creates a result.
  const RouteMatch();
}

/// A route matches the path and the method.
final class RouteFound<V> extends RouteMatch<V> {
  /// Creates the result.
  const RouteFound(this.value, this.parameters);

  /// The value registered for the route.
  final V value;

  /// Path parameters by name (the wildcard as `*`), percent-decoded.
  final Map<String, String> parameters;
}

/// Some route matches the path, none matches the method.
final class RouteMethodNotAllowed<V> extends RouteMatch<V> {
  /// Creates the result.
  const RouteMethodNotAllowed(this.allowed);

  /// Methods accepted for the path, sorted; `HEAD` is included when `GET`
  /// is.
  final List<String> allowed;
}

/// No route matches the path.
final class RouteNotFound<V> extends RouteMatch<V> {
  /// Creates the result.
  const RouteNotFound();
}
```

`packages/dartnest/lib/src/routing/router.dart`:

```dart
import 'pattern_segment.dart';
import 'route_match.dart';
import 'route_pattern.dart';
import 'routing_error.dart';

/// A segment trie (radix tree over path segments) mapping method + path to
/// a value.
///
/// Matching priority at every segment: static > `:param` > `*`, with
/// backtracking, so `/users/me` (static) and `/users/:id/posts` both work
/// and `DELETE /users/me` reaches `DELETE /users/:id` when the static route
/// has no `DELETE`. The result does not depend on insertion order. A router
/// is filled once at startup and only read afterwards.
final class Router<V> {
  /// Creates an empty router.
  Router();

  final _Node<V> _root = _Node<V>();

  /// Registers [value] for [method] and [pattern]; [source] describes the
  /// handler for [DuplicateRouteError].
  void add(
    String method,
    RoutePattern pattern,
    V value, {
    required String source,
  }) {
    var node = _root;
    for (final segment in pattern.segments) {
      node = node.child(segment);
    }
    final verb = method.toUpperCase();
    final existing = node.endpoints[verb];
    if (existing != null) {
      throw DuplicateRouteError(
        method: verb,
        path: pattern.toString(),
        existing: existing.source,
        duplicate: source,
      );
    }
    node.endpoints[verb] = _Endpoint(value, pattern.parameterNames, source);
  }

  /// Matches [method] against non-empty, decoded path [segments]. `HEAD`
  /// falls back to the `GET` route of the same path.
  RouteMatch<V> match(String method, List<String> segments) {
    final search = _Search<V>(segments, method.toUpperCase());
    final found = search.visit(_root, 0);
    if (found != null) return found;
    if (search.allowed.isEmpty) return RouteNotFound<V>();
    return RouteMethodNotAllowed<V>(search.allowed.toList()..sort());
  }
}

final class _Endpoint<V> {
  _Endpoint(this.value, this.parameterNames, this.source);

  final V value;
  final List<String> parameterNames;
  final String source;
}

final class _Node<V> {
  final Map<String, _Node<V>> statics = {};
  final Map<String, _Endpoint<V>> endpoints = {};
  _Node<V>? param;
  _Node<V>? wildcard;

  _Node<V> child(PatternSegment segment) => switch (segment) {
    StaticSegment(:final value) => statics.putIfAbsent(value, _Node<V>.new),
    ParamSegment() => param ??= _Node<V>(),
    WildcardSegment() => wildcard ??= _Node<V>(),
  };

  Set<String> get allowedMethods => {
    ...endpoints.keys,
    if (endpoints.containsKey('GET')) 'HEAD',
  };
}

/// One depth-first search; collects the methods of path matches that did
/// not accept [method], for 405.
final class _Search<V> {
  _Search(this.segments, this.method);

  final List<String> segments;
  final String method;
  final Set<String> allowed = {};
  final List<String> captured = [];

  RouteFound<V>? visit(_Node<V> node, int index) {
    if (index == segments.length) return _accept(node);
    final segment = segments[index];
    final exact = node.statics[segment];
    if (exact != null) {
      final found = visit(exact, index + 1);
      if (found != null) return found;
    }
    final param = node.param;
    if (param != null) {
      captured.add(segment);
      final found = visit(param, index + 1);
      captured.removeLast();
      if (found != null) return found;
    }
    final wildcard = node.wildcard;
    if (wildcard == null) return null;
    captured.add(segments.sublist(index).join('/'));
    final found = _accept(wildcard);
    captured.removeLast();
    return found;
  }

  RouteFound<V>? _accept(_Node<V> node) {
    final endpoint =
        node.endpoints[method] ??
        (method == 'HEAD' ? node.endpoints['GET'] : null);
    if (endpoint == null) {
      allowed.addAll(node.allowedMethods);
      return null;
    }
    return RouteFound<V>(
      endpoint.value,
      Map.fromIterables(endpoint.parameterNames, captured),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run from `packages/dartnest`: `dart test test/routing/router_test.dart`
Expected: `+11: All tests passed!`

Run from `packages/dartnest`: `dart test`
Expected: `+119: All tests passed!`

- [ ] **Step 5: Analyze, format and commit**

Run from repo root: `dart analyze && dart format --output=none --set-exit-if-changed packages`
Expected: `No issues found!` and `Formatted N files (0 changed)`.

```bash
git add \
  packages/dartnest/lib/src/routing/route_match.dart \
  packages/dartnest/lib/src/routing/router.dart \
  packages/dartnest/test/routing/router_test.dart
git commit -m "feat(routing): add segment-trie router with 404/405 and HEAD fallback"
```

---

### Task 5: Компоненти конвеєра та `ExecutionContext`

Контракти компонентів конвеєра та контекст запиту. `PipelineComponent` — маркер, щоб у списках можна було змішувати `Use<T>()` і готові екземпляри. `Enhancers` — об'єкт-параметр (`guards`, `interceptors`, `pipes`, `filters`) замість чотирьох окремих параметрів у `Controller`/`Route`/`Application` (правило «≤ 5 параметрів»). `ExceptionFilter<E>` — абстрактний клас із `catches(error) => error is E`, бо фільтр потребує типу винятку під час виконання. `HttpContext extends Transport` — це і є `HttpTransport` зі специфікації. У цій задачі `ExecutionContext` ще без `pipes`, `param`, `query`, `bodyAs` — їх додає Task 6.

**Files:**
- Create: `packages/dartnest/lib/src/pipeline/pipeline_component.dart`
- Create: `packages/dartnest/lib/src/pipeline/use.dart`
- Create: `packages/dartnest/lib/src/pipeline/enhancers.dart`
- Create: `packages/dartnest/lib/src/pipeline/guard.dart`
- Create: `packages/dartnest/lib/src/pipeline/interceptor.dart`
- Create: `packages/dartnest/lib/src/pipeline/argument_source.dart`
- Create: `packages/dartnest/lib/src/pipeline/argument_meta.dart`
- Create: `packages/dartnest/lib/src/pipeline/pipe.dart`
- Create: `packages/dartnest/lib/src/pipeline/exception_filter.dart`
- Create: `packages/dartnest/lib/src/pipeline/transport.dart`
- Create: `packages/dartnest/lib/src/pipeline/execution_context.dart`
- Modify: `packages/dartnest/lib/dartnest.dart`
- Create: `packages/dartnest/test/helpers/http_fixtures.dart`
- Test: `packages/dartnest/test/pipeline/execution_context_test.dart`

**Interfaces:**
- Consumes: `Injector` (DI), `HttpRequest`, `ResponseHead`, `RequestBody` (Task 2).
- Produces:
  - `abstract interface class PipelineComponent {}`
  - `final class Use<T extends PipelineComponent> implements PipelineComponent { const Use(); Type get type; T resolve(Injector injector); }`
  - `final class Enhancers { const Enhancers({List<PipelineComponent> guards, interceptors, pipes, filters}); static const none; }`
  - `abstract interface class Guard implements PipelineComponent { FutureOr<bool> canActivate(ExecutionContext context); }`
  - `typedef Next<T> = Future<T> Function();` and `abstract interface class Interceptor implements PipelineComponent { FutureOr<Object?> intercept(ExecutionContext context, Next<Object?> next); }`
  - `enum ArgumentSource { path, query, body; String label; }`, `final class ArgumentMeta { const ArgumentMeta({required ArgumentSource source, required String name, required Type type}); }`
  - `abstract interface class Pipe<I, O> implements PipelineComponent { FutureOr<O> transform(I value, ArgumentMeta meta); }`
  - `abstract class ExceptionFilter<E extends Object> implements PipelineComponent { const ExceptionFilter(); bool catches(Object error); FutureOr<Object?> handle(E error, ExecutionContext context); }`
  - `sealed class Transport` with `HttpContext({required HttpRequest request, required ResponseHead response, Map<String, String> pathParameters})`.
  - `final class ExecutionContext { ExecutionContext({required Transport transport, required Type controllerType, required String handlerName, List<Object> metadata}); Map<Object, Object?> items; HttpContext switchToHttp(); T? metadata<T extends Object>(); String? header(String name); RequestBody get body; }`
  - Test helpers `requestFor(method, target, {headers, body})` and `contextFor(request, {pathParameters, metadata})` in `test/helpers/http_fixtures.dart`.

- [ ] **Step 1: Write the failing tests**

`packages/dartnest/test/helpers/http_fixtures.dart`:

```dart
// Shared builders for pipeline and HTTP tests.
import 'dart:convert';

import 'package:dartnest/dartnest.dart';

/// A request for [method] and [target] with an optional JSON or raw body.
HttpRequest requestFor(
  String method,
  String target, {
  Map<String, String> headers = const {},
  String? body,
}) => HttpRequest(
  method: method,
  uri: Uri.parse(target),
  headers: HeaderMap.of(headers),
  body: body == null ? null : RequestBody.bytes(utf8.encode(body)),
);

/// An HTTP context for [request] with the given matched path parameters.
ExecutionContext contextFor(
  HttpRequest request, {
  Map<String, String> pathParameters = const {},
  List<Object> metadata = const [],
}) => ExecutionContext(
  transport: HttpContext(
    request: request,
    response: ResponseHead(),
    pathParameters: pathParameters,
  ),
  controllerType: Object,
  handlerName: 'test',
  metadata: metadata,
);
```

`packages/dartnest/test/pipeline/execution_context_test.dart`:

```dart
import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

import '../helpers/http_fixtures.dart';

final class Roles {
  const Roles(this.names);
  final List<String> names;
}

final class Public {
  const Public();
}

final class AllowAll implements Guard {
  @override
  bool canActivate(ExecutionContext context) => true;
}

final class StateErrorFilter extends ExceptionFilter<StateError> {
  const StateErrorFilter();

  @override
  Object? handle(StateError error, ExecutionContext context) => 'handled';
}

void main() {
  group('ExecutionContext', () {
    test('exposes the HTTP view, header and body', () async {
      final request = requestFor(
        'POST',
        '/users/7',
        headers: {'X-Token': 'abc'},
        body: '{"a":1}',
      );
      final context = contextFor(request, pathParameters: {'id': '7'});

      expect(context.switchToHttp().request, same(request));
      expect(context.switchToHttp().pathParameters, {'id': '7'});
      expect(context.header('x-token'), 'abc');
      expect(context.header('missing'), isNull);
      expect(await context.body.json(), {'a': 1});
    });

    test('route metadata overrides controller metadata', () {
      final context = contextFor(
        requestFor('GET', '/'),
        metadata: [
          const Roles(['admin']),
          const Public(),
          const Roles(['user']),
        ],
      );

      expect(context.metadata<Roles>()?.names, ['admin']);
      expect(context.metadata<Public>(), isNotNull);
      expect(context.metadata<String>(), isNull);
    });

    test('items carry data from guards to handlers', () {
      final context = contextFor(requestFor('GET', '/'));
      context.items[#user] = 'ann';

      expect(context.items[#user], 'ann');
    });
  });

  group('pipeline contracts', () {
    test('Use resolves the component from the injector', () async {
      final container = await Container.create(
        Module(id: 'app', providers: [Provider((i) => AllowAll())]),
      );

      const use = Use<AllowAll>();

      expect(use.type, AllowAll);
      expect(use.resolve(container.root), same(container.root.get<AllowAll>()));
      expect(use.toString(), 'Use<AllowAll>');
    });

    test('ExceptionFilter catches only its type', () {
      const filter = StateErrorFilter();

      expect(filter.catches(StateError('x')), isTrue);
      expect(filter.catches(ArgumentError('x')), isFalse);
    });

    test('Enhancers.none is empty', () {
      expect(Enhancers.none.guards, isEmpty);
      expect(Enhancers.none.interceptors, isEmpty);
      expect(Enhancers.none.pipes, isEmpty);
      expect(Enhancers.none.filters, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run from `packages/dartnest`: `dart test test/pipeline/execution_context_test.dart`
Expected: FAIL at compile time, first error: `Error: Type 'Guard' not found.`

- [ ] **Step 3: Implement**

`packages/dartnest/lib/src/pipeline/pipeline_component.dart`:

```dart
/// Marker for everything that can be listed in `Enhancers`: guards,
/// interceptors, pipes, exception filters, and `Use` references to them.
///
/// Implement `Guard`, `Interceptor`, `Pipe` or extend `ExceptionFilter`
/// rather than this type directly.
abstract interface class PipelineComponent {}
```

`packages/dartnest/lib/src/pipeline/use.dart`:

```dart
import '../di/injector.dart';
import 'pipeline_component.dart';

/// A pipeline component taken from dependency injection.
///
/// `Use<AuthGuard>()` is replaced at startup by the `AuthGuard` provider
/// visible in the module that declares the controller (the root module for
/// application-level components), so a guard can inject services. A missing
/// provider fails `Application.create` with `MissingProviderError`.
final class Use<T extends PipelineComponent> implements PipelineComponent {
  /// Creates the reference.
  const Use();

  /// The referenced component type.
  Type get type => T;

  /// Resolves the component through [injector].
  T resolve(Injector injector) => injector.get<T>();

  @override
  String toString() => 'Use<$T>';
}
```

`packages/dartnest/lib/src/pipeline/enhancers.dart`:

````dart
import 'pipeline_component.dart';

/// Guards, interceptors, pipes and exception filters attached to an
/// application, a controller or a route.
///
/// Each entry is a ready instance or a [Use] reference resolved from DI.
/// Levels compose as follows: guards, interceptors and pipes run
/// application → controller → route (interceptors wrap like an onion, the
/// application's outermost); exception filters are tried route → controller
/// → application, then the default filter.
///
/// ```dart
/// const Enhancers(guards: [Use<AuthGuard>()], filters: [DbErrorFilter()]);
/// ```
final class Enhancers {
  /// Creates the lists; every list defaults to empty.
  const Enhancers({
    this.guards = const [],
    this.interceptors = const [],
    this.pipes = const [],
    this.filters = const [],
  });

  /// No components.
  static const none = Enhancers();

  /// `Guard`s or `Use` references to them.
  final List<PipelineComponent> guards;

  /// `Interceptor`s or `Use` references to them.
  final List<PipelineComponent> interceptors;

  /// `Pipe`s or `Use` references to them.
  final List<PipelineComponent> pipes;

  /// `ExceptionFilter`s or `Use` references to them.
  final List<PipelineComponent> filters;
}
````

`packages/dartnest/lib/src/pipeline/guard.dart`:

```dart
import 'dart:async';

import 'execution_context.dart';
import 'pipeline_component.dart';

/// Decides whether a request may reach its handler.
///
/// Returning `false` produces 403 (`ForbiddenException`); throwing an
/// `HttpException` (for example `UnauthorizedException`) produces that
/// status instead.
abstract interface class Guard implements PipelineComponent {
  /// Whether the handler may run for [context].
  FutureOr<bool> canActivate(ExecutionContext context);
}
```

`packages/dartnest/lib/src/pipeline/interceptor.dart`:

````dart
import 'dart:async';

import 'execution_context.dart';
import 'pipeline_component.dart';

/// Continues to the next step of a chain and completes with its result.
typedef Next<T> = Future<T> Function();

/// Wraps the handler: runs code before and after it, replaces its result,
/// or answers without calling it.
///
/// ```dart
/// final class TimingInterceptor implements Interceptor {
///   @override
///   Future<Object?> intercept(ExecutionContext context, Next<Object?> next) async {
///     final watch = Stopwatch()..start();
///     final result = await next();
///     context.switchToHttp().response.headers.set('x-ms', '${watch.elapsedMilliseconds}');
///     return result;
///   }
/// }
/// ```
abstract interface class Interceptor implements PipelineComponent {
  /// Handles [context]; call [next] at most once to run the inner chain.
  FutureOr<Object?> intercept(ExecutionContext context, Next<Object?> next);
}
````

`packages/dartnest/lib/src/pipeline/argument_source.dart`:

```dart
/// Where a handler argument comes from.
enum ArgumentSource {
  /// A `:name` or `*` path parameter.
  path('path parameter'),

  /// A query string parameter.
  query('query parameter'),

  /// The request body.
  body('request body');

  const ArgumentSource(this.label);

  /// Human-readable name used in error messages.
  final String label;
}
```

`packages/dartnest/lib/src/pipeline/argument_meta.dart`:

```dart
import 'argument_source.dart';

/// Describes the argument a `Pipe` is transforming.
final class ArgumentMeta {
  /// Creates the description.
  const ArgumentMeta({
    required this.source,
    required this.name,
    required this.type,
  });

  /// Where the raw value comes from.
  final ArgumentSource source;

  /// Parameter name; `body` for the request body.
  final String name;

  /// The type the handler asked for.
  final Type type;
}
```

`packages/dartnest/lib/src/pipeline/pipe.dart`:

```dart
import 'dart:async';

import 'argument_meta.dart';
import 'pipeline_component.dart';

/// Transforms or validates one handler argument.
///
/// Pipes run inside `ExecutionContext.param`, `query` and `bodyAs`, in the
/// order application → controller → route → the call's own `pipes`, on the
/// raw value: a `String` (or `null` when a query parameter is absent) for
/// parameters, the decoded JSON for the body. Built-in conversion to the
/// requested type runs after the pipes, and only when the value is not
/// already of that type. Throw `BadRequestException` to reject a value.
///
/// Pipes listed in `Enhancers` see every argument, so they should implement
/// `Pipe<Object?, Object?>` and pass through values they do not handle.
abstract interface class Pipe<I, O> implements PipelineComponent {
  /// Transforms [value] of the argument described by [meta].
  FutureOr<O> transform(I value, ArgumentMeta meta);
}
```

`packages/dartnest/lib/src/pipeline/exception_filter.dart`:

````dart
import 'dart:async';

import 'execution_context.dart';
import 'pipeline_component.dart';

/// Turns an error of type [E] into a result.
///
/// A filter is a class to extend (not an interface) because [catches] needs
/// the type argument at runtime. The first filter whose [catches] accepts
/// the error handles it; route filters are tried before controller and
/// application filters. The returned value is serialized like a handler
/// result (return an `HttpResponse` to control the status). A filter may
/// throw: the new error goes to the filters after it, then to the default
/// filter.
///
/// ```dart
/// final class UserMissingFilter extends ExceptionFilter<UserMissing> {
///   const UserMissingFilter();
///   @override
///   Object? handle(UserMissing error, ExecutionContext context) =>
///       throw NotFoundException(message: 'No user ${error.id}');
/// }
/// ```
abstract class ExceptionFilter<E extends Object> implements PipelineComponent {
  /// Creates a filter.
  const ExceptionFilter();

  /// Whether this filter handles [error].
  bool catches(Object error) => error is E;

  /// Handles [error] for the request in [context].
  FutureOr<Object?> handle(E error, ExecutionContext context);
}
````

`packages/dartnest/lib/src/pipeline/transport.dart`:

```dart
import '../http/http_request.dart';
import '../http/response_head.dart';

/// The protocol an `ExecutionContext` serves. Sealed: HTTP now, GraphQL
/// later.
sealed class Transport {
  /// Creates a transport.
  const Transport();
}

/// The HTTP view of a request: the request, the response head handlers may
/// change, and the matched path parameters.
final class HttpContext extends Transport {
  /// Creates the HTTP view.
  HttpContext({
    required this.request,
    required this.response,
    this.pathParameters = const {},
  });

  /// The incoming request.
  final HttpRequest request;

  /// Status and headers for the response.
  final ResponseHead response;

  /// Matched path parameters, percent-decoded; the wildcard is `*`.
  final Map<String, String> pathParameters;
}
```

`packages/dartnest/lib/src/pipeline/execution_context.dart`:

```dart
import '../http/request_body.dart';
import 'transport.dart';

/// Everything the pipeline knows about the request being handled; passed to
/// guards, interceptors, filters and handlers.
///
/// One context is created per request, after routing.
final class ExecutionContext {
  /// Creates a context. [metadata] is ordered most specific first (route,
  /// then controller).
  ExecutionContext({
    required this.transport,
    required this.controllerType,
    required this.handlerName,
    List<Object> metadata = const [],
  }) : _metadata = metadata;

  /// The protocol of the request.
  final Transport transport;

  /// The controller class that declares the handler.
  final Type controllerType;

  /// Name of the handler (the route's `name`).
  final String handlerName;

  /// Free-form storage for passing data between guards, interceptors and
  /// the handler (for example the authenticated user).
  final Map<Object, Object?> items = {};

  final List<Object> _metadata;

  /// The HTTP view of the request.
  HttpContext switchToHttp() => switch (transport) {
    HttpContext http => http,
  };

  /// The first metadata value of type [T]: route metadata overrides
  /// controller metadata. `null` when neither declares one.
  T? metadata<T extends Object>() {
    for (final value in _metadata) {
      if (value is T) return value;
    }
    return null;
  }

  /// The first value of request header [name] (case-insensitive).
  String? header(String name) => switchToHttp().request.headers[name];

  /// The raw request body, read once and cached.
  RequestBody get body => switchToHttp().request.body;
}
```

- [ ] **Step 4: Export the public types**

Add to `packages/dartnest/lib/dartnest.dart`, keeping all `export` lines sorted:

```dart
export 'src/pipeline/argument_meta.dart';
export 'src/pipeline/argument_source.dart';
export 'src/pipeline/enhancers.dart';
export 'src/pipeline/exception_filter.dart';
export 'src/pipeline/execution_context.dart';
export 'src/pipeline/guard.dart';
export 'src/pipeline/interceptor.dart';
export 'src/pipeline/pipe.dart';
export 'src/pipeline/pipeline_component.dart';
export 'src/pipeline/transport.dart';
export 'src/pipeline/use.dart';
```

- [ ] **Step 5: Run the tests to verify they pass**

Run from `packages/dartnest`: `dart test test/pipeline/execution_context_test.dart`
Expected: `+6: All tests passed!`

Run from `packages/dartnest`: `dart test`
Expected: `+125: All tests passed!`

- [ ] **Step 6: Analyze, format and commit**

Run from repo root: `dart analyze && dart format --output=none --set-exit-if-changed packages`
Expected: `No issues found!` and `Formatted N files (0 changed)`.

```bash
git add \
  packages/dartnest/lib/src/pipeline/pipeline_component.dart \
  packages/dartnest/lib/src/pipeline/use.dart \
  packages/dartnest/lib/src/pipeline/enhancers.dart \
  packages/dartnest/lib/src/pipeline/guard.dart \
  packages/dartnest/lib/src/pipeline/interceptor.dart \
  packages/dartnest/lib/src/pipeline/argument_source.dart \
  packages/dartnest/lib/src/pipeline/argument_meta.dart \
  packages/dartnest/lib/src/pipeline/pipe.dart \
  packages/dartnest/lib/src/pipeline/exception_filter.dart \
  packages/dartnest/lib/src/pipeline/transport.dart \
  packages/dartnest/lib/src/pipeline/execution_context.dart \
  packages/dartnest/test/helpers/http_fixtures.dart \
  packages/dartnest/test/pipeline/execution_context_test.dart \
  packages/dartnest/lib/dartnest.dart
git commit -m "feat(pipeline): add pipeline component contracts and ExecutionContext"
```

---

### Task 6: Аргументи: pipes, конвертація типів, `bodyAs`

Читання аргументів. `param<T>`, `query<T>` і `bodyAs<T>` асинхронні (відхилення від специфікації: `Pipe.transform` повертає `FutureOr`, тому `await ctx.param<int>('id')`). Pipes працюють на сирому значенні в порядку app → controller → route → pipes виклику; вбудована конвертація (`ValueConverter`: `int`, `double`, `num`, `bool`, `DateTime`, `String` і nullable-варіанти) виконується в кінці й лише якщо значення ще не `T`. Відсутнє значення для nonnullable `T` — 400, для nullable — `null`. Тип без конвертера й без pipe — `UnsupportedConversionError` (дефект коду, 500), невідоме ім'я параметра — `UnknownRouteParameterError`. `EnumPipe` перетворює значення enum за іменем.

**Files:**
- Create: `packages/dartnest/lib/src/pipeline/pipeline_error.dart`
- Create: `packages/dartnest/lib/src/pipeline/value_converter.dart`
- Create: `packages/dartnest/lib/src/pipeline/argument_resolver.dart`
- Create: `packages/dartnest/lib/src/pipeline/enum_pipe.dart`
- Modify: `packages/dartnest/lib/src/pipeline/execution_context.dart`
- Modify: `packages/dartnest/lib/dartnest.dart`
- Test: `packages/dartnest/test/pipeline/argument_binding_test.dart`

**Interfaces:**
- Consumes: `ExecutionContext`, `Pipe`, `ArgumentMeta`, `ArgumentSource` (Task 5); `BadRequestException` (Task 1).
- Produces:
  - `sealed class PipelineError extends DartnestError` with `UnsupportedConversionError({required ArgumentMeta argument, required Type valueType})` and `UnknownRouteParameterError({required String name, required String handlerName, required List<String> declared})`.
  - `abstract final class ValueConverter { static T convert<T>(String raw, ArgumentMeta meta); }`; internal.
  - `abstract final class ArgumentResolver { static Future<T> resolve<T>(Object? raw, ArgumentMeta meta, List<Pipe<Object?, Object?>> pipes); static Future<Object?> pipe(Object? raw, ArgumentMeta meta, List<Pipe<Object?, Object?>> pipes); }`; internal.
  - `final class EnumPipe<E extends Enum> implements Pipe<Object?, Object?> { const EnumPipe(List<E> values); }`
  - `ExecutionContext` gains `List<Pipe<Object?, Object?>> pipes` in the constructor and `Future<T> param<T>(String name, {pipes})`, `Future<T> query<T>(String name, {pipes})`, `Future<T> bodyAs<T>(T Function(Map<String, Object?>) fromJson, {pipes})`.

- [ ] **Step 1: Write the failing tests**

`packages/dartnest/test/pipeline/argument_binding_test.dart`:

```dart
import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

import '../helpers/http_fixtures.dart';

enum Status { active, banned }

final class CreateUser {
  CreateUser(this.name);

  factory CreateUser.fromJson(Map<String, Object?> json) => switch (json) {
    {'name': final String name} => CreateUser(name),
    _ => throw const FormatException('"name" must be a string'),
  };

  final String name;
}

/// Records what it sees and upper-cases strings.
final class UpperPipe implements Pipe<Object?, Object?> {
  final List<String> seen = [];

  @override
  Object? transform(Object? value, ArgumentMeta meta) {
    seen.add('${meta.source.name}:${meta.name}:${meta.type}');
    return value is String ? value.toUpperCase() : value;
  }
}

/// Supplies a default for an absent value.
final class DefaultPipe implements Pipe<Object?, Object?> {
  const DefaultPipe(this.fallback);
  final Object fallback;

  @override
  Object? transform(Object? value, ArgumentMeta meta) => value ?? fallback;
}

ExecutionContext contextWithPipes(
  String target, {
  Map<String, String> pathParameters = const {},
  List<Pipe<Object?, Object?>> pipes = const [],
  String? body,
}) => ExecutionContext(
  transport: HttpContext(
    request: requestFor('POST', target, body: body),
    response: ResponseHead(),
    pathParameters: pathParameters,
  ),
  controllerType: Object,
  handlerName: 'UsersController.find',
  pipes: pipes,
);

Matcher badRequest(String messagePart) => throwsA(
  isA<BadRequestException>().having(
    (e) => e.message,
    'message',
    contains(messagePart),
  ),
);

void main() {
  group('param', () {
    test('converts built-in types', () async {
      final context = contextWithPipes(
        '/',
        pathParameters: {
          'i': '7',
          'd': '1.5',
          'n': '3',
          'b': 'true',
          't': '2026-10-13T10:00:00Z',
          's': 'x',
        },
      );

      expect(await context.param<int>('i'), 7);
      expect(await context.param<double>('d'), 1.5);
      expect(await context.param<num>('n'), 3);
      expect(await context.param<bool>('b'), isTrue);
      expect(
        await context.param<DateTime>('t'),
        DateTime.utc(2026, 10, 13, 10),
      );
      expect(await context.param<String>('s'), 'x');
      expect(await context.param<int?>('i'), 7);
    });

    test('unparsable value is a 400 naming the parameter', () async {
      final context = contextWithPipes('/', pathParameters: {'id': 'abc'});

      await expectLater(
        context.param<int>('id'),
        badRequest('Invalid path parameter "id": expected int, got "abc".'),
      );
      await expectLater(context.param<bool>('id'), badRequest('expected bool'));
    });

    test('unknown parameter name is a programming error', () async {
      final context = contextWithPipes('/', pathParameters: {'id': '1'});

      await expectLater(
        context.param<int>('idd'),
        throwsA(
          isA<UnknownRouteParameterError>()
              .having((e) => e.declared, 'declared', ['id'])
              .having((e) => e.handlerName, 'handler', 'UsersController.find'),
        ),
      );
    });

    test('type without built-in conversion needs a pipe', () async {
      final context = contextWithPipes('/', pathParameters: {'u': 'x'});

      await expectLater(
        context.param<Uri>('u'),
        throwsA(
          isA<UnsupportedConversionError>().having(
            (e) => e.message,
            'message',
            contains('add a Pipe that returns Uri'),
          ),
        ),
      );
    });
  });

  group('query', () {
    test('absent parameter: null when nullable, 400 otherwise', () async {
      final context = contextWithPipes('/users?page=2');

      expect(await context.query<int>('page'), 2);
      expect(await context.query<int?>('size'), isNull);
      await expectLater(
        context.query<int>('size'),
        badRequest('Missing query parameter "size".'),
      );
    });

    test('takes the first of repeated values', () async {
      final context = contextWithPipes('/?tag=a&tag=b');

      expect(await context.query<String>('tag'), 'a');
    });

    test('EnumPipe converts by name and rejects unknown names', () async {
      final context = contextWithPipes('/?status=banned&bad=x');
      const pipes = [EnumPipe(Status.values)];

      expect(
        await context.query<Status>('status', pipes: pipes),
        Status.banned,
      );
      expect(await context.query<Status?>('none', pipes: pipes), isNull);
      await expectLater(
        context.query<Status>('bad', pipes: pipes),
        badRequest('expected one of active, banned, got "x"'),
      );
    });
  });

  group('pipes', () {
    test('configured pipes run before call pipes, on the raw value', () async {
      final upper = UpperPipe();
      final context = contextWithPipes('/?name=ann', pipes: [upper]);

      final name = await context.query<String>(
        'name',
        pipes: [const DefaultPipe('nobody')],
      );

      expect(name, 'ANN');
      expect(upper.seen, ['query:name:String']);
    });

    test('a pipe may supply a value for an absent parameter', () async {
      final context = contextWithPipes('/');

      expect(
        await context.query<int>('page', pipes: [const DefaultPipe('1')]),
        1,
      );
    });
  });

  // Review Focus 2: bad bodies are client errors, not server errors.
  group('bodyAs', () {
    test('decodes a JSON object', () async {
      final context = contextWithPipes('/', body: '{"name":"ann"}');

      final user = await context.bodyAs(CreateUser.fromJson);

      expect(user.name, 'ann');
    });

    test('malformed JSON is a 400', () async {
      final context = contextWithPipes('/', body: '{"name":');

      await expectLater(
        context.bodyAs(CreateUser.fromJson),
        badRequest('Request body is not valid JSON'),
      );
    });

    test('a JSON array where an object is expected is a 400', () async {
      final context = contextWithPipes('/', body: '[1,2]');

      await expectLater(
        context.bodyAs(CreateUser.fromJson),
        badRequest('Request body must be a JSON object.'),
      );
    });

    test('FormatException from fromJson is a 400', () async {
      final context = contextWithPipes('/', body: '{"name":1}');

      await expectLater(
        context.bodyAs(CreateUser.fromJson),
        badRequest('Invalid request body: "name" must be a string'),
      );
    });

    test('pipes see the decoded JSON before fromJson', () async {
      final upper = UpperPipe();
      final context = contextWithPipes(
        '/',
        body: '{"name":"ann"}',
        pipes: [upper],
      );

      await context.bodyAs(CreateUser.fromJson);

      expect(upper.seen, ['body:body:CreateUser']);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run from `packages/dartnest`: `dart test test/pipeline/argument_binding_test.dart`
Expected: FAIL at compile time, first error: `Error: No named parameter with the name 'pipes'.`

- [ ] **Step 3: Implement**

`packages/dartnest/lib/src/pipeline/pipeline_error.dart`:

```dart
import '../di/errors.dart';
import 'argument_meta.dart';

/// Programming errors detected while a request runs through the pipeline.
/// They reach the client as 500.
sealed class PipelineError extends DartnestError {
  /// Creates a pipeline error.
  const PipelineError();
}

/// A handler asked for an argument type that has no built-in conversion and
/// no pipe produced it.
final class UnsupportedConversionError extends PipelineError {
  /// Creates the error.
  const UnsupportedConversionError({
    required this.argument,
    required this.valueType,
  });

  /// The argument and the requested type.
  final ArgumentMeta argument;

  /// Runtime type of the value the pipes produced.
  final Type valueType;

  @override
  String get message =>
      'Cannot convert ${argument.source.label} "${argument.name}" from '
      '$valueType to ${argument.type}. Built-in conversion supports String, '
      'int, double, num, bool and DateTime; add a Pipe that returns '
      '${argument.type}.';
}

/// A handler read a path parameter that its route does not declare.
final class UnknownRouteParameterError extends PipelineError {
  /// Creates the error.
  const UnknownRouteParameterError({
    required this.name,
    required this.handlerName,
    required this.declared,
  });

  /// The requested parameter.
  final String name;

  /// The handler that asked for it.
  final String handlerName;

  /// Parameters the route declares.
  final List<String> declared;

  @override
  String get message =>
      'Handler "$handlerName" reads path parameter "$name", but its route '
      'declares ${declared.isEmpty ? 'none' : declared.join(', ')}.';
}
```

`packages/dartnest/lib/src/pipeline/value_converter.dart`:

```dart
import '../http/http_exception.dart';
import 'argument_meta.dart';
import 'pipeline_error.dart';

/// Built-in conversion of a raw string argument to `int`, `double`, `num`,
/// `bool` (`true`/`false`) or `DateTime` (ISO 8601), nullable or not.
abstract final class ValueConverter {
  /// Converts [raw] to [T]; an unparsable value throws
  /// [BadRequestException], an unsupported [T] throws
  /// [UnsupportedConversionError].
  static T convert<T>(String raw, ArgumentMeta meta) {
    final Object? parsed;
    if (_targets<T, int>()) {
      parsed = int.tryParse(raw);
    } else if (_targets<T, double>()) {
      parsed = double.tryParse(raw);
    } else if (_targets<T, num>()) {
      parsed = num.tryParse(raw);
    } else if (_targets<T, bool>()) {
      parsed = switch (raw) {
        'true' => true,
        'false' => false,
        _ => null,
      };
    } else if (_targets<T, DateTime>()) {
      parsed = DateTime.tryParse(raw);
    } else {
      throw UnsupportedConversionError(argument: meta, valueType: String);
    }
    if (parsed is T && parsed != null) return parsed;
    throw BadRequestException(
      message:
          'Invalid ${meta.source.label} "${meta.name}": expected '
          '${_typeOf<T>()}, got "$raw".',
    );
  }

  /// Whether [T] is [S] or `S?`.
  static bool _targets<T, S>() => T == S || T == _typeOf<S?>();

  static Type _typeOf<X>() => X;
}
```

`packages/dartnest/lib/src/pipeline/argument_resolver.dart`:

```dart
import 'dart:async';

import '../http/http_exception.dart';
import 'argument_meta.dart';
import 'pipe.dart';
import 'pipeline_error.dart';
import 'value_converter.dart';

/// Runs pipes over a raw argument and converts the result to the requested
/// type.
abstract final class ArgumentResolver {
  /// Pipes [raw] through [pipes] in order, then: a value that already is a
  /// [T] is returned; `null` for a non-nullable [T] throws
  /// [BadRequestException] (missing argument); a `String` goes through
  /// [ValueConverter]; anything else throws [UnsupportedConversionError].
  static Future<T> resolve<T>(
    Object? raw,
    ArgumentMeta meta,
    List<Pipe<Object?, Object?>> pipes,
  ) async {
    final value = await pipe(raw, meta, pipes);
    if (value is T) return value;
    if (value == null) {
      throw BadRequestException(
        message: 'Missing ${meta.source.label} "${meta.name}".',
      );
    }
    if (value is String) return ValueConverter.convert<T>(value, meta);
    throw UnsupportedConversionError(
      argument: meta,
      valueType: value.runtimeType,
    );
  }

  /// Pipes [raw] through [pipes] in order.
  static Future<Object?> pipe(
    Object? raw,
    ArgumentMeta meta,
    List<Pipe<Object?, Object?>> pipes,
  ) async {
    var value = raw;
    for (final pipe in pipes) {
      value = await pipe.transform(value, meta);
    }
    return value;
  }
}
```

`packages/dartnest/lib/src/pipeline/enum_pipe.dart`:

````dart
import '../http/http_exception.dart';
import 'argument_meta.dart';
import 'pipe.dart';

/// Converts a string argument to the enum value with that name.
///
/// ```dart
/// final status = await context.query<Status>(
///   'status',
///   pipes: [EnumPipe(Status.values)],
/// );
/// ```
///
/// Non-string values (including `null` for an absent query parameter) pass
/// through unchanged.
final class EnumPipe<E extends Enum> implements Pipe<Object?, Object?> {
  /// Creates the pipe for [values] (usually `MyEnum.values`).
  const EnumPipe(this.values);

  /// The accepted values.
  final List<E> values;

  @override
  Object? transform(Object? value, ArgumentMeta meta) {
    if (value is! String) return value;
    for (final candidate in values) {
      if (candidate.name == value) return candidate;
    }
    throw BadRequestException(
      message:
          'Invalid ${meta.source.label} "${meta.name}": expected one of '
          '${values.map((v) => v.name).join(', ')}, got "$value".',
    );
  }
}
````

Replace the whole `packages/dartnest/lib/src/pipeline/execution_context.dart` with:

````dart
import '../http/http_exception.dart';
import '../http/request_body.dart';
import 'argument_meta.dart';
import 'argument_resolver.dart';
import 'argument_source.dart';
import 'pipe.dart';
import 'pipeline_error.dart';
import 'transport.dart';

/// Everything the pipeline knows about the request being handled; passed to
/// guards, interceptors, filters and handlers.
///
/// One context is created per request, after routing. Arguments are read
/// with [param], [query] and [bodyAs], which run the pipes and convert the
/// value:
///
/// ```dart
/// Route.get('/:id', (c, ctx) async => c.findOne(await ctx.param<int>('id')));
/// ```
final class ExecutionContext {
  /// Creates a context. [metadata] is ordered most specific first (route,
  /// then controller); [pipes] are the resolved application, controller and
  /// route pipes in that order.
  ExecutionContext({
    required this.transport,
    required this.controllerType,
    required this.handlerName,
    List<Object> metadata = const [],
    List<Pipe<Object?, Object?>> pipes = const [],
  }) : _metadata = metadata,
       _pipes = pipes;

  /// The protocol of the request.
  final Transport transport;

  /// The controller class that declares the handler.
  final Type controllerType;

  /// Name of the handler (the route's `name`).
  final String handlerName;

  /// Free-form storage for passing data between guards, interceptors and
  /// the handler (for example the authenticated user).
  final Map<Object, Object?> items = {};

  final List<Object> _metadata;
  final List<Pipe<Object?, Object?>> _pipes;

  /// The HTTP view of the request.
  HttpContext switchToHttp() => switch (transport) {
    HttpContext http => http,
  };

  /// The first metadata value of type [T]: route metadata overrides
  /// controller metadata. `null` when neither declares one.
  T? metadata<T extends Object>() {
    for (final value in _metadata) {
      if (value is T) return value;
    }
    return null;
  }

  /// The first value of request header [name] (case-insensitive).
  String? header(String name) => switchToHttp().request.headers[name];

  /// The raw request body, read once and cached.
  RequestBody get body => switchToHttp().request.body;

  /// Path parameter [name] as [T], after the configured [pipes] and the
  /// call's own [pipes]. A name the route does not declare throws
  /// [UnknownRouteParameterError]; an unparsable value throws
  /// [BadRequestException].
  Future<T> param<T>(
    String name, {
    List<Pipe<Object?, Object?>> pipes = const [],
  }) async {
    final parameters = switchToHttp().pathParameters;
    final raw = parameters[name];
    if (raw == null) {
      throw UnknownRouteParameterError(
        name: name,
        handlerName: handlerName,
        declared: parameters.keys.toList(),
      );
    }
    return ArgumentResolver.resolve<T>(
      raw,
      ArgumentMeta(source: ArgumentSource.path, name: name, type: T),
      [..._pipes, ...pipes],
    );
  }

  /// Query parameter [name] (its first value) as [T]. An absent parameter
  /// is `null` for a nullable [T] and a [BadRequestException] otherwise.
  Future<T> query<T>(
    String name, {
    List<Pipe<Object?, Object?>> pipes = const [],
  }) {
    final values = switchToHttp().request.uri.queryParametersAll[name];
    return ArgumentResolver.resolve<T>(
      values == null || values.isEmpty ? null : values.first,
      ArgumentMeta(source: ArgumentSource.query, name: name, type: T),
      [..._pipes, ...pipes],
    );
  }

  /// The JSON body decoded with [fromJson], after the pipes ran on the
  /// decoded JSON. A body that is not a JSON object, malformed JSON, or a
  /// [FormatException] thrown by [fromJson] is a [BadRequestException].
  Future<T> bodyAs<T>(
    T Function(Map<String, Object?> json) fromJson, {
    List<Pipe<Object?, Object?>> pipes = const [],
  }) async {
    final meta = ArgumentMeta(
      source: ArgumentSource.body,
      name: 'body',
      type: T,
    );
    final value = await ArgumentResolver.pipe(await body.json(), meta, [
      ..._pipes,
      ...pipes,
    ]);
    if (value is T) return value;
    if (value is! Map<String, Object?>) {
      throw const BadRequestException(
        message: 'Request body must be a JSON object.',
      );
    }
    try {
      return fromJson(value);
    } on FormatException catch (error) {
      throw BadRequestException(
        message: 'Invalid request body: ${error.message}',
      );
    }
  }
}
````

- [ ] **Step 4: Export the public types**

Add to `packages/dartnest/lib/dartnest.dart`, keeping all `export` lines sorted:

```dart
export 'src/pipeline/enum_pipe.dart';
export 'src/pipeline/pipeline_error.dart';
```

- [ ] **Step 5: Run the tests to verify they pass**

Run from `packages/dartnest`: `dart test test/pipeline/argument_binding_test.dart`
Expected: `+14: All tests passed!`

Run from `packages/dartnest`: `dart test`
Expected: `+139: All tests passed!`

- [ ] **Step 6: Analyze, format and commit**

Run from repo root: `dart analyze && dart format --output=none --set-exit-if-changed packages`
Expected: `No issues found!` and `Formatted N files (0 changed)`.

```bash
git add \
  packages/dartnest/lib/src/pipeline/pipeline_error.dart \
  packages/dartnest/lib/src/pipeline/value_converter.dart \
  packages/dartnest/lib/src/pipeline/argument_resolver.dart \
  packages/dartnest/lib/src/pipeline/enum_pipe.dart \
  packages/dartnest/lib/src/pipeline/execution_context.dart \
  packages/dartnest/test/pipeline/argument_binding_test.dart \
  packages/dartnest/lib/dartnest.dart
git commit -m "feat(pipeline): bind path, query and body arguments through pipes"
```

---

### Task 7: `HandlerSpec`, `Route`, `Controller` і `Module.controllers`

Опис хендлерів і контролерів як значень. `HandlerSpec` — спільна база для `Route` (і для `Field` резолвера у v2). `Route<T>` має фабрики `get/post/put/patch/delete`; `name` за замовчуванням `'METHOD path'`. `Controller<T>` створює екземпляр через інжектор свого модуля; будь-який виняток фабрики, крім `DartnestError`, загортається в `ControllerCreationError` (нова sealed-родина `ApplicationError`; `InjectionError` не змінюється). `Module` отримує шостий іменований параметр `controllers` (відхилення від правила ≤ 5 параметрів, яке вимагає специфікація), а `ModuleGraph` порівнює форму модулів також за типами контролерів. У цій же задачі оновлюється `CLAUDE.md`: перелік меж, де дозволено `on Object`, бо їх додають Task 7–11.

**Files:**
- Create: `packages/dartnest/lib/src/pipeline/handler_spec.dart`
- Create: `packages/dartnest/lib/src/controller/route.dart`
- Create: `packages/dartnest/lib/src/controller/controller.dart`
- Create: `packages/dartnest/lib/src/app/application_error.dart`
- Modify: `packages/dartnest/lib/src/di/module.dart`
- Modify: `packages/dartnest/lib/src/di/module_graph.dart`
- Modify: `packages/dartnest/lib/dartnest.dart`
- Modify: `CLAUDE.md`
- Test: `packages/dartnest/test/controller/controller_test.dart`

**Interfaces:**
- Consumes: `Enhancers`, `ExecutionContext` (Task 5); `Injector`, `Module`, `ModuleGraph`, `DartnestError` (DI).
- Produces:
  - `abstract base class HandlerSpec { HandlerSpec({required String name, Enhancers enhancers, List<Object> metadata}); FutureOr<Object?> invoke(Object target, ExecutionContext context); }`
  - `typedef RouteHandler<T> = FutureOr<Object?> Function(T controller, ExecutionContext context);` and `final class Route<T extends Object> extends HandlerSpec { Route.get/post/put/patch/delete(String path, RouteHandler<T> handler, {String? name, Enhancers enhancers, List<Object> metadata}); String method; String path; RouteHandler<T> handler; }`
  - `typedef ControllerFactory<T> = T Function(Injector injector);`, `sealed class ControllerSpec { String path; Type type; Enhancers enhancers; List<Object> metadata; List<Route<Object>> routes; Object instantiate(Injector injector); }` and `final class Controller<T extends Object> implements ControllerSpec { Controller({String path = '', required ControllerFactory<T> create, required List<Route<T>> routes, Enhancers enhancers, List<Object> metadata}); }`
  - `sealed class ApplicationError extends DartnestError` with `ControllerCreationError({required Type controllerType, required String moduleId, required Object error, required StackTrace stackTrace})`.
  - `Module({required String id, List<Module> imports, List<ProviderSpec> providers, List<ControllerSpec> controllers = const [], List<Object> exports, bool global})` and `final List<ControllerSpec> controllers`.

- [ ] **Step 1: Write the failing tests**

`packages/dartnest/test/controller/controller_test.dart`:

```dart
import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

import '../helpers/http_fixtures.dart';

final class Greeter {
  String greet(String name) => 'Hello, $name';
}

final class GreetController {
  GreetController(this.greeter);
  final Greeter greeter;

  String hello(String name) => greeter.greet(name);
}

final class Broken {
  Broken() {
    throw StateError('no config');
  }
}

final greetController = Controller<GreetController>(
  path: '/greet',
  create: (i) => GreetController(i.get()),
  metadata: const ['controller-level'],
  routes: [
    Route.get(
      '/:name',
      (c, ctx) async => c.hello(await ctx.param<String>('name')),
      name: 'hello',
    ),
    Route.post('/', (c, ctx) => 'posted'),
  ],
);

void main() {
  group('Route', () {
    test('factories set the method and default the name', () {
      final routes = <Route<GreetController>>[
        Route.get('/a', (c, ctx) => null),
        Route.post('/a', (c, ctx) => null),
        Route.put('/a', (c, ctx) => null),
        Route.patch('/a', (c, ctx) => null),
        Route.delete('/a', (c, ctx) => null, name: 'remove'),
      ];

      expect(routes.map((r) => r.method), [
        'GET',
        'POST',
        'PUT',
        'PATCH',
        'DELETE',
      ]);
      expect(routes.first.name, 'GET /a');
      expect(routes.last.name, 'remove');
      expect(routes.first.enhancers, same(Enhancers.none));
    });

    test('invoke calls the handler with the controller', () async {
      final controller = GreetController(Greeter());
      final context = contextFor(
        requestFor('GET', '/greet/ann'),
        pathParameters: {'name': 'ann'},
      );

      final result = await greetController.routes.first.invoke(
        controller,
        context,
      );

      expect(result, 'Hello, ann');
    });
  });

  group('Controller', () {
    test('instantiate uses the injector of the module', () async {
      final container = await Container.create(
        Module(id: 'app', providers: [Provider((i) => Greeter())]),
      );

      final instance = greetController.instantiate(container.root);

      expect(instance.greeter, same(container.root.get<Greeter>()));
      expect(greetController.type, GreetController);
      expect(greetController.path, '/greet');
      expect(greetController.metadata, ['controller-level']);
    });

    test('a throwing factory is wrapped with controller and module', () async {
      final container = await Container.create(Module(id: 'app'));
      final broken = Controller<Broken>(create: (i) => Broken(), routes: []);

      expect(
        () => broken.instantiate(container.root),
        throwsA(
          isA<ControllerCreationError>()
              .having((e) => e.controllerType, 'type', Broken)
              .having((e) => e.moduleId, 'module', 'app')
              .having((e) => e.error, 'error', isA<StateError>())
              .having((e) => e.message, 'message', contains('no config')),
        ),
      );
    });

    test('DI errors from the factory pass through unchanged', () async {
      final container = await Container.create(Module(id: 'app'));

      expect(
        () => greetController.instantiate(container.root),
        throwsA(
          isA<MissingProviderError>().having((e) => e.key, 'key', Greeter),
        ),
      );
    });
  });

  group('Module.controllers', () {
    test('defaults to empty and keeps declaration order', () {
      final other = Controller<Greeter>(create: (i) => Greeter(), routes: []);
      final module = Module(id: 'm', controllers: [greetController, other]);

      expect(Module(id: 'x').controllers, isEmpty);
      expect(module.controllers.map((c) => c.type), [GreetController, Greeter]);
    });

    test('same id with different controllers is a duplicate module', () {
      final first = Module(id: 'shared', controllers: [greetController]);
      final second = Module(id: 'shared');

      expect(
        () => ModuleGraph.build(Module(id: 'app', imports: [first, second])),
        throwsA(isA<DuplicateModuleIdError>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run from `packages/dartnest`: `dart test test/controller/controller_test.dart`
Expected: FAIL at compile time, first error: `Error: Undefined name 'Route'.`

- [ ] **Step 3: Implement**

`packages/dartnest/lib/src/pipeline/handler_spec.dart`:

```dart
import 'dart:async';

import 'enhancers.dart';
import 'execution_context.dart';

/// What the pipeline needs to know about one handler, independent of the
/// transport: its name, its own pipeline components and metadata, and how
/// to invoke it.
///
/// HTTP `Route` extends it; GraphQL fields will too, so both share the
/// guards → interceptors → handler → filters pipeline.
abstract base class HandlerSpec {
  /// Creates the description.
  HandlerSpec({
    required this.name,
    this.enhancers = Enhancers.none,
    this.metadata = const [],
  });

  /// Handler name, reported as `ExecutionContext.handlerName`.
  final String name;

  /// Pipeline components of this handler (innermost level).
  final Enhancers enhancers;

  /// Metadata of this handler; overrides the controller's.
  final List<Object> metadata;

  /// Invokes the handler on [target] (the controller instance).
  FutureOr<Object?> invoke(Object target, ExecutionContext context);
}
```

`packages/dartnest/lib/src/controller/route.dart`:

````dart
import 'dart:async';

import '../pipeline/enhancers.dart';
import '../pipeline/execution_context.dart';
import '../pipeline/handler_spec.dart';

/// Handles a request with the controller instance and the request context.
/// The result is serialized into the response.
typedef RouteHandler<T> =
    FutureOr<Object?> Function(T controller, ExecutionContext context);

typedef _RouteOptions = ({
  String? name,
  Enhancers enhancers,
  List<Object> metadata,
});

/// An HTTP endpoint of a `Controller<T>`: method, path relative to the
/// controller path, and handler.
///
/// ```dart
/// Route.get('/:id', (c, ctx) async => c.findOne(await ctx.param<int>('id')),
///     name: 'findOne');
/// ```
///
/// [path] may contain `:name` parameters and a trailing `*`. [name] defaults
/// to `'GET /:id'`; the generator passes the method name.
final class Route<T extends Object> extends HandlerSpec {
  /// A `GET` route.
  Route.get(
    String path,
    RouteHandler<T> handler, {
    String? name,
    Enhancers enhancers = Enhancers.none,
    List<Object> metadata = const [],
  }) : this._('GET', path, handler, (
         name: name,
         enhancers: enhancers,
         metadata: metadata,
       ));

  /// A `POST` route.
  Route.post(
    String path,
    RouteHandler<T> handler, {
    String? name,
    Enhancers enhancers = Enhancers.none,
    List<Object> metadata = const [],
  }) : this._('POST', path, handler, (
         name: name,
         enhancers: enhancers,
         metadata: metadata,
       ));

  /// A `PUT` route.
  Route.put(
    String path,
    RouteHandler<T> handler, {
    String? name,
    Enhancers enhancers = Enhancers.none,
    List<Object> metadata = const [],
  }) : this._('PUT', path, handler, (
         name: name,
         enhancers: enhancers,
         metadata: metadata,
       ));

  /// A `PATCH` route.
  Route.patch(
    String path,
    RouteHandler<T> handler, {
    String? name,
    Enhancers enhancers = Enhancers.none,
    List<Object> metadata = const [],
  }) : this._('PATCH', path, handler, (
         name: name,
         enhancers: enhancers,
         metadata: metadata,
       ));

  /// A `DELETE` route.
  Route.delete(
    String path,
    RouteHandler<T> handler, {
    String? name,
    Enhancers enhancers = Enhancers.none,
    List<Object> metadata = const [],
  }) : this._('DELETE', path, handler, (
         name: name,
         enhancers: enhancers,
         metadata: metadata,
       ));

  Route._(this.method, this.path, this.handler, _RouteOptions options)
    : super(
        name: options.name ?? '$method $path',
        enhancers: options.enhancers,
        metadata: options.metadata,
      );

  /// Upper-cased HTTP method.
  final String method;

  /// Path relative to the controller path.
  final String path;

  /// The handler.
  final RouteHandler<T> handler;

  @override
  FutureOr<Object?> invoke(Object target, ExecutionContext context) =>
      handler(target as T, context);

  @override
  String toString() => 'Route($method $path)';
}
````

`packages/dartnest/lib/src/controller/controller.dart`:

````dart
import '../app/application_error.dart';
import '../di/errors.dart';
import '../di/injector.dart';
import '../pipeline/enhancers.dart';
import 'route.dart';

/// Creates a controller instance with the injector of its module.
typedef ControllerFactory<T> = T Function(Injector injector);

/// Non-generic view of a controller: what `Module.controllers` holds.
///
/// Non-generic for the same reason as `ProviderSpec`: a generic element type
/// would push `Object` into the inference of `Controller(...)` written in
/// the list literal.
sealed class ControllerSpec {
  /// Path prefix of every route.
  String get path;

  /// The controller class.
  Type get type;

  /// Controller-level pipeline components.
  Enhancers get enhancers;

  /// Controller-level metadata; route metadata overrides it.
  List<Object> get metadata;

  /// The routes, in declaration order.
  List<Route<Object>> get routes;

  /// Creates the instance; throws [ControllerCreationError] when the factory
  /// throws anything but a `DartnestError`.
  Object instantiate(Injector injector);
}

/// A controller: a class whose instance handles the requests of [routes].
///
/// The instance is created once at startup, after the providers of its
/// module, with that module's injector.
///
/// ```dart
/// final usersController = Controller<UsersController>(
///   path: '/users',
///   create: (i) => UsersController(i.get()),
///   enhancers: const Enhancers(guards: [Use<AuthGuard>()]),
///   routes: [
///     Route.get('/:id', (c, ctx) async => c.findOne(await ctx.param('id'))),
///   ],
/// );
/// ```
///
/// Write the type argument: `Controller<UsersController>(...)` lets the
/// route handlers infer `c`.
final class Controller<T extends Object> implements ControllerSpec {
  /// Creates a controller.
  Controller({
    this.path = '',
    required ControllerFactory<T> create,
    required this.routes,
    this.enhancers = Enhancers.none,
    this.metadata = const [],
  }) : _create = create;

  @override
  final String path;

  @override
  final List<Route<T>> routes;

  @override
  final Enhancers enhancers;

  @override
  final List<Object> metadata;

  final ControllerFactory<T> _create;

  @override
  Type get type => T;

  @override
  T instantiate(Injector injector) {
    // Factory boundary, like ModuleInjector: wrap any failure with the
    // controller and module, keep the cause and stack, never swallow.
    try {
      return _create(injector);
    } on Object catch (error, stackTrace) {
      if (error is DartnestError) rethrow;
      Error.throwWithStackTrace(
        ControllerCreationError(
          controllerType: T,
          moduleId: injector.moduleId,
          error: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }

  @override
  String toString() => 'Controller<$T>($path)';
}
````

`packages/dartnest/lib/src/app/application_error.dart`:

```dart
import '../di/errors.dart';

/// Errors raised while assembling or running an `Application`.
sealed class ApplicationError extends DartnestError {
  /// Creates an application error.
  const ApplicationError();
}

/// A controller factory threw.
final class ControllerCreationError extends ApplicationError {
  /// Creates the error.
  const ControllerCreationError({
    required this.controllerType,
    required this.moduleId,
    required this.error,
    required this.stackTrace,
  });

  /// The controller class.
  final Type controllerType;

  /// The module that declares the controller.
  final String moduleId;

  /// The original error.
  final Object error;

  /// The original stack trace.
  final StackTrace stackTrace;

  @override
  String get message =>
      'Factory of controller $controllerType in module "$moduleId" threw: '
      '$error';
}
```

Apply to `packages/dartnest/lib/src/di/module.dart`:

```diff
--- a/packages/dartnest/lib/src/di/module.dart
+++ b/packages/dartnest/lib/src/di/module.dart
@@ -1,3 +1,4 @@
+import '../controller/controller.dart';
 import 'provider.dart';
 import 'token.dart';
 
@@ -6,8 +7,9 @@
 ///
 /// A module is a value, not a class. Dynamic modules are therefore plain
 /// functions that return a [Module]. Two modules with the same [id] are
-/// treated as one: their shape (imports, provider keys, exports, [global])
-/// must match or `ModuleGraph.build` throws `DuplicateModuleIdError`.
+/// treated as one: their shape (imports, provider keys, controller types,
+/// exports, [global]) must match or `ModuleGraph.build` throws
+/// `DuplicateModuleIdError`.
 /// Configuration captured inside factories is not compared and the first-seen
 /// instance wins, so a dynamic module that can be configured differently in
 /// one application must encode it in its [id] (for example `'database:$name'`).
@@ -29,6 +31,7 @@
     required this.id,
     this.imports = const [],
     this.providers = const [],
+    this.controllers = const [],
     this.exports = const [],
     this.global = false,
   });
@@ -44,6 +47,10 @@
   /// provider that is declared before it (or in an imported module).
   final List<ProviderSpec> providers;
 
+  /// Controllers whose instances are created with this module's injector
+  /// after its providers, and whose routes the application serves.
+  final List<ControllerSpec> controllers;
+
   /// What importers of this module can see: a [Type] or [Token] of one of
   /// [providers], or a [Module] from [imports] (re-export).
   final List<Object> exports;
```

Apply to `packages/dartnest/lib/src/di/module_graph.dart`:

```diff
--- a/packages/dartnest/lib/src/di/module_graph.dart
+++ b/packages/dartnest/lib/src/di/module_graph.dart
@@ -8,8 +8,8 @@
 /// provider instances: duplicate ids with different shape, import cycles,
 /// duplicate provider keys, invalid exports, keys exported to one module by
 /// several modules. Modules with equal ids are
-/// compared by shape only (id, `global`, import ids, provider keys and export
-/// keys); the first-seen instance wins.
+/// compared by shape only (id, `global`, import ids, provider keys,
+/// controller types and export keys); the first-seen instance wins.
 final class ModuleGraph {
   ModuleGraph._(this.root, this.ordered, this._byId);
 
@@ -161,8 +161,8 @@
     }
   }
 
-  /// Structural equality (id, `global`, import ids, provider keys and export
-  /// keys; not factory configuration) used
+  /// Structural equality (id, `global`, import ids, provider keys, controller
+  /// types and export keys; not factory configuration) used
   /// to accept the same dynamic module imported from several places.
   static bool _sameShape(Module a, Module b) {
     if (a.id != b.id || a.global != b.global) return false;
@@ -175,6 +175,12 @@
     )) {
       return false;
     }
+    if (!_sameList(
+      a.controllers.map((c) => c.type),
+      b.controllers.map((c) => c.type),
+    )) {
+      return false;
+    }
     Object exportKey(Object e) => e is Module ? 'module:${e.id}' : e;
     return _sameList(a.exports.map(exportKey), b.exports.map(exportKey));
   }
```

`CLAUDE.md` (section «Dart style»): replace the paragraph tail

```markdown
returns. No `catch` without `on`; never catch `Error`; the one exception is the
provider-factory boundary in `ModuleInjector`, which catches `on Object` to
wrap every factory failure in `ProviderCreationError` with its cause, chain
and original stack trace, and never swallows it; `rethrow` keeps the
stack trace. Never silence a lint: no `// ignore:` without a comment on why,
and no rule removed from `analysis_options.yaml` to make a change pass.
```

with

```markdown
returns. No `catch` without `on`; never catch `Error`. The exceptions are
the boundaries where user code runs; each catches `on Object`, has a comment
naming the boundary, and never swallows the failure:
- factory boundaries: `ModuleInjector` (provider factories) and
  `Controller.instantiate` wrap the failure in `ProviderCreationError` /
  `ControllerCreationError` with its cause and original stack trace;
- request boundaries: `Pipeline.run` hands the failure to the exception
  filters and rethrows it when none handles it; `RequestDispatcher.dispatch`
  and `Application.handle` turn it into a 500 through `HttpErrorResponder`,
  which logs it;
- `ResponseSerializer` catches `JsonUnsupportedObjectError` (an `Error` the
  JSON encoder throws for a user value) and throws `SerializationError` with
  the original stack trace.
`rethrow` keeps the stack trace. Never silence a lint: no `// ignore:`
without a comment on why, and no rule removed from `analysis_options.yaml`
to make a change pass.
```

- [ ] **Step 4: Export the public types**

Add to `packages/dartnest/lib/dartnest.dart`, keeping all `export` lines sorted:

```dart
export 'src/app/application_error.dart';
export 'src/controller/controller.dart';
export 'src/controller/route.dart';
export 'src/pipeline/handler_spec.dart';
```

- [ ] **Step 5: Run the tests to verify they pass**

Run from `packages/dartnest`: `dart test test/controller/controller_test.dart`
Expected: `+7: All tests passed!`

Run from `packages/dartnest`: `dart test`
Expected: `+146: All tests passed!`

- [ ] **Step 6: Analyze, format and commit**

Run from repo root: `dart analyze && dart format --output=none --set-exit-if-changed packages`
Expected: `No issues found!` and `Formatted N files (0 changed)`.

```bash
git add \
  packages/dartnest/lib/src/pipeline/handler_spec.dart \
  packages/dartnest/lib/src/controller/route.dart \
  packages/dartnest/lib/src/controller/controller.dart \
  packages/dartnest/lib/src/app/application_error.dart \
  packages/dartnest/lib/src/di/module.dart \
  packages/dartnest/lib/src/di/module_graph.dart \
  packages/dartnest/test/controller/controller_test.dart \
  packages/dartnest/lib/dartnest.dart \
  CLAUDE.md
git commit -m "feat(controller): add Controller, Route and Module.controllers"
```

---

### Task 8: Виконання конвеєра: guards → interceptors → handler → filters

Виконання одного ендпоінта. `ResolvedEnhancers.resolve` перетворює `Enhancers` на типізовані списки (резолвить `Use<T>` інжектором модуля; компонент не того виду — `InvalidComponentError` на старті), `chain` склеює рівні app → controller → route (фільтри — у зворотному порядку: route → controller → app). `Pipeline.run`: guards по черзі (перший `false` → `ForbiddenException('Forbidden resource')`), interceptors цибулею, хендлер, `finish` (серіалізація). Будь-який виняток іде у фільтри; результат фільтра теж проходить через `finish`; якщо фільтр кидає, новий виняток бачать лише наступні фільтри; необроблений виняток перекидається з оригінальним стеком.

**Files:**
- Create: `packages/dartnest/lib/src/pipeline/resolved_enhancers.dart`
- Create: `packages/dartnest/lib/src/pipeline/endpoint.dart`
- Create: `packages/dartnest/lib/src/pipeline/pipeline.dart`
- Modify: `packages/dartnest/lib/src/app/application_error.dart`
- Create: `packages/dartnest/test/helpers/pipeline_fixtures.dart`
- Test: `packages/dartnest/test/pipeline/resolved_enhancers_test.dart`
- Test: `packages/dartnest/test/pipeline/pipeline_test.dart`

**Interfaces:**
- Consumes: `Enhancers`, `Use`, `Guard`, `Interceptor`, `Pipe`, `ExceptionFilter`, `ExecutionContext` (Task 5–6); `ForbiddenException` (Task 1); `ApplicationError` (Task 7).
- Produces:
  - `InvalidComponentError({required String owner, required String slot, required Type actualType, required Type expectedType})` in the `ApplicationError` family.
  - `final class ResolvedEnhancers { const ResolvedEnhancers({guards, interceptors, pipes, filters}); static ResolvedEnhancers resolve(Enhancers enhancers, Injector injector, {required String owner}); static ResolvedEnhancers chain(List<ResolvedEnhancers> outerToInner); }`; internal.
  - `final class Endpoint { const Endpoint({required Type controllerType, required String handlerName, required List<Object> metadata, required ResolvedEnhancers enhancers, required FutureOr<Object?> Function(ExecutionContext) invoke}); }`; internal.
  - `abstract final class Pipeline { static Future<R> run<R>(Endpoint endpoint, ExecutionContext context, FutureOr<R> Function(Object? result) finish); }`; internal.
  - Test helpers `LogGuard`, `LogInterceptor`, `LogFilter`, `endpointWith(List<String> log, {ResolvedEnhancers enhancers, FutureOr<Object?> Function()? handler})`, `plainContext()` in `test/helpers/pipeline_fixtures.dart`.

- [ ] **Step 1: Write the failing tests**

`packages/dartnest/test/helpers/pipeline_fixtures.dart`:

```dart
// Recording pipeline components for ordering tests.
import 'dart:async';

import 'package:dartnest/dartnest.dart';
import 'package:dartnest/src/pipeline/endpoint.dart';
import 'package:dartnest/src/pipeline/resolved_enhancers.dart';

import 'http_fixtures.dart';

/// A guard that logs its [name] and answers [allow].
final class LogGuard implements Guard {
  LogGuard(this.log, this.name, {this.allow = true});
  final List<String> log;
  final String name;
  final bool allow;

  @override
  bool canActivate(ExecutionContext context) {
    log.add('guard $name');
    return allow;
  }
}

/// An interceptor that logs before and after the inner chain.
final class LogInterceptor implements Interceptor {
  LogInterceptor(this.log, this.name);
  final List<String> log;
  final String name;

  @override
  Future<Object?> intercept(
    ExecutionContext context,
    Next<Object?> next,
  ) async {
    log.add('before $name');
    final result = await next();
    log.add('after $name');
    return result;
  }
}

/// A filter for [E] that logs and answers `'<name> handled <error>'`.
final class LogFilter<E extends Object> extends ExceptionFilter<E> {
  LogFilter(this.log, this.name, {this.rethrowAs});
  final List<String> log;
  final String name;
  final Object? rethrowAs;

  @override
  Object? handle(E error, ExecutionContext context) {
    log.add('filter $name');
    final replacement = rethrowAs;
    if (replacement != null) throw replacement;
    return '$name handled $error';
  }
}

/// An endpoint whose handler logs `handler` and returns [handler]'s result.
Endpoint endpointWith(
  List<String> log, {
  ResolvedEnhancers enhancers = const ResolvedEnhancers(),
  FutureOr<Object?> Function()? handler,
}) => Endpoint(
  controllerType: Object,
  handlerName: 'test',
  metadata: const [],
  enhancers: enhancers,
  invoke: (context) {
    log.add('handler');
    return handler == null ? 'result' : handler();
  },
);

/// A context for `GET /`.
ExecutionContext plainContext() => contextFor(requestFor('GET', '/'));
```

`packages/dartnest/test/pipeline/resolved_enhancers_test.dart`:

```dart
import 'package:dartnest/dartnest.dart';
import 'package:dartnest/src/pipeline/resolved_enhancers.dart';
import 'package:test/test.dart';

final class AuthGuard implements Guard {
  @override
  bool canActivate(ExecutionContext context) => true;
}

final class Timing implements Interceptor {
  @override
  Object? intercept(ExecutionContext context, Next<Object?> next) => next();
}

final class TrimPipe implements Pipe<Object?, Object?> {
  const TrimPipe();

  @override
  Object? transform(Object? value, ArgumentMeta meta) =>
      value is String ? value.trim() : value;
}

final class AnyFilter extends ExceptionFilter<Object> {
  const AnyFilter(this.name);
  final String name;

  @override
  Object? handle(Object error, ExecutionContext context) => name;
}

void main() {
  group('ResolvedEnhancers.resolve', () {
    test('resolves Use through the injector and keeps instances', () async {
      final container = await Container.create(
        Module(id: 'app', providers: [Provider((i) => AuthGuard())]),
      );
      final timing = Timing();

      final resolved = ResolvedEnhancers.resolve(
        Enhancers(
          guards: const [Use<AuthGuard>()],
          interceptors: [timing],
          pipes: const [TrimPipe()],
          filters: const [AnyFilter('a')],
        ),
        container.root,
        owner: 'Application',
      );

      expect(resolved.guards.single, same(container.root.get<AuthGuard>()));
      expect(resolved.interceptors.single, same(timing));
      expect(resolved.pipes.single, isA<TrimPipe>());
      expect(resolved.filters.single, isA<AnyFilter>());
    });

    test('a component of the wrong kind fails with its location', () async {
      final container = await Container.create(Module(id: 'app'));

      expect(
        () => ResolvedEnhancers.resolve(
          Enhancers(guards: [Timing()]),
          container.root,
          owner: 'UsersController',
        ),
        throwsA(
          isA<InvalidComponentError>()
              .having((e) => e.owner, 'owner', 'UsersController')
              .having((e) => e.slot, 'slot', 'guards')
              .having((e) => e.actualType, 'actual', Timing)
              .having((e) => e.expectedType, 'expected', Guard)
              .having(
                (e) => e.message,
                'message',
                'UsersController lists Timing in guards, but it is not a Guard.',
              ),
        ),
      );
    });

    test('Use of a missing provider fails with MissingProviderError', () async {
      final container = await Container.create(Module(id: 'users'));

      expect(
        () => ResolvedEnhancers.resolve(
          const Enhancers(guards: [Use<AuthGuard>()]),
          container.root,
          owner: 'UsersController',
        ),
        throwsA(
          isA<MissingProviderError>()
              .having((e) => e.key, 'key', AuthGuard)
              .having((e) => e.moduleId, 'module', 'users'),
        ),
      );
    });
  });

  group('ResolvedEnhancers.chain', () {
    test('outer to inner, filters reversed', () {
      final app = ResolvedEnhancers(
        pipes: const [TrimPipe()],
        filters: const [AnyFilter('app')],
      );
      final controller = ResolvedEnhancers(
        filters: const [AnyFilter('controller')],
      );
      final route = ResolvedEnhancers(
        pipes: const [TrimPipe()],
        filters: const [AnyFilter('route')],
      );

      final chained = ResolvedEnhancers.chain([app, controller, route]);

      expect(chained.pipes, hasLength(2));
      expect(chained.filters.map((f) => (f as AnyFilter).name), [
        'route',
        'controller',
        'app',
      ]);
    });
  });
}
```

`packages/dartnest/test/pipeline/pipeline_test.dart`:

```dart
import 'package:dartnest/dartnest.dart';
import 'package:dartnest/src/pipeline/pipeline.dart';
import 'package:dartnest/src/pipeline/resolved_enhancers.dart';
import 'package:test/test.dart';

import '../helpers/pipeline_fixtures.dart';

Object? identity(Object? result) => result;

void main() {
  group('Pipeline.run', () {
    test('guards, interceptors, handler, finish in order', () async {
      final log = <String>[];
      final endpoint = endpointWith(
        log,
        enhancers: ResolvedEnhancers(
          guards: [LogGuard(log, 'app'), LogGuard(log, 'route')],
          interceptors: [
            LogInterceptor(log, 'outer'),
            LogInterceptor(log, 'inner'),
          ],
        ),
      );

      final result = await Pipeline.run(endpoint, plainContext(), (r) {
        log.add('finish');
        return r;
      });

      expect(result, 'result');
      expect(log, [
        'guard app',
        'guard route',
        'before outer',
        'before inner',
        'handler',
        'after inner',
        'after outer',
        'finish',
      ]);
    });

    test('a false guard stops the chain with 403', () async {
      final log = <String>[];
      final endpoint = endpointWith(
        log,
        enhancers: ResolvedEnhancers(
          guards: [LogGuard(log, 'a', allow: false), LogGuard(log, 'b')],
        ),
      );

      await expectLater(
        Pipeline.run(endpoint, plainContext(), identity),
        throwsA(isA<ForbiddenException>()),
      );
      expect(log, ['guard a']);
    });

    test('an interceptor can answer without the handler', () async {
      final log = <String>[];
      final endpoint = endpointWith(
        log,
        enhancers: ResolvedEnhancers(interceptors: [_ShortCircuit()]),
      );

      expect(await Pipeline.run(endpoint, plainContext(), identity), 'cached');
      expect(log, isEmpty);
    });

    test('an interceptor can replace the result', () async {
      final endpoint = endpointWith(
        [],
        enhancers: ResolvedEnhancers(interceptors: [_Wrap()]),
      );

      expect(await Pipeline.run(endpoint, plainContext(), identity), {
        'data': 'result',
      });
    });
  });

  group('Pipeline.run exception filters', () {
    test('first matching filter handles, result goes through finish', () async {
      final log = <String>[];
      final endpoint = endpointWith(
        log,
        handler: () => throw StateError('boom'),
        enhancers: ResolvedEnhancers(
          filters: [
            LogFilter<ArgumentError>(log, 'args'),
            LogFilter<StateError>(log, 'state'),
            LogFilter<Object>(log, 'any'),
          ],
        ),
      );

      final result = await Pipeline.run(
        endpoint,
        plainContext(),
        (r) => 'finished: $r',
      );

      expect(result, 'finished: state handled Bad state: boom');
      expect(log, ['handler', 'filter state']);
    });

    test('a throwing filter passes the new error to later filters', () async {
      final log = <String>[];
      final endpoint = endpointWith(
        log,
        handler: () => throw StateError('db down'),
        enhancers: ResolvedEnhancers(
          filters: [
            LogFilter<StateError>(
              log,
              'map',
              rethrowAs: const NotFoundException(),
            ),
            LogFilter<StateError>(log, 'unreached'),
            LogFilter<HttpException>(log, 'http'),
          ],
        ),
      );

      final result = await Pipeline.run(endpoint, plainContext(), identity);

      expect(result, startsWith('http handled NotFoundException(404)'));
      expect(log, ['handler', 'filter map', 'filter http']);
    });

    test('guard and finish errors reach the filters too', () async {
      final log = <String>[];
      final endpoint = endpointWith(
        log,
        enhancers: ResolvedEnhancers(
          guards: [LogGuard(log, 'deny', allow: false)],
          filters: [LogFilter<ForbiddenException>(log, 'forbidden')],
        ),
      );

      expect(
        await Pipeline.run(endpoint, plainContext(), identity),
        startsWith('forbidden handled'),
      );

      final failingFinish = endpointWith(
        log,
        enhancers: ResolvedEnhancers(
          filters: [LogFilter<FormatException>(log, 'fmt')],
        ),
      );
      expect(
        await Pipeline.run(failingFinish, plainContext(), (r) {
          if (r == 'result') throw const FormatException('bad');
          return r;
        }),
        startsWith('fmt handled'),
      );
    });

    test('an unhandled error is rethrown with its stack trace', () async {
      final endpoint = endpointWith([], handler: _throwDeep);

      await expectLater(
        Pipeline.run(endpoint, plainContext(), identity),
        throwsA(isA<FormatException>()),
      );
      try {
        await Pipeline.run(endpoint, plainContext(), identity);
      } on FormatException catch (_, stackTrace) {
        expect(stackTrace.toString(), contains('_throwDeep'));
      }
    });
  });
}

Never _throwDeep() => throw const FormatException('deep');

final class _ShortCircuit implements Interceptor {
  @override
  Object? intercept(ExecutionContext context, Next<Object?> next) => 'cached';
}

final class _Wrap implements Interceptor {
  @override
  Future<Object?> intercept(
    ExecutionContext context,
    Next<Object?> next,
  ) async => {'data': await next()};
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run from `packages/dartnest`: `dart test test/pipeline/resolved_enhancers_test.dart test/pipeline/pipeline_test.dart`
Expected: FAIL at compile time, first error: `Error: Error when reading 'lib/src/pipeline/resolved_enhancers.dart': No such file or directory`

- [ ] **Step 3: Implement**

`packages/dartnest/lib/src/pipeline/resolved_enhancers.dart`:

```dart
import '../app/application_error.dart';
import '../di/injector.dart';
import 'enhancers.dart';
import 'exception_filter.dart';
import 'guard.dart';
import 'interceptor.dart';
import 'pipe.dart';
import 'pipeline_component.dart';
import 'use.dart';

/// [Enhancers] with every `Use` resolved and every entry type-checked.
final class ResolvedEnhancers {
  /// Creates the lists.
  const ResolvedEnhancers({
    this.guards = const [],
    this.interceptors = const [],
    this.pipes = const [],
    this.filters = const [],
  });

  /// Guards in execution order.
  final List<Guard> guards;

  /// Interceptors, outermost first.
  final List<Interceptor> interceptors;

  /// Pipes in execution order.
  final List<Pipe<Object?, Object?>> pipes;

  /// Exception filters in the order they are tried.
  final List<ExceptionFilter<Object>> filters;

  /// Resolves [enhancers] through [injector]; [owner] names the declaring
  /// application, controller or route in [InvalidComponentError].
  static ResolvedEnhancers resolve(
    Enhancers enhancers,
    Injector injector, {
    required String owner,
  }) {
    List<C> all<C extends PipelineComponent>(
      List<PipelineComponent> components,
      String slot,
    ) => [
      for (final component in components)
        _resolveOne<C>(component, injector, owner: owner, slot: slot),
    ];
    return ResolvedEnhancers(
      guards: all<Guard>(enhancers.guards, 'guards'),
      interceptors: all<Interceptor>(enhancers.interceptors, 'interceptors'),
      pipes: all<Pipe<Object?, Object?>>(enhancers.pipes, 'pipes'),
      filters: all<ExceptionFilter<Object>>(enhancers.filters, 'filters'),
    );
  }

  /// Combines levels given outermost first (application, controller,
  /// route): guards, interceptors and pipes keep that order; filters are
  /// reversed so the innermost level is tried first.
  static ResolvedEnhancers chain(List<ResolvedEnhancers> outerToInner) =>
      ResolvedEnhancers(
        guards: [for (final level in outerToInner) ...level.guards],
        interceptors: [for (final level in outerToInner) ...level.interceptors],
        pipes: [for (final level in outerToInner) ...level.pipes],
        filters: [for (final level in outerToInner.reversed) ...level.filters],
      );

  static C _resolveOne<C extends PipelineComponent>(
    PipelineComponent component,
    Injector injector, {
    required String owner,
    required String slot,
  }) {
    final resolved = switch (component) {
      Use() => component.resolve(injector),
      _ => component,
    };
    if (resolved is C) return resolved;
    throw InvalidComponentError(
      owner: owner,
      slot: slot,
      actualType: resolved.runtimeType,
      expectedType: C,
    );
  }
}
```

`packages/dartnest/lib/src/pipeline/endpoint.dart`:

```dart
import 'dart:async';

import 'execution_context.dart';
import 'resolved_enhancers.dart';

/// A handler ready to run: bound to its controller instance, with the
/// application, controller and route components resolved and combined.
final class Endpoint {
  /// Creates the endpoint.
  const Endpoint({
    required this.controllerType,
    required this.handlerName,
    required this.metadata,
    required this.enhancers,
    required this.invoke,
  });

  /// The controller class.
  final Type controllerType;

  /// The handler name.
  final String handlerName;

  /// Route metadata followed by controller metadata.
  final List<Object> metadata;

  /// The combined pipeline components.
  final ResolvedEnhancers enhancers;

  /// Calls the handler on the bound controller instance.
  final FutureOr<Object?> Function(ExecutionContext context) invoke;
}
```

`packages/dartnest/lib/src/pipeline/pipeline.dart`:

```dart
import 'dart:async';

import '../http/http_exception.dart';
import 'endpoint.dart';
import 'exception_filter.dart';
import 'execution_context.dart';

/// Runs one request through guards → interceptors → handler → finish, and
/// sends any error to the exception filters. Transport-neutral: the
/// transport passes [run] a `finish` step that turns a result into its
/// response (HTTP serialization).
abstract final class Pipeline {
  /// Runs [endpoint] for [context].
  ///
  /// 1. Guards in order; the first `false` throws [ForbiddenException].
  /// 2. Interceptors as an onion around the handler.
  /// 3. `finish` on the result.
  ///
  /// An error from any step goes to the first filter that catches it; its
  /// result goes through `finish`. If a filter throws, the new error goes to
  /// the filters after it. An error no filter handles is rethrown with its
  /// original stack trace for the transport's default filter.
  static Future<R> run<R>(
    Endpoint endpoint,
    ExecutionContext context,
    FutureOr<R> Function(Object? result) finish,
  ) async {
    // Request boundary: every failure of user code, Errors included, must
    // reach the exception filters; nothing is swallowed (see CLAUDE.md).
    try {
      for (final guard in endpoint.enhancers.guards) {
        if (!await guard.canActivate(context)) {
          throw const ForbiddenException(message: 'Forbidden resource');
        }
      }
      return await finish(await _intercept(endpoint, context, 0));
    } on Object catch (error, stackTrace) {
      return _filter(endpoint.enhancers.filters, context, finish, (
        error,
        stackTrace,
      ));
    }
  }

  static Future<Object?> _intercept(
    Endpoint endpoint,
    ExecutionContext context,
    int index,
  ) async {
    final interceptors = endpoint.enhancers.interceptors;
    if (index == interceptors.length) return endpoint.invoke(context);
    return interceptors[index].intercept(
      context,
      () => _intercept(endpoint, context, index + 1),
    );
  }

  static Future<R> _filter<R>(
    List<ExceptionFilter<Object>> filters,
    ExecutionContext context,
    FutureOr<R> Function(Object? result) finish,
    (Object, StackTrace) failure,
  ) async {
    var (error, stackTrace) = failure;
    for (final filter in filters) {
      if (!filter.catches(error)) continue;
      try {
        return await finish(await filter.handle(error, context));
      } on Object catch (next, nextStackTrace) {
        (error, stackTrace) = (next, nextStackTrace);
      }
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
}
```

Append to the end of `packages/dartnest/lib/src/app/application_error.dart` (after one blank line):

```dart
/// An `Enhancers` list holds a component of the wrong kind, for example an
/// interceptor among the guards.
final class InvalidComponentError extends ApplicationError {
  /// Creates the error.
  const InvalidComponentError({
    required this.owner,
    required this.slot,
    required this.actualType,
    required this.expectedType,
  });

  /// Where the list is declared: `Application`, a controller type, or
  /// `Controller.handler`.
  final String owner;

  /// The list: `guards`, `interceptors`, `pipes` or `filters`.
  final String slot;

  /// Runtime type of the (resolved) component.
  final Type actualType;

  /// The kind the list requires.
  final Type expectedType;

  @override
  String get message =>
      '$owner lists $actualType in $slot, but it is not a $expectedType.';
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run from `packages/dartnest`: `dart test test/pipeline/resolved_enhancers_test.dart test/pipeline/pipeline_test.dart`
Expected: `+12: All tests passed!`

Run from `packages/dartnest`: `dart test`
Expected: `+158: All tests passed!`

- [ ] **Step 5: Analyze, format and commit**

Run from repo root: `dart analyze && dart format --output=none --set-exit-if-changed packages`
Expected: `No issues found!` and `Formatted N files (0 changed)`.

```bash
git add \
  packages/dartnest/lib/src/pipeline/resolved_enhancers.dart \
  packages/dartnest/lib/src/pipeline/endpoint.dart \
  packages/dartnest/lib/src/pipeline/pipeline.dart \
  packages/dartnest/lib/src/app/application_error.dart \
  packages/dartnest/test/helpers/pipeline_fixtures.dart \
  packages/dartnest/test/pipeline/resolved_enhancers_test.dart \
  packages/dartnest/test/pipeline/pipeline_test.dart
git commit -m "feat(pipeline): run guards, interceptors, handler and exception filters"
```

---

### Task 9: Серіалізація відповідей і HTTP-помилки

Перетворення результату хендлера на `HttpResponse` і помилки на JSON. Мапінг: `HttpResponse` — як є (з доданими заголовками з `ResponseHead`); `null` → 204; `String` → `text/plain`; `Uint8List` і `Stream<List<int>>` → `application/octet-stream`; усе інше (включно з `List<int>`) → JSON через `toJson()` або `app.serializers.register<T>`. Статус і заголовки з `ResponseHead` перекривають типові. `JsonUnsupportedObjectError` кодувальника стає `SerializationError` (500 з підказкою). `HttpErrorResponder` — типовий фільтр: тіло `{statusCode, error, message, details?}`; не-`HttpException` → 500 «Internal server error», логується, а з `debug: true` у тілі є повідомлення й стек; кодування не може кинути (`toEncodable`).

**Files:**
- Create: `packages/dartnest/lib/src/pipeline/serializer_registry.dart`
- Create: `packages/dartnest/lib/src/pipeline/response_serializer.dart`
- Create: `packages/dartnest/lib/src/pipeline/http_error_responder.dart`
- Modify: `packages/dartnest/lib/src/pipeline/pipeline_error.dart`
- Modify: `packages/dartnest/lib/dartnest.dart`
- Test: `packages/dartnest/test/pipeline/response_serializer_test.dart`
- Test: `packages/dartnest/test/pipeline/http_error_responder_test.dart`

**Interfaces:**
- Consumes: `HttpResponse`, `ResponseHead`, `HttpException`, `StatusCode` (Task 1–2); `PipelineError` (Task 6).
- Produces:
  - `SerializationError({required Type valueType, Object? cause})` in the `PipelineError` family.
  - `final class SerializerRegistry { void register<T extends Object>(Object? Function(T value) toJson); Object? prepare(Object? value); }`
  - `final class ResponseSerializer { const ResponseSerializer(SerializerRegistry registry); HttpResponse serialize(Object? result, ResponseHead head); }`; internal.
  - `typedef ErrorLogger = void Function(Object error, StackTrace stackTrace);` and `final class HttpErrorResponder { const HttpErrorResponder({required bool debug, required ErrorLogger log}); HttpResponse respond(Object error, StackTrace stackTrace); static void printError(Object, StackTrace); }`; only `ErrorLogger` is exported.

- [ ] **Step 1: Write the failing tests**

`packages/dartnest/test/pipeline/response_serializer_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartnest/dartnest.dart';
import 'package:dartnest/src/pipeline/response_serializer.dart';
import 'package:test/test.dart';

final class User {
  User(this.name);
  final String name;
  Map<String, Object?> toJson() => {'name': name};
}

final class Money {
  Money(this.cents);
  final int cents;
}

final class Opaque {}

Future<String> text(HttpResponse response) async =>
    utf8.decode(await response.body.readAll());

HttpResponse serialize(
  Object? result, {
  ResponseHead? head,
  SerializerRegistry? registry,
}) => ResponseSerializer(
  registry ?? SerializerRegistry(),
).serialize(result, head ?? ResponseHead());

void main() {
  group('ResponseSerializer', () {
    test('null is 204 without a body', () async {
      final response = serialize(null);

      expect(response.status, 204);
      expect(response.headers['content-type'], isNull);
      expect(await response.body.readAll(), isEmpty);
    });

    test('String is text/plain', () async {
      final response = serialize('hi');

      expect(response.status, 200);
      expect(response.headers['content-type'], 'text/plain; charset=utf-8');
      expect(await text(response), 'hi');
    });

    test('Uint8List and byte streams are octet-stream', () async {
      final bytes = serialize(Uint8List.fromList([1, 2]));
      final streamed = serialize(Stream.value(const [3, 4]));

      expect(bytes.headers['content-type'], 'application/octet-stream');
      expect(await bytes.body.readAll(), [1, 2]);
      expect(streamed.body, isA<StreamBody>());
      expect(await streamed.body.readAll(), [3, 4]);
    });

    test('maps, lists, scalars and toJson objects are JSON', () async {
      final response = serialize({
        'users': [User('ann')],
        'n': 1,
        'ok': true,
      });

      expect(
        response.headers['content-type'],
        'application/json; charset=utf-8',
      );
      expect(
        await text(response),
        '{"users":[{"name":"ann"}],"n":1,"ok":true}',
      );
      expect(await text(serialize(42)), '42');
    });

    // Review Focus 1: a list of ints is data, not bytes.
    test('List<int> is a JSON array, not a byte body', () async {
      final response = serialize(<int>[1, 2, 3]);

      expect(
        response.headers['content-type'],
        'application/json; charset=utf-8',
      );
      expect(await text(response), '[1,2,3]');
    });

    test('HttpResponse passes through and keeps its own headers', () {
      final head = ResponseHead()
        ..status = 201
        ..headers.set('x-trace', '7')
        ..headers.set('content-type', 'text/html');
      final original = HttpResponse.text('x', status: 202);

      final response = serialize(original, head: head);

      expect(response.status, 202);
      expect(response.headers['x-trace'], '7');
      expect(response.headers['content-type'], 'text/plain; charset=utf-8');
    });

    test('head status and headers override the defaults', () {
      final head = ResponseHead()
        ..status = 201
        ..headers.set('content-type', 'text/html; charset=utf-8')
        ..headers.set('location', '/users/1');

      final response = serialize('<b>made</b>', head: head);

      expect(response.status, 201);
      expect(response.headers['content-type'], 'text/html; charset=utf-8');
      expect(response.headers['location'], '/users/1');
    });

    test('registered serializers handle types without toJson', () async {
      final registry = SerializerRegistry()
        ..register<Money>((m) => {'cents': m.cents});

      final response = serialize({
        'price': Money(150),
        'history': [Money(1)],
      }, registry: registry);

      expect(
        await text(response),
        '{"price":{"cents":150},"history":[{"cents":1}]}',
      );
    });

    test('an unencodable value is a SerializationError', () {
      expect(
        () => serialize({'x': Opaque()}),
        throwsA(
          isA<SerializationError>()
              .having((e) => e.valueType, 'type', Opaque)
              .having(
                (e) => e.message,
                'message',
                contains('register<Opaque>'),
              ),
        ),
      );
    });
  });
}
```

`packages/dartnest/test/pipeline/http_error_responder_test.dart`:

```dart
import 'dart:convert';

import 'package:dartnest/dartnest.dart';
import 'package:dartnest/src/pipeline/http_error_responder.dart';
import 'package:test/test.dart';

final class Unprintable {
  @override
  String toString() => 'unprintable';
}

Future<Object?> jsonOf(HttpResponse response) async =>
    jsonDecode(utf8.decode(await response.body.readAll()));

void main() {
  group('HttpErrorResponder', () {
    final logged = <Object>[];
    final responder = HttpErrorResponder(
      debug: false,
      log: (error, stackTrace) => logged.add(error),
    );

    setUp(logged.clear);

    test('HttpException keeps status, message, details and headers', () async {
      final response = responder.respond(
        const UnauthorizedException(
          message: 'Token expired',
          details: {'realm': 'api'},
          headers: {'www-authenticate': 'Bearer'},
        ),
        StackTrace.current,
      );

      expect(response.status, 401);
      expect(response.headers['www-authenticate'], 'Bearer');
      expect(
        response.headers['content-type'],
        'application/json; charset=utf-8',
      );
      expect(await jsonOf(response), {
        'statusCode': 401,
        'error': 'Unauthorized',
        'message': 'Token expired',
        'details': {'realm': 'api'},
      });
      expect(logged, isEmpty);
    });

    test('details without a JSON form are sent as text', () async {
      final response = responder.respond(
        BadRequestException(details: Unprintable()),
        StackTrace.current,
      );

      expect((await jsonOf(response) as Map)['details'], 'unprintable');
    });

    test('an unknown error is a logged 500 without internals', () async {
      final error = StateError('db password is hunter2');

      final response = responder.respond(error, StackTrace.current);

      expect(response.status, 500);
      expect(await jsonOf(response), {
        'statusCode': 500,
        'error': 'Internal Server Error',
        'message': 'Internal server error',
      });
      expect(logged, [same(error)]);
    });

    test('debug mode includes the message and the stack', () async {
      final debug = HttpErrorResponder(debug: true, log: (_, _) {});

      final body =
          await jsonOf(debug.respond(StateError('boom'), StackTrace.current))
              as Map<String, Object?>;

      expect(body['message'], 'Bad state: boom');
      expect(body['stack'], contains('http_error_responder_test.dart'));
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run from `packages/dartnest`: `dart test test/pipeline/response_serializer_test.dart test/pipeline/http_error_responder_test.dart`
Expected: FAIL at compile time, first error: `Error: Error when reading 'lib/src/pipeline/response_serializer.dart': No such file or directory`

- [ ] **Step 3: Implement**

`packages/dartnest/lib/src/pipeline/serializer_registry.dart`:

````dart
/// Converters to JSON values for types that have no `toJson()`, such as
/// third-party classes.
///
/// ```dart
/// app.serializers.register<Money>((m) => {'amount': m.cents, 'cur': m.code});
/// ```
///
/// A converter applies to a handler result and to values nested in its
/// `Map`s and `List`s; it does not reach inside the output of another
/// object's `toJson()`. The first registered converter whose type matches
/// wins.
final class SerializerRegistry {
  /// Creates an empty registry.
  SerializerRegistry();

  final List<_Converter<Object>> _converters = [];

  /// Registers [toJson] for values of type [T].
  void register<T extends Object>(Object? Function(T value) toJson) {
    _converters.add(_Converter<T>(toJson));
  }

  /// Returns [value] with every registered type replaced by its JSON form,
  /// walking `Map` values and `List` elements; unchanged when nothing is
  /// registered.
  Object? prepare(Object? value) {
    if (_converters.isEmpty) return value;
    final converted = _convert(value);
    return switch (converted) {
      Map<Object?, Object?>() => {
        for (final MapEntry(:key, :value) in converted.entries)
          key: prepare(value),
      },
      List<Object?>() => [for (final item in converted) prepare(item)],
      _ => converted,
    };
  }

  Object? _convert(Object? value) {
    if (value == null) return null;
    for (final converter in _converters) {
      if (converter.accepts(value)) return converter.apply(value);
    }
    return value;
  }
}

final class _Converter<T extends Object> {
  _Converter(this._toJson);

  final Object? Function(T value) _toJson;

  bool accepts(Object value) => value is T;

  Object? apply(Object value) => _toJson(value as T);
}
````

`packages/dartnest/lib/src/pipeline/response_serializer.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import '../http/header_map.dart';
import '../http/http_response.dart';
import '../http/response_body.dart';
import '../http/response_head.dart';
import '../http/status_code.dart';
import 'pipeline_error.dart';
import 'serializer_registry.dart';

/// Turns a handler (or filter) result into an [HttpResponse].
///
/// | Result | Response |
/// | --- | --- |
/// | [HttpResponse] | as is, plus head headers it does not set |
/// | `null` | 204, empty |
/// | [String] | `text/plain; charset=utf-8` |
/// | [Uint8List] | `application/octet-stream` |
/// | `Stream<List<int>>` | streamed `application/octet-stream` |
/// | anything else | JSON (`Map`, `List` (also `List<int>`), `num`, `bool`, objects with `toJson()`, registered types) |
///
/// The [ResponseHead] status replaces the default status (200, or 204 for
/// `null`), and its headers replace the defaults. A value JSON cannot encode
/// throws [SerializationError].
final class ResponseSerializer {
  /// Creates a serializer using [registry] for types without `toJson()`.
  const ResponseSerializer(this.registry);

  /// Converters for types without `toJson()`.
  final SerializerRegistry registry;

  /// Serializes [result] with the status and headers in [head].
  HttpResponse serialize(Object? result, ResponseHead head) => switch (result) {
    HttpResponse() => result.mergeHeaders(head.headers),
    null => _build(head, StatusCode.noContent, null, BytesBody(const [])),
    String() => _build(
      head,
      StatusCode.ok,
      'text/plain; charset=utf-8',
      BytesBody(utf8.encode(result)),
    ),
    Uint8List() => _build(
      head,
      StatusCode.ok,
      'application/octet-stream',
      BytesBody(result),
    ),
    Stream<List<int>>() => _build(
      head,
      StatusCode.ok,
      'application/octet-stream',
      StreamBody(result),
    ),
    _ => _build(
      head,
      StatusCode.ok,
      'application/json; charset=utf-8',
      BytesBody(utf8.encode(_encode(result))),
    ),
  };

  HttpResponse _build(
    ResponseHead head,
    int defaultStatus,
    String? contentType,
    ResponseBody body,
  ) {
    final headers = HeaderMap();
    if (contentType != null) headers.set('content-type', contentType);
    headers.setAll(head.headers);
    return HttpResponse(
      head.status ?? defaultStatus,
      headers: headers,
      body: body,
    );
  }

  String _encode(Object value) {
    // jsonEncode calls toJson() itself and signals failure with this SDK
    // error; it is converted to the documented SerializationError.
    try {
      return jsonEncode(registry.prepare(value));
    } on JsonUnsupportedObjectError catch (error, stackTrace) {
      Error.throwWithStackTrace(
        SerializationError(
          valueType: error.unsupportedObject.runtimeType,
          cause: error.cause,
        ),
        stackTrace,
      );
    }
  }
}
```

`packages/dartnest/lib/src/pipeline/http_error_responder.dart`:

```dart
import 'dart:convert';

import '../http/header_map.dart';
import '../http/http_exception.dart';
import '../http/http_response.dart';
import '../http/response_body.dart';
import '../http/status_code.dart';

/// Receives errors that become 500 responses, with their stack traces.
typedef ErrorLogger = void Function(Object error, StackTrace stackTrace);

/// The default exception filter: turns any error into a JSON error response
/// and never throws.
///
/// - [HttpException] → its status and headers, body
///   `{"statusCode", "error", "message"}` plus `"details"` when present.
/// - Anything else → logged through [log], then 500 with
///   `"message": "Internal server error"`; with [debug] the message is the
///   error's `toString()` and `"stack"` holds the stack trace.
final class HttpErrorResponder {
  /// Creates the responder.
  const HttpErrorResponder({required this.debug, required this.log});

  /// Whether 500 responses reveal the error and its stack trace.
  final bool debug;

  /// Where unexpected errors are reported.
  final ErrorLogger log;

  /// The response for [error].
  HttpResponse respond(Object error, StackTrace stackTrace) {
    if (error is HttpException) {
      return _json(error.status, HeaderMap.of(error.headers), {
        'statusCode': error.status,
        'error': StatusCode.reasonPhrase(error.status),
        'message': error.message,
        if (error.details != null) 'details': error.details,
      });
    }
    log(error, stackTrace);
    return _json(StatusCode.internalServerError, HeaderMap(), {
      'statusCode': StatusCode.internalServerError,
      'error': StatusCode.reasonPhrase(StatusCode.internalServerError),
      'message': debug ? '$error' : 'Internal server error',
      if (debug) 'stack': '$stackTrace',
    });
  }

  /// The default [ErrorLogger]: prints the error and stack trace.
  static void printError(Object error, StackTrace stackTrace) {
    print('dartnest: unhandled error: $error\n$stackTrace');
  }

  static HttpResponse _json(
    int status,
    HeaderMap headers,
    Map<String, Object?> body,
  ) {
    headers.set('content-type', 'application/json; charset=utf-8');
    // Anything that is not a JSON value is sent as its toString(), so
    // building an error response cannot fail.
    final text = jsonEncode(body, toEncodable: (Object? value) => '$value');
    return HttpResponse(
      status,
      headers: headers,
      body: BytesBody(utf8.encode(text)),
    );
  }
}
```

Append to the end of `packages/dartnest/lib/src/pipeline/pipeline_error.dart` (after one blank line):

```dart
/// A handler result cannot be encoded as JSON.
final class SerializationError extends PipelineError {
  /// Creates the error.
  const SerializationError({required this.valueType, this.cause});

  /// Runtime type of the value that could not be encoded.
  final Type valueType;

  /// What the JSON encoder reported, if anything.
  final Object? cause;

  @override
  String get message =>
      'Cannot serialize $valueType to JSON'
      '${cause == null ? '' : ' ($cause)'}. Give it a toJson() method, '
      'return an HttpResponse, or register a serializer with '
      'app.serializers.register<$valueType>(...).';
}
```

- [ ] **Step 4: Export the public types**

Add to `packages/dartnest/lib/dartnest.dart`, keeping all `export` lines sorted:

```dart
export 'src/pipeline/http_error_responder.dart' show ErrorLogger;
export 'src/pipeline/serializer_registry.dart';
```

- [ ] **Step 5: Run the tests to verify they pass**

Run from `packages/dartnest`: `dart test test/pipeline/response_serializer_test.dart test/pipeline/http_error_responder_test.dart`
Expected: `+13: All tests passed!`

Run from `packages/dartnest`: `dart test`
Expected: `+171: All tests passed!`

- [ ] **Step 6: Analyze, format and commit**

Run from repo root: `dart analyze && dart format --output=none --set-exit-if-changed packages`
Expected: `No issues found!` and `Formatted N files (0 changed)`.

```bash
git add \
  packages/dartnest/lib/src/pipeline/serializer_registry.dart \
  packages/dartnest/lib/src/pipeline/response_serializer.dart \
  packages/dartnest/lib/src/pipeline/http_error_responder.dart \
  packages/dartnest/lib/src/pipeline/pipeline_error.dart \
  packages/dartnest/test/pipeline/response_serializer_test.dart \
  packages/dartnest/test/pipeline/http_error_responder_test.dart \
  packages/dartnest/lib/dartnest.dart
git commit -m "feat(pipeline): serialize handler results and render HTTP errors"
```

---

### Task 10: Таблиця роутів і диспетчер запитів

Збирання таблиці роутів і обробка одного запиту без middleware. `RouteTableBuilder.validate(graph)` перевіряє шаблони й дублікати **до** запуску будь-якої фабрики провайдера (fail fast). `RouteTableBuilder.build(container, enhancers)` — внутрішній хук старту: проходить модулі в порядку графа, створює контролери через `Container.injectorFor(module.id)`, резолвить enhancers і заповнює `Router<Endpoint>`. `RequestDispatcher.dispatch` нормалізує шлях (порожні сегменти відкидаються, сегменти декодовані), відповідає 404/405 через `HttpErrorResponder` (користувацькі фільтри їх не бачать — специфікація відносить фільтри до кроків 5–8), запускає `Pipeline.run` і ловить усе на межі запиту.

**Files:**
- Create: `packages/dartnest/lib/src/app/route_table_builder.dart`
- Create: `packages/dartnest/lib/src/app/request_dispatcher.dart`
- Create: `packages/dartnest/test/helpers/app_fixtures.dart`
- Test: `packages/dartnest/test/app/route_table_builder_test.dart`
- Test: `packages/dartnest/test/app/request_dispatcher_test.dart`

**Interfaces:**
- Consumes: `Container.injectorFor`, `ModuleGraph` (DI); `Router`, `RoutePattern` (Task 3–4); `ResolvedEnhancers`, `Endpoint`, `Pipeline` (Task 8); `ResponseSerializer`, `HttpErrorResponder` (Task 9); `ControllerSpec` (Task 7).
- Produces:
  - `abstract final class RouteTableBuilder { static void validate(ModuleGraph graph); static Router<Endpoint> build(Container container, Enhancers enhancers); }`; internal.
  - `final class RequestDispatcher { const RequestDispatcher({required ResponseSerializer serializer, required HttpErrorResponder errors}); Future<HttpResponse> dispatch(HttpRequest request, Router<Endpoint> router); }`; internal.
  - Test fixture app in `test/helpers/app_fixtures.dart`: `UsersService`, `User`, `CreateUserDto`, `AuthGuard`, `RolesGuard`, `Roles`, `UserMissingFilter`, `usersController`, `usersModule()`, `appModule()`.

- [ ] **Step 1: Write the failing tests**

`packages/dartnest/test/helpers/app_fixtures.dart`:

```dart
// A small users application shared by dispatcher, application and e2e
// tests.
import 'package:dartnest/dartnest.dart';

/// Thrown by [UsersService] for an unknown id.
final class UserMissing implements Exception {
  UserMissing(this.id);
  final int id;
}

/// A user.
final class User {
  User(this.id, this.name);
  final int id;
  final String name;
  Map<String, Object?> toJson() => {'id': id, 'name': name};
}

/// Body of `POST /users`.
final class CreateUserDto {
  CreateUserDto(this.name);

  factory CreateUserDto.fromJson(Map<String, Object?> json) => switch (json) {
    {'name': final String name} when name.isNotEmpty => CreateUserDto(name),
    _ => throw const FormatException('"name" must be a non-empty string'),
  };

  final String name;
}

/// In-memory users.
final class UsersService {
  final Map<int, User> _users = {1: User(1, 'ann'), 2: User(2, 'bob')};

  List<User> list({required int limit}) => _users.values.take(limit).toList();

  User find(int id) => _users[id] ?? (throw UserMissing(id));

  User create(String name) {
    final user = User(_users.length + 1, name);
    _users[user.id] = user;
    return user;
  }
}

/// Route metadata: roles allowed to call a handler.
final class Roles {
  const Roles(this.names);
  final List<String> names;
}

/// Accepts `authorization: Bearer <role>`; stores the role in `items`.
final class AuthGuard implements Guard {
  @override
  bool canActivate(ExecutionContext context) {
    final header = context.header('authorization');
    if (header == null || !header.startsWith('Bearer ')) {
      throw const UnauthorizedException(
        headers: {'www-authenticate': 'Bearer'},
      );
    }
    context.items[#role] = header.substring('Bearer '.length);
    return true;
  }
}

/// Allows a handler only for the roles in its [Roles] metadata.
final class RolesGuard implements Guard {
  @override
  bool canActivate(ExecutionContext context) {
    final roles = context.metadata<Roles>();
    return roles == null || roles.names.contains(context.items[#role]);
  }
}

/// Maps [UserMissing] to 404.
final class UserMissingFilter extends ExceptionFilter<UserMissing> {
  const UserMissingFilter();

  @override
  Object? handle(UserMissing error, ExecutionContext context) =>
      throw NotFoundException(message: 'No user ${error.id}');
}

/// Handlers of `/users`.
final class UsersController {
  UsersController(this.service);
  final UsersService service;

  List<User> list(int limit) => service.list(limit: limit);
  User findOne(int id) => service.find(id);
  User create(CreateUserDto dto) => service.create(dto.name);
}

/// The users controller: reads are public, writes need an admin.
final usersController = Controller<UsersController>(
  path: '/users',
  create: (i) => UsersController(i.get()),
  enhancers: const Enhancers(filters: [UserMissingFilter()]),
  routes: [
    Route.get(
      '/',
      (c, ctx) async => c.list(await ctx.query<int?>('limit') ?? 10),
      name: 'list',
    ),
    Route.get(
      '/:id',
      (c, ctx) async => c.findOne(await ctx.param<int>('id')),
      name: 'findOne',
    ),
    Route.post(
      '/',
      (c, ctx) async {
        final user = c.create(await ctx.bodyAs(CreateUserDto.fromJson));
        ctx.switchToHttp().response
          ..status = StatusCode.created
          ..headers.set('location', '/users/${user.id}');
        return user;
      },
      name: 'create',
      enhancers: const Enhancers(guards: [Use<AuthGuard>(), Use<RolesGuard>()]),
      metadata: const [
        Roles(['admin']),
      ],
    ),
  ],
);

/// Module with [usersController] and its providers.
Module usersModule() => Module(
  id: 'users',
  providers: [
    Provider((i) => UsersService()),
    Provider((i) => AuthGuard()),
    Provider((i) => RolesGuard()),
  ],
  controllers: [usersController],
);

/// The application root.
Module appModule() => Module(id: 'app', imports: [usersModule()]);
```

`packages/dartnest/test/app/route_table_builder_test.dart`:

```dart
import 'package:dartnest/dartnest.dart';
import 'package:dartnest/src/app/route_table_builder.dart';
import 'package:dartnest/src/routing/route_match.dart';
import 'package:test/test.dart';

import '../helpers/app_fixtures.dart';

final class PingController {
  String ping() => 'pong';
}

final class NeedsMissing implements Guard {
  @override
  bool canActivate(ExecutionContext context) => true;
}

Controller<PingController> ping(
  String path, {
  Enhancers enhancers = Enhancers.none,
}) => Controller<PingController>(
  path: path,
  create: (i) => PingController(),
  enhancers: enhancers,
  routes: [Route.get('/', (c, ctx) => c.ping(), name: 'ping')],
);

void main() {
  group('RouteTableBuilder.validate', () {
    test('accepts the sample application', () {
      expect(
        () => RouteTableBuilder.validate(ModuleGraph.build(appModule())),
        returnsNormally,
      );
    });

    test('duplicate routes across modules name both handlers', () {
      final root = Module(
        id: 'app',
        imports: [
          Module(id: 'a', controllers: [ping('/ping')]),
          Module(id: 'b', controllers: [ping('ping/')]),
        ],
      );

      expect(
        () => RouteTableBuilder.validate(ModuleGraph.build(root)),
        throwsA(
          isA<DuplicateRouteError>()
              .having((e) => e.path, 'path', '/ping')
              .having(
                (e) => e.existing,
                'existing',
                'PingController.ping (module "a")',
              )
              .having(
                (e) => e.duplicate,
                'duplicate',
                'PingController.ping (module "b")',
              ),
        ),
      );
    });

    test('an invalid pattern is reported', () {
      final root = Module(id: 'app', controllers: [ping('/files/*/x')]);

      expect(
        () => RouteTableBuilder.validate(ModuleGraph.build(root)),
        throwsA(isA<InvalidRoutePatternError>()),
      );
    });
  });

  group('RouteTableBuilder.build', () {
    test('creates controllers and registers their routes', () async {
      final container = await Container.create(appModule());

      final router = RouteTableBuilder.build(container, Enhancers.none);

      final match = router.match('GET', ['users', '1']);
      expect(
        match,
        isA<RouteFound<Object>>().having((m) => m.parameters, 'parameters', {
          'id': '1',
        }),
      );
    });

    test('Use with no visible provider fails at startup', () async {
      final container = await Container.create(
        Module(
          id: 'app',
          controllers: [
            ping(
              '/',
              enhancers: const Enhancers(guards: [Use<NeedsMissing>()]),
            ),
          ],
        ),
      );

      expect(
        () => RouteTableBuilder.build(container, Enhancers.none),
        throwsA(
          isA<MissingProviderError>()
              .having((e) => e.key, 'key', NeedsMissing)
              .having((e) => e.moduleId, 'module', 'app'),
        ),
      );
    });

    test('application Use resolves through the root module', () async {
      final container = await Container.create(
        Module(id: 'app', imports: [usersModule()]),
      );

      expect(
        () => RouteTableBuilder.build(
          container,
          const Enhancers(guards: [Use<AuthGuard>()]),
        ),
        throwsA(
          isA<MissingProviderError>()
              .having((e) => e.key, 'key', AuthGuard)
              .having((e) => e.moduleId, 'module', 'app'),
        ),
      );
    });
  });
}
```

`packages/dartnest/test/app/request_dispatcher_test.dart`:

```dart
import 'dart:convert';

import 'package:dartnest/dartnest.dart';
import 'package:dartnest/src/app/request_dispatcher.dart';
import 'package:dartnest/src/app/route_table_builder.dart';
import 'package:dartnest/src/pipeline/endpoint.dart';
import 'package:dartnest/src/pipeline/http_error_responder.dart';
import 'package:dartnest/src/pipeline/response_serializer.dart';
import 'package:dartnest/src/routing/router.dart';
import 'package:test/test.dart';

import '../helpers/app_fixtures.dart';
import '../helpers/http_fixtures.dart';

final class FilesController {
  String read(String path) => 'file $path';
}

final filesController = Controller<FilesController>(
  path: '/files',
  create: (i) => FilesController(),
  routes: [
    Route.get('/:name', (c, ctx) async => c.read(await ctx.param('name'))),
    Route.get('/raw/*', (c, ctx) async => c.read(await ctx.param('*'))),
  ],
);

Future<(RequestDispatcher, Router<Endpoint>)> dispatcherFor(Module root) async {
  final container = await Container.create(root);
  final dispatcher = RequestDispatcher(
    serializer: ResponseSerializer(SerializerRegistry()),
    errors: HttpErrorResponder(debug: false, log: (_, _) {}),
  );
  return (dispatcher, RouteTableBuilder.build(container, Enhancers.none));
}

Future<Object?> jsonOf(HttpResponse response) async =>
    jsonDecode(utf8.decode(await response.body.readAll()));

void main() {
  late RequestDispatcher dispatcher; // set in setUp before every test
  late Router<Endpoint> router; // set in setUp before every test

  Future<HttpResponse> send(
    String method,
    String target, {
    Map<String, String> headers = const {},
    String? body,
  }) => dispatcher.dispatch(
    requestFor(method, target, headers: headers, body: body),
    router,
  );

  setUp(() async {
    (dispatcher, router) = await dispatcherFor(
      Module(
        id: 'app',
        imports: [usersModule()],
        controllers: [filesController],
      ),
    );
  });

  group('RequestDispatcher', () {
    test('runs the handler and serializes the result', () async {
      final response = await send('GET', '/users/1');

      expect(response.status, 200);
      expect(await jsonOf(response), {'id': 1, 'name': 'ann'});
    });

    test('unknown path is 404 with the default body', () async {
      final response = await send('GET', '/nope');

      expect(response.status, 404);
      expect(await jsonOf(response), {
        'statusCode': 404,
        'error': 'Not Found',
        'message': 'Cannot GET /nope',
      });
    });

    test('wrong method is 405 with allow', () async {
      final response = await send('DELETE', '/users/1');

      expect(response.status, 405);
      expect(response.headers['allow'], 'GET, HEAD');
    });

    test('controller filter maps a domain error', () async {
      final response = await send('GET', '/users/99');

      expect(response.status, 404);
      expect((await jsonOf(response) as Map)['message'], 'No user 99');
    });

    test('guard header survives the error response', () async {
      final response = await send('POST', '/users', body: '{"name":"cy"}');

      expect(response.status, 401);
      expect(response.headers['www-authenticate'], 'Bearer');
    });

    test('head status and location from the handler', () async {
      final response = await send(
        'POST',
        '/users',
        headers: {'authorization': 'Bearer admin'},
        body: '{"name":"cy"}',
      );

      expect(response.status, 201);
      expect(response.headers['location'], '/users/3');
      expect(await jsonOf(response), {'id': 3, 'name': 'cy'});
    });

    test('route metadata reaches the guard: non-admin is 403', () async {
      final response = await send(
        'POST',
        '/users',
        headers: {'authorization': 'Bearer user'},
        body: '{"name":"cy"}',
      );

      expect(response.status, 403);
    });

    // Review Focus 4: path normalization and decoding.
    test('trailing and repeated slashes, percent-decoding, wildcard', () async {
      expect((await send('GET', '/users/')).status, 200);
      expect(await jsonOf(await send('GET', '/users//2')), {
        'id': 2,
        'name': 'bob',
      });
      expect(
        utf8.decode(await (await send('GET', '/files/a%20b')).body.readAll()),
        'file a b',
      );
      expect(
        utf8.decode(
          await (await send('GET', '/files/raw/x/y%2Fz')).body.readAll(),
        ),
        'file x/y/z',
      );
    });

    test('HEAD is routed to GET', () async {
      expect((await send('HEAD', '/users/1')).status, 200);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run from `packages/dartnest`: `dart test test/app/route_table_builder_test.dart test/app/request_dispatcher_test.dart`
Expected: FAIL at compile time, first error: `Error: Error when reading 'lib/src/app/route_table_builder.dart': No such file or directory`

- [ ] **Step 3: Implement**

`packages/dartnest/lib/src/app/route_table_builder.dart`:

```dart
import '../controller/controller.dart';
import '../di/container.dart';
import '../di/injector.dart';
import '../di/module_graph.dart';
import '../pipeline/endpoint.dart';
import '../pipeline/enhancers.dart';
import '../pipeline/resolved_enhancers.dart';
import '../routing/route_pattern.dart';
import '../routing/router.dart';

/// Turns the controllers of a module graph into a [Router] of [Endpoint]s.
///
/// Modules are visited in `ModuleGraph.ordered` order, controllers and
/// routes in declaration order, so duplicate reports are deterministic.
abstract final class RouteTableBuilder {
  /// Checks every route pattern and rejects duplicate routes without
  /// creating anything, so `Application.create` can fail before any provider
  /// factory runs. Throws a `RoutingError`.
  static void validate(ModuleGraph graph) {
    final dryRun = Router<void>();
    for (final module in graph.ordered) {
      for (final controller in module.controllers) {
        for (final route in controller.routes) {
          dryRun.add(
            route.method,
            RoutePattern.join(controller.path, route.path),
            null,
            source: _source(controller, route.name, module.id),
          );
        }
      }
    }
  }

  /// Creates every controller with its module's injector, resolves the
  /// application [enhancers] through the root injector and the controller
  /// and route enhancers through the controller's module injector, and
  /// registers one [Endpoint] per route.
  static Router<Endpoint> build(Container container, Enhancers enhancers) {
    final application = ResolvedEnhancers.resolve(
      enhancers,
      container.root,
      owner: 'Application',
    );
    final router = Router<Endpoint>();
    for (final module in container.graph.ordered) {
      final injector = container.injectorFor(module.id);
      for (final controller in module.controllers) {
        _addController(router, controller, injector, application);
      }
    }
    return router;
  }

  static void _addController(
    Router<Endpoint> router,
    ControllerSpec controller,
    Injector injector,
    ResolvedEnhancers application,
  ) {
    final instance = controller.instantiate(injector);
    final controllerLevel = ResolvedEnhancers.resolve(
      controller.enhancers,
      injector,
      owner: '${controller.type}',
    );
    for (final route in controller.routes) {
      final routeLevel = ResolvedEnhancers.resolve(
        route.enhancers,
        injector,
        owner: '${controller.type}.${route.name}',
      );
      final endpoint = Endpoint(
        controllerType: controller.type,
        handlerName: route.name,
        metadata: [...route.metadata, ...controller.metadata],
        enhancers: ResolvedEnhancers.chain([
          application,
          controllerLevel,
          routeLevel,
        ]),
        invoke: (context) => route.invoke(instance, context),
      );
      router.add(
        route.method,
        RoutePattern.join(controller.path, route.path),
        endpoint,
        source: _source(controller, route.name, injector.moduleId),
      );
    }
  }

  static String _source(
    ControllerSpec controller,
    String handler,
    String moduleId,
  ) => '${controller.type}.$handler (module "$moduleId")';
}
```

`packages/dartnest/lib/src/app/request_dispatcher.dart`:

```dart
import '../http/http_exception.dart';
import '../http/http_request.dart';
import '../http/http_response.dart';
import '../http/response_head.dart';
import '../pipeline/endpoint.dart';
import '../pipeline/execution_context.dart';
import '../pipeline/http_error_responder.dart';
import '../pipeline/pipeline.dart';
import '../pipeline/response_serializer.dart';
import '../pipeline/transport.dart';
import '../routing/route_match.dart';
import '../routing/router.dart';

/// Routes one request and runs it through the pipeline; always answers.
final class RequestDispatcher {
  /// Creates the dispatcher.
  const RequestDispatcher({required this.serializer, required this.errors});

  /// Turns results into responses.
  final ResponseSerializer serializer;

  /// The default exception filter.
  final HttpErrorResponder errors;

  /// Answers [request] with [router]: 404 for an unknown path, 405 with
  /// `allow` for a known path with another method, otherwise the pipeline's
  /// response. Path segments are percent-decoded and empty segments are
  /// ignored, so `/users/` and `/users//1` match `/users` and `/users/1`.
  Future<HttpResponse> dispatch(
    HttpRequest request,
    Router<Endpoint> router,
  ) async {
    final segments = [
      for (final segment in request.uri.pathSegments)
        if (segment.isNotEmpty) segment,
    ];
    return switch (router.match(request.method, segments)) {
      RouteFound(:final value, :final parameters) => _run(
        request,
        value,
        parameters,
      ),
      RouteMethodNotAllowed(:final allowed) => errors.respond(
        MethodNotAllowedException(allowed),
        StackTrace.current,
      ),
      RouteNotFound() => errors.respond(
        NotFoundException(
          message: 'Cannot ${request.method} ${request.uri.path}',
        ),
        StackTrace.current,
      ),
    };
  }

  Future<HttpResponse> _run(
    HttpRequest request,
    Endpoint endpoint,
    Map<String, String> parameters,
  ) async {
    final head = ResponseHead();
    final context = ExecutionContext(
      transport: HttpContext(
        request: request,
        response: head,
        pathParameters: parameters,
      ),
      controllerType: endpoint.controllerType,
      handlerName: endpoint.handlerName,
      metadata: endpoint.metadata,
      pipes: endpoint.enhancers.pipes,
    );
    // Request boundary: errors no filter handled become the default
    // filter's response; head headers (for example www-authenticate set by
    // a guard) are kept.
    try {
      return await Pipeline.run(
        endpoint,
        context,
        (result) => serializer.serialize(result, head),
      );
    } on Object catch (error, stackTrace) {
      return errors.respond(error, stackTrace).mergeHeaders(head.headers);
    }
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run from `packages/dartnest`: `dart test test/app/route_table_builder_test.dart test/app/request_dispatcher_test.dart`
Expected: `+15: All tests passed!`

Run from `packages/dartnest`: `dart test`
Expected: `+186: All tests passed!`

- [ ] **Step 5: Analyze, format and commit**

Run from repo root: `dart analyze && dart format --output=none --set-exit-if-changed packages`
Expected: `No issues found!` and `Formatted N files (0 changed)`.

```bash
git add \
  packages/dartnest/lib/src/app/route_table_builder.dart \
  packages/dartnest/lib/src/app/request_dispatcher.dart \
  packages/dartnest/test/helpers/app_fixtures.dart \
  packages/dartnest/test/app/route_table_builder_test.dart \
  packages/dartnest/test/app/request_dispatcher_test.dart
git commit -m "feat(app): build the route table and dispatch requests"
```

---

### Task 11: `Application`: create, handle, middleware, listen, close

Публічна точка входу. `Application.create(Module Function())` (вимога 10.1: граф можна перебудувати після hot reload) і `Application.fromModule(Module)` (у Dart немає union-типів). `handle` читає `_router` один раз на запит, тому `replaceRoutes` (`@internal`, для етапу 5b) атомарно підміняє таблицю: запит, що вже йде, завершується старою. `close()` повторюваний: усі виклики повертають той самий `Future`; адаптер зупиняється, нові запити отримують 503, запити в польоті завершуються (якщо не `force`), потім закривається контейнер. `Container` отримує ідемпотентний `close()` (заготовка під shutdown-хуки v1.1); `Container.reassemble` не реалізується і нічим не заблокований. `HttpAdapter` — лише інтерфейс; реалізації з `dart:io` і shelf — етап 3.

**Files:**
- Create: `packages/dartnest/lib/src/app/http_adapter.dart`
- Create: `packages/dartnest/lib/src/app/middleware.dart`
- Create: `packages/dartnest/lib/src/app/in_flight_requests.dart`
- Create: `packages/dartnest/lib/src/app/application.dart`
- Modify: `packages/dartnest/lib/src/di/container.dart`
- Modify: `packages/dartnest/lib/src/app/application_error.dart`
- Modify: `packages/dartnest/lib/dartnest.dart`
- Create: `packages/dartnest/test/helpers/fake_adapter.dart`
- Test: `packages/dartnest/test/app/application_test.dart`
- Test: `packages/dartnest/test/app/application_lifecycle_test.dart`

**Interfaces:**
- Consumes: `RouteTableBuilder`, `RequestDispatcher` (Task 10); `SerializerRegistry`, `HttpErrorResponder` (Task 9); `ApplicationError` (Task 7); `Container` (DI).
- Produces:
  - `ApplicationStateError({required String operation, required String reason})` in the `ApplicationError` family.
  - `Container.close()` (idempotent, same future) and `bool get isClosed`.
  - `typedef RequestHandler = Future<HttpResponse> Function(HttpRequest request);` and `abstract interface class HttpAdapter { Future<void> listen(RequestHandler handler, {required Object address, required int port}); Future<void> close({bool force = false}); }`
  - `typedef Middleware = Future<HttpResponse> Function(HttpRequest request, Next<HttpResponse> next);`
  - `final class InFlightRequests { int get count; Future<T> track<T>(Future<T> Function() handle); Future<void> get idle; }`; internal.
  - `final class Application { static Future<Application> create(Module Function() root, {HttpAdapter? adapter, Enhancers enhancers, bool debug, ErrorLogger? onError}); static Future<Application> fromModule(Module root, {HttpAdapter? adapter, Enhancers enhancers, bool debug, ErrorLogger? onError}); Container container; SerializerRegistry get serializers; bool get isClosed; void use(Middleware); Future<HttpResponse> handle(HttpRequest); Future<void> listen({required int port, Object address = 'localhost'}); Future<void> close({bool force = false}); @internal void replaceRoutes(Router<Endpoint>); }`
  - Test helper `FakeAdapter implements HttpAdapter` in `test/helpers/fake_adapter.dart`.

- [ ] **Step 1: Write the failing tests**

`packages/dartnest/test/helpers/fake_adapter.dart`:

```dart
// An HttpAdapter that records calls instead of opening sockets.
import 'package:dartnest/dartnest.dart';

/// Records `listen` and `close` calls; [send] plays the native server.
final class FakeAdapter implements HttpAdapter {
  RequestHandler? handler;
  Object? address;
  int? port;
  final List<bool> closeCalls = [];

  @override
  Future<void> listen(
    RequestHandler handler, {
    required Object address,
    required int port,
  }) async {
    this.handler = handler;
    this.address = address;
    this.port = port;
  }

  @override
  Future<void> close({bool force = false}) async => closeCalls.add(force);

  /// Delivers [request] the way a server would.
  Future<HttpResponse> send(HttpRequest request) {
    final current = handler;
    if (current == null) throw StateError('listen was not called');
    return current(request);
  }
}
```

`packages/dartnest/test/app/application_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:dartnest/dartnest.dart';
import 'package:dartnest/src/app/route_table_builder.dart';
import 'package:test/test.dart';

import '../helpers/app_fixtures.dart';
import '../helpers/http_fixtures.dart';

final class Answer {
  Answer(this.text);
  final String text;
}

/// A module whose `GET /slow` waits for [gate] and answers [label].
Module slowModule(String label, Completer<void> gate) => Module(
  id: 'slow',
  controllers: [
    Controller<Answer>(
      create: (i) => Answer(label),
      routes: [
        Route.get('/slow', (c, ctx) async {
          await gate.future;
          return c.text;
        }),
      ],
    ),
  ],
);

Future<String> textOf(HttpResponse response) async =>
    utf8.decode(await response.body.readAll());

void silent(Object error, StackTrace stackTrace) {}

void main() {
  group('Application.create', () {
    test('takes a module function and answers through handle', () async {
      final app = await Application.create(appModule, onError: silent);

      final response = await app.handle(requestFor('GET', '/users/2'));

      expect(response.status, 200);
      expect(await textOf(response), '{"id":2,"name":"bob"}');
      expect(app.container.injectorFor('users').get<UsersService>(), isNotNull);
    });

    test('fromModule takes a module value', () async {
      final app = await Application.fromModule(appModule(), onError: silent);

      expect((await app.handle(requestFor('GET', '/users'))).status, 200);
    });

    test('a bad route fails before any provider is created', () async {
      var created = false;
      final root = Module(
        id: 'app',
        providers: [
          Provider((i) {
            created = true;
            return Answer('x');
          }),
        ],
        controllers: [
          Controller<Answer>(
            create: (i) => i.get(),
            routes: [Route.get('/*/x', (c, ctx) => c.text)],
          ),
        ],
      );

      await expectLater(
        Application.fromModule(root),
        throwsA(isA<InvalidRoutePatternError>()),
      );
      expect(created, isFalse);
    });

    test('application enhancers resolve through the root module', () async {
      final app = await Application.create(
        () => Module(
          id: 'app',
          imports: [usersModule()],
          providers: [Provider((i) => AuthGuard())],
        ),
        enhancers: const Enhancers(guards: [Use<AuthGuard>()]),
        onError: silent,
      );

      expect((await app.handle(requestFor('GET', '/users'))).status, 401);
    });

    test('serializers registered on the app are used', () async {
      final app = await Application.create(
        () => Module(
          id: 'app',
          controllers: [
            Controller<Answer>(
              create: (i) => Answer('x'),
              routes: [Route.get('/', (c, ctx) => c)],
            ),
          ],
        ),
        onError: silent,
      );
      app.serializers.register<Answer>((a) => {'text': a.text});

      expect(
        await textOf(await app.handle(requestFor('GET', '/'))),
        '{"text":"x"}',
      );
    });
  });

  group('Application middleware', () {
    test('runs in registration order around routing', () async {
      final app = await Application.create(appModule, onError: silent);
      final log = <String>[];
      app
        ..use((request, next) async {
          log.add('outer in');
          final response = await next();
          log.add('outer out');
          return response.mergeHeaders(HeaderMap.of({'x-outer': '1'}));
        })
        ..use((request, next) async {
          log.add('inner');
          return next();
        });

      final response = await app.handle(requestFor('GET', '/nope'));

      expect(response.status, 404);
      expect(response.headers['x-outer'], '1');
      expect(log, ['outer in', 'inner', 'outer out']);
    });

    test('can answer without routing, errors become 500', () async {
      final errors = <Object>[];
      final app = await Application.create(
        appModule,
        onError: (error, _) => errors.add(error),
      );
      app.use((request, next) async {
        if (request.uri.path == '/boom') throw StateError('boom');
        return HttpResponse.text('short');
      });

      expect(
        await textOf(await app.handle(requestFor('GET', '/users'))),
        'short',
      );
      expect((await app.handle(requestFor('GET', '/boom'))).status, 500);
      expect(errors, [isA<StateError>()]);
    });
  });

  group('Application route table', () {
    test('a request keeps the table it started with', () async {
      final gate = Completer<void>();
      final app = await Application.create(() => slowModule('old', gate));
      final next = RouteTableBuilder.build(
        await Container.create(slowModule('new', gate)),
        Enhancers.none,
      );

      final inFlight = app.handle(requestFor('GET', '/slow'));
      app.replaceRoutes(next);
      final after = app.handle(requestFor('GET', '/slow'));
      gate.complete();

      expect(await textOf(await inFlight), 'old');
      expect(await textOf(await after), 'new');
    });
  });
}
```

`packages/dartnest/test/app/application_lifecycle_test.dart`:

```dart
import 'dart:async';

import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

import '../helpers/app_fixtures.dart';
import '../helpers/fake_adapter.dart';
import '../helpers/http_fixtures.dart';

final class Waiter {
  Waiter(this.gate);
  final Completer<void> gate;
}

Module waitingModule(Completer<void> gate) => Module(
  id: 'app',
  controllers: [
    Controller<Waiter>(
      create: (i) => Waiter(gate),
      routes: [
        Route.get('/wait', (c, ctx) async {
          await c.gate.future;
          return 'done';
        }),
      ],
    ),
  ],
);

void main() {
  group('Application.listen', () {
    test('hands handle, address and port to the adapter', () async {
      final adapter = FakeAdapter();
      final app = await Application.create(appModule, adapter: adapter);

      await app.listen(port: 0);

      expect(adapter.address, 'localhost');
      expect(adapter.port, 0);
      final response = await adapter.send(requestFor('GET', '/users/1'));
      expect(response.status, 200);
    });

    test(
      'rejects a missing adapter, a second listen and a closed app',
      () async {
        final bare = await Application.create(appModule);
        expect(
          () => bare.listen(port: 0),
          throwsA(
            isA<ApplicationStateError>().having(
              (e) => e.message,
              'message',
              'Cannot listen: no HttpAdapter was passed to Application.create.',
            ),
          ),
        );

        final app = await Application.create(appModule, adapter: FakeAdapter());
        await app.listen(port: 0);
        expect(
          () => app.listen(port: 0),
          throwsA(isA<ApplicationStateError>()),
        );

        final closed = await Application.create(
          appModule,
          adapter: FakeAdapter(),
        );
        await closed.close();
        expect(
          () => closed.listen(port: 0),
          throwsA(isA<ApplicationStateError>()),
        );
      },
    );
  });

  // Review Focus 5: close is repeatable and graceful.
  group('Application.close', () {
    test('is idempotent and closes the adapter and container once', () async {
      final adapter = FakeAdapter();
      final app = await Application.create(appModule, adapter: adapter);
      await app.listen(port: 0);

      final first = app.close(force: true);
      final second = app.close();
      await first;

      expect(identical(first, second), isTrue);
      expect(adapter.closeCalls, [true]);
      expect(app.isClosed, isTrue);
      expect(app.container.isClosed, isTrue);
    });

    test('does not close an adapter that never listened', () async {
      final adapter = FakeAdapter();
      final app = await Application.create(appModule, adapter: adapter);

      await app.close();

      expect(adapter.closeCalls, isEmpty);
    });

    test('waits for in-flight requests, new ones get 503', () async {
      final gate = Completer<void>();
      final app = await Application.create(() => waitingModule(gate));
      final inFlight = app.handle(requestFor('GET', '/wait'));

      var closed = false;
      final closing = app.close().then((_) => closed = true);
      await pumpEventQueue();

      expect(closed, isFalse);
      expect((await app.handle(requestFor('GET', '/wait'))).status, 503);

      gate.complete();
      expect((await inFlight).status, 200);
      await closing;
      expect(closed, isTrue);
    });

    test('force does not wait for in-flight requests', () async {
      final gate = Completer<void>();
      final app = await Application.create(() => waitingModule(gate));
      unawaited(app.handle(requestFor('GET', '/wait')));

      await app.close(force: true);

      expect(app.container.isClosed, isTrue);
      gate.complete();
    });
  });

  group('Container.close', () {
    test('is idempotent', () async {
      final container = await Container.create(Module(id: 'app'));

      expect(container.isClosed, isFalse);
      final first = container.close();
      expect(identical(first, container.close()), isTrue);
      expect(container.isClosed, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run from `packages/dartnest`: `dart test test/app/application_test.dart test/app/application_lifecycle_test.dart`
Expected: FAIL at compile time, first error: `Error: Undefined name 'Application'.`

- [ ] **Step 3: Implement**

`packages/dartnest/lib/src/app/http_adapter.dart`:

```dart
import '../http/http_request.dart';
import '../http/http_response.dart';

/// Answers one request; `Application.handle` is the implementation.
typedef RequestHandler = Future<HttpResponse> Function(HttpRequest request);

/// Connects an HTTP server library to an `Application`.
///
/// Implemented outside this package (`dartnest_io`, `dartnest_shelf`).
/// Contract:
///
/// - [listen] is called at most once, by `Application.listen`, and completes
///   when the server accepts connections. For every native request the
///   adapter builds an [HttpRequest] (upper-cased method; `uri` with path and
///   query; every header value, multi-valued headers included; the body as
///   an unread stream; `connectionInfo` when known), awaits `handler`, and
///   writes the response status, every header value and the body (bytes, or
///   the stream chunk by chunk). It writes no body for `HEAD` requests.
///   `handler` answers every request, errors included; if it ever throws,
///   the adapter answers 500 without a body and keeps serving.
/// - [address] is adapter-specific (a host name or an address object); a
///   [port] of 0 asks for an ephemeral port.
/// - [close] stops accepting connections. With `force: false` it completes
///   after the responses in progress are written; with `force: true` it
///   drops open connections. It is idempotent and completes at once if
///   [listen] was never called. `Application.close` calls it before waiting
///   for in-flight requests.
abstract interface class HttpAdapter {
  /// Starts serving [handler] on [address] and [port].
  Future<void> listen(
    RequestHandler handler, {
    required Object address,
    required int port,
  });

  /// Stops serving; see the class documentation.
  Future<void> close({bool force = false});
}
```

`packages/dartnest/lib/src/app/middleware.dart`:

````dart
import '../http/http_request.dart';
import '../http/http_response.dart';
import '../pipeline/interceptor.dart';

/// Application-level HTTP middleware: runs before routing, for every
/// request, in the order of `Application.use`; the first registered is the
/// outermost.
///
/// ```dart
/// app.use((request, next) async {
///   final response = await next();
///   return response.mergeHeaders(HeaderMap.of({'x-powered-by': 'dartnest'}));
/// });
/// ```
typedef Middleware =
    Future<HttpResponse> Function(HttpRequest request, Next<HttpResponse> next);
````

`packages/dartnest/lib/src/app/in_flight_requests.dart`:

```dart
import 'dart:async';

/// Counts requests being handled so that a graceful close can wait for them.
final class InFlightRequests {
  /// Creates an idle counter.
  InFlightRequests();

  int _count = 0;
  Completer<void>? _idle;

  /// Number of requests being handled.
  int get count => _count;

  /// Runs [handle] while counting it as in flight.
  Future<T> track<T>(Future<T> Function() handle) async {
    _count++;
    try {
      return await handle();
    } finally {
      _count--;
      if (_count == 0) {
        _idle?.complete();
        _idle = null;
      }
    }
  }

  /// Completes when no request is in flight.
  Future<void> get idle {
    if (_count == 0) return Future.value();
    return (_idle ??= Completer<void>()).future;
  }
}
```

`packages/dartnest/lib/src/app/application.dart`:

````dart
import 'package:meta/meta.dart';

import '../di/container.dart';
import '../di/errors.dart';
import '../di/module.dart';
import '../di/module_graph.dart';
import '../http/http_exception.dart';
import '../http/http_request.dart';
import '../http/http_response.dart';
import '../pipeline/endpoint.dart';
import '../pipeline/enhancers.dart';
import '../pipeline/http_error_responder.dart';
import '../pipeline/response_serializer.dart';
import '../pipeline/serializer_registry.dart';
import '../routing/router.dart';
import 'application_error.dart';
import 'http_adapter.dart';
import 'in_flight_requests.dart';
import 'middleware.dart';
import 'request_dispatcher.dart';
import 'route_table_builder.dart';

/// A started dartnest application: the container, the route table and the
/// request pipeline. Works without a server through [handle]; serves HTTP
/// through an [HttpAdapter] and [listen].
///
/// ```dart
/// final app = await Application.create(appModule);
/// final response = await app.handle(
///   HttpRequest(method: 'GET', uri: Uri.parse('/users/1')),
/// );
/// await app.close();
/// ```
final class Application {
  Application._({
    required this.container,
    required Router<Endpoint> router,
    required HttpAdapter? adapter,
    required HttpErrorResponder errors,
  }) : _router = router,
       _adapter = adapter,
       _errors = errors,
       _dispatcher = RequestDispatcher(
         serializer: ResponseSerializer(SerializerRegistry()),
         errors: errors,
       );

  /// Builds the module returned by [root], validates the routes, starts the
  /// container, creates the controllers and builds the route table.
  ///
  /// [root] is a function so that the module graph can be rebuilt after a
  /// hot reload. [enhancers] are the application-level components, resolved
  /// through the root module. [debug] adds error details to 500 responses;
  /// [onError] receives unexpected errors (default: print).
  ///
  /// Fails fast: a `RoutingError` before any provider is created, an
  /// `InjectionError` or `ApplicationError` before the application is
  /// returned (the container is closed first).
  static Future<Application> create(
    Module Function() root, {
    HttpAdapter? adapter,
    Enhancers enhancers = Enhancers.none,
    bool debug = false,
    ErrorLogger? onError,
  }) => fromModule(
    root(),
    adapter: adapter,
    enhancers: enhancers,
    debug: debug,
    onError: onError,
  );

  /// Like [create], for a module value.
  static Future<Application> fromModule(
    Module root, {
    HttpAdapter? adapter,
    Enhancers enhancers = Enhancers.none,
    bool debug = false,
    ErrorLogger? onError,
  }) async {
    RouteTableBuilder.validate(ModuleGraph.build(root));
    final container = await Container.create(root);
    try {
      return Application._(
        container: container,
        router: RouteTableBuilder.build(container, enhancers),
        adapter: adapter,
        errors: HttpErrorResponder(
          debug: debug,
          log: onError ?? HttpErrorResponder.printError,
        ),
      );
    } on DartnestError {
      await container.close();
      rethrow;
    }
  }

  /// The started dependency container.
  final Container container;

  /// Converters for result types without `toJson()`.
  SerializerRegistry get serializers => _dispatcher.serializer.registry;

  Router<Endpoint> _router;
  final HttpAdapter? _adapter;
  final HttpErrorResponder _errors;
  final RequestDispatcher _dispatcher;
  final List<Middleware> _middleware = [];
  final InFlightRequests _inFlight = InFlightRequests();
  Future<void>? _closing;
  bool _listening = false;

  /// Whether [close] was called.
  bool get isClosed => _closing != null;

  /// Adds [middleware] after the ones added before (it runs inside them).
  void use(Middleware middleware) => _middleware.add(middleware);

  /// Answers [request]; never throws. After [close] it answers 503.
  ///
  /// The route table is read once per request, so a request keeps the table
  /// it started with even if [replaceRoutes] runs meanwhile.
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
    final chain = List.of(_middleware);
    return _inFlight.track(() => _answer(request, router, chain));
  }

  /// Serves [handle] through the adapter on [address] and [port]; throws
  /// [ApplicationStateError] without an adapter, after [close], or when
  /// already listening.
  Future<void> listen({required int port, Object address = 'localhost'}) {
    final adapter = _adapter;
    if (adapter == null) {
      throw const ApplicationStateError(
        operation: 'listen',
        reason: 'no HttpAdapter was passed to Application.create',
      );
    }
    if (isClosed) {
      throw const ApplicationStateError(
        operation: 'listen',
        reason: 'the application is closed',
      );
    }
    if (_listening) {
      throw const ApplicationStateError(
        operation: 'listen',
        reason: 'the application is already listening',
      );
    }
    _listening = true;
    return adapter.listen(handle, address: address, port: port);
  }

  /// Stops the application: the adapter stops accepting requests, new
  /// [handle] calls answer 503, in-flight requests finish (unless [force]),
  /// then the container closes. Every call returns the same future; [force]
  /// of later calls is ignored.
  Future<void> close({bool force = false}) =>
      _closing ??= _shutdown(force: force);

  /// Replaces the route table in one assignment. Requests already running
  /// finish on the table they started with. For hot reload; not public API.
  @internal
  void replaceRoutes(Router<Endpoint> router) => _router = router;

  Future<void> _shutdown({required bool force}) async {
    final adapter = _adapter;
    if (_listening && adapter != null) await adapter.close(force: force);
    if (!force) await _inFlight.idle;
    await container.close();
  }

  Future<HttpResponse> _answer(
    HttpRequest request,
    Router<Endpoint> router,
    List<Middleware> chain,
  ) async {
    // Request boundary: a throwing middleware still gets an answer.
    try {
      return await _next(request, router, chain, 0);
    } on Object catch (error, stackTrace) {
      return _errors.respond(error, stackTrace);
    }
  }

  Future<HttpResponse> _next(
    HttpRequest request,
    Router<Endpoint> router,
    List<Middleware> chain,
    int index,
  ) {
    if (index == chain.length) return _dispatcher.dispatch(request, router);
    return chain[index](
      request,
      () => _next(request, router, chain, index + 1),
    );
  }
}
````

Apply to `packages/dartnest/lib/src/di/container.dart`:

```diff
--- a/packages/dartnest/lib/src/di/container.dart
+++ b/packages/dartnest/lib/src/di/container.dart
@@ -67,4 +67,14 @@
   /// Injector of the module with [moduleId]; throws `UnknownModuleError`.
   Injector injectorFor(String moduleId) =>
       _injectors[moduleId] ?? (throw UnknownModuleError(moduleId));
+
+  Future<void>? _closing;
+
+  /// Whether [close] was called.
+  bool get isClosed => _closing != null;
+
+  /// Shuts the container down. Idempotent: every call returns the same
+  /// future. Providers have no shutdown hooks yet, so nothing else happens;
+  /// instances stay readable.
+  Future<void> close() => _closing ??= Future<void>.value();
 }
```

Append to the end of `packages/dartnest/lib/src/app/application_error.dart` (after one blank line):

```dart
/// An `Application` method was called in a state that does not allow it.
final class ApplicationStateError extends ApplicationError {
  /// Creates the error.
  const ApplicationStateError({required this.operation, required this.reason});

  /// The rejected method, for example `listen`.
  final String operation;

  /// Why it was rejected.
  final String reason;

  @override
  String get message => 'Cannot $operation: $reason.';
}
```

- [ ] **Step 4: Export the public types**

Add to `packages/dartnest/lib/dartnest.dart`, keeping all `export` lines sorted:

```dart
export 'src/app/application.dart';
export 'src/app/http_adapter.dart';
export 'src/app/middleware.dart';
```

- [ ] **Step 5: Run the tests to verify they pass**

Run from `packages/dartnest`: `dart test test/app/application_test.dart test/app/application_lifecycle_test.dart`
Expected: `+15: All tests passed!`

Run from `packages/dartnest`: `dart test`
Expected: `+201: All tests passed!`

- [ ] **Step 6: Analyze, format and commit**

Run from repo root: `dart analyze && dart format --output=none --set-exit-if-changed packages`
Expected: `No issues found!` and `Formatted N files (0 changed)`.

```bash
git add \
  packages/dartnest/lib/src/app/http_adapter.dart \
  packages/dartnest/lib/src/app/middleware.dart \
  packages/dartnest/lib/src/app/in_flight_requests.dart \
  packages/dartnest/lib/src/app/application.dart \
  packages/dartnest/lib/src/di/container.dart \
  packages/dartnest/lib/src/app/application_error.dart \
  packages/dartnest/test/helpers/fake_adapter.dart \
  packages/dartnest/test/app/application_test.dart \
  packages/dartnest/test/app/application_lifecycle_test.dart \
  packages/dartnest/lib/dartnest.dart
git commit -m "feat(app): add Application with middleware, adapters and graceful close"
```

---

### Task 12: `TestClient`, e2e без сервера і документація

Тестування без сервера: `TestClient(app)` викликає `app.handle` напряму, `TestResponse` дає повністю прочитане тіло (`text`, `json`). Окрема бібліотека `package:dartnest/testing.dart` не тягне `package:test`. E2e-тест проходить увесь стек на застосунку користувачів із Task 10. Наприкінці — розділ README про HTTP і рядок етапу 2 у ROADMAP.

**Files:**
- Create: `packages/dartnest/lib/src/testing/test_response.dart`
- Create: `packages/dartnest/lib/src/testing/test_client.dart`
- Create: `packages/dartnest/lib/testing.dart`
- Modify: `packages/dartnest/README.md`
- Modify: `docs/superpowers/ROADMAP.md`
- Test: `packages/dartnest/test/e2e/users_app_test.dart`

**Interfaces:**
- Consumes: `Application.handle` (Task 11); `HttpRequest`, `RequestBody`, `HeaderMap` (Task 1–2); fixture app (Task 10).
- Produces:
  - `final class TestClient { TestClient(Application app); Future<TestResponse> get/delete(String target, {Map<String, String> headers}); post/put/patch(String target, {Object? json, Map<String, String> headers}); request(String method, String target, {Object? json, String? body, Map<String, String> headers}); send(HttpRequest request); }`
  - `final class TestResponse { int status; HeaderMap headers; Uint8List bytes; String get text; Object? get json; }`
  - Library `package:dartnest/testing.dart` exporting both.

- [ ] **Step 1: Write the failing tests**

`packages/dartnest/test/e2e/users_app_test.dart`:

```dart
// The whole stack through TestClient: routing, guards, pipes, filters,
// serialization and errors, without a server.
import 'package:dartnest/dartnest.dart';
import 'package:dartnest/testing.dart';
import 'package:test/test.dart';

import '../helpers/app_fixtures.dart';

enum Status { active, banned }

/// `GET /status/:status` echoes an enum path parameter.
Module statusModule() => Module(
  id: 'status',
  controllers: [
    Controller<Object>(
      path: '/status',
      create: (i) => Object(),
      routes: [
        Route.get(
          '/:status',
          (c, ctx) async => {
            'status': (await ctx.param<Status>(
              'status',
              pipes: const [EnumPipe(Status.values)],
            )).name,
          },
        ),
      ],
    ),
  ],
);

void main() {
  late Application app; // Set in setUp before every test.
  late TestClient client; // Set in setUp before every test.
  final errors = <Object>[];

  setUp(() async {
    errors.clear();
    app = await Application.create(
      () => Module(id: 'app', imports: [usersModule(), statusModule()]),
      onError: (error, _) => errors.add(error),
    );
    client = TestClient(app);
  });

  tearDown(() => app.close());

  test('lists users with a query limit', () async {
    final response = await client.get('/users?limit=1');

    expect(response.status, 200);
    expect(response.headers['content-type'], startsWith('application/json'));
    expect(response.json, [
      {'id': 1, 'name': 'ann'},
    ]);
  });

  test('finds one user by an int path parameter', () async {
    expect((await client.get('/users/2')).json, {'id': 2, 'name': 'bob'});
  });

  test('a filter maps a domain error to 404', () async {
    final response = await client.get('/users/9');

    expect(response.status, 404);
    expect(response.json, {
      'statusCode': 404,
      'error': 'Not Found',
      'message': 'No user 9',
    });
  });

  test('POST creates a user: 201 with location', () async {
    final response = await client.post(
      '/users',
      json: {'name': 'cid'},
      headers: {'authorization': 'Bearer admin'},
    );

    expect(response.status, 201);
    expect(response.headers['location'], '/users/3');
    expect(response.json, {'id': 3, 'name': 'cid'});
  });

  test('POST without a token is 401 with www-authenticate', () async {
    final response = await client.post('/users', json: {'name': 'cid'});

    expect(response.status, 401);
    expect(response.headers['www-authenticate'], 'Bearer');
  });

  test('POST by a non-admin is 403', () async {
    final response = await client.post(
      '/users',
      json: {'name': 'cid'},
      headers: {'authorization': 'Bearer guest'},
    );

    expect(response.status, 403);
    expect((response.json as Map)['message'], 'Forbidden resource');
  });

  test('malformed JSON and an invalid DTO are 400', () async {
    const admin = {'authorization': 'Bearer admin'};

    final malformed = await client.request(
      'POST',
      '/users',
      body: '{"name":',
      headers: admin,
    );
    final invalid = await client.post(
      '/users',
      json: {'name': ''},
      headers: admin,
    );

    expect(malformed.status, 400);
    expect(invalid.status, 400);
    expect((invalid.json as Map)['message'], contains('"name"'));
  });

  test('an invalid int query is 400', () async {
    final response = await client.get('/users?limit=ten');

    expect(response.status, 400);
    expect((response.json as Map)['message'], contains('limit'));
  });

  test('a wrong method is 405 with allow, an unknown path is 404', () async {
    final wrongMethod = await client.delete('/users');
    final unknown = await client.get('/nope');

    expect(wrongMethod.status, 405);
    expect(wrongMethod.headers['allow'], 'GET, HEAD, POST');
    expect(unknown.status, 404);
    expect(errors, isEmpty);
  });

  test('EnumPipe converts a path parameter by name', () async {
    expect((await client.get('/status/banned')).json, {'status': 'banned'});

    final invalid = await client.get('/status/gone');
    expect(invalid.status, 400);
    expect(
      (invalid.json as Map)['message'],
      'Invalid path parameter "status": expected one of active, banned, '
      'got "gone".',
    );
  });

  test('after close every request is 503', () async {
    await app.close();

    expect((await client.get('/users')).status, 503);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run from `packages/dartnest`: `dart test test/e2e/users_app_test.dart`
Expected: FAIL at compile time, first error: `Error: Error when reading 'lib/testing.dart': No such file or directory`

- [ ] **Step 3: Implement**

`packages/dartnest/lib/src/testing/test_response.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import '../http/header_map.dart';

/// A fully read response returned by `TestClient`.
final class TestResponse {
  /// Creates a response with an already collected body.
  TestResponse({
    required this.status,
    required this.headers,
    required this.bytes,
  });

  /// Status code.
  final int status;

  /// Response headers.
  final HeaderMap headers;

  /// The whole body.
  final Uint8List bytes;

  /// The body decoded as UTF-8 (malformed bytes are replaced).
  String get text => utf8.decode(bytes, allowMalformed: true);

  /// The body decoded as JSON; throws `FormatException` if it is not JSON.
  Object? get json => jsonDecode(text);

  @override
  String toString() => 'TestResponse($status, $text)';
}
```

`packages/dartnest/lib/src/testing/test_client.dart`:

````dart
import 'dart:convert';

import '../app/application.dart';
import '../http/header_map.dart';
import '../http/http_request.dart';
import '../http/request_body.dart';
import 'test_response.dart';

/// Sends requests straight to [Application.handle], without a server.
///
/// ```dart
/// final client = TestClient(app);
/// final response = await client.get('/users/1');
/// expect(response.json, {'id': 1, 'name': 'ann'});
/// ```
final class TestClient {
  /// Creates a client for [app].
  TestClient(this.app);

  /// The application under test.
  final Application app;

  /// Sends `GET` to [target] (a path with an optional query).
  Future<TestResponse> get(
    String target, {
    Map<String, String> headers = const {},
  }) => request('GET', target, headers: headers);

  /// Sends `DELETE` to [target].
  Future<TestResponse> delete(
    String target, {
    Map<String, String> headers = const {},
  }) => request('DELETE', target, headers: headers);

  /// Sends `POST` to [target] with [json] encoded as the body.
  Future<TestResponse> post(
    String target, {
    Object? json,
    Map<String, String> headers = const {},
  }) => request('POST', target, json: json, headers: headers);

  /// Sends `PUT` to [target] with [json] encoded as the body.
  Future<TestResponse> put(
    String target, {
    Object? json,
    Map<String, String> headers = const {},
  }) => request('PUT', target, json: json, headers: headers);

  /// Sends `PATCH` to [target] with [json] encoded as the body.
  Future<TestResponse> patch(
    String target, {
    Object? json,
    Map<String, String> headers = const {},
  }) => request('PATCH', target, json: json, headers: headers);

  /// Sends [method] to [target]. The body is [json] encoded as JSON (with
  /// `content-type: application/json`) or the raw [body] string; passing
  /// both is an `ArgumentError`.
  Future<TestResponse> request(
    String method,
    String target, {
    Object? json,
    String? body,
    Map<String, String> headers = const {},
  }) {
    if (json != null && body != null) {
      throw ArgumentError('Pass either json or body, not both.');
    }
    final requestHeaders = HeaderMap.of(headers);
    final text = json == null ? body : jsonEncode(json);
    if (json != null && requestHeaders['content-type'] == null) {
      requestHeaders.set('content-type', 'application/json');
    }
    return send(
      HttpRequest(
        method: method,
        uri: Uri.parse(target),
        headers: requestHeaders,
        body: text == null ? null : RequestBody.bytes(utf8.encode(text)),
      ),
    );
  }

  /// Sends a prepared [request] and reads the whole response body.
  Future<TestResponse> send(HttpRequest request) async {
    final response = await app.handle(request);
    return TestResponse(
      status: response.status,
      headers: response.headers,
      bytes: await response.body.readAll(),
    );
  }
}
````

`packages/dartnest/lib/testing.dart`:

```dart
/// Helpers for testing dartnest applications without a server.
library;

export 'src/testing/test_client.dart';
export 'src/testing/test_response.dart';
```

- [ ] **Step 4: Document the HTTP layer**

`packages/dartnest/README.md`: replace the last paragraph

```markdown
Annotations, an analyzer-based generator, HTTP adapters and the request
pipeline are planned in later milestones; see the repository's `docs/`
directory for the roadmap.
```

with

````markdown
## HTTP

Controllers are values too. A handler receives its controller instance and an
`ExecutionContext`; arguments are read through the context, so a value that
does not parse becomes `400 Bad Request` on its own. Excerpt; the full
version is `test/helpers/app_fixtures.dart`:

```dart
final usersController = Controller<UsersController>(
  path: '/users',
  create: (i) => UsersController(i.get()),
  enhancers: const Enhancers(filters: [UserMissingFilter()]),
  routes: [
    Route.get('/:id', (c, ctx) async => c.findOne(await ctx.param<int>('id'))),
    Route.post(
      '/',
      (c, ctx) async => c.create(await ctx.bodyAs(CreateUserDto.fromJson)),
      enhancers: const Enhancers(guards: [Use<AuthGuard>(), Use<RolesGuard>()]),
      metadata: const [Roles(['admin'])],
    ),
  ],
);

Module usersModule() => Module(
  id: 'users',
  providers: [
    Provider((i) => UsersService()),
    Provider((i) => AuthGuard()),
    Provider((i) => RolesGuard()),
  ],
  controllers: [usersController],
);

final app = await Application.create(() => Module(id: 'app', imports: [usersModule()]));
final response = await TestClient(app).get('/users/1'); // package:dartnest/testing.dart
await app.close();
```

Rules:

- A request goes through middleware (`app.use`), the router, guards,
  interceptors, the handler and serialization. An exception from a guard,
  interceptor, pipe, the handler or serialization goes to the exception
  filters (route, then controller, then application) and finally to the
  default JSON error response.
- Guards, interceptors, pipes and filters are declared per application,
  controller or route in `Enhancers(...)`, as instances or as `Use<T>()`,
  which resolves `T` from the controller's module (so a guard can inject
  services).
- Routes: static segments, `:name` parameters and a trailing `*`; static wins
  over a parameter, a parameter over `*`. An unknown path is 404, a known path
  with another method is 405 with `allow`; `HEAD` is served by the `GET` route.
- Results: an `HttpResponse` is sent as is, `null` is 204, a `String` is
  `text/plain`, bytes and byte streams are `application/octet-stream`, and
  anything else is JSON via `toJson()` or `app.serializers.register<T>(...)`.
- Errors: throw an `HttpException` (`NotFoundException`, `BadRequestException`,
  ...) to answer `{statusCode, error, message, details?}`. Any other exception
  is a logged 500; `debug: true` adds the error and stack trace to the body.
- `Application.create` takes a function returning the root module; routes are
  checked before any provider is created. `app.close()` can be called any
  number of times: new requests get 503, running ones finish, then the
  container closes.

This package has no server: `app.handle(request)` answers an `HttpRequest`
directly and `TestClient` wraps it for tests. Annotations, an analyzer-based
generator and HTTP adapters (`dart:io`, shelf) are planned in later
milestones; see the repository's `docs/` directory for the roadmap.
````

`docs/superpowers/ROADMAP.md`: in the v1.0 table replace

```markdown
| 2 | **HTTP-конвеєр** | `dartnest` |
```

with

```markdown
| 2 | **HTTP-конвеєр** (план `2026-10-13-dartnest-http-pipeline.md`) | `dartnest` |
```

- [ ] **Step 5: Run the tests to verify they pass**

Run from `packages/dartnest`: `dart test test/e2e/users_app_test.dart`
Expected: `+11: All tests passed!`

Run from `packages/dartnest`: `dart test`
Expected: `+212: All tests passed!`

- [ ] **Step 6: Analyze, format and commit**

Run from repo root: `dart analyze && dart format --output=none --set-exit-if-changed packages`
Expected: `No issues found!` and `Formatted N files (0 changed)`.

```bash
git add \
  packages/dartnest/lib/src/testing/test_response.dart \
  packages/dartnest/lib/src/testing/test_client.dart \
  packages/dartnest/lib/testing.dart \
  packages/dartnest/test/e2e/users_app_test.dart \
  packages/dartnest/README.md \
  docs/superpowers/ROADMAP.md
git commit -m "feat(testing): add TestClient and the end-to-end users app test"
```

---

## Самоперевірка

**Покриття специфікації.**

| Вимога специфікації | Задача |
|---|---|
| 5: `HttpRequest` (method, uri, регістронезалежні headers, body, connectionInfo), `HttpResponse` з фабриками `json/text/bytes/stream/redirect` | 1, 2 |
| 4, крок 3: radix-роутер, static > `:param` > `*`, 404/405 | 3, 4, 10 |
| 4, ExecutionContext: transport (sealed), `switchToHttp`, `controllerType`, `handlerName`, `metadata<T>` (роут перекриває контролер), `items`, `param/query/header/body`, конвертери `String/int/double/bool/num/DateTime/enum-by-name` | 5, 6 |
| 4: `Controller<T>`/`Route` на `HandlerSpec`, `Use<T>` через DI модуля контролера, екземпляр контролера один раз на старті | 7, 8, 10 |
| 4, кроки 5–9: guards app → controller → route (перший `false` → 403), interceptors цибулею, pipes, хендлер, серіалізація, filters route → controller → app → типовий | 8, 9, 10 |
| 4, крок 2: middleware рівня застосунку | 11 |
| 4, серіалізація: `HttpResponse`, `null` → 204, `String`, JSON, `app.serializers.register<T>`, `toJson()`, `SerializationError` | 9, 11 |
| 7: `RoutingError` (`DuplicateRoute`), `HttpException` і підкласи, JSON `{statusCode, error, message}`, 500 у лог, стек у `debug: true` | 1, 3, 4, 9 |
| 5: `HttpAdapter`, `RequestHandler`, `Application.create(..., adapter:)`, `listen`, `close`, `app.handle` без адаптера, `TestClient` | 11, 12 |
| 10.1: `Module Function()`, повторюваний `close()`, атомарна підміна таблиці роутів, контролери створюються заново з `injectorFor` | 7, 10, 11 |
| 8: тести роутера й конвеєра без HTTP, через `app.handle` і `TestClient` | усі |

Поза цим планом (за роадмапом): адаптери й conformance-набір (етап 3), прив'язка параметрів з анотацій (етап 4), `Container.reassemble` (етап 5b), lifecycle-хуки (v1.1).

**Плейсхолдери.** Пошук `TBD`, `TODO`, `...same...`, «similar to Task», «add error handling» — нічого (`...` трапляється лише як spread у Dart і в прикладах README). Кожен крок містить повний код або точний diff.

**Узгодженість типів.** Імена, які задачі використовують одна в одної, звірено з кодом: `Enhancers`, `ResolvedEnhancers.resolve/chain`, `Endpoint`, `Pipeline.run`, `ResponseSerializer.serialize`, `HttpErrorResponder.respond`, `RouteTableBuilder.validate/build`, `RequestDispatcher.dispatch`, `Container.injectorFor/close`, `Application.create/fromModule/handle/use/listen/close/replaceRoutes`, `TestClient.get/post/request/send`.

**Перевірка виконанням.** Код кожної задачі прогнано по черзі в чистій копії поточного `master`: після кожної задачі `dart analyze` — «No issues found!», `dart format` — 0 змінених файлів, увесь набір тестів зелений; кількості тестів у кроках узято з цього прогону. Найбільший файл у `lib/` — `application.dart` (211 рядків), у `test/` — `argument_binding_test.dart` (237 рядків).

**Review Focus.** Кожен пункт закріплено тестом із коментарем `// Review Focus N` у задачі, вказаній вище: 1 → Task 9, 2 → Task 6, 3 → Task 4, 4 → Task 10, 5 → Task 11.
