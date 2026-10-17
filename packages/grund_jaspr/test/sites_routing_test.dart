import 'dart:io';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/server.dart' hide Key;
import 'package:test/test.dart';

import 'helpers/pages.dart';
import 'helpers/pages_app.dart';
import 'helpers/sites.dart';

Future<TestClient> startSites([List<Module> extra = const []]) =>
    PagesApp.start([
      const JasprModule(),
      const PublicSiteModule(),
      const AdminSiteModule(),
      const HomePagesModule(),
      const UsersPagesModule(),
      ...extra,
    ]);

Future<TestClient> startCustom(List<Page> pages) =>
    startPublic([homePage(const Component.text('Home')), ...pages]);

void main() {
  group('routing', () {
    test('GET / renders the public home page', () async {
      final client = await startSites();

      final response = await client.get('/');

      expect(response.status, 200);
      expect(response.headers['content-type'], 'text/html; charset=utf-8');
      expect(response.text, contains('Home'));
    });

    test('GET /about renders a public page', () async {
      final client = await startSites();

      expect((await client.get('/about')).status, 200);
    });

    test('an admin page with the guard header is rendered', () async {
      final client = await startSites();

      final response = await client.get('/admin/users', headers: adminHeaders);

      expect(response.status, 200);
      expect(response.text, contains('Users'));
    });

    test('a path parameter reaches the builder', () async {
      final client = await startSites();

      final response = await client.get(
        '/admin/users/7',
        headers: adminHeaders,
      );

      expect(response.text, contains('User 7'));
    });

    test('the admin site root page is rendered', () async {
      final client = await startSites();

      final response = await client.get('/admin', headers: adminHeaders);

      expect(response.text, contains('Dashboard'));
    });

    test('an admin page without the header is 401', () async {
      final client = await startSites();

      expect((await client.get('/admin/users')).status, 401);
    });

    test('the admin shell wraps admin pages', () async {
      final client = await startSites();

      final response = await client.get('/admin/users', headers: adminHeaders);

      expect(response.text, contains('<div class="admin">'));
    });
  });

  group('not found', () {
    test('an unknown public path is the public notFound() with 404', () async {
      final client = await startSites();

      final response = await client.get('/nope');

      expect(response.status, 404);
      expect(response.headers['content-type'], contains('text/html'));
      expect(response.text, contains('public not found'));
    });

    test(
      'an unknown admin path is the admin notFound() in its shell',
      () async {
        final client = await startSites();

        final response = await client.get('/admin/nope', headers: adminHeaders);

        expect(response.status, 404);
        expect(response.text, contains('<div class="admin">'));
        expect(response.text, contains('admin not found'));
      },
    );

    test(
      'an unknown admin path for a guest is 401, not the admin 404',
      () async {
        final client = await startSites();

        expect((await client.get('/admin/nope')).status, 401);
      },
    );

    test('a builder that throws NotFoundException is the site 404', () async {
      final client = await startCustom([
        Page('/gone', build: (_) => throw const NotFoundException()),
      ]);

      final response = await client.get('/gone');

      expect(response.status, 404);
      expect(response.text, contains('public not found'));
    });
  });

  group('hardening', () {
    test('HEAD of a page is 200', () async {
      final client = await startSites();

      final response = await client.request('HEAD', '/about');

      expect(response.status, 200);
    });

    test('a doubled or trailing slash still reaches the page', () async {
      final client = await startSites();

      expect((await client.get('//about')).status, 200);
      expect((await client.get('/about/')).status, 200);
    });

    test('another letter case does not reach the admin site', () async {
      final client = await startSites();

      final response = await client.get('/ADMIN/users', headers: adminHeaders);

      expect(response.status, 404);
      expect(response.text, isNot(contains('admin')));
    });

    test('an encoded slash does not serve an admin page', () async {
      final client = await startSites();

      final response = await client.get(
        '/admin%2Fusers',
        headers: adminHeaders,
      );

      expect(response.text, isNot(contains('Users')));
    });

    test('two sites do not mix: /users is public, not admin', () async {
      final client = await startSites([const PublicUsersModule()]);

      final response = await client.get('/users');

      expect(response.text, contains('Public users'));
      expect(response.text, isNot(contains('class="admin"')));
    });
  });

  group('failures', () {
    test('a builder that throws StateError is 500', () async {
      final stderrText = StringBuffer();
      final response = await IOOverrides.runZoned(() async {
        final client = await startCustom([
          Page('/boom', build: (_) => throw StateError('secret detail')),
        ]);
        return client.get('/boom');
      }, stderr: () => CapturedStderr(stderrText));

      expect(response.status, 500);
      expect(response.text, isNot(contains('secret detail')));
    });

    test('a component that throws while rendering is 500', () async {
      final stderrText = StringBuffer();
      final response = await IOOverrides.runZoned(() async {
        final client = await startCustom([
          Page('/broken', build: (_) => const BrokenPage()),
        ]);
        return client.get('/broken');
      }, stderr: () => CapturedStderr(stderrText));

      expect(response.status, 500);
    });
  });
}
