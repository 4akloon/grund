import 'dart:async';

import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:grund_jaspr/src/sitemap/sitemap_chunk_cache.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'helpers/sitemap_app.dart';
import 'helpers/sitemap_sites.dart';

List<Page> _projects(RecordingEntries source) => [
  mapPage('/p/:slug', sitemap: PageSitemap(entries: source.entries)),
];

void main() {
  const lifetime = Duration(seconds: 60);
  const config = JasprConfig(sitemapChunkSize: 3);

  group('through the routes', () {
    test('two requests within the lifetime count once, then again', () async {
      final source = RecordingEntries(2);
      final h = await startSitemap([mapModule(_projects(source))]);

      await h.client.get('/sitemap.xml');
      await h.client.get('/sitemap.xml');
      expect(source.counts, 1);

      h.clock.advance(lifetime + const Duration(seconds: 1));
      await h.client.get('/sitemap.xml');
      expect(source.counts, 2);
    });

    test('20 concurrent requests count once', () async {
      final source = RecordingEntries(2);
      final h = await startSitemap([mapModule(_projects(source))]);

      final responses = await Future.wait([
        for (var i = 0; i < 20; i++) h.client.get('/sitemap.xml'),
      ]);

      expect(responses.map((r) => r.status), everyElement(200));
      expect(source.counts, 1);
      expect(source.slices, hasLength(1));
    });

    test('invalidateSitemap drops the cache', () async {
      final source = RecordingEntries(2);
      final h = await startSitemap([mapModule(_projects(source))]);
      await h.client.get('/sitemap.xml');

      source.total = 3;
      h.catalog.invalidateSitemap();
      final body = (await h.client.get('/sitemap.xml')).text;

      expect(source.counts, 2);
      expect(body, contains('https://x.test/p/s2'));
    });

    test('a chunk asks the source only for its own range', () async {
      final source = RecordingEntries(7);
      final h = await startSitemap([
        mapModule(_projects(source)),
      ], config: config);

      await h.client.get('/sitemap/2.xml');

      // The root page is address 0, so chunk 2 holds entries 2..4.
      expect(source.slices, [(2, 3)]);
      await h.client.get('/sitemap/3.xml');
      expect(source.slices, [(2, 3), (5, 2)]);
    });

    test('a chunk before the entries never asks for them', () async {
      final source = RecordingEntries(7);
      final h = await startSitemap([
        mapModule([..._projects(source), mapPage('/z')]),
      ], config: config);

      await h.client.get('/sitemap/1.xml');

      expect(source.slices, [(0, 2)]);
    });

    test('an all source is loaded once per fill', () async {
      var loads = 0;
      final h = await startSitemap([
        mapModule([
          mapPage(
            '/p/:slug',
            sitemap: PageSitemap(
              entries: slugEntries([
                'a',
                'b',
                'c',
                'd',
              ], onLoad: (_) => loads++),
            ),
          ),
        ]),
      ], config: config);

      await h.client.get('/sitemap/2.xml');
      await h.client.get('/sitemap/2.xml');

      // One load for the plan, one for the chunk; the second request hits.
      expect(loads, 2);
    });

    test('a failing source is 500, logged, and not cached', () async {
      final source = RecordingEntries(2)..failure = StateError('db down');
      final h = await startSitemap([mapModule(_projects(source))]);
      final records = <LogRecord>[];
      final subscription = Logger.root.onRecord.listen(records.add);
      addTearDown(subscription.cancel);
      final level = Logger.root.level;
      Logger.root.level = Level.ALL;
      addTearDown(() => Logger.root.level = level);

      final failed = await h.client.get('/sitemap.xml');
      source.failure = null;
      final fixed = await h.client.get('/sitemap.xml');

      expect(failed.status, 500);
      expect(records.where((r) => r.level == Level.SEVERE), isNotEmpty);
      expect(fixed.status, 200);
      expect(fixed.text, contains('https://x.test/p/s1'));
    });

    test('mismatching entry keys are 500', () async {
      final h = await startSitemap([
        mapModule([
          mapPage(
            '/p/:slug',
            sitemap: PageSitemap(
              entries: SitemapEntries.all(
                (_) async => [
                  SitemapEntry(params: {'other': 'x'}),
                ],
              ),
            ),
          ),
        ]),
      ]);

      expect((await h.client.get('/sitemap.xml')).status, 500);
    });
  });

  group('SitemapChunkCache', () {
    test('a failed load is not stored and the next get retries', () async {
      final cache = SitemapChunkCache(lifetime, FakeClock().now);
      var calls = 0;

      await expectLater(
        cache.get<int>('k', () async {
          calls++;
          throw StateError('x');
        }),
        throwsStateError,
      );
      final value = await cache.get<int>('k', () async => ++calls);

      expect(value, 2);
    });

    test('a throwing load does not leave a pending failure', () async {
      final cache = SitemapChunkCache(lifetime, FakeClock().now);

      await expectLater(
        cache.get<int>('k', () => throw StateError('sync')),
        throwsStateError,
      );

      expect(await cache.get<int>('k', () async => 1), 1);
    });

    test('at most 64 keys stay; the oldest is evicted', () async {
      final cache = SitemapChunkCache(lifetime, FakeClock().now);
      for (var i = 0; i < SitemapChunkCache.maxKeys + 1; i++) {
        await cache.get<int>('k$i', () async => i);
      }
      var reloads = 0;

      await cache.get<int>('k0', () async => ++reloads);
      await cache.get<int>('k64', () async => ++reloads);

      expect(reloads, 1);
    });

    test('a load running during clear is not stored', () async {
      final cache = SitemapChunkCache(lifetime, FakeClock().now);
      final gate = Completer<int>();
      final pending = cache.get<int>('k', () => gate.future);

      cache.clear();
      gate.complete(1);
      await pending;

      expect(await cache.get<int>('k', () async => 2), 2);
    });
  });
}
