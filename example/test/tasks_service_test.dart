// Unit tests: the service is a plain class, and a test module written with
// the explicit API swaps the store for a fake, even though the application
// itself is wired with annotations.
import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:tasks_api/tasks_api.dart';
import 'package:test/test.dart';

/// A store that is always empty and refuses every change.
final class _EmptyStore implements TaskStore {
  @override
  List<Task> all() => const [];

  @override
  Task? find(int id) => null;

  @override
  Task add(String title) => throw UnsupportedError('read-only');

  @override
  bool replace(Task task) => false;

  @override
  bool remove(int id) => false;
}

/// A test module written with the explicit API.
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

void main() {
  test('list filters by state', () {
    final service = TasksService(InMemoryTaskStore());

    expect(service.list(done: false).map((task) => task.id), [1]);
    expect(service.list().map((task) => task.id), [1, 2]);
  });

  test('update changes only the given fields', () {
    final service = TasksService(InMemoryTaskStore());

    final task = service.update(2, const UpdateTask(title: 'Run it again'));

    expect(task.toJson(), {'id': 2, 'title': 'Run it again', 'done': true});
  });

  test('a test module provides a fake store through DI', () async {
    final app = await TestApp.start(root: const _FakeStoreModule());
    addTearDown(app.close);
    final service = app<TasksService>();

    expect(service.list(), isEmpty);
    expect(() => service.find(1), throwsA(isA<TaskNotFound>()));
    expect(() => service.delete(1), throwsA(isA<TaskNotFound>()));
  });
}
