// The addresses of the pages on the same four servers as e2e_test.dart: the
// Markdown alternate of the home page, content negotiation, the canonical
// redirect of a trailing slash and a generated site file.
import 'package:tasks_api/tasks_api.dart';
import 'package:test/test.dart';

import 'helpers/loopback_server.dart';

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

  test('GET /index.md is the Markdown of the home page', () async {
    final page = await server.send('GET', '/index.md');

    expect(page.status, 200);
    expect(page.headers['content-type'], 'text/markdown; charset=utf-8');
    expect(page.body, startsWith('# Tasks'));
    expect(page.body, contains('- [ ] Read the grund README'));
  });

  test('HEAD /index.md answers 200 without a body', () async {
    final page = await server.send('HEAD', '/index.md');

    expect(page.status, 200);
    expect(page.headers['content-type'], 'text/markdown; charset=utf-8');
    expect(page.body, isEmpty);
  });

  test(
    'GET / with accept: text/markdown is Markdown, varying on accept',
    () async {
      final page = await server.send(
        'GET',
        '/',
        headers: {'accept': 'text/markdown'},
      );

      expect(page.status, 200);
      expect(page.headers['content-type'], 'text/markdown; charset=utf-8');
      expect(page.headers['vary'], contains('accept'));
      expect(page.body, startsWith('# Tasks'));
    },
  );

  test('a browser GET / is HTML that links the alternate', () async {
    final page = await server.send(
      'GET',
      '/',
      headers: {'accept': 'text/html,application/xhtml+xml,*/*;q=0.8'},
    );

    expect(page.status, 200);
    expect(page.headers['content-type'], 'text/html; charset=utf-8');
    expect(page.headers['vary'], contains('accept'));
    expect(page.headers['link'], contains('rel="alternate"'));
    expect(page.headers['link'], contains('/index.md'));
  });

  test('GET /login/ redirects to /login without a canonical link', () async {
    final page = await server.send('GET', '/login/');

    expect(page.status, 308);
    expect(page.headers['location'], '/login');
    expect(page.headers['link'] ?? '', isNot(contains('rel="canonical"')));
  });

  test('GET /robots.txt is a plain text site file', () async {
    final file = await server.send('GET', '/robots.txt');

    expect(file.status, 200);
    expect(file.headers['content-type'], 'text/plain; charset=utf-8');
    expect(file.body, contains('User-agent: *'));
  });
}
