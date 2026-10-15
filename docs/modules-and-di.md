# Modules and dependency injection

A module groups bindings (services, repositories, hooks, APIs) and decides
which of them other modules may use. The container checks the whole module
graph first and then creates every singleton once, at startup; no
partially started container is ever returned.

## Modules and bindings

A module is a class that extends `Module` and overrides the getters it
needs. All of them default to empty, and the constructor is `const`:

```dart
import 'package:grund/grund.dart';

final class Clock {}

abstract interface class UserStore {
  List<String> names();
}

final class MemoryUserStore implements UserStore {
  @override
  List<String> names() => ['ada', 'linus'];
}

final class UsersService {
  UsersService(this.store, this.clock);
  final UserStore store;
  final Clock clock;
}

final class UsersModule extends Module {
  const UsersModule();

  @override
  List<Module> get imports => const [TimeModule()];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<UserStore>((i) => MemoryUserStore(), dependsOn: const []),
    Singleton<UsersService>(
      (i) => UsersService(i<UserStore>(), i<Clock>()),
      dependsOn: const [Key<UserStore>(), Key<Clock>()],
    ),
  ];

  @override
  List<Object> get exports => const [Key<UsersService>()];
}

final class TimeModule extends Module {
  const TimeModule();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<Clock>((i) => Clock(), dependsOn: const []),
  ];

  @override
  List<Object> get exports => const [Key<Clock>()];
}

Future<void> main() async {
  final app = await TestApp.start(root: const UsersModule());
  print(app<UsersService>().store.names());
  await app.close();
}
```

(`TestApp` is in `package:grund/testing.dart`; a real application calls
`App(root: const UsersModule()).run()`.)

- **Always write the type argument** (`Singleton<UserStore>(...)`): it is the
  key under which the value is visible, so `Singleton<UserStore>((i) =>
  MemoryUserStore(), ...)` provides the interface and consumers ask for
  `UserStore`. Without it Dart infers `Object`, which is rejected.
- **`i<T>()`** resolves a value in the factory. `i<T>('name')` resolves a
  named one, `i.maybe<T>()` returns `null` when there is none and
  `i.all<T>()` every visible `T`.
- **`dependsOn`** lists the keys the factory resolves. The container checks
  them before it runs any factory: a missing provider, a cycle or a
  singleton that depends on a call-scoped value is found at startup, with
  the chain. `Singleton.factory(...)` declares none (the escape hatch for
  third-party types); then a wrong `i<T>()` fails when the factory runs
  instead. A named binding is `Singleton<Db>(..., name: 'primary')` and its
  key `Key<Db>('primary')`.
- **Async factories.** A factory may return a `Future`: the singleton is
  awaited at startup and every other provider can `i<T>()` the result
  synchronously.

There are no lazy singletons: when the application has started, every one
exists. A factory that throws stops the startup with a `ProviderCreationError`
that wraps it; what was created is disposed again.

## Scopes

| Binding | Lives | Use it for |
| --- | --- | --- |
| `Singleton<T>` | one instance for the application, created at startup | services, repositories, configuration |
| `Scoped<T>` | one instance per call (an HTTP request), created on first use | the current user, a unit of work |
| `Transient<T>` | a new instance on every resolution | cheap value holders |

A call scope is opened by whoever runs a call; for HTTP, the server opens
one per request on the injector of the API's module. A hook puts a value on
it with `c.set<CurrentUser>(user)`, and the handler reads it with
`c<CurrentUser>()`. `Scoped` instances that implement `Disposable` are
disposed when the call ends, singletons when the application closes. A
singleton that depends on a `Scoped` binding is a `CaptiveDependencyError`
(or `captive_dependency` in the generator).

## Visibility

- A binding is visible in its own module and, if its key is in `exports`,
  in every module that imports that module.
- `exports` may also list imported modules (`exports: const [AuthModule()]`)
  to pass their exports on.
- `global => true` makes a module's exports visible everywhere without an
  import; use it for configuration and for adapters (`IoAdapterModule` is
  global).
- A module is identified by its class and its `qualifier`. The same module
  imported from two places is built once; two instances with one class and
  different imports, keys or exports are a `ConflictingModuleError`. Give a
  module a `qualifier` (`Object? get qualifier`) to have several instances
  of one class, for example two database connections.

## Lifecycle, overrides and errors

`Module.onInit(injector)` runs once the whole graph exists, in import order;
`onShutdown(injector)` runs at close, in reverse order, before any
singleton is disposed. `App(root: ..., overrides: [...])` replaces the
bindings with the same keys wherever they are declared; an override that
matches no binding is an `UnusedOverrideError`.

Every failure is a subclass of `GrundError` (an abstract base class), and its families
(`GraphError`, `ResolutionError`, `AppError`) are sealed, so a test or a
startup script can match on them. Before any factory runs, the graph is
checked for import cycles, conflicting modules, duplicate bindings, exports
of something the module does not have, ambiguous exports, missing or
invisible providers, dependency cycles and captive dependencies. A missing
provider names the chain:

```text
MissingProviderError: No provider for Clock is visible in module UsersModule,
required by UsersService. Declare it there, or import a module that exports it.
```

A module that needs parameters is a class with fields (or a function that
returns one): `const DatabaseModule(url: 'postgres://...')`. With several
instances, give each a `qualifier`.

## The same with annotations

The annotations are in `package:grund/annotations.dart`: `@Module`,
`@Injectable`, `@Provides`, `Bind` and `@Named`, with `Scope` for the
scope. The explicit API is imported with a prefix (`as grund`) because the
names `Module` clash:

```dart
import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;

import 'users_module.g.dart';

@Module(
  imports: [TimeModule()],
  providers: [Bind<UserStore, MemoryUserStore>(), UsersService],
  exports: [UsersService],
)
final class UsersModule extends grund.Module with $UsersModule {
  const UsersModule();

  /// A `@Provides` method is a singleton of its return type; a `Future`
  /// result is awaited at startup.
  @Provides()
  static AppConfig config() => AppConfig.demo;
}

@Injectable()
final class UsersService {
  UsersService(this.store, @Named('primary') this.db);
  final UserStore store;
  final Database db;
}
```

The generator writes `users_module.g.dart` with `mixin $UsersModule on
grund.Module`, which overrides `imports`, `bindings` and `exports` for you;
the class you write is an ordinary `Module` and works in tests and in the
explicit graph unchanged. `@Injectable(scope: Scope.call)` and
`@Provides(scope: ...)` make a `Scoped` or `Transient` binding. `imports`
takes `const` module instances; a hand-written module (with an async
provider, say) joins an annotated graph the same way, and the other way
round. See [annotations-and-codegen.md](annotations-and-codegen.md) for the
rules, and `example/lib/src/tasks/tasks_module.dart` for a real module.
