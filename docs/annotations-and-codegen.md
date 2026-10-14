# Annotations and code generation

Annotations are a shorter way to write the explicit API. They have no
behavior: a generator reads them with the Dart analyzer and writes
`lib/<package>.dartnest.dart`, one ordinary library per package, which you
commit next to your code. Nothing else in your package is changed, and no
`part` files are involved.

## What is generated

For each class the generator writes a function:

| You write | The generated library has |
| --- | --- |
| `@Module(id: 'tasks', ...) final class TasksModule {}` | `Module tasksModule()` |
| `@Controller('/tasks') final class TasksController` | `Controller<TasksController> tasksController()` |
| `@Injectable() final class TasksService` | a private factory used by the module's `Provider` |

They are functions rather than top-level `final`s so that a hot reload can
build the graph again. Pass the root module's function to
`Application.create(appModule)`. The example's committed
[`lib/tasks_api.dartnest.dart`](../example/lib/tasks_api.dartnest.dart)
shows the whole output for a real application.

## Running the generator

| Driver | Command | Use it when |
| --- | --- | --- |
| `dartnest_cli` | `dartnest gen`, `dartnest gen --watch`, `dartnest dev` | the default; fast incremental analysis, hot reload |
| `dartnest_build` | `dart run build_runner build` / `watch` | the package already uses build_runner (see [build-runner.md](build-runner.md)) |

Both produce the same bytes. Run one driver per package.

To keep the committed file honest in CI:

```sh
dartnest gen && git diff --exit-code lib/my_app.dartnest.dart
```

The example does the same in a test (`example/test/generated_library_test.dart`).

## Static validation

The generator checks the module graph before writing anything. A problem
is printed as `path:line:column: error: message [code]`, the generated
library is left as it was, and `gen` exits with 1:

```text
lib/src/todos.dart:19:24: error: No provider for TodoList in module "todos" (resolving: TodosController). [missing_provider]
```

It finds missing and circular dependencies, duplicate module ids and
providers, invalid exports, import cycles, handler parameters it cannot
bind, private types the generated library cannot name, and more; the
[`dartnest_generator` README](../packages/dartnest_generator/README.md)
lists every code. What it cannot see is checked again by
`Application.create` at startup, so a mistake never reaches a request.

## Rules worth knowing

- `Module` and `Controller` are names of both the annotations and the
  explicit API. A file that uses annotations and also needs the explicit
  API (for `Guard`, `ExecutionContext`, `Token`, ...) imports
  `package:dartnest/dartnest.dart` with `hide Controller, Module`.
- Set `@Module(id:)` explicitly. It defaults to the class name, so a rename
  would change the id.
- Injection uses the unnamed public constructor. Every parameter is a
  non-nullable class type or carries `@Inject(token)`.
- `providers` takes `@Injectable()` classes, `Bind<Interface, Impl>()` and
  `Value(value, token: ...)`; `imports` takes `@Module` classes and
  tear-offs of functions without required parameters that return a
  `Module`, which is how hand-written modules (for example one with an
  async provider) join an annotated graph.
- A nullable `@Query` parameter is optional. A non-nullable one is
  required even when it has a Dart default value: the default is never
  used. Make it nullable and apply the default in the method.
- Route metadata are `const` instances of your `RouteMetadata` subclasses,
  placed on the method or the class, like `@Roles([Role.editor])`.

The full list is in the
[`dartnest_annotations` README](../packages/dartnest_annotations/README.md).

## One application, two styles

`example/lib/explicit.dart` wires the example's classes by hand, and
`example/test/e2e_test.dart` runs the same suite against both graphs. Read
the two side by side to see what each annotation stands for.

## Several packages

`gen` handles one package per run. A `@Module` class from another package
is imported from that package's own generated library, so generate the
dependencies first. The generator does not look inside a module from
another package (or inside a module returned by a function): it treats it
as opaque, and for the whole package that references it leaves
`missing_provider` and `circular_dependency` to `Application.create`. See
[faq.md](faq.md#known-limitations).
