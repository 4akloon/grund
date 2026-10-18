import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:test/test.dart';

import 'helpers/client_samples.dart';

void main() {
  group('JasprConfig', () {
    test('has the documented defaults', () {
      const config = JasprConfig();
      expect(config.staticPath, '/static');
      expect(config.rootFiles, isEmpty);
      expect(config.sitemapChunkSize, 50000);
      expect(config.sitemapCacheLifetime, const Duration(seconds: 60));
    });

    for (final (name, config) in [
      (
        'a staticPath without a leading slash',
        const JasprConfig(staticPath: 'static'),
      ),
      (
        'a staticPath with a trailing slash',
        const JasprConfig(staticPath: '/static/'),
      ),
      ('an empty staticPath', const JasprConfig(staticPath: '')),
      (
        'a rootFiles entry with a slash',
        const JasprConfig(rootFiles: ['a/b.txt']),
      ),
      ('an empty rootFiles entry', const JasprConfig(rootFiles: [''])),
      ('a "." rootFiles entry', const JasprConfig(rootFiles: ['.'])),
      ('a ".." rootFiles entry', const JasprConfig(rootFiles: ['..'])),
      ('a rootFiles entry with a star', const JasprConfig(rootFiles: ['*'])),
      ('a rootFiles entry with a colon', const JasprConfig(rootFiles: [':a'])),
      ('a staticPath with a star', const JasprConfig(staticPath: '/st*')),
      ('a staticPath with a colon', const JasprConfig(staticPath: '/:x')),
      ('a sitemapChunkSize below 1', const JasprConfig(sitemapChunkSize: 0)),
    ]) {
      test('validate refuses $name', () {
        expect(config.validate, throwsA(isA<JasprSetupError>()));
      });
    }

    test('validate accepts the defaults', () {
      expect(const JasprConfig().validate, returnsNormally);
    });

    test('withLiveReloadUrl keeps the new fields', () {
      final copy = const JasprConfig(
        staticPath: '/assets',
        rootFiles: ['robots.txt'],
        sitemapChunkSize: 10,
        sitemapCacheLifetime: Duration(seconds: 5),
      ).withLiveReloadUrl(Uri.parse('http://localhost:1/'));
      expect(copy.staticPath, '/assets');
      expect(copy.rootFiles, ['robots.txt']);
      expect(copy.sitemapChunkSize, 10);
      expect(copy.sitemapCacheLifetime, const Duration(seconds: 5));
      expect(copy.liveReloadUrl, Uri.parse('http://localhost:1/'));
    });

    group('clients', () {
      const counter = ClientComponent<Counter>(
        'counter',
        decode: Counter.fromParams,
        encode: Counter.toParams,
      );
      const clients = ClientComponents([counter]);

      test('clientId is derived from the default staticPath', () {
        expect(
          const JasprConfig(clients: clients).clientId,
          'static/client/main.client.dart.js',
        );
      });

      test('clientId follows a custom staticPath', () {
        expect(
          const JasprConfig(staticPath: '/assets', clients: clients).clientId,
          'assets/client/main.client.dart.js',
        );
      });

      test('clientId is null without clients', () {
        expect(const JasprConfig().clientId, isNull);
      });

      test('clientId is null for an empty list', () {
        expect(
          const JasprConfig(clients: ClientComponents([])).clientId,
          isNull,
        );
      });

      test('withLiveReloadUrl keeps the same clients object', () {
        final copy = const JasprConfig(clients: clients)
            .withLiveReloadUrl(Uri.parse('http://localhost:1/'));
        expect(copy.clients, same(clients));
      });

      test('validate reports every problem of the list', () {
        const config = JasprConfig(
          clients: ClientComponents([
            counter,
            ClientComponent<Plain>('counter', decode: _plain),
            ClientComponent<LoudCounter>('Bad Name', decode: _loud),
          ]),
        );
        expect(
          config.validate,
          throwsA(
            isA<JasprSetupError>().having(
              (e) => e.reason,
              'reason',
              allOf(
                contains("'counter' is registered twice"),
                contains("'Bad Name'"),
              ),
            ),
          ),
        );
      });

      test('validate accepts a correct list', () {
        expect(const JasprConfig(clients: clients).validate, returnsNormally);
      });
    });
  });
}

Plain _plain(Map<String, Object?> _) => const Plain();

LoudCounter _loud(Map<String, Object?> _) => const LoudCounter(0, '');
