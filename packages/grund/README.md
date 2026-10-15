# grund

NestJS-style modular backend framework for Dart without `dart:mirrors`.

Modules are values and providers are typed factories. The module structure
is validated before any provider is created; missing or circular dependencies
fail fast during startup, and `Container.create` never returns a partially
started container. Annotations (`grund_annotations`) and an analyzer-based
generator (`grund_generator`, run by `grund_cli` or `grund_build`)
are an optional layer on top that also validates the graph at build time;
everything works without them, and both styles produce the same values.

| Package | What it adds |
| --- | --- |
| `grund` | This package: modules, DI, controllers, the request pipeline, `TestClient` |
| `grund_io` | `IoAdapter`, a `dart:io` `HttpServer` adapter |
| `grund_shelf` | `ShelfAdapter` and `shelfHandler` for shelf |
| `grund_annotations` | `@Module`, `@Controller`, `@Get`, `@Injectable`, ... |
| `grund_generator` | The analyzer-based generator behind the annotations |
| `grund_cli` | `grund gen`, `grund dev` (hot reload), `grund init` |
| `grund_build` | The same generator as a `build_runner` builder |

## Dependency injection

Excerpt; the full runnable version is `example/grund_example.dart`:

```dart
const dbUrl = Token<String>('db.url');

Module databaseModule({required String url}) => Module(
  id: 'database',
  providers: [
    Provider.value(url, token: dbUrl),
    Provider.async((i) async => Db.connect(i.get(dbUrl))),
  ],
  exports: [Db],
);

final greetingModule = Module(
  id: 'greeting',
  imports: [databaseModule(url: 'pg://localhost')],
  providers: [Provider((i) => Greeter(i.get()))],   // types are inferred
  exports: [Greeter],
);

final container = await Container.create(Module(id: 'app', imports: [greetingModule]));
container.root.get<Greeter>();
```

Rules:

- A provider is visible inside its module and, when listed in `exports`, in
  modules that import it. `global: true` makes exports visible everywhere.
- Every provider is a singleton created at `Container.create`, in
  imports-first module order. Sync providers may be declared in any order;
  an async provider must be declared before the providers that use it (or
  live in an imported module).
- Problems fail fast with a typed error; all of them extend the sealed
  `InjectionError`. Before any factory runs (`ModuleGraph.build`) the
  container rejects duplicate module ids with a different shape
  (`DuplicateModuleIdError`), import cycles (`CircularModuleImportError`),
  duplicate provider keys (`DuplicateProviderError`) and invalid exports
  (`InvalidExportError`), and a key that several modules export into one scope
  (`AmbiguousProviderError`). During startup, while providers are created, it
  reports a missing provider with the resolution chain and the modules that
  declare it (`MissingProviderError`), a circular provider dependency
  (`CircularDependencyError`), a sync `get` of an async provider that is not
  ready yet (`AsyncProviderNotReadyError`), and a factory that throws,
  wrapped with its cause (`ProviderCreationError`).
- Global modules (and the modules they import) start first, so any other
  module can use a global module's async exports without importing it. Only a
  module inside a global's import closure that needs another global's async
  export should import that global explicitly.

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
final response = await TestClient(app).get('/users/1'); // package:grund/testing.dart
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
  `text/plain`, a `Uint8List` and byte streams are `application/octet-stream`
  (a `List<int>` is a JSON array), and anything else is JSON via `toJson()` or
  `app.serializers.register<T>(...)`. Registered serializers apply to the
  result and to the `Map`s and `List`s inside it, not to values nested in the
  output of a `toJson()`.
- Errors: throw an `HttpException` (`NotFoundException`, `BadRequestException`,
  ...) to answer `{statusCode, error, message, details?}`. Any other exception
  is a logged 500 (`onError`) with the message
  `Internal server error`; `debug: true` puts the error text in `message`
  and adds a `stack` field.
- `Application.create` takes a function returning the root module; routes are
  checked before any provider is created. `app.close()` can be called any
  number of times: new requests get 503, running ones finish, then the
  container closes.

## Hot reload

`dart run grund_cli dev` (see the `grund_cli` README) hot reloads a
running application; this package provides the hooks it uses.

- `app.reassemble()` calls the module function given to `Application.create`
  again, validates the new graph and builds a new container with
  `Container.reassemble`: provider instances are kept by module id and key,
  new providers are created, and providers that are gone are dropped.
  Controllers, enhancers and the route table are always built anew. The new
  container and routes replace the old ones in one step; a request already
  running finishes on the table it started with. It returns a
  `ReassembleReport` with the added and removed routes.
- A failure (an invalid graph, a factory that throws, a module function
  that throws) leaves the previous container and routes serving and is
  passed on. `reassemble()` fails with `ApplicationStateError` after
  `close()` and while another reassemble runs.
- A kept instance keeps its state, also when its class changed: a hot
  reload that changes fields or constructors is followed by a restart in
  `dev`, not by `reassemble()`. A `Provider.value` keeps its old value; a
  changed configuration value needs a restart.
- Outside product mode (`dart.vm.product`), `Application.create` registers
  the VM service extensions `ext.grund.reassemble` (reassembles every
  open application; the result lists the added and removed routes, an error
  carries the failure) and `ext.grund.close` (closes every open
  application). AOT and `--define=dart.vm.product=true` builds register
  nothing.

This package has no server of its own: `app.handle(request)` answers an
`HttpRequest` directly and `TestClient` wraps it for tests. To serve over
HTTP, pass an adapter to `Application.create`: `IoAdapter` from
`grund_io` (a `dart:io` `HttpServer`) or `ShelfAdapter` from
`grund_shelf`; `shelfHandler(app)` from `grund_shelf` embeds an
application in an existing shelf pipeline. The repository's `docs/`
directory has the guides, and its `example/` directory a complete
application written in both styles.
