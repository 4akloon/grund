import 'package:grund/grund.dart';

import '../error/page_runtime_error.dart';
import '../jaspr_config.dart';
import '../page/page_address.dart';
import '../page/page_path.dart';
import '../page/page_sitemap.dart';
import '../page/site_page.dart';
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
  /// the site has no `baseUrl`.
  Stream<SitemapUrl> urls(List<DeclaredPage> pages) async* {
    for (final declared in listed(pages)) {
      final sitemap = declared.page.page.meta.sitemap;
      final path = PagePath.parse(declared.page.path);
      if (!path.hasParams) {
        yield _urlOf(declared.page, declared.page.path, sitemap, null);
        continue;
      }
      yield* _entryUrls(declared, sitemap, path.paramNames);
    }
  }

  /// The pages of [pages] that appear in the sitemap, in the same order;
  /// none when the site has no `baseUrl`.
  static List<DeclaredPage> listed(List<DeclaredPage> pages) => [
    for (final declared in pages)
      if (declared.page.site.baseUrl != null &&
          _isListed(declared, declared.page.page.meta.sitemap))
        declared,
  ];

  /// How many addresses each of [listed] gives, in the same order: one for
  /// a static page, the number of entries for a parameterised one.
  Future<List<int>> plan(List<DeclaredPage> listed) async => [
    for (final declared in listed) await _countOf(declared),
  ];

  Future<int> _countOf(DeclaredPage declared) async {
    if (!PagePath.parse(declared.page.path).hasParams) return 1;
    final entries = declared.page.page.meta.sitemap.entries;
    return entries == null ? 0 : entries.count(declared.injector);
  }

  /// The addresses at the global positions [start] to [end] (exclusive) of
  /// [listed], whose per-page counts are [counts] (from [plan]).
  ///
  /// Only the entries inside the range are asked of the sources: whole
  /// pages before it are skipped by their count.
  Future<List<SitemapUrl>> range(
    List<DeclaredPage> listed,
    List<int> counts,
    int start,
    int end,
  ) async {
    final urls = <SitemapUrl>[];
    var first = 0;
    for (var i = 0; i < listed.length && first < end; i++) {
      final last = first + counts[i];
      if (counts[i] > 0 && last > start) {
        final from = start > first ? start - first : 0;
        final to = (end < last ? end : last) - first;
        urls.addAll(await _slice(listed[i], from, to));
      }
      first = last;
    }
    return urls;
  }

  Future<List<SitemapUrl>> _slice(
    DeclaredPage declared,
    int from,
    int to,
  ) async {
    final sitemap = declared.page.page.meta.sitemap;
    final path = PagePath.parse(declared.page.path);
    if (!path.hasParams) {
      return [_urlOf(declared.page, declared.page.path, sitemap, null)];
    }
    final entries = sitemap.entries;
    if (entries == null) return const [];
    final injector = declared.injector;
    final List<SitemapEntry> loaded;
    if (entries is AllSitemapEntries) {
      final all = await entries.loadAll(injector);
      loaded = all.sublist(
        from < all.length ? from : all.length,
        to < all.length ? to : all.length,
      );
    } else {
      loaded = await entries.slice(injector, from, to - from);
    }
    return [
      for (final entry in loaded.take(to - from))
        _checkedUrl(declared, path.paramNames, sitemap, entry),
    ];
  }

  SitemapUrl _checkedUrl(
    DeclaredPage declared,
    List<String> paramNames,
    PageSitemap sitemap,
    SitemapEntry entry,
  ) {
    final path = declared.page.path;
    _checkParams(path, paramNames, entry);
    return _urlOf(declared.page, path, sitemap, entry);
  }

  // The rules of the sitemap: an explicit `false` leaves a page out; a page
  // with its own hooks needs an explicit `true`.
  static bool _isListed(DeclaredPage declared, PageSitemap sitemap) {
    if (sitemap.included == false) return false;
    final hooked = declared.page.page.hooks.use.isNotEmpty;
    return !hooked || sitemap.included == true;
  }

  Stream<SitemapUrl> _entryUrls(
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
      yield _urlOf(declared.page, path, sitemap, entry);
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
    SitePage page,
    String path,
    PageSitemap sitemap,
    SitemapEntry? entry,
  ) => SitemapUrl(
    location: page.site.baseUrl!.resolve(
      PageAddress.pathOf(
        path,
        entry?.params ?? const {},
        page.site.trailingSlash,
        pageSuffixes: page.pageSuffixes,
      ),
    ),
    lastModified: entry?.lastModified ?? sitemap.lastModified,
    changeFrequency: sitemap.changeFrequency,
    priority: sitemap.priority,
  );
}
