# grund_http

The HTTP layer of grund: request and response values, routing, hooks and
middleware, problem responses, the HTTP server runner and the contract an
adapter implements. It depends on `grund` and on nothing that serves
sockets: `grund_io` (`dart:io`) or `grund_shelf` supplies the adapter.

```dart
import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_io/grund_io.dart';

final class HelloRoutes extends HttpApi {
  HelloRoutes(super.injector);

  @override
  String get path => '/hello';

  @override
  List<Route> get routes => [
    Route.get('/', (c) => {'hello': c.query.stringOrNull('name') ?? 'world'}),
  ];
}

final class AppModule extends Module {
  const AppModule();

  @override
  List<Module> get imports => const [HttpModule(), IoAdapterModule()];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<HelloRoutes>((i) => HelloRoutes(i), dependsOn: const []),
  ];
}

Future<void> main() => App(root: const AppModule()).run();
```

- **`HttpModule`** binds the `HttpServer` (a `Runner` named `http`) and the
  `HttpConfig` (address, port, `maxBodyBytes`, `debug`, `accessLog`;
  `HttpModule.fromEnvironment` reads `HOST` and `PORT`), and
  takes global hooks (`use:`), `middleware` and response codecs. It needs a
  module that provides the `HttpAdapter`.
- **`HttpApi`** is a class with a `path`, route-level `use` hooks and
  `routes`; every `HttpApi` bound in the module graph is served. The
  generated `XRoutes` of `@Api` classes extend it.
- **Hooks** (`HttpHook`) wrap a route: `before`, `after` and `onError`
  replace guards, interceptors and exception filters. Hooks are named by
  `HookRef<T>.type()` (resolved from the module graph) or
  `HookRef<T>.instance(...)`; in annotations they are written
  `use: [ApiKeyHook, RolesHook(Role.editor)]`. An `HttpException` thrown
  from a hook (`onError` included) keeps what it replaced as `cause` and
  `causeStackTrace`; the responder logs it on `grund.http` and never sends
  the cause to the client.
- **Errors** are `application/problem+json` (RFC 9457) with a stable `code`:
  `HttpException` and its subclasses (`NotFoundException`, ...) are
  answered with their status, anything else is a logged 500 with the generic
  detail `Internal server error` (the error and its stack trace only with
  `HttpConfig(debug: true)`). A malformed percent-encoding in the path is a 400.
- **Annotations** for the generator are in
  `package:grund_http/annotations.dart` (`@Api`, `@Get`, `@Post`, `@Path`,
  `@Query`, `@Header`, `@Cookie`, `@Body`, `@Range`, `@Length`, `@Pattern`,
  `@OneOf`), a library of its own because `Pattern` and `Cookie` clash with
  `dart:core` and `dart:io`; in a file that uses them, hide the clashing name
  (`import 'dart:io' hide Cookie;`) or import `dart:io` with a prefix.
- `package:grund_http/testing.dart` has `TestClient`, which sends requests
  straight to the server without a socket; `package:grund_http/adapter.dart`
  has the building blocks for adapter authors.

The repository's `docs/` directory has the guides, among them
`docs/http-and-hooks.md`.
