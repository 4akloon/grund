import 'package:grund_http/grund_http.dart';

import '../catalog/sitemap_source.dart';
import '../catalog/snapshot_index.dart';
import '../catalog/snapshot_pages.dart';
import '../error/page_runtime_error.dart';
import '../jaspr_config.dart';
import '../site/page_registry.dart';
import '../site/page_site.dart';
import 'sitemap_chunk_cache.dart';
import 'sitemap_writer.dart';

/// Answers `sitemap.xml` and `sitemap/<n>.xml` of a site.
///
/// The plan (addresses per page) and every rendered chunk go through the
/// [SitemapChunkCache]; a chunk asks the `entries` only for its own range.
/// A failing `entries` source fails the request (the HTTP server logs it as
/// `SEVERE`) and leaves nothing in the cache.
final class SitemapHandlers {
  /// Creates the handlers over the snapshot in [_registry].
  SitemapHandlers(this._registry, this._index, this._cache, this._config)
    : _source = SitemapSource(_config);

  final PageRegistry _registry;
  final SnapshotIndex _index;
  final SitemapChunkCache _cache;
  final JasprConfig _config;
  final SitemapSource _source;

  static final _chunkName = RegExp(r'^([1-9][0-9]*)\.xml$');

  /// `GET <path>/sitemap.xml` of [site]: the only file, or the index.
  Future<HttpResponse> document(PageSite site) async {
    final view = _view(site);
    final plan = await _plan(view);
    final chunks = _chunkCount(plan);
    if (chunks == 1) return _xml(await _chunk(view, plan, 1));
    final prefix = site.path.endsWith('/')
        ? site.path.substring(0, site.path.length - 1)
        : site.path;
    final base = site.sitemapBaseUrl!;
    return _xml(
      SitemapWriter.index([
        for (var n = 1; n <= chunks; n++)
          base.resolve('$prefix/sitemap/$n.xml'),
      ]),
    );
  }

  /// `GET <path>/sitemap/:chunk` of [site], where [name] is `<n>.xml`;
  /// throws [NotFoundException] for any other name (before the sources are
  /// touched) or an `n` outside the plan.
  Future<HttpResponse> chunk(PageSite site, String name) async {
    final number = int.tryParse(_chunkName.firstMatch(name)?.group(1) ?? '');
    if (number == null) throw const NotFoundException();
    final view = _view(site);
    final plan = await _plan(view);
    if (number > _chunkCount(plan)) throw const NotFoundException();
    return _xml(await _chunk(view, plan, number));
  }

  Future<List<int>> _plan(_SiteView view) =>
      _cache.get('${view.key}/plan', () => _source.plan(view.listed));

  Future<String> _chunk(_SiteView view, List<int> plan, int number) {
    final size = _config.sitemapChunkSize;
    return _cache.get('${view.key}/chunk/$number', () async {
      final total = plan.fold(0, (sum, count) => sum + count);
      final start = (number - 1) * size;
      final end = start + size < total ? start + size : total;
      final urls = await _source.range(view.listed, plan, start, end);
      return SitemapWriter.urlSet(urls);
    });
  }

  int _chunkCount(List<int> plan) {
    final total = plan.fold(0, (sum, count) => sum + count);
    final size = _config.sitemapChunkSize;
    return total <= size ? 1 : (total + size - 1) ~/ size;
  }

  // Reads the snapshot and its generation in one synchronous step, so the
  // cache key always belongs to the pages the plan is computed from. Never
  // the live module.
  _SiteView _view(PageSite site) {
    final snapshot =
        _registry.current ?? (throw const PageCatalogNotReadyError());
    return _SiteView(
      '${site.runtimeType}/${_registry.generation}',
      SitemapSource.listed(_index.declaredOf(snapshot, site.runtimeType)),
    );
  }

  static HttpResponse _xml(String body) => HttpResponse.text(
    body,
    headers: HeaderMap.of({'content-type': 'application/xml; charset=utf-8'}),
  );
}

// The sitemap pages of one site in one snapshot and the cache key prefix.
final class _SiteView {
  const _SiteView(this.key, this.listed);

  final String key;
  final List<DeclaredPage> listed;
}
