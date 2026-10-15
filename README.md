# grund

A NestJS-style modular backend framework for Dart, without `dart:mirrors`.

Modules, providers, hooks (guards, interceptors and exception filters in
one type), middleware and APIs work the way they do in NestJS, but they are
plain Dart values: a module is a class with `imports`, `bindings` and
`exports`, a provider is a typed factory, a route is a closure. The
container checks the whole module graph before it creates anything, so a
missing or circular dependency fails at startup with the chain that led to
it, never in the middle of a request. Annotations are an optional layer on
top: a generator turns them into the same classes, checks the graph at
build time and writes one ordinary Dart file next to each annotated
library.

- **No reflection, no magic at runtime.** The explicit API works in tests,
  scripts and AOT builds without any code generation.
- **Errors before the first request.** Typed `GrundError`s with the
  resolution chain; with annotations, `path:line:column` diagnostics.
- **Typed keys** (`Key<Clock>()`, `Key<Clock>('primary')`) instead of strings.
- **Hot reload that keeps state.** `grund dev` reloads code changes into
  the running server; singletons keep their instances, routes are rebuilt.
- **Two servers, one contract.** `dart:io` or shelf, both checked by the
  same conformance suite on real sockets.

## Quick start

### With annotations

```sh
dart pub global activate grund_cli
grund init my_app
cd my_app
dart pub get
grund gen          # writes lib/src/app_module.g.dart and lib/src/hello.g.dart
grund dev          # runs bin/main.dart and hot reloads it
curl 'http://localhost:8080/hello?name=you'    # {"message":"Hello, you!"}
```

`init` writes this API (`lib/src/hello.dart`):

```dart
import 'package:grund/annotations.dart';
import 'package:grund_http/annotations.dart';
import 'package:grund_http/grund_http.dart' as http;

part 'hello.g.dart';

@Injectable()
final class HelloService {
  Map<String, String> greet(String name) => {'message': 'Hello, $name!'};
}

@Api('/hello')
final class HelloApi {
  HelloApi(this.service);
  final HelloService service;

  @Get('/')
  Map<String, String> hello(@Query() String? name) =>
      service.greet(name ?? 'world');
}
```

and this root module (`lib/src/app_module.dart`):

```dart
import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;
import 'package:grund_http/grund_http.dart';
import 'package:grund_io/grund_io.dart';

import 'app_module.g.dart';
import 'hello.dart';

@Module(
  imports: [HttpModule(), IoAdapterModule()],
  providers: [HelloService, HelloApi],
)
final class AppModule extends grund.Module with $AppModule {
  const AppModule();
}
```

The annotations are in `package:grund/annotations.dart` and
`package:grund_http/annotations.dart`, libraries of their own because
`Module`, `Pattern` and `Cookie` would clash with the explicit API and with
`dart:core`; the explicit API is imported with a prefix (`as grund`,
`as http`); in a file that uses `@Pattern` or `@Cookie`, a `dart:io` or
`dart:core` name that clashes is hidden or imported with a prefix
(`import 'dart:io' hide Cookie;`). For every library with annotations the generator writes one
file next to it, `X.g.dart`: the `$AppModule` mixin for a `@Module`, the
`part` with `HelloRoutes extends http.HttpApi` for an `@Api`. A library
declares one of the two. Hooks go in `use:`, by type or by instance:
`@Api('/tasks', use: [ApiKeyHook, RolesHook(Role.editor)])`. The generated
files are committed; they change only when the annotations do.

### Without code generation

```yaml
# pubspec.yaml
dependencies:
  grund: ^0.1.0
  grund_http: ^0.1.0
  grund_io: ^0.1.0
```

```dart
import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_io/grund_io.dart';

final class Greeter {
  Map<String, String> greet(String name) => {'message': 'Hello, $name!'};
}

final class HelloRoutes extends HttpApi {
  HelloRoutes(super.injector, this._greeter);

  final Greeter _greeter;

  @override
  String get path => '/hello';

  @override
  List<Route> get routes => [
    Route.get(
      '/',
      (c) => _greeter.greet(c.query.stringOrNull('name') ?? 'world'),
    ),
  ];
}

final class AppModule extends Module {
  const AppModule();

  @override
  List<Module> get imports => const [HttpModule(), IoAdapterModule()];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<Greeter>((_) => Greeter(), dependsOn: const []),
    Singleton<HelloRoutes>(
      (i) => HelloRoutes(i, i<Greeter>()),
      dependsOn: const [Key<Greeter>()],
    ),
  ];
}

Future<void> main() => App(root: const AppModule()).run();
```

The two styles mix freely: a generated module can import a hand-written one
and the other way round.

## Packages

