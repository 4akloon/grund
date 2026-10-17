import 'package:grund_auth/grund_auth.dart';
import 'package:grund_auth/src/session/session_tokens.dart';
import 'package:test/test.dart';

import 'helpers/frozen_store.dart';
import 'helpers/session_app.dart';

const _form = {'content-type': 'application/x-www-form-urlencoded'};

void main() {
  test(
    'start sets an HttpOnly session cookie with the configured attributes',
    () async {
      final client = await SessionApp.start();

      final response = await client.request(
        'POST',
        '/login',
        body: 'name=ann',
        headers: _form,
      );

      expect(response.status, 303);
      expect(
        SessionApp.header(response, 'grund_sid'),
        matches(
          RegExp(
            r'^grund_sid=[A-Za-z0-9_-]{43}; Max-Age=604800; Path=/; Secure; HttpOnly; SameSite=Lax$',
          ),
        ),
      );
    },
  );

  test('the session cookie signs the next request in', () async {
    final client = await SessionApp.start();
    final login = await client.request(
      'POST',
      '/login',
      body: 'name=ann',
      headers: _form,
    );
    final token = SessionApp.cookie(login, 'grund_sid');

    final me = await client.get('/me', headers: {'cookie': 'grund_sid=$token'});

    expect(me.text, 'ann');
  });

  test('the session cookie and the handler\'s own cookie both reach the client (RF5)', () async {
    final client = await SessionApp.start();

    final response = await client.request(
      'POST',
      '/login',
      body: 'name=ann',
      headers: _form,
    );

    expect(SessionApp.cookie(response, 'grund_sid'), isNotNull);
    expect(SessionApp.cookie(response, 'flash'), 'signed-in');
  });

  test('signing in replaces the token the request came with (RF1)', () async {
    final client = await SessionApp.start();
    final mallory = await client.request(
      'POST',
      '/login',
      body: 'name=mallory',
      headers: _form,
    );
    final planted = SessionApp.cookie(mallory, 'grund_sid');

    final ann = await client.request(
      'POST',
      '/login',
      body: 'name=ann',
      headers: {..._form, 'cookie': 'grund_sid=$planted'},
    );
    final withPlanted = await client.get(
      '/me',
      headers: {'cookie': 'grund_sid=$planted'},
    );

    expect(SessionApp.cookie(ann, 'grund_sid'), isNot(planted));
    expect(withPlanted.text, 'nobody');
  });

  test(
    'a token the attacker made up is not adopted on sign-in (RF1)',
    () async {
      final store = FrozenStore();
      final client = await SessionApp.start(store: () => store);
      const planted = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

      final ann = await client.request(
        'POST',
        '/login',
        body: 'name=ann',
        headers: {..._form, 'cookie': 'grund_sid=$planted'},
      );

      expect(SessionApp.cookie(ann, 'grund_sid'), isNot(planted));
      expect(store.sessions.keys, isNot(contains(planted)));
    },
  );

  test('end deletes the session and expires the cookie', () async {
    final client = await SessionApp.start();
    final login = await client.request(
      'POST',
      '/login',
      body: 'name=ann',
      headers: _form,
    );
    final cookie = {
      'cookie': 'grund_sid=${SessionApp.cookie(login, 'grund_sid')}',
    };

    final logout = await client.post('/logout', headers: cookie);
    final me = await client.get('/me', headers: cookie);

    expect(
      SessionApp.header(logout, 'grund_sid'),
      startsWith('grund_sid=; Max-Age=0; Path=/;'),
    );
    expect(me.text, 'nobody');
  });

  test('start puts the CurrentUser in the call scope', () async {
    final client = await SessionApp.start();

    final response = await client.post('/login-echo');

    expect(response.text, 'ann');
  });

  test('a store that returns an expired session does not sign in', () async {
    final store = FrozenStore();
    final token = SessionTokens().next();
    final past = DateTime.now().subtract(const Duration(hours: 1));
    await store.create(
      Session(
        id: token,
        userId: 'ann',
        createdAt: past.subtract(const Duration(days: 1)),
        expiresAt: past,
      ),
    );
    final client = await SessionApp.start(store: () => store);

    final me = await client.get('/me', headers: {'cookie': 'grund_sid=$token'});

    expect(me.text, 'nobody');
    expect(store.reads, 1);
  });
}
