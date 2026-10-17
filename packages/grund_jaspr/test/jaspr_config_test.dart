import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:test/test.dart';

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
  });
}
