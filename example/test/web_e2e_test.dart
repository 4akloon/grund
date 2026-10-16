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
  _signIn(() => server);
  _signOut(() => server);
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

  test('GET /login renders the sign-in page beside the API POST', () async {
    final page = await server().send('GET', '/login');

    expect(page.status, 200);
    expect(page.headers['content-type'], 'text/html; charset=utf-8');
    expect(page.body, contains('<form'));
    expect(page.body, contains('action="/login"'));
  });

  test('a path without a page is the 404 of the site', () async {
    final page = await server().send('GET', '/nowhere');

    expect(page.status, 404);
    expect(page.body, contains('No page here.'));
  });
}

/// Signing in through the form.
void _signIn(LoopbackServer Function() server) {
  Future<ApiResponse> signIn(String name, {Map<String, String>? headers}) =>
      server().send(
        'POST',
        '/login',
        form: 'name=${Uri.encodeQueryComponent(name)}',
        headers: headers ?? const {},
      );

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

  test(
    'the flash shows on the next page and is gone on the one after',
    () async {
      final login = await signIn('ann');
      final cookie = _cookieHeader(login);

      final first = await server().send(
        'GET',
        '/',
        headers: {'cookie': cookie},
      );
      // The browser applied `flash=; Max-Age=0`: only the session comes back.
      final second = await server().send(
        'GET',
        '/',
        headers: {'cookie': _sessionOnly(login)},
      );

      expect(first.body, contains('Signed in as ann.'));
      expect(first.body, contains('class="flash"'));
      expect(first.setCookies, contains(startsWith('flash=; ')));
      expect(second.body, contains('Signed in as ann.'));
      expect(second.body, isNot(contains('class="flash"')));
    },
  );

  test('a hostile name is escaped in the page', () async {
    final login = await signIn('<script>alert(1)</script>');

    final home = await server().send(
      'GET',
      '/',
      headers: {'cookie': _cookieHeader(login)},
    );

    expect(home.body, contains('&lt;script&gt;alert(1)&lt;/script&gt;'));
    expect(home.body, isNot(contains('<script>alert(1)')));
  });

  test('a session id the browser already had is not accepted', () async {
    final planted = 'A' * 43;

    final login = await signIn(
      'ann',
      headers: {'cookie': 'grund_sid=$planted'},
    );

    expect(_sessionOnly(login), isNot(contains(planted)));
    final home = await server().send(
      'GET',
      '/',
      headers: {'cookie': 'grund_sid=$planted'},
    );
    expect(home.body, isNot(contains('Signed in as')));
  });

  test('signing in again replaces the session and kills the old id', () async {
    final first = _sessionOnly(await signIn('ann'));

    final second = _sessionOnly(
      await signIn('bob', headers: {'cookie': first}),
    );

    expect(second, isNot(first));
    final old = await server().send('GET', '/', headers: {'cookie': first});
    final current = await server().send(
      'GET',
      '/',
      headers: {'cookie': second},
    );
    expect(old.body, isNot(contains('Signed in as')));
    expect(current.body, contains('Signed in as bob.'));
  });

  for (final (label, name) in [
    ('empty', ''),
    ('over 40 characters', 'x' * 41),
  ]) {
    test('$label name is a 400 and starts no session', () async {
      final login = await signIn(name);

      expect(login.status, 400);
      expect(login.setCookies, isEmpty);
    });
  }

  test('a browser-style same-origin sign-in is accepted', () async {
    final login = await signIn(
      'ann',
      headers: {
        'origin': 'http://127.0.0.1:${server().port}',
        'sec-fetch-site': 'same-origin',
      },
    );

    expect(login.status, 303);
    expect(login.setCookies, contains(startsWith('grund_sid=')));
    final home = await server().send(
      'GET',
      '/',
      headers: {'cookie': _cookieHeader(login)},
    );
    expect(home.body, contains('Signed in as ann.'));
  });

  test('a form posted from another site is refused', () async {
    final login = await signIn(
      'ann',
      headers: {'sec-fetch-site': 'cross-site'},
    );

    expect(login.status, 403);
    expect(login.setCookies, isEmpty);
  });

  test('a form posted with a foreign Origin is refused', () async {
    final login = await signIn('ann', headers: {'origin': 'http://evil.test'});

    expect(login.status, 403);
    expect(login.setCookies, isEmpty);
  });
}

/// Signing out through the form.
void _signOut(LoopbackServer Function() server) {
  Future<Map<String, String>> signedIn() async {
    final login = await server().send('POST', '/login', form: 'name=ann');
    return {'cookie': _cookieHeader(login)};
  }

  test('signing out ends the session', () async {
    final cookie = await signedIn();

    final logout = await server().send('POST', '/logout', headers: cookie);
    final home = await server().send('GET', '/', headers: cookie);

    expect(logout.status, 303);
    expect(logout.setCookies, contains(startsWith('grund_sid=; Max-Age=0; ')));
    expect(home.body, isNot(contains('Signed in as')));
  });

  for (final (label, header) in [
    ('Sec-Fetch-Site', {'sec-fetch-site': 'cross-site'}),
    ('Origin', {'origin': 'http://evil.test'}),
  ]) {
    test('a sign-out posted from another site ($label) is refused', () async {
      final cookie = await signedIn();

      final logout = await server().send(
        'POST',
        '/logout',
        headers: {...cookie, ...header},
      );
      final home = await server().send('GET', '/', headers: cookie);

      expect(logout.status, 403);
      expect(home.body, contains('Signed in as ann.'));
    });
  }
}

/// The `cookie` header a browser sends after [response]: the name and value
/// of every cookie it set.
String _cookieHeader(ApiResponse response) =>
    response.setCookies.map((cookie) => cookie.split(';').first).join('; ');

/// Only the session cookie of [response], as a browser keeps it after the
/// flash cookie was deleted.
String _sessionOnly(ApiResponse response) => response.setCookies
    .map((cookie) => cookie.split(';').first)
    .firstWhere((pair) => pair.startsWith('grund_sid='));
