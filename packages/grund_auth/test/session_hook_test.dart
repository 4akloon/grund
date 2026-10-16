import 'package:grund_auth/grund_auth.dart';
import 'package:test/test.dart';

import 'helpers/frozen_store.dart';
import 'helpers/session_app.dart';

const _token = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

Session _session({required Duration endsIn}) => Session(
  id: _token,
  userId: 'ann',
  createdAt: DateTime.now().subtract(const Duration(days: 1)),
  expiresAt: DateTime.now().add(endsIn),
);

void main() {
  test('a live session puts the CurrentUser in the call scope', () async {
    final store = FrozenStore();
    store.sessions[_token] = _session(endsIn: const Duration(hours: 1));
    final client = await SessionApp.start(store: () => store);

    final me = await client.get(
      '/me',
      headers: {'cookie': 'grund_sid=$_token'},
    );

    expect(me.text, 'ann');
  });

  test('no cookie means no CurrentUser and no error', () async {
    final client = await SessionApp.start();

    final me = await client.get('/me');

    expect(me.status, 200);
    expect(me.text, 'nobody');
  });

  test('an unknown token means no CurrentUser', () async {
    final client = await SessionApp.start();

    final me = await client.get(
      '/me',
      headers: {'cookie': 'grund_sid=$_token'},
    );

    expect(me.text, 'nobody');
  });

  test(
    'an expired session means no CurrentUser, also from a store that keeps it',
    () async {
      final store = FrozenStore();
      store.sessions[_token] = _session(endsIn: const Duration(seconds: -1));
      final client = await SessionApp.start(store: () => store);

      final me = await client.get(
        '/me',
        headers: {'cookie': 'grund_sid=$_token'},
      );

      expect(me.text, 'nobody');
    },
  );

  test('a forged value that is not a token is not looked up', () async {
    final store = FrozenStore();
    final client = await SessionApp.start(store: () => store);

    final me = await client.get('/me', headers: {'cookie': 'grund_sid=admin'});

    expect(me.text, 'nobody');
    expect(store.reads, 0);
  });

  test('refuses a cross-site POST by default', () async {
    final client = await SessionApp.start();

    final response = await client.post(
      '/echo',
      headers: {'sec-fetch-site': 'cross-site'},
    );

    expect(response.status, 403);
    expect(response.json, containsPair('code', 'cross_site_request'));
  });

  test('lets a cross-site POST through with sameOrigin off', () async {
    final client = await SessionApp.start(
      config: const SessionConfig(sameOrigin: false),
    );

    final response = await client.post(
      '/echo',
      headers: {'sec-fetch-site': 'cross-site'},
    );

    expect(response.status, 200);
  });
}
