# Controllers and the request pipeline

## Controllers and routes

A controller is a class with handler methods; `Controller<T>` describes how
to create it and which routes call which method:

```dart
Controller<UsersController>(
  path: '/users',
  create: (i) => UsersController(i.get()),
  routes: [
    Route.get('', (c, ctx) async => c.list(await ctx.query<int?>('limit'))),
    Route.get('/:id', (c, ctx) async => c.find(await ctx.param<int>('id'))),
    Route.post('', (c, ctx) async => c.create(await ctx.bodyAs(CreateUser.fromJson))),
  ],
)
```

The controller instance is created once, at startup, like a provider of
its module, so it can inject everything that module sees.

- **Paths**: static segments, `:name` parameters and a trailing `*`. A
  static segment wins over a parameter, a parameter over `*`.
- **404 and 405**: an unknown path is 404; a known path with another
  method is 405 with an `allow` header. `HEAD` is served by the `GET` route.
- **Arguments** come from the `ExecutionContext`: `param<T>`, `query<T>`
  (nullable `T` for an optional one), `header`, `bodyAs(fromJson)`, `body`
  for the raw stream. `T` is `String`, `int`, `double`, `num`, `bool` or
  `DateTime`; an enum needs a pipe:
  `ctx.query<Status>('status', pipes: [EnumPipe(Status.values)])` (the
  generator adds it for you). A value that does not convert is a 400 that
  names the parameter.
- **Results**: a `Map`, a `List` or an object with `toJson()` is JSON;
  a `String` is `text/plain`; `null` (or a `void` method) is 204; a
  `Uint8List` or a `Stream<List<int>>` is `application/octet-stream`; an
  `HttpResponse` is sent as it is. `app.serializers.register<T>(...)` adds a
  JSON conversion for a type you do not own.
- **Status and headers**: return an `HttpResponse`, or set them on
  `ctx.switchToHttp().response` and return the body, as the example's
  `TasksController.create` does for `201` and `location`.

## Errors

Throw an `HttpException` to answer with its status:

```dart
throw NotFoundException(message: 'No user $id.');
// 404 {"statusCode": 404, "error": "Not Found", "message": "No user 7."}
```

`BadRequestException`, `UnauthorizedException`, `ForbiddenException`,
`NotFoundException`, `MethodNotAllowedException` and
`ServiceUnavailableException` are built in; extend `HttpException` for
another status. Each takes an optional `details` value (a JSON value, for
example the list of invalid fields). Any other exception is a 500 with
the message `Internal server error`; it goes to `Application.create(onError:)`
(by default printed). `Application.create(debug: true)` puts the error text
and the stack trace into the 500 body; never enable it in production.

## The pipeline

```text
request
  -> middleware (app.use, outermost first)
  -> router (404 / 405)
  -> guards          (application, controller, route)
  -> interceptors    (application, controller, route; each wraps the rest)
  -> pipes           (inside ctx.param / query / bodyAs, per argument)
  -> handler
  -> serialization
exceptions from guards .. serialization
  -> exception filters (route, controller, application) -> default JSON error
```

Components are declared in `Enhancers` at three levels:

```dart
Application.create(appModule, enhancers: const Enhancers(interceptors: [Use<TimingInterceptor>()]));
Controller<T>(..., enhancers: const Enhancers(guards: [Use<ApiKeyGuard>()]));
Route.post('', ..., enhancers: const Enhancers(guards: [Use<RolesGuard>()]));
```

`Use<T>()` resolves `T` as a provider of the controller's module (for the
application level, of the root module), so a guard can inject services. An
instance (`guards: [AllowAll()]`) is used as it is.

| Component | Interface | Example file |
| --- | --- | --- |
| Guard | `FutureOr<bool> canActivate(ExecutionContext)`; `false` is 403, or throw for another status | `example/lib/src/auth/api_key_guard.dart` |
| Route metadata | a `const` subclass of `RouteMetadata`, read with `ctx.metadata<T>()`; the route's wins over the controller's | `example/lib/src/auth/roles.dart`, `roles_guard.dart` |
| Interceptor | `FutureOr<Object?> intercept(ExecutionContext, Next<Object?> next)`; call `next()` at most once | `example/lib/src/common/timing_interceptor.dart` |
| Pipe | `FutureOr<O> transform(I value, ArgumentMeta meta)`; throw `BadRequestException` to reject | `example/lib/src/common/trim_strings_pipe.dart` |
| Exception filter | `extends ExceptionFilter<E>`, `handle(E error, ExecutionContext)`; return a result or throw an `HttpException` | `example/lib/src/tasks/task_not_found_filter.dart` |
| Middleware | `Future<HttpResponse> Function(HttpRequest, Next<HttpResponse>)`, registered with `app.use` | `example/lib/src/common/request_id_middleware.dart` |

Some differences from NestJS:

- Pipes run when the handler reads an argument, on the raw value (a
  `String` for parameters, the decoded JSON for the body), before the
  built-in conversion. A pipe in `Enhancers` sees every argument, so it
  should accept `Object?` and pass through what it does not handle.
- Guards and filters do not see middleware: middleware runs outside the
  router, so an exception thrown in middleware goes straight to the default
  error response.
- A guard can pass data to the handler through `ctx.items`, a map that
  lives for one request (the example's `ApiKeyGuard` stores the caller's
  role there).

## The same with annotations

```dart
@Controller('/tasks')
@UseGuards([ApiKeyGuard])
@UsePipes([TrimStringsPipe])
@UseFilters([TaskNotFoundFilter])
final class TasksController {
  TasksController(this.service);
  final TasksService service;

  @Get()
  List<Task> list(@Query('done') bool? done) => service.list(done: done);

  @Post()
  @UseGuards([RolesGuard])
  @Roles([Role.editor])
  Task create(@Body() CreateTaskDto dto, ExecutionContext context) { ... }
}
```

Each type in `@UseGuards` and its siblings becomes `Use<T>()`, so it must be
a provider visible to the controller's module (the example's `TasksModule`
lists `TrimStringsPipe` and `TaskNotFoundFilter`, and imports `AuthModule`
for the guards). The complete rules for handler parameters are in the
[`dartnest_annotations` README](../packages/dartnest_annotations/README.md).
