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

## A test module

To test several providers together, or to swap one for a fake, write a
module for the test with the explicit API, also when the application uses
annotations:

```dart
test('a test module provides a fake store through DI', () async {
  final container = await Container.create(
    Module(
      id: 'test',
      providers: [
        Provider<TaskStore>((i) => _EmptyStore()),
        Provider((i) => TasksService(i.get())),
      ],
    ),
  );
  addTearDown(container.close);

  expect(container.root.get<TasksService>().list(), isEmpty);
});
```

There is no `overrideProvider`: compose the graph you want instead. A
module function with parameters (`tasksModule({TaskStore? store})`) is the
usual way to let tests replace a dependency of a real module.

## The HTTP layer without a socket

`TestClient` from `package:grund/testing.dart` sends requests through
`app.handle`, the full pipeline (middleware, guards, interceptors, pipes,
filters, serialization) without a server:

```dart
test('GET /health', () async {
  final app = await Application.create(appModule);
  addTearDown(app.close);

  final response = await TestClient(app).get('/health');

  expect(response.status, 200);
  expect(response.json, {'status': 'ok', 'name': 'tasks_api'});
});
```

`TestClient` has `get`, `post`, `put`, `patch`, `delete` and `request`;
`json:` sends a JSON body, `headers:` adds headers. A `TestResponse` has
`status`, `headers`, `bytes`, `text` and `json`. Unlike a real server it
keeps the body of a `HEAD` response.

## End to end on a real socket

To test an adapter as well, listen on an ephemeral loopback port and use
`HttpClient`:

```dart
final adapter = IoAdapter();
final app = await Application.create(appModule, adapter: adapter);
await app.listen(port: 0, address: InternetAddress.loopbackIPv4);
final uri = Uri.http('127.0.0.1:${adapter.port}', '/health');
```

`example/test/helpers/loopback_server.dart` wraps this for both adapters,
and `example/test/e2e_test.dart` runs one suite on both. Pass an
`onError` that collects errors and expect the list to be empty in
`tearDown`: a failure that never reached a response is otherwise invisible.

## The generated library

Check in a test (or in CI) that the committed library matches the sources:

```sh
grund gen && git diff --exit-code lib/my_app.grund.dart
```

`example/test/generated_library_test.dart` does it in Dart: it copies the
package to a temporary directory, generates there, and compares the
result with the committed file.

## Both styles, one suite

When a package keeps a hand-written graph next to the annotations (as the
example does to document them), run the same tests against both module
functions:

```dart
for (final (name, root) in [('annotations', appModule), ('explicit', explicitAppModule)]) {
  group(name, () { /* ... */ });
}
```
