# HTTP APIs, hooks and errors

`grund_http` is the HTTP layer. An application imports `HttpModule` and a
module that provides the adapter (`IoAdapterModule`, `ShelfAdapterModule`);
every `HttpApi` bound in the module graph is then served. Everything below
is the explicit API; the annotations in
[annotations-and-codegen.md](annotations-and-codegen.md) generate exactly
these classes.

## APIs and routes

An `HttpApi` is a class with a `path` prefix and a list of `Route`s. It
gets the injector of the module that declares it, and its handlers close
over the services they need:

```dart
final class UsersApi extends HttpApi {
  UsersApi(super.injector, this._users);

  final UsersService _users;

  @override
  String get path => '/users';

  @override
  List<Route> get routes => [
    Route.get('/', (c) => _users.list(limit: c.query.integerOrNull('limit'))),
    Route.get('/:id', (c) => _users.find(c.path.integer('id'))),
    Route.post(
      '/',
      (c) async => _users.create(await c.body(CreateUser.fromJson)),
      status: 201,
    ),
  ];
}
```

Bind it as a singleton in a module, like any other provider:

```dart
Singleton<UsersApi>(
  (i) => UsersApi(i, i<UsersService>()),
  dependsOn: const [Key<UsersService>()],
),
```

- **Paths** are static segments, `:name` parameters and a trailing `*`. A
  static segment wins over a parameter, a parameter over `*`. Two routes
  with the same method and path pattern are a `DuplicateRouteError` when
  the server starts, before it listens.
- **404 and 405.** An unknown path is 404 (`route_not_found`); a known path
  with another method is 405 with an `allow` header. `HEAD` is served by
  the `GET` route. A malformed percent-encoding in the path is 400.
- **`Route.get`, `post`, `put`, `patch`, `delete`** take `status:` (the
  response status; it wins over the default) and `use:` (hooks of this
  route only).
- **Return `routes` as a new list on every call.** The server reads it again
  after a hot reload, so the edited handlers are served.

## The context: `HttpCtx`

A handler receives an `HttpCtx` (`c`) that lives for one request:

| Member | What it gives |
| --- | --- |
| `c.path`, `c.query`, `c.headers`, `c.cookies` | typed `Params` readers |
| `await c.body(T.fromJson)` | the JSON object body as a `T` |
| `await c.bodyList(T.fromJson)` | a JSON array of objects, as `List<T>` |
| `await c.form()` | an `application/x-www-form-urlencoded` body, as `Params` |
| `await c.bytes()` | the raw body |
| `c.request` | the `HttpRequest` (method, `uri`, headers, body stream) |
| `c.response` | the `ResponseHead` being built: `status` and `headers` |
| `c<T>()`, `c.maybe<T>()` | a value of the call scope: a `Scoped` binding, a singleton, or what a hook `set` |
| `c.set<T>(value)` | makes `value` resolvable as `T` for the rest of the request |
| `c.cancel` | fires when the server no longer waits for the request |

`Params` readers validate as they read. `c.query.integer('limit', min: 1,
max: 100)` is required and bounded; `integerOrNull` returns `null` when the
parameter is absent. The same readers exist for `string` (with `minLength`,
`maxLength`, `pattern` and `oneOf`), `decimal`, `boolean`, `dateTime`, `uri` and
`enumOf`, each with an `...OrNull` twin, and `all(name)` returns every value
of a repeated parameter. An absent required value is a 400
(`parameter_missing`), a value of the wrong type or violating a pattern is a
400 (`parameter_invalid`), a number or length outside its bounds is a 400
(`parameter_out_of_range`); each names the location and parameter in the
`pointer` (`/query/limit`). A body that is not JSON, not an object, or that
`fromJson` rejects is a 400 (`body_invalid`, pointer `/body`); one over
`HttpConfig.maxBodyBytes` (1 MiB by default) is a 413 (`body_too_large`).
`c.form()` reads the fields of a form post with the same readers (a problem
points at `/body/<name>`); a malformed escape or UTF-8 sequence is a 400
`body_invalid`. It does not check the `content-type`.

## Results

What a handler returns is turned into the response:

