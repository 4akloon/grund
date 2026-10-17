# Testing

Everything in grund is a value, so tests need no special module and no
server. The example's `test/` directory uses each technique below.

## Services: plain classes

A service is a class with a constructor; create it with what it needs.

```dart
test('list filters by state', () {
  final service = TasksService(InMemoryTaskStore());
  expect(service.list(done: false).map((task) => task.id), [1]);
});
```

## `TestApp`: the graph without a server

`TestApp` from `package:grund/testing.dart` builds and validates the module
graph and creates the singletons, but starts no runner, so no port is
opened. To swap one dependency for a fake, either write a module for the
test on the explicit API (also when the application uses annotations):

```dart
final class _FakeStoreModule extends Module {
  const _FakeStoreModule();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<TaskStore>((_) => _EmptyStore(), dependsOn: const []),
    Singleton<TasksService>(
      (i) => TasksService(i<TaskStore>()),
      dependsOn: const [Key<TaskStore>()],
    ),
  ];
}

test('a test module provides a fake store through DI', () async {
  final app = await TestApp.start(root: const _FakeStoreModule());
  addTearDown(app.close);

  expect(app<TasksService>().list(), isEmpty);
});
```

or keep the real graph and override one binding:
`TestApp.start(root: AppModule(), overrides: [Singleton<TaskStore>((_) =>
_EmptyStore(), dependsOn: const [])])`. An override replaces the bindings
with the same key wherever they are declared; one that matches no binding is
an `UnusedOverrideError`, so a typo fails loudly. `app<T>()` resolves a value
visible to the root module.

## The HTTP layer without a socket

`TestClient` from `package:grund_http/testing.dart` sends requests straight to
the `HttpServer` of a `TestApp`: the whole pipeline (middleware, hooks, the
handler, serialization, problem responses) without an adapter listening:

```dart
late TestApp app;
late TestClient client;

setUp(() async {
  app = await TestApp.start(
    root: ServingModule(const AppModule(), AdapterKind.io),
  );
  client = TestClient.of(app);
});
tearDown(() => app.close());

test('an editor creates a task', () async {
  final created = await client.post(
    '/tasks',
    json: {'title': 'Ship 0.1.0'},
    headers: {'x-api-key': 'editor-key'},
  );
  expect(created.status, 201);
});
```

The root module must import `HttpModule` and an adapter module (the
adapter never listens in a `TestApp`). `TestClient` has `get`, `post`, `put`,
`patch`, `delete`, `head` and `request`; `json:` sends a JSON body, `headers:` adds
headers. A `TestResponse` has `status`, `headers`, `bytes`, `text` and
`json`. Unlike a real server it keeps the body of a `HEAD` response.

## End to end on a real socket

To test an adapter as well, start the application with `HttpConfig(port: 0)`
on loopback and use `HttpClient`:

```dart
final app = App(
  root: ServingModule(
    const AppModule(),
    AdapterKind.io,
    address: InternetAddress.loopbackIPv4,
    port: 0,
  ),
);
await app.start();
final adapter = app.container.all<HttpAdapter>().first as IoAdapter;
final uri = Uri.http('127.0.0.1:${adapter.port}', '/health');
```

`example/test/helpers/loopback_server.dart` wraps this for both adapters, and
`example/test/e2e_test.dart` runs one suite on both. Pass an `onError` to the
adapter module that collects errors and attach a `LogOutput` with a `sink` at
`Level.WARNING` (see [logging.md](logging.md)); expect both lists to be empty
in `tearDown`: a failure that never reached a response is otherwise
invisible. `TestApp` and `App.start` attach no log output, so tests stay
silent.

## The generated files

Check in a test (or in CI) that the committed `*.g.dart` files match the
sources:

```sh
grund gen && git diff --exit-code
```

`example/test/generated_library_test.dart` does it in Dart: it copies the
sources to a temporary directory, runs the CLI's `GenerationSession` there and
compares the result with the committed files.

## Both styles, one suite

When a package keeps a hand-written graph next to the annotations (as the
example does to document them), run the same tests against both root modules:
`example/test/e2e_test.dart` loops over the module style and the adapter and
runs one suite for every combination.
