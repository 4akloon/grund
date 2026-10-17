// The task list on HTML fragments: guest and signed-in markup, create with
// validation (422), delete, escaping, the same-origin guard and the vendored
// htmx file, on the same four servers as web_e2e_test.dart.
import 'package:tasks_api/tasks_api.dart';
import 'package:test/test.dart';

import 'helpers/loopback_server.dart';
import 'helpers/web_session.dart';

void main() {
  for (final style in ModuleStyle.values) {
    for (final kind in AdapterKind.values) {
      group('${style.name} on ${kind.name}', () => _suite(style, kind));
    }
  }
}

int _items(String html) => RegExp(r'<li[ >]').allMatches(html).length;

void _suite(ModuleStyle style, AdapterKind kind) {
  late LoopbackServer server; // Set in setUp before every test.
  setUp(() async => server = await LoopbackServer.start(style, kind));
  tearDown(() async {
    await server.close();
    expect(server.errors, isEmpty);
  });

  Future<Map<String, String>> member() async => {
    'cookie': await WebSession.signIn(server, 'ann'),
    'origin': 'http://127.0.0.1:${server.port}',
    'sec-fetch-site': 'same-origin',
  };

  test('a guest sees the plain list and no htmx attributes', () async {
    final page = await server.send('GET', '/');

    expect(page.body, contains('<li>Read the grund README</li>'));
    expect(page.body, isNot(contains('hx-post')));
  });

  test('a guest cannot write fragments (401)', () async {
    final answer = await server.send(
      'POST',
      '/fragments/tasks',
      form: 'title=x',
    );

    expect(answer.status, 401);
  });

  test('a signed-in page has the htmx form, buttons and config', () async {
    final page = await server.send('GET', '/', headers: await member());

    expect(page.body, contains('hx-post="/fragments/tasks"'));
    expect(page.body, contains('hx-delete='));
    expect(page.body, contains('/static/vendor/htmx.min.js'));
    expect(page.body, contains('htmx-config'));
    expect(page.body, contains('422'));
  });

  test('POST creates a task and answers the panel only (201)', () async {
    final answer = await server.send(
      'POST',
      '/fragments/tasks',
      form: 'title=Buy+milk',
      headers: await member(),
    );

    expect(answer.status, 201);
    expect(answer.headers['content-type'], contains('text/html'));
    expect(answer.body, startsWith('<section id="tasks"'));
    expect(answer.body, contains('Buy milk'));
    expect(answer.body, isNot(contains('<html')));
  });

  for (final (label, title) in [
    ('empty', ''),
    ('blank', '+++'),
    ('over 200 characters', 'x' * 201),
  ]) {
    test('a $label title is refused with the panel (422)', () async {
      final headers = await member();
      final before = await server.send('GET', '/', headers: headers);

      final answer = await server.send(
        'POST',
        '/fragments/tasks',
        form: 'title=$title',
        headers: headers,
      );

      expect(answer.status, 422);
      expect(answer.body, startsWith('<section id="tasks"'));
      expect(answer.body, contains('1 to 200 characters'));
      expect(answer.body, contains('hx-post="/fragments/tasks"'));
      expect(_items(answer.body), _items(before.body));
    });
  }

  test('a hostile title is escaped, also as the draft of a 422', () async {
    final headers = await member();
    final title = Uri.encodeQueryComponent('<b>x</b>&"');

    final created = await server.send(
      'POST',
      '/fragments/tasks',
      form: 'title=$title',
      headers: headers,
    );
    final refused = await server.send(
      'POST',
      '/fragments/tasks',
      form: 'title=${Uri.encodeQueryComponent('<b>x</b>&"' * 30)}',
      headers: headers,
    );

    expect(created.body, contains('&lt;b&gt;'));
    expect(created.body, isNot(contains('<b>x')));
    expect(refused.status, 422);
    expect(refused.body, contains('value="&lt;b&gt;'));
    expect(refused.body, isNot(contains('<b>x')));
  });

  test('DELETE removes a task; an unknown id is 404', () async {
    final headers = await member();
    final created = await server.send(
      'POST',
      '/fragments/tasks',
      form: 'title=Gone+soon',
      headers: headers,
    );
    final id = RegExp(r'Gone soon<button hx-delete="/fragments/tasks/(\d+)"')
        .firstMatch(created.body)!
        .group(1);

    final deleted = await server.send(
      'DELETE',
      '/fragments/tasks/$id',
      headers: headers,
    );
    final unknown = await server.send(
      'DELETE',
      '/fragments/tasks/99999',
      headers: headers,
    );

    expect(deleted.status, 200);
    expect(deleted.body, startsWith('<section id="tasks"'));
    expect(deleted.body, isNot(contains('Gone soon')));
    expect(unknown.status, 404);
  });

  test('a cross-site write is refused, same-origin passes', () async {
    final headers = await member();
    final cookie = {'cookie': headers['cookie']!};

    for (final foreign in [
      {'sec-fetch-site': 'cross-site'},
      {'origin': 'http://evil.test'},
    ]) {
      final refused = await server.send(
        'POST',
        '/fragments/tasks',
        form: 'title=x',
        headers: {...cookie, ...foreign},
      );
      expect(refused.status, 403);
      expect(refused.json, containsPair('code', 'cross_site_request'));
    }
    final allowed = await server.send(
      'POST',
      '/fragments/tasks',
      form: 'title=x',
      headers: headers,
    );
    expect(allowed.status, 201);
  });

  test('a cross-site DELETE is refused and the task stays', () async {
    final headers = await member();
    final created = await server.send(
      'POST',
      '/fragments/tasks',
      form: 'title=Stays',
      headers: headers,
    );
    final id = RegExp(r'Stays<button hx-delete="/fragments/tasks/(\d+)"')
        .firstMatch(created.body)!
        .group(1);

    final refused = await server.send(
      'DELETE',
      '/fragments/tasks/$id',
      headers: {'cookie': headers['cookie']!, 'sec-fetch-site': 'cross-site'},
    );
    final after = await server.send('GET', '/', headers: headers);

    expect(refused.status, 403);
    expect(refused.json, containsPair('code', 'cross_site_request'));
    expect(after.body, contains('Stays'));
  });

  test('htmx is served with an ETag and revalidates to 304', () async {
    final first = await server.send('GET', '/static/vendor/htmx.min.js');
    final again = await server.send(
      'GET',
      '/static/vendor/htmx.min.js',
      headers: {'if-none-match': first.headers['etag']!},
    );

    expect(first.status, 200);
    expect(first.headers['content-type'], contains('javascript'));
    expect(first.headers['etag'], isNotNull);
    expect(again.status, 304);
  });
}
