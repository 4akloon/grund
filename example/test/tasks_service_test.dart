// Unit tests: the service is a plain class, and a test module written with
// the explicit API swaps the store for a fake, even though the application
// itself is wired with annotations.
import 'package:grund/grund.dart';
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

void main() {
  test('list filters by state', () {
    final service = TasksService(InMemoryTaskStore());

    expect(service.list(done: false).map((task) => task.id), [1]);
    expect(service.list().map((task) => task.id), [1, 2]);
  });

  test('update changes only the given fields', () {
    final service = TasksService(InMemoryTaskStore());

    final task = service.update(2, const UpdateTaskDto(title: 'Run it again'));

    expect(task.toJson(), {'id': 2, 'title': 'Run it again', 'done': true});
  });

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
    final service = container.root.get<TasksService>();

    expect(service.list(), isEmpty);
    expect(() => service.find(1), throwsA(isA<TaskNotFound>()));
    expect(() => service.delete(1), throwsA(isA<TaskNotFound>()));
  });
}
