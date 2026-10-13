# dartnest

NestJS-style modular backend framework for Dart without `dart:mirrors`.

Modules are values, providers are typed factories, and the dependency graph
is validated before anything starts. Annotations and code generation are an
optional layer on top (coming in later milestones); everything works without
them.

## Dependency injection

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
- Problems fail fast with a typed `InjectionError`: missing provider (with
  the resolution chain and the modules that declare it), circular
  dependency, duplicate module id with a different shape (imports, provider
  keys, exports, `global`), invalid export.
- A module that depends on an async provider exported by a `global` module
  should import that module explicitly: modules start in imports-first
  order, so without the import it may start before the global one.

See `example/di_example.dart` and `docs/superpowers/ROADMAP.md`.
