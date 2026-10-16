// The pages and the session on the same four servers as e2e_test.dart:
// pages rendered with data from DI, a static file, sign-in through a form
// with both cookies over the wire, and sign-out.
import 'package:tasks_api/tasks_api.dart';
import 'package:test/test.dart';

import 'helpers/api_response.dart';
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

  _pages(() => server);
  _session(() => server);
}

/// Pages and files without a session.
void _pages(LoopbackServer Function() server) {
  test('GET / renders the tasks of the service as HTML', () async {
    final page = await server().send('GET', '/');

    expect(page.status, 200);
    expect(page.headers['content-type'], 'text/html; charset=utf-8');
    expect(page.headers['cache-control'], 'private, no-cache');
    expect(page.body, contains('<li>Read the grund README</li>'));
    expect(page.body, contains('href="/login"'));
  });

  test('the stylesheet is served from web/', () async {
    final css = await server().send('GET', '/styles.css');

    expect(css.status, 200);
    expect(css.headers['content-type'], 'text/css; charset=utf-8');
  });

  test('a path without a page is the 404 of the site', () async {
    final page = await server().send('GET', '/nowhere');

    expect(page.status, 404);
    expect(page.body, contains('No page here.'));
  });
}

/// Signing in and out through the forms.
void _session(LoopbackServer Function() server) {
  Future<ApiResponse> signIn(String name) =>
      server().send('POST', '/login', form: 'name=$name');

  test('signing in sets the session and the flash cookie (RF4, RF5)', () async {
    final login = await signIn('ann');

    expect(login.status, 303);
    expect(login.headers['location'], '/');
    expect(login.setCookies, hasLength(2));
    expect(
      login.setCookies,
      contains(
        matches(
          RegExp(
            r'^grund_sid=[A-Za-z0-9_-]{43}; Max-Age=604800; Path=/; '
            r'HttpOnly; SameSite=Lax$',
          ),
        ),
      ),
    );
    expect(login.setCookies, contains(startsWith('flash=signed-in; ')));
  });

  test('the next page sees the user and shows the flash once', () async {
    final cookie = _cookieHeader(await signIn('ann'));

    final home = await server().send('GET', '/', headers: {'cookie': cookie});

    expect(home.body, contains('Signed in as ann.'));
    expect(home.body, contains('class="flash"'));
    expect(home.setCookies, contains(startsWith('flash=; ')));
  });

  test('the name is escaped in the page', () async {
    final login = await signIn('%3Cb%3Eann');

    final home = await server().send(
      'GET',
      '/',
      headers: {'cookie': _cookieHeader(login)},
    );

    expect(home.body, contains('&lt;b&gt;ann'));
    expect(home.body, isNot(contains('<b>ann')));
  });

  test('signing out ends the session', () async {
    final cookie = {'cookie': _cookieHeader(await signIn('ann'))};

    final logout = await server().send('POST', '/logout', headers: cookie);
    final home = await server().send('GET', '/', headers: cookie);

    expect(logout.status, 303);
    expect(logout.setCookies, contains(startsWith('grund_sid=; Max-Age=0; ')));
    expect(home.body, isNot(contains('Signed in as')));
  });

  test('a form posted from another site is refused', () async {
    final login = await server().send(
      'POST',
      '/login',
      form: 'name=ann',
      headers: {'sec-fetch-site': 'cross-site'},
    );

    expect(login.status, 403);
    expect(login.setCookies, isEmpty);
  });
}

/// The `cookie` header a browser sends after [response]: the name and value
/// of every cookie it set.
String _cookieHeader(ApiResponse response) =>
    response.setCookies.map((cookie) => cookie.split(';').first).join('; ');
