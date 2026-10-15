// Without a server: TestClient sends requests straight to app.handle, the
// fastest way to test routes, guards and filters.
import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:tasks_api/tasks_api.dart';
import 'package:tasks_api/tasks_api.grund.dart';
import 'package:test/test.dart';

void main() {
  late Application app; // Set in setUp before every test.
  late TestClient client; // Set together with app.

  setUp(() async {
    app = await TasksApp.create(appModule);
    client = TestClient(app);
  });
  tearDown(() => app.close());

  test('an editor creates a task, a reader reads it', () async {
    final created = await client.post(
      '/tasks',
      json: {'title': 'Ship 0.1.0'},
      headers: {'x-api-key': 'editor-key'},
    );
    final read = await client.get(
      '/tasks/3',
      headers: {'x-api-key': 'reader-key'},
    );

    expect(created.status, 201);
    expect(read.json, {'id': 3, 'title': 'Ship 0.1.0', 'done': false});
  });

  test(
    'providers are singletons: a delete is seen by the next request',
    () async {
      await client.delete('/tasks/1', headers: {'x-api-key': 'editor-key'});

      final list = await client.get(
        '/tasks',
        headers: {'x-api-key': 'reader-key'},
      );
      expect(list.json, [
        {'id': 2, 'title': 'Run grund dev', 'done': true},
      ]);
    },
  );
}
