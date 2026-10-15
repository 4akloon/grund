# Modules and dependency injection

A module groups providers (services, repositories, guards, ...) and
controllers, and decides which of its providers other modules may use. The
container builds every provider once, at startup, after it has checked the
whole graph.

## Providers

```dart
import 'package:grund/grund.dart';

/// A typed token for a value that is not a class of its own.
const dbUrl = Token<String>('db.url');

final class Db {
  Db._(this.url);
  final String url;
  static Future<Db> connect(String url) async => Db._(url);
}

abstract interface class UserStore {
  List<String> names();
}

final class DbUserStore implements UserStore {
  DbUserStore(this.db);
  final Db db;
  @override
  List<String> names() => ['ada', 'linus'];
}

final class UsersService {
  UsersService(this.store, this.url);
  final UserStore store;
  final String url;
}

Module usersModule() => Module(
  id: 'users',
  providers: [
    Provider.value('postgres://localhost/app', token: dbUrl),
    Provider.async((i) async => Db.connect(i.get(dbUrl))),
    Provider<UserStore>((i) => DbUserStore(i.get())),
    Provider((i) => UsersService(i.get(), i.get(dbUrl))),
  ],
  exports: [UsersService],
);

Future<void> main() async {
  final container = await Container.create(usersModule());
  final users = container.root.get<UsersService>();
  print('${users.store.names()} from ${users.url}');
  await container.close();
}
```

- `Provider((i) => X(...))` provides `X`; the type is inferred from the
  factory. `i.get()` infers the type it returns from the parameter it
  fills, so constructor arguments need no type arguments.
- `Provider<UserStore>((i) => DbUserStore(...))` provides an interface by
  an implementation: consumers ask for `UserStore`.
- `Provider.value(v, token: t)` provides a constant; `Token<T>` gives it a
  name and a type. `i.get(dbUrl)` returns a `String`.
- `Provider.async` awaits its factory during `Container.create`; every
  other provider can then `get` the result synchronously. Declare an async
  provider before the providers that use it, or put it in an imported
  module.

There are no lazy providers: when `Container.create` (or
`Application.create`) returns, every provider exists. A factory that
throws stops the startup with a `ProviderCreationError` that wraps it.

## Visibility

```dart
Module appModule() => Module(
  id: 'app',
  imports: [configModule(), usersModule()],
  controllers: [/* may use UsersService, not UserStore */],
);
```

- A provider is visible in its own module and, if it is in `exports`, in
  every module that imports that module. `UserStore` above is private to
  `users`.
- `exports` may also list tokens (`exports: [dbUrl]`) and imported modules
  (re-export).
- `global: true` makes a module's exports visible everywhere, without an
  import. Use it for configuration, as the example's `ConfigModule` does.
- A module id names one module per application. The same module imported
  from two places (an equal id, providers and imports) is built once; two
  modules with one id and different contents are a
  `DuplicateModuleIdError`.

## Dynamic modules

A module that needs parameters is a function:

```dart
Module databaseModule({required String url}) => Module(
  id: 'database',
  providers: [
    Provider.value(url, token: dbUrl),
    Provider.async((i) async => Db.connect(i.get(dbUrl))),
  ],
  exports: [Db],
);
```

This replaces NestJS's `forRoot` and, because providers can be async,
`forRootAsync`.

## Errors

Every DI failure is a subclass of the sealed `InjectionError`, so a test or
a startup script can match on it. Before any factory runs, the graph is
checked for duplicate module ids, import cycles, duplicate providers,
exports of something the module does not have, and a key that two imports
export into one module. While providers are created, a missing provider is
reported with the chain that needed it:

```text
MissingProviderError: No provider for Clock in module "users" (resolving: UsersService).
```

With annotations most of these errors are found by `grund gen`, with a
file, a line and a column, before the program is compiled. The full list
is in the [`grund` README](../packages/grund/README.md).

## The same with annotations

```dart
@Module(
  id: 'users',
  providers: [
    Value('postgres://localhost/app', token: dbUrl),
    Bind<UserStore, DbUserStore>(),
    UsersService,
  ],
  exports: [UsersService],
)
final class UsersModule {}

@Injectable()
final class UsersService {
  UsersService(this.store, @Inject(dbUrl) this.url);
  final UserStore store;
  final String url;
}
```

The generator writes `Module usersModule()` with the same providers. An
async provider has no annotation of its own: write the module that
creates it on the explicit API, wrap it in a function without required
parameters (`Module appDatabase() => databaseModule(url: ...)`) and list
that function in `imports: [appDatabase]`.
See [annotations-and-codegen.md](annotations-and-codegen.md).
