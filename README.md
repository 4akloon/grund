# dartnest

A NestJS-style modular backend framework for Dart, without `dart:mirrors`.

Modules, providers, controllers, guards, interceptors, pipes and exception
filters work the way they do in NestJS, but they are plain Dart values: a
module is a `Module(...)`, a provider is a typed factory, a route is a
closure. The container checks the whole module graph before it creates
anything, so a missing or circular dependency fails at startup with the
chain that led to it, never in the middle of a request. Annotations are an
optional layer on top: a generator turns them into the same values, checks
the graph at build time and writes one ordinary Dart file per package.

- **No reflection, no magic at runtime.** The explicit API works in tests,
  scripts and AOT builds without any code generation.
- **Errors before the first request.** Typed `InjectionError`s with the
  resolution chain; with annotations, `path:line:column` diagnostics.
- **Typed tokens** (`Token<String>('db.url')`) instead of strings.
- **Hot reload that keeps state.** `dartnest dev` reloads code changes into
  the running server; providers keep their instances, routes are rebuilt.
- **Two servers, one contract.** `dart:io` or shelf, both checked by the
  same conformance suite on real sockets.

## Quick start

### With annotations

```sh
dart pub global activate dartnest_cli
dartnest init my_app
cd my_app
dart pub get
dartnest gen          # writes lib/my_app.dartnest.dart
dartnest dev          # runs bin/main.dart and hot reloads it
curl 'http://localhost:8080/hello?name=you'    # {"message":"Hello, you!"}
```

`init` writes this controller (`lib/src/hello.dart`):

```dart
@Controller('/hello')
final class HelloController {
  HelloController(this.service);
  final HelloService service;

  @Get()
  Map<String, String> hello(@Query('name') String? name) =>
      service.greet(name ?? 'world');
}

@Module(id: 'app', providers: [HelloService], controllers: [HelloController])
final class AppModule {}
```

and the generator turns `AppModule` into `Module appModule()`, which
`bin/main.dart` passes to `Application.create`.

### Without code generation

```yaml
# pubspec.yaml
dependencies:
  dartnest: ^0.1.0
  dartnest_io: ^0.1.0
```

```dart
import 'package:dartnest/dartnest.dart';
import 'package:dartnest_io/dartnest_io.dart';

final class Greeter {
  Map<String, String> greet(String name) => {'message': 'Hello, $name!'};
}

final class HelloController {
  HelloController(this.greeter);
  final Greeter greeter;

  Map<String, String> hello(String? name) => greeter.greet(name ?? 'world');
}

Module appModule() => Module(
  id: 'app',
  providers: [Provider((i) => Greeter())],
  controllers: [
    Controller<HelloController>(
      path: '/hello',
      create: (i) => HelloController(i.get()),
      routes: [
        Route.get(
          '',
          (c, ctx) async => c.hello(await ctx.query<String?>('name')),
        ),
      ],
    ),
  ],
);

Future<void> main() async {
  final app = await Application.create(appModule, adapter: IoAdapter());
  await app.listen(port: 8080);
  print('Listening on http://localhost:8080/hello');
}
```

The two styles mix freely: a generated module can import a hand-written one
and the other way round.

## Packages

| Package | What it is |
| --- | --- |
| [`dartnest`](packages/dartnest) | The core: modules, DI, controllers, the request pipeline, `TestClient`, the hot reload hooks. No `dart:io`. |
| [`dartnest_io`](packages/dartnest_io) | `IoAdapter`: serves an application on a `dart:io` `HttpServer`. |
| [`dartnest_shelf`](packages/dartnest_shelf) | `ShelfAdapter`, and `shelfHandler(app)` to mount an application in a shelf pipeline. |
| [`dartnest_annotations`](packages/dartnest_annotations) | `@Module`, `@Injectable`, `@Controller`, `@Get`, ... No dependencies. |
| [`dartnest_generator`](packages/dartnest_generator) | Turns the annotations into code and validates the module graph. A library for the drivers below. |
| [`dartnest_cli`](packages/dartnest_cli) | The `dartnest` command: `gen`, `gen --watch`, `dev` (hot reload), `init`. |
| [`dartnest_build`](packages/dartnest_build) | The same generator as a build_runner builder. |

Every package README lists the exact rules of that package.

## Coming from NestJS

| NestJS | dartnest (explicit API) | dartnest (annotations) |
| --- | --- | --- |
| `@Module({imports, providers, controllers, exports})` | `Module(id: ..., imports: ..., ...)` | `@Module(id: ..., ...)` on a class |
| `@Global()` | `Module(global: true)` | `@Module(global: true)` |
| `@Injectable()` class | `Provider((i) => Service(i.get()))` | `@Injectable()` |
| `{provide: TOKEN, useValue: v}` | `Provider.value(v, token: Token<T>('name'))` | `Value(v, token: ...)` |
| `{provide: Abstract, useClass: Impl}` | `Provider<Abstract>((i) => Impl())` | `Bind<Abstract, Impl>()` |
| `useFactory` with `async`, `forRootAsync` | `Provider.async((i) async => ...)` | a function returning a `Module`, in `imports` |
| `@Inject(TOKEN)` | `i.get(token)` | `@Inject(token)` |
| `@Controller('users')`, `@Get(':id')` | `Controller<T>(path: '/users', routes: [Route.get('/:id', ...)])` | `@Controller('/users')`, `@Get('/:id')` |
| `@Param`, `@Query`, `@Body`, `@Headers` | `ctx.param<T>`, `ctx.query<T>`, `ctx.bodyAs`, `ctx.header` | `@Param`, `@Query`, `@Body`, `@Header` |
| `CanActivate`, `@UseGuards` | `Guard`, `Enhancers(guards: [...])` | `@UseGuards([...])` |
| `NestInterceptor`, `PipeTransform` | `Interceptor`, `Pipe<I, O>` | `@UseInterceptors`, `@UsePipes` |
| `ExceptionFilter`, `@Catch(E)` | `ExceptionFilter<E>` | `@UseFilters([...])` |
| `SetMetadata` + `Reflector` | a `RouteMetadata` subclass + `ctx.metadata<T>()` | the same class as an annotation |
| `NestMiddleware`, `app.use` | `app.use(middleware)` | the same |
| `NotFoundException`, `HttpException` | the same names | the same |
| `NestFactory.create(AppModule)` | `Application.create(appModule, adapter: IoAdapter())` | the same, with the generated `appModule` |
| platform-express / platform-fastify | `dartnest_io` / `dartnest_shelf` | the same |
| `Test.createTestingModule`, supertest | `Container.create(testModule)`, `TestClient(app)` | the same |
| `nest start --watch` | `dartnest dev` (reload, not restart) | the same |
| `nest new` | `dartnest init` | the same |

Not in 0.1.0: request-scoped providers, lifecycle hooks (`OnModuleInit`),
WebSockets, SSE, GraphQL, microservice transports, OpenAPI generation. See
[docs/faq.md](docs/faq.md).

## Documentation

- [Getting started](docs/getting-started.md)
- [Modules and dependency injection](docs/modules-and-di.md)
- [Controllers and the request pipeline](docs/controllers-and-pipeline.md)
- [Annotations and code generation](docs/annotations-and-codegen.md)
- [Adapters: dart:io and shelf](docs/adapters.md)
- [Dev mode and hot reload](docs/dev-mode.md)
- [build_runner](docs/build-runner.md)
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
