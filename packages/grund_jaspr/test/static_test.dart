import 'dart:io';

import 'package:grund/grund.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/server.dart' hide Key;
import 'package:test/test.dart';

import 'helpers/pages_app.dart';
import 'helpers/sites.dart';
import 'helpers/static_site.dart';
import 'helpers/temp_dir.dart';

void main() {
  test('a file under the static path is served with its type', () async {
    final client = await startWithStatic(staticDirectory());

    final response = await client.get('/static/styles.css');

    expect(response.status, 200);
    expect(response.headers['content-type'], 'text/css; charset=utf-8');
    expect(response.text, 'body{}');
  });

  test('a nested file is served', () async {
    final client = await startWithStatic(staticDirectory());

    final response = await client.get('/static/sub/a.txt');

    expect(response.status, 200);
    expect(response.text, 'nested');
  });

  test('a rootFiles entry is served at the root', () async {
    final client = await startWithStatic(staticDirectory());

    final response = await client.get('/favicon.ico');

    expect(response.status, 200);
    expect(response.text, 'icon');
  });

  test('a file that is not a rootFiles entry is not served at the root', () {
    final dir = staticDirectory();
    return startWithStatic(dir).then((client) async {
      final response = await client.get('/styles.css');

      expect(response.status, 404);
      expect(response.json, containsPair('code', 'file_not_found'));
    });
  });

  test('a missing file is a 404 problem with file_not_found', () async {
    final client = await startWithStatic(staticDirectory());

    final response = await client.get('/static/missing.css');

    expect(response.status, 404);
    expect(response.headers['content-type'], 'application/problem+json');
    expect(response.json, containsPair('code', 'file_not_found'));
  });

  test('a directory under the static path is a 404', () async {
    final client = await startWithStatic(staticDirectory());

    final response = await client.get('/static/sub');

    expect(response.status, 404);
    expect(response.json, containsPair('code', 'file_not_found'));
  });

  test('the page /:slug does not swallow static files', () async {
    final client = await startWithStatic(staticDirectory());

    final css = await client.get('/static/styles.css');
    final icon = await client.get('/favicon.ico');
    final page = await client.get('/about');

    expect(css.text, 'body{}');
    expect(icon.text, 'icon');
    expect(page.text, contains('slug page'));
  });

  test('a guest gets static files although the site is guarded', () async {
    final dir = staticDirectory();
    final client = await PagesApp.start([
      JasprModule(config: staticConfig(dir)),
      const UsersPagesModule(),
    ]);

    final response = await client.get('/static/styles.css');
    final guarded = await client.get('/admin/users');

    expect(response.status, 200);
    expect(guarded.status, 401);
  });

  // The test client normalises `..` and `%2e%2e` (Uri.normalizePath) before
  // the request reaches the app, so `/static/%2e%2e/x` arrives as `/x`; the
  // segment check itself is covered in static_files_test.dart. What is
  // asserted here: a 404 and no content of the files outside the directory.
  for (final target in [
    '/static/../x',
    '/static/%2e%2e/x',
    '/static/%2e%2e/secret.txt',
    '/static/a/%2F..%2F..%2Fsecret.txt',
    '/static/.hidden',
    '/static/a%5C..%5Csecret.txt',
  ]) {
    test('$target never leaves the static directory', () async {
      final dir = TempDir.create()
        ..write('web/.hidden', 'TOPSECRET')
        ..write('secret.txt', 'TOPSECRET');
      final client = await startPublic([
        homePage(const Component.text('Home')),
      ], config: JasprConfig(staticDirectory: dir.resolve('web')));

      final response = await client.get(target);

      expect(response.status, 404);
      expect(response.text, isNot(contains('TOPSECRET')));
    });
  }

  test('a symlink out of the static directory is not served', () async {
    final dir = TempDir.create()..write('secret.txt', 'TOPSECRET');
    Directory(dir.resolve('web')).createSync();
    Link(dir.resolve('web/link.txt')).createSync(dir.resolve('secret.txt'));
    final client = await startPublic([
      homePage(const Component.text('Home')),
    ], config: JasprConfig(staticDirectory: dir.resolve('web')));

    final response = await client.get('/static/link.txt');

    expect(response.status, 404);
    expect(response.text, isNot(contains('TOPSECRET')));
  });

  test('a file with a page suffix is a file under the static path', () async {
    final dir = staticDirectory()..write('doc.html', '<p>doc</p>');
    final client = await startWithStatic(dir);

    final response = await client.get('/static/doc.html');

    expect(response.status, 200);
    expect(response.text, '<p>doc</p>');
  });

  test('a site on the static path is an InvalidSitePathError', () {
    expect(
      PagesApp.start([
        const JasprModule(),
        _SiteModule<_StaticRootSite>(_StaticRootSite.new),
      ]),
      throwsA(_declaration<InvalidSitePathError>()),
    );
  });

  test('a site under the static path is an InvalidSitePathError', () {
    expect(
      PagesApp.start([
        const JasprModule(),
        _SiteModule<_StaticChildSite>(_StaticChildSite.new),
      ]),
      throwsA(_declaration<InvalidSitePathError>()),
    );
  });

  test('a page under the static path is a ReservedPagePathError', () {
    expect(
      startPublic([
        homePage(const Component.text('Home')),
        Page('/static/x', build: (_) => const Component.text('x')),
      ]),
      throwsA(_declaration<ReservedPagePathError>()),
    );
  });

  test('a page at a rootFiles entry is a ReservedPagePathError', () {
    expect(
      startPublic([
        homePage(const Component.text('Home')),
        Page('/favicon.ico', build: (_) => const Component.text('x')),
      ], config: const JasprConfig(rootFiles: ['favicon.ico'])),
      throwsA(_declaration<ReservedPagePathError>()),
    );
  });

  test('a page named like the static path is a ReservedPagePathError', () {
    expect(
      startPublic([
        homePage(const Component.text('Home')),
        Page('/static', build: (_) => const Component.text('x')),
      ]),
      throwsA(_declaration<ReservedPagePathError>()),
    );
  });

  test('ReservedPagePathError names the path and the reason', () {
    const error = ReservedPagePathError(path: '/static/x', reason: 'why');

    expect(error.message, contains('/static/x'));
    expect(error.message, contains('why'));
  });
}

/// Matches [T], whether the start failure wraps it or not.
Matcher _declaration<T extends Object>() =>
    predicate<Object>((error) => error is T || '$error'.contains('$T'), 'a $T');

final class _StaticRootSite extends PageSite {
  _StaticRootSite(super.injector);

  @override
  String get path => '/static';
}

final class _StaticChildSite extends PageSite {
  _StaticChildSite(super.injector);

  @override
  String get path => '/static/docs';
}

final class _SiteModule<S extends PageSite> extends Module {
  const _SiteModule(this._create);

  final S Function(Injector) _create;

  @override
  List<Binding<Object>> get bindings => Pages.site<S>(_create);
}
