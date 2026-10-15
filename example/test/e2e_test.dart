// One suite, four servers: the annotated and the hand-written module graph,
// each served by dart:io and by shelf on a loopback port.
import 'package:tasks_api/tasks_api.dart';
import 'package:test/test.dart';

import 'helpers/loopback_server.dart';

const _reader = {'x-api-key': 'reader-key'};
const _editor = {'x-api-key': 'editor-key'};

void main() {
  for (final style in ModuleStyle.values) {
    for (final kind in AdapterKind.values) {
      group('${style.name} on ${kind.name}', () => _suite(style, kind));
    }
  }
}

void _suite(ModuleStyle style, AdapterKind kind) {
  late LoopbackServer server; // Set in setUp before every test.
  setUp(() async => server = await LoopbackServer.start(style, kind));
  tearDown(() async {
    await server.close();
    expect(server.errors, isEmpty);
  });

  _public(() => server);
  _reading(() => server);
  _writing(() => server);
}

/// What needs no API key: the health check, the middleware, the hook.
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
    expect(unrouted.headers['content-type'], contains('problem+json'));
    expect(unrouted.headers['x-request-id'], startsWith('req-'));
  });

  test('the global hook times routed requests, also failed ones', () async {
    final ok = await server().send('GET', '/health');
    final failed = await server().send('GET', '/tasks');
    final timing = matches(RegExp(r'^handler;dur=\d+\.\d$'));

    expect(ok.headers['server-timing'], timing);
    expect(failed.status, 401);
    expect(failed.headers['server-timing'], timing);
  });
}

/// Reading tasks: the key hook, query and path parameters, the error hook.
void _reading(LoopbackServer Function() server) {
  test('a missing or unknown key is a 401 problem', () async {
    final missing = await server().send('GET', '/tasks');
    final unknown = await server().send(
      'GET',
      '/tasks',
      headers: {'x-api-key': 'nope'},
    );

    expect(missing.status, 401);
    expect(missing.headers['content-type'], contains('problem+json'));
    expect(missing.json, containsPair('detail', 'Send a valid x-api-key.'));
    expect(missing.json, containsPair('code', 'api_key_invalid'));
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
    expect(invalid.json, containsPair('status', 400));
  });

  test('GET /tasks/:id finds a task; the hook maps a miss to 404', () async {
    final found = await server().send('GET', '/tasks/1', headers: _reader);
    final missing = await server().send('GET', '/tasks/99', headers: _reader);
    final invalid = await server().send('GET', '/tasks/one', headers: _reader);

    expect((found.json as Map)['title'], 'Read the grund README');
    expect(missing.status, 404);
    expect(missing.json, containsPair('detail', 'No task 99.'));
    expect(missing.json, containsPair('code', 'task_not_found'));
    expect(missing.headers['server-timing'], isNotNull);
    expect(invalid.status, 400);
  });
}

/// Changing tasks: the roles hook, the bodies, the location hook.
void _writing(LoopbackServer Function() server) {
  test('a reader cannot create a task: 403', () async {
    final response = await server().send(
      'POST',
      '/tasks',
      headers: _reader,
      json: {'title': 'Nope'},
    );

    expect(response.status, 403);
    expect(response.json, containsPair('code', 'role_required'));
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
    expect(
      response.json,
      containsPair('errors', contains(containsPair('pointer', '/body'))),
    );
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
