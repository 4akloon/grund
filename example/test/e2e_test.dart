// One suite, four servers: the generated and the hand-written module graph,
// each served by dart:io and by shelf on a loopback port.
import 'package:grund/grund.dart';
import 'package:tasks_api/explicit.dart';
import 'package:tasks_api/tasks_api.dart';
import 'package:tasks_api/tasks_api.grund.dart';
import 'package:test/test.dart';

import 'helpers/loopback_server.dart';

const _reader = {'x-api-key': 'reader-key'};
const _editor = {'x-api-key': 'editor-key'};

void main() {
  final graphs = <String, Module Function()>{
    'annotations': appModule,
    'explicit': explicitAppModule,
  };
  graphs.forEach((style, root) {
    for (final kind in AdapterKind.values) {
      group('$style on ${kind.name}', () => _suite(root, kind));
    }
  });
}

void _suite(Module Function() root, AdapterKind kind) {
  late LoopbackServer server; // Set in setUp before every test.

  setUp(() async => server = await LoopbackServer.start(root, kind));
  tearDown(() async {
    await server.close();
    expect(server.errors, isEmpty);
  });

  _public(() => server);
  _reading(() => server);
  _writing(() => server);
}

/// What needs no API key: the health check and the middleware.
void _public(LoopbackServer Function() server) {
  test('GET /health answers without a key', () async {
    final response = await server().send('GET', '/health');

    expect(response.status, 200);
    expect(response.json, {'status': 'ok', 'name': 'tasks_api'});
  });

  test('middleware adds x-request-id, also to unrouted requests', () async {
    final own = await server().send(
      'GET',
      '/health',
      headers: {'x-request-id': 'abc'},
    );
    final unrouted = await server().send('GET', '/nowhere');

    expect(own.headers['x-request-id'], 'abc');
    expect(unrouted.status, 404);
    expect(unrouted.headers['x-request-id'], startsWith('req-'));
  });

  test('the interceptor times routed requests', () async {
    final response = await server().send('GET', '/health');

    expect(
      response.headers['server-timing'],
      matches(RegExp(r'^handler;dur=\d+\.\d$')),
    );
  });
}

/// Reading tasks: the key guard, query and path parameters, the filter.
void _reading(LoopbackServer Function() server) {
  test('a missing or unknown key is 401', () async {
    final missing = await server().send('GET', '/tasks');
    final unknown = await server().send(
      'GET',
      '/tasks',
      headers: {'x-api-key': 'nope'},
    );

    expect(missing.status, 401);
    expect((missing.json as Map)['message'], 'Send a valid x-api-key.');
    expect(unknown.status, 401);
  });

  test('a reader lists tasks, filtered by ?done=', () async {
    final all = await server().send('GET', '/tasks', headers: _reader);
    final done = await server().send(
      'GET',
      '/tasks?done=true',
      headers: _reader,
    );
    final invalid = await server().send(
      'GET',
      '/tasks?done=maybe',
      headers: _reader,
    );

    expect(all.json, hasLength(2));
    expect(done.json, [
      {'id': 2, 'title': 'Run grund dev', 'done': true},
    ]);
    expect(invalid.status, 400);
  });

  test('GET /tasks/:id finds a task; the filter maps a miss to 404', () async {
    final found = await server().send('GET', '/tasks/1', headers: _reader);
    final missing = await server().send('GET', '/tasks/99', headers: _reader);
    final invalid = await server().send('GET', '/tasks/one', headers: _reader);

    expect((found.json as Map)['title'], 'Read the grund README');
    expect(missing.status, 404);
    expect((missing.json as Map)['message'], 'No task 99.');
    expect(invalid.status, 400);
  });
}

/// Changing tasks: the roles guard, the body DTOs and the pipe.
void _writing(LoopbackServer Function() server) {
  test('a reader cannot create a task: 403', () async {
    final response = await server().send(
      'POST',
      '/tasks',
      headers: _reader,
      json: {'title': 'Nope'},
    );

    expect(response.status, 403);
  });

  test('an editor creates a task: 201, location, trimmed title', () async {
    final created = await server().send(
      'POST',
      '/tasks',
      headers: _editor,
      json: {'title': '  Write the docs  '},
    );
    final read = await server().send('GET', '/tasks/3', headers: _reader);

    expect(created.status, 201);
    expect(created.headers['location'], '/tasks/3');
    expect(created.json, {'id': 3, 'title': 'Write the docs', 'done': false});
    expect(read.json, created.json);
  });

  test('a title of blanks is trimmed first, then rejected: 400', () async {
    final response = await server().send(
      'POST',
      '/tasks',
      headers: _editor,
      json: {'title': '   '},
    );

    expect(response.status, 400);
  });

  test('PATCH changes the state; a wrong type is 400', () async {
    final changed = await server().send(
      'PATCH',
      '/tasks/1',
      headers: _editor,
      json: {'done': true},
    );
    final invalid = await server().send(
      'PATCH',
      '/tasks/1',
      headers: _editor,
      json: {'done': 'yes'},
    );

    expect(changed.json, {
      'id': 1,
      'title': 'Read the grund README',
      'done': true,
    });
    expect(invalid.status, 400);
  });

  test('DELETE answers 204, then the task is gone', () async {
    final deleted = await server().send('DELETE', '/tasks/2', headers: _editor);
    final again = await server().send('DELETE', '/tasks/2', headers: _editor);

    expect(deleted.status, 204);
    expect(deleted.body, isEmpty);
    expect(again.status, 404);
  });
}
