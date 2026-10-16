# Getting started

grund needs the Dart SDK 3.8 or later (`dart --version`).

## Create an application

```sh
dart pub global activate grund_cli   # installs the `grund` command
grund init my_app
cd my_app
dart pub get
grund gen
dart run bin/main.dart
```

Without a global activation every command also works as
`dart run grund_cli <command>` inside a package that has `grund_cli` in its
`dev_dependencies` (the scaffold has).

`init` writes a package that uses annotations:

```text
my_app/
  pubspec.yaml            grund, grund_http, grund_io; dev: grund_cli, test
  analysis_options.yaml
  .gitignore              .dart_tool/
  bin/main.dart           App(root: const AppModule()).run(...)
  lib/src/app_module.dart AppModule: HttpModule, IoAdapterModule, the providers
  lib/src/hello.dart      HelloService and HelloApi
  test/hello_test.dart    a smoke test of GET /hello, in process (dart test)
```

`grund gen` reads `lib/` and writes one file next to every library that has
annotations: `lib/src/hello.g.dart` (the part with `HelloApiRoutes`, the
`HttpApi` that serves `HelloApi`) and `lib/src/app_module.g.dart` (the
`$AppModule` mixin that `AppModule` applies). They are ordinary Dart on the
explicit API. Commit them; they change only when the annotations do.

```sh
curl 'http://localhost:8080/hello?name=you'   # {"message":"Hello, you!"}
curl 'http://localhost:8080/hello'            # {"message":"Hello, world!"}
curl 'http://localhost:8080/nothing'          # 404, application/problem+json
```

```json
{"type":"about:blank","title":"Not Found","status":404,
 "detail":"Cannot GET /nothing","instance":"/nothing","code":"route_not_found"}
```

`bin/main.dart` runs `App(root: const AppModule()).run(only:
Runners.fromArgs(arguments))`: `run` starts the application, prints the log
to the console and closes on Ctrl+C or `SIGTERM`; `--only=http` selects
which runners start. See [logging.md](logging.md).

## Develop with hot reload

```sh
grund dev
```

`dev` runs `bin/main.dart`, regenerates the files on every save and hot
reloads the running process: change the greeting in `HelloService`, save,
and the next request answers with the new text, on the same port and with
the same singleton instances. Add a route and it is served after the save.
See [dev-mode.md](dev-mode.md).

## Add a feature

A feature is a module with its providers and APIs. A library declares
either a `@Module` or an `@Api`, never both (see
[annotations-and-codegen.md](annotations-and-codegen.md)), so the API and
the module go into two files. `lib/src/todos.dart`:

```dart
import 'package:grund/annotations.dart';
import 'package:grund_http/annotations.dart';
import 'package:grund_http/grund_http.dart' as http;

part 'todos.g.dart';

/// Keeps the todo items in memory.
@Injectable()
final class TodoList {
  final List<String> _items = [];

  /// The items, oldest first.
  List<String> all() => List.unmodifiable(_items);

  /// Adds [item].
  void add(String item) => _items.add(item);
}

/// `GET /todos` and `POST /todos`.
@Api('/todos')
final class TodosApi {
  /// Creates the API.
  TodosApi(this.list);

  /// The items.
  final TodoList list;

  /// Lists the items.
  @Get('/')
  List<String> all() => list.all();

  /// Adds the `item` field of the JSON body.
  @Post('/', status: 201)
  List<String> add(@Body() Map<String, Object?> body) {
    list.add('${body['item']}');
    return list.all();
  }
}
```

and `lib/src/todos_module.dart`:

```dart
import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;

import 'todos.dart';
import 'todos_module.g.dart';

/// The todos feature.
@Module(providers: [TodoList, TodosApi])
final class TodosModule extends grund.Module with $TodosModule {
  /// Creates the module.
  const TodosModule();
}
```

Import it from the root module, in `lib/src/app_module.dart`
(`import 'todos_module.dart';`):

```dart
@Module(
  imports: [HttpModule(), IoAdapterModule(), TodosModule()],
  providers: [HelloService, HelloApi],
)
final class AppModule extends grund.Module with $AppModule {
  const AppModule();
}
```

```sh
grund gen
curl -X POST -H 'content-type: application/json' -d '{"item": "milk"}' \
  localhost:8080/todos                        # 201 ["milk"]
```

The annotations are checked when you generate. Declare a path parameter
the route does not have (`List<String> all(@Path() int id)` on
`@Get('/')`) and `grund gen` prints, exits with 1 and changes no file:

```text
lib/src/todos.dart:30:32: error: The path /todos has no parameter :id for id; its parameters are []. [unknown_path_parameter]
1 problem; no generated file was changed.
```

What the generator cannot see, the application checks before it serves.
`AppModule` imports `HttpModule`, a module from another package, which the
generator treats as opaque, so it does not report `missing_provider` for a
dependency that no module of the package binds (the opaque module might
export it; [faq.md](faq.md#known-limitations)). Remove `TodoList` from
`providers` and `grund gen` stays silent, but `dart run bin/main.dart` fails
at once, before it listens:

```text
MissingProviderError: No provider for TodoList is visible in module TodosModule, required by TodosApi. Declare it there, or import a module that exports it.
```

## Without annotations

Everything the generator writes can be written by hand; the README's
[quick start](../README.md#without-code-generation) shows the same
application on the explicit API, and [modules-and-di.md](modules-and-di.md)
and [http-and-hooks.md](http-and-hooks.md) explain it.

## A site with pages

`grund init --template <api|fullstack> my_site` chooses the scaffold (`api`,
the one above, is the default). `fullstack` writes an application with HTML
pages rendered on the server by Jaspr, a sign-in form and a cookie session,
on the explicit API (no `gen` needed). Run it with
`dart run grund_cli dev` (or `grund dev`): it reloads the code and, because
`grund_jaspr` injects a small script while `dev` runs, tells open pages in
the browser to reload (never in a product build). See
[Pages and sessions](jaspr.md).

## Next

- [Modules and dependency injection](modules-and-di.md)
- [HTTP APIs, hooks and errors](http-and-hooks.md)
- [The example application](../example/README.md): modules, hooks, a
  middleware and both adapters in a real API, written in both styles.