| Result | Response |
| --- | --- |
| `null` (or a `void` method) | 204, empty |
| a `Map`, `List`, number, `bool` or an object with `toJson()` | JSON |
| a `String` | `text/plain; charset=utf-8` |
| a `Uint8List` or a `Stream<List<int>>` | `application/octet-stream` |
| an `HttpResponse` | sent as it is |

`c.response.status = 202` or `c.response.headers.set('location', ...)`
change the status and headers of a serialized result; the route's `status:`
wins over both. A type you do not own gets a JSON form from a codec:
`HttpModule(codecs: [ResponseCodec<Money>((m) => {'cents': m.cents})])`
(write the type argument). A value that cannot be encoded is a
`SerializationError`, answered as a 500.

## Hooks

An `HttpHook` runs around a route handler. One type replaces the guards,
interceptors, pipes and exception filters of other frameworks; all three
methods are optional:

```dart
final class ApiKeyHook extends HttpHook {
  ApiKeyHook(this.config);
  final AppConfig config;

  @override
  void before(HttpCtx c) {
    final role = config.apiKeys[c.headers.stringOrNull('x-api-key')];
    if (role == null) {
      throw const UnauthorizedException(
        message: 'Send a valid x-api-key.',
        code: 'api_key_invalid',
      );
    }
    c.set<CurrentUser>(CurrentUser(role));   // for the hooks and the handler after it
  }
}
```

- `before(c)` runs before the handler. Throw an `HttpException` to refuse
  the request, or hand a value on with `c.set<T>(value)`.
- `after(c, result)` runs after the handler returned, with its result; it
  can change `c.response`.
- `onError(c, error, stack)` is offered every failure of the chain and may
  return an `HttpResponse` to answer instead; `null` passes it on.

**Order.** Hooks are listed outermost first: the global ones
(`HttpModule(use:)`), then those of the API (`HttpApi.use`), then those of
the route (`Route.use`). `before` runs outer to inner, `after` and
`onError` inner to outer. A failure in any `before` ends the chain: no later
`before`, no handler and no `after` runs; the error goes to the `onError`
methods, which are asked even on hooks whose `before` did not run (do not
rely on state `before` sets up). When nobody answers, the error becomes a
problem response. The serializer runs after the chain, so a
`SerializationError` is answered as a 500 without going through `onError`.

**Naming a hook: `HookRef`.** The explicit API lists `HookRef`s:

```dart
HttpModule(use: const [HookRef<TimingHook>.instance(TimingHook())])

@override
List<HookRef<HttpHook>> get use => const [HookRef<ApiKeyHook>.type()];

Route.post('/', handler, use: const [
  HookRef<RolesHook>.instance(RolesHook(Role.editor)),
]);
```

