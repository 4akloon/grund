# dartnest

NestJS-style modular backend framework for Dart without `dart:mirrors`.

Modules are values and providers are typed factories. The module structure
is validated before any provider is created; missing or circular dependencies
fail fast during startup, and `Container.create` never returns a partially
started container. Static validation of the full graph is planned for the
generator in a later milestone. Annotations and code generation are an
optional layer on top (coming in later milestones); everything works without
them.

## Dependency injection

Excerpt; the full runnable version is `example/di_example.dart`:

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

Annotations, an analyzer-based generator, HTTP adapters and the request
pipeline are planned in later milestones; see the repository's `docs/`
directory for the roadmap.