| Package | What it is |
| --- | --- |
| [`grund`](packages/grund) | The core: modules, typed DI, call scopes, runners, logging, the DI annotations (`package:grund/annotations.dart`), `TestApp`. No HTTP, no `dart:io` server. |
| [`grund_http`](packages/grund_http) | The HTTP layer: `HttpModule`, `HttpApi`, routes, hooks, middleware, RFC 9457 problem responses, the adapter contract and the HTTP annotations (`package:grund_http/annotations.dart`). |
| [`grund_io`](packages/grund_io) | `IoAdapterModule`: serves an application on a `dart:io` `HttpServer`. |
| [`grund_shelf`](packages/grund_shelf) | `ShelfAdapterModule`, and `shelfHandler(app)` to mount an application in a shelf pipeline. |
| [`grund_generator`](packages/grund_generator) | Turns `@Module`, `@Injectable`, `@Provides` and `Bind` into code and validates the module graph. Knows no HTTP; a library for the drivers below. |
| [`grund_http_generator`](packages/grund_http_generator) | The `@Api` part of the generator: routes, parameters, hooks, validators, bodies. |
| [`grund_cli`](packages/grund_cli) | The `grund` command: `gen`, `gen --watch`, `dev` (hot reload), `init`. |
| [`grund_build`](packages/grund_build) | The same generation as a build_runner builder. |

Every package README lists the exact rules of that package.

## Coming from NestJS

| NestJS | grund (explicit API) | grund (annotations) |
| --- | --- | --- |
| `@Module({imports, providers, controllers, exports})` | `class M extends Module` with `imports`, `bindings`, `exports` | `@Module(imports: ..., providers: ...)` on a class |
| `@Global()` | `bool get global => true` | `@Module(global: true)` |
| `@Injectable()` class | `Singleton<T>((i) => T(i<Dep>()), dependsOn: [...])` | `@Injectable()` |
| `{provide: TOKEN, useValue: v}` | a `Singleton` of a named `Key` | `@Provides` method of the module |
| `{provide: Abstract, useClass: Impl}` | `Singleton<Abstract>((i) => Impl())` | `Bind<Abstract, Impl>()` |
| `useFactory` with `async`, `forRootAsync` | `Singleton` with an async factory; a function returning a `Module` | a function returning a `Module`, in `imports` |
| `@Inject(TOKEN)` | `i<T>()`, `Key<T>('name')` | `@Named('name')` |
| `@Controller('users')`, `@Get(':id')` | `HttpApi` with `path` and `Route.get('/:id', ...)` | `@Api('/users')`, `@Get('/:id')` |
| `@Param`, `@Query`, `@Body`, `@Headers` | `c.path`, `c.query`, `await c.body(T.fromJson)`, `c.headers` | `@Path`, `@Query`, `@Body`, `@Header` |
| `CanActivate`, `NestInterceptor`, `ExceptionFilter` | `HttpHook` (`before`, `after`, `onError`), `HookRef` | `use: [MyHook, RolesHook(Role.editor)]` |
| `PipeTransform`, `ValidationPipe` | `Params` readers with bounds | `@Range`, `@Length`, `@Pattern`, `@OneOf` |
| `NestMiddleware` | `Middleware`, `HttpModule(middleware: [...])` | the same |
| `NotFoundException`, `HttpException` | the same names, answered as `application/problem+json` | the same |
| `NestFactory.create(AppModule)` | `App(root: const AppModule()).run()` | the same |
| platform-express / platform-fastify | `grund_io` / `grund_shelf` | the same |
| `Test.createTestingModule`, supertest | `TestApp`, overrides | the same |
| `nest start --watch` | `grund dev` (reload, not restart) | the same |
| `nest new` | `grund init` | the same |

Not in 0.1.0: request-scoped providers beyond call scopes, WebSockets, SSE,
GraphQL, microservice transports, OpenAPI generation. See
[docs/faq.md](docs/faq.md).

## Documentation

- [Getting started](docs/getting-started.md)
- [Modules and dependency injection](docs/modules-and-di.md)
- [HTTP APIs, hooks and errors](docs/http-and-hooks.md)
- [Annotations and code generation](docs/annotations-and-codegen.md)
- [Adapters: dart:io and shelf](docs/adapters.md)
- [Dev mode and hot reload](docs/dev-mode.md)
- [build_runner](docs/build-runner.md)
- [Logging](docs/logging.md)
- [Testing](docs/testing.md)
- [FAQ and known limitations](docs/faq.md)

[`example/`](example) is one application, a small tasks API, written in
both styles and tested end to end on both adapters.

## Requirements

Dart SDK 3.8 or later. Developed and tested on Linux; see
[docs/faq.md](docs/faq.md) for macOS and Windows.

## Development

This repository is a pub workspace: `dart pub get` at the root resolves
every package and the example. `CLAUDE.md` lists the commands that CI runs;
`docs/RELEASING.md` describes a release.

## License

MIT, see [LICENSE](LICENSE).
