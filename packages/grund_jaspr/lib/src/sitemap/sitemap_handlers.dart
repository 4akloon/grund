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

  static final _chunkName = RegExp(r'^([0-9]+)\.xml$');

  /// `GET <path>/sitemap.xml` of [site]: the only file, or the index.
  Future<HttpResponse> document(PageSite site) async {
    final plan = await _plan(site);
    final chunks = _chunkCount(plan);
    if (chunks == 1) return _xml(await _chunk(site, plan, 1));
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
  /// throws [NotFoundException] for any other name or an `n` outside the
  /// plan.
  Future<HttpResponse> chunk(PageSite site, String name) async {
    final number = int.tryParse(_chunkName.firstMatch(name)?.group(1) ?? '');
    final plan = await _plan(site);
    if (number == null || number < 1 || number > _chunkCount(plan)) {
      throw const NotFoundException();
    }
    return _xml(await _chunk(site, plan, number));
  }

  Future<List<int>> _plan(PageSite site) =>
      _cache.get('${site.runtimeType}/plan', () => _source.plan(_listed(site)));

  Future<String> _chunk(PageSite site, List<int> plan, int number) {
    final size = _config.sitemapChunkSize;
    return _cache.get('${site.runtimeType}/chunk/$number', () async {
      final total = plan.fold(0, (sum, count) => sum + count);
      final start = (number - 1) * size;
      final end = start + size < total ? start + size : total;
      final urls = await _source.range(_listed(site), plan, start, end);
      return SitemapWriter.urlSet(urls);
    });
  }

  int _chunkCount(List<int> plan) {
    final total = plan.fold(0, (sum, count) => sum + count);
    final size = _config.sitemapChunkSize;
    return total <= size ? 1 : (total + size - 1) ~/ size;
  }

  // Reads the snapshot at the time of the request, never the live module.
  List<DeclaredPage> _listed(PageSite site) {
    final snapshot =
        _registry.current ?? (throw const PageCatalogNotReadyError());
    return SitemapSource.listed(_index.declaredOf(snapshot, site.runtimeType));
  }

  static HttpResponse _xml(String body) => HttpResponse.text(
    body,
    headers: HeaderMap.of({'content-type': 'application/xml; charset=utf-8'}),
  );
}
