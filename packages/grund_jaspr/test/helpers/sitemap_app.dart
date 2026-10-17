import 'package:grund/grund.dart';
import 'package:grund_http/testing.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:grund_jaspr/src/site/page_registry.dart';
import 'package:grund_jaspr/src/sitemap/sitemap_chunk_cache.dart';

import 'pages_app.dart';

/// A clock the test moves by hand.
final class FakeClock {
  DateTime _now = DateTime.utc(2026, 1, 1);

  /// The current fake time.
  DateTime now() => _now;

  /// Moves the clock forward by [duration].
  void advance(Duration duration) => _now = _now.add(duration);
}

/// A started application with its client, catalog and clock.
typedef SitemapHarness = ({
  PageRegistry registry,
  TestClient client,
  PageCatalog catalog,
  FakeClock clock,
});

/// Starts [modules] with a [SitemapChunkCache] on a fake clock.
Future<SitemapHarness> startSitemap(
  List<Module> modules, {
  JasprConfig config = const JasprConfig(),
}) async {
  final clock = FakeClock();
  final app = await StartedPagesApp.startWith(
    [JasprModule(config: config), ...modules],
    overrides: [
      Singleton<SitemapChunkCache>(
        (_) => SitemapChunkCache(config.sitemapCacheLifetime, clock.now),
        dependsOn: const [],
      ),
    ],
  );
  return (
    registry: app.injector<PageRegistry>(),
    client: TestClient.of(app),
    catalog: app.injector<PageCatalog>(),
    clock: clock,
  );
}

/// A paged source of [total] entries for `slug` that records its calls.
final class RecordingEntries {
  /// Creates a source of [total] entries.
  RecordingEntries(this.total);

  /// The number of entries.
  int total;

  /// When set, `count` and `load` throw this.
  Object? failure;

  /// How many times `count` was called.
  int counts = 0;

  /// The `(offset, limit)` of every `load` call.
  final List<(int, int)> slices = [];

  /// The source to put in `PageSitemap`.
  late final SitemapEntries entries = SitemapEntries.paged(
    count: (_) async {
      counts++;
      final error = failure;
      if (error != null) throw error;
      return total;
    },
    load: (_, offset, limit) async {
      slices.add((offset, limit));
      final end = offset + limit < total ? offset + limit : total;
      return [
        for (var i = offset; i < end; i++)
          SitemapEntry(params: {'slug': 's$i'}),
      ];
    },
  );
}

/// Collects the log records of the test; restored after it.
List<LogRecord> captureLog() {
  final records = <LogRecord>[];
  final level = Logger.root.level;
  Logger.root.level = Level.ALL;
  final subscription = Logger.root.onRecord.listen(records.add);
  addTearDown(() {
    Logger.root.level = level;
    return subscription.cancel();
  });
  return records;
}
