import 'package:grund/grund.dart';

import '../error/page_runtime_error.dart';
import '../jaspr_config.dart';
import '../page/page_path.dart';
import '../page/page_sitemap.dart';
import '../sitemap/all_sitemap_entries.dart';
import '../sitemap/sitemap_entries.dart';
import '../sitemap/sitemap_entry.dart';
import '../sitemap/sitemap_url.dart';
import 'snapshot_pages.dart';

/// Turns the pages of one site into sitemap addresses, reading the
/// `entries` of parameterised pages chunk by chunk.
final class SitemapSource {
  /// Creates the source; [_config] gives the chunk size.
  SitemapSource(this._config);

  final JasprConfig _config;

  /// The addresses of [pages] (all of one site, sorted by path); empty when
  /// the site has no `sitemapBaseUrl`.
  Stream<SitemapUrl> urls(List<DeclaredPage> pages) async* {
    for (final declared in pages) {
      final base = declared.page.site.sitemapBaseUrl;
      final sitemap = declared.page.page.meta.sitemap;
      if (base == null || !_isListed(declared, sitemap)) continue;
      final path = PagePath.parse(declared.page.path);
      if (!path.hasParams) {
        yield _urlOf(base, declared.page.path, sitemap, null);
        continue;
      }
      yield* _entryUrls(base, declared, sitemap, path.paramNames);
    }
  }

  // The rules of the sitemap: an explicit `false` leaves a page out; a page
  // with its own hooks needs an explicit `true`.
  static bool _isListed(DeclaredPage declared, PageSitemap sitemap) {
    if (sitemap.included == false) return false;
    final hooked = declared.page.page.hooks.use.isNotEmpty;
    return !hooked || sitemap.included == true;
  }

  Stream<SitemapUrl> _entryUrls(
    Uri base,
    DeclaredPage declared,
    PageSitemap sitemap,
    List<String> paramNames,
  ) async* {
    final entries = sitemap.entries;
    if (entries == null) return;
    final injector = declared.injector;
    final path = declared.page.path;
    final chunk = _config.sitemapChunkSize;
    final Stream<List<SitemapEntry>> chunks;
    if (entries is AllSitemapEntries) {
      chunks = _inMemoryChunks(await entries.loadAll(injector), chunk);
    } else {
      chunks = _pagedChunks(entries, injector, chunk);
    }
    await for (final entry in chunks.expand((list) => list)) {
      _checkParams(path, paramNames, entry);
      yield _urlOf(base, path, sitemap, entry);
    }
  }

  static Stream<List<SitemapEntry>> _inMemoryChunks(
    List<SitemapEntry> all,
    int chunk,
  ) async* {
    for (var offset = 0; offset < all.length; offset += chunk) {
      final end = offset + chunk < all.length ? offset + chunk : all.length;
      yield all.sublist(offset, end);
    }
  }

  static Stream<List<SitemapEntry>> _pagedChunks(
    SitemapEntries entries,
    Injector injector,
    int chunk,
  ) async* {
    final total = await entries.count(injector);
    for (var offset = 0; offset < total; offset += chunk) {
      final limit = total - offset < chunk ? total - offset : chunk;
      yield await entries.slice(injector, offset, limit);
    }
  }

  static void _checkParams(
    String path,
    List<String> paramNames,
    SitemapEntry entry,
  ) {
    final keys = entry.params.keys.toList()..sort();
    if (keys.length != paramNames.length ||
        !keys.toSet().containsAll(paramNames)) {
      throw PageEntriesMismatchError(
        path: path,
        expected: [...paramNames]..sort(),
        actual: keys,
      );
    }
    for (final MapEntry(:key, :value) in entry.params.entries) {
      if (value.isEmpty || value == '.' || value == '..') {
        throw PageEntryValueError(path: path, name: key, value: value);
      }
    }
  }

  static SitemapUrl _urlOf(
    Uri base,
    String path,
    PageSitemap sitemap,
    SitemapEntry? entry,
  ) => SitemapUrl(
    location: base.resolve(_encodedPath(path, entry?.params ?? const {})),
    lastModified: entry?.lastModified ?? sitemap.lastModified,
    changeFrequency: sitemap.changeFrequency,
    priority: sitemap.priority,
  );

  // Every segment is percent-encoded, so a value never adds a segment.
  static String _encodedPath(String path, Map<String, String> params) {
    if (path == '/') return '/';
    final segments = [
      for (final segment in path.substring(1).split('/'))
        Uri.encodeComponent(
          segment.startsWith(':')
              ? (params[segment.substring(1)] ?? segment)
              : segment,
        ),
    ];
    return '/${segments.join('/')}';
  }
}
