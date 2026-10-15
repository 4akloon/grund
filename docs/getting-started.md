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
`dart run grund_cli <command>` inside a package that has `grund_cli`
in its `dev_dependencies` (the scaffold has).

`init` writes a package that uses annotations:

```text
my_app/
  pubspec.yaml            grund, grund_annotations, grund_io; dev: grund_cli
  analysis_options.yaml
  .gitignore              .dart_tool/
  bin/main.dart           creates the application and listens on port 8080
  lib/src/hello.dart      HelloService, HelloController, AppModule
```

`grund gen` reads `lib/` and writes `lib/my_app.grund.dart`. That
file is ordinary Dart on the explicit API: `Module appModule()` for
`AppModule` and `Controller<HelloController> helloController()` for the
controller. Commit it; it changes only when the annotations do.

```sh
curl 'http://localhost:8080/hello?name=you'   # {"message":"Hello, you!"}
curl 'http://localhost:8080/hello'            # {"message":"Hello, world!"}
curl 'http://localhost:8080/nothing'          # 404: {"statusCode":404,"error":"Not Found",...}
```

## Develop with hot reload

```sh
grund dev
```

`dev` runs `bin/main.dart`, regenerates the library on every save and hot
reloads the running process: change the greeting in `HelloService`, save,
and the next request answers with the new text, on the same port and with
the same provider instances. Add a route and it is served after the save.
See [dev-mode.md](dev-mode.md).

## Add a feature

A feature is a module with its providers and controllers. Create
`lib/src/todos.dart`:

```dart
import 'package:grund_annotations/grund_annotations.dart';

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
@Controller('/todos')
final class TodosController {
  /// Creates the controller.
  TodosController(this.list);

  /// The items.
  final TodoList list;

  /// Lists the items.
  @Get()
  List<String> all() => list.all();

  /// Adds the `item` field of the JSON body.
  @Post()
  List<String> add(@Body() Map<String, Object?> body) {
    list.add('${body['item']}');
    return list.all();
  }
}

/// The todos feature.
@Module(id: 'todos', providers: [TodoList], controllers: [TodosController])
final class TodosModule {}
```

Import it from the root module in `lib/src/hello.dart`
(`import 'todos.dart';`):

```dart
@Module(
  id: 'app',
  imports: [TodosModule],
  providers: [HelloService],
  controllers: [HelloController],
)
final class AppModule {}
```

```sh
curl -X POST -H 'content-type: application/json' -d '{"item": "milk"}' \
  localhost:8080/todos                        # ["milk"]
```

A mistake is reported before anything runs. Remove `TodoList` from
`providers` and `grund gen` prints, exits with 1 and leaves the
generated library as it was:

```text
lib/src/todos.dart:19:24: error: No provider for TodoList in module "todos" (resolving: TodosController). [missing_provider]
1 problem; lib/my_app.grund.dart was not changed.
```

## Without annotations

Everything the generator writes can be written by hand; the README's
[quick start](../README.md#without-code-generation) shows the same
application on the explicit API, and
[modules-and-di.md](modules-and-di.md) explains it.

## Next

- [Modules and dependency injection](modules-and-di.md)
- [Controllers and the request pipeline](controllers-and-pipeline.md)
- [The example application](../example/README.md): guards, pipes,
  interceptors, filters and middleware in a real API.