`HookRef<T>.type()` resolves `T` from the module graph (the hook is a
provider of the API's module, so it may inject services); `.instance(hook)`
is a `const` instance, for a hook with parameters, and reads services with
`c<T>()`. The type argument is needed for `.type()`, and for `.instance`
when the list is typed `List<HookRef<HttpHook>>` (without it the context
infers `HttpHook`). In annotations the wrapper is not needed:
`@Api('/tasks', use: [ApiKeyHook, TaskNotFoundHook])` and
`@Post('/', use: [RolesHook(Role.editor)])` generate these `HookRef`s;
`HookRef` constants are still accepted there.

### Errors in hooks: what happens to the original stack trace

A hook can turn a domain error into a response. The example's
`TaskNotFoundHook` (a hook of the `TasksApi`) answers the service's
`TaskNotFound` with a 404, so the service stays free of HTTP:

```dart
@override
HttpResponse? onError(HttpCtx c, Object error, StackTrace stack) {
  if (error is! TaskNotFound) return null;
  throw NotFoundException(
    message: 'No task ${error.id}.',
    code: 'task_not_found',
    cause: error,
    causeStackTrace: stack,
  );
}
```

Does throwing from `onError` lose the original stack trace? It replaces the
error that the remaining hooks, and then the caller, see; the original is
kept only if the exception you throw carries it. Every `HttpException` takes
`cause:` and `causeStackTrace:`, so pass them as above. Without them the
replaced error survives only in a `FINE` record of the hook chain on
`grund.http` (the hook's type and both error types, with the replaced error
and its stack trace). With them:

- the problem response never shows the cause to the client, also with
  `HttpConfig(debug: true)`;
- the responder logs the exception with its cause and `causeStackTrace` on
  `grund.http`: `SEVERE` when the status is 500 or more, `FINE` below. An
  `HttpException` without a cause is a deliberate response and is not
  logged.

## Errors

An `HttpException` thrown from a handler or a hook is answered with its
status as `application/problem+json` (RFC 9457):

```dart
throw NotFoundException(message: 'No user 7.', code: 'user_not_found');
```

```json
{"type": "about:blank", "title": "Not Found", "status": 404,
 "detail": "No user 7.", "instance": "/users/7", "code": "user_not_found"}
```

`BadRequestException`, `UnauthorizedException`, `ForbiddenException`,
`NotFoundException`, `MethodNotAllowedException`, `PayloadTooLargeException`,
`UnprocessableContentException` and `ServiceUnavailableException` are
built in; extend `HttpException` for another status. `HttpException` takes a
`message` (the `detail`), a stable machine-readable `code` (clients switch
on it, never on the message), a `pointer` (a JSON pointer to the bad input,
sent as an entry of `errors`), `details` (a JSON value; a list of
`ProblemError`s is sent as `errors`), `headers` and the `cause` above. The
built-in subclasses take a subset: `pointer` only on `BadRequestException`
and `UnprocessableContentException`, `headers` only on
`UnauthorizedException` (`MethodNotAllowedException` sets `allow` from its
list of allowed methods, and it takes no `details`); the others take
`message`, `code`, `details` and `cause`.

Anything else that is thrown is a 500 with the detail `Internal server
error`. It is logged as `SEVERE` on `grund.http` (message `Unhandled
error`) with the error and its stack trace; the response shows neither,
unless `HttpConfig(debug: true)` (never in production). See
[logging.md](logging.md) for where those records go, and what a log listener
that throws does.

## Middleware

Middleware wraps the whole request, before routing: request ids, CORS,
compression, rate limits. It sees every request, also the ones that match no
route, and returns the response:

```dart
final class RequestIdMiddleware implements Middleware {
  int _count = 0;

  @override
  Future<HttpResponse> handle(HttpRequest request, Next next) async {
    final id = request.headers['x-request-id'] ?? 'req-${++_count}';
    final response = await next();
    return response.mergeHeaders(HeaderMap.of({'x-request-id': id}));
  }
}
```

Register it with `HttpModule(middleware: [RequestIdMiddleware()])`, outermost
first. It knows nothing about the route or the call scope; use a hook for
that. Hooks do not see middleware either: a failure in middleware is
answered as a problem without going through `onError`.

## Putting it together

```dart
final class AppModule extends Module {
  const AppModule();

  @override
  List<Module> get imports => [
    const IoAdapterModule(),
    HttpModule(
      use: const [HookRef<TimingHook>.instance(TimingHook())],
      middleware: [RequestIdMiddleware()],
      config: const HttpConfig(port: 8080, accessLog: true),
    ),
    const UsersModule(),
  ];
}
```

`HttpConfig` has `address`, `port` (0 for an ephemeral one), `maxBodyBytes`,
`debug` and `accessLog`. `example/lib/src/server/serving_module.dart` is a
complete example; the two hook files that matter are
`example/lib/src/auth/roles_hook.dart` (a parameterized instance hook) and
`example/lib/src/tasks/task_not_found_hook.dart` (error translation).

## Coming from NestJS

| NestJS | grund |
| --- | --- |
| Guard (`CanActivate`) | `HttpHook.before` that throws |
| Interceptor | `HttpHook.before` and `after` (a `before` that records, an `after` that stamps) |
| Pipe | `Params` readers with bounds, or `@Range`/`@Length`/`@Pattern`/`@OneOf` |
| Exception filter | `HttpHook.onError` |
| Middleware | `Middleware` |
| `@Controller` | `HttpApi` (`@Api`) |
