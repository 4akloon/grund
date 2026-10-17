import 'package:grund/grund.dart';

import 'sitemap_entries.dart';
import 'sitemap_entry.dart';

/// The [SitemapEntries.all] source. It is not exported: the sitemap code
/// recognises it to load the list once per pass instead of per chunk.
final class AllSitemapEntries implements SitemapEntries {
  /// Creates the source around [_load].
  const AllSitemapEntries(this._load);

  final Future<List<SitemapEntry>> Function(Injector injector) _load;

  /// The whole list, loaded once.
  Future<List<SitemapEntry>> loadAll(Injector injector) => _load(injector);

  @override
  Future<int> count(Injector injector) async => (await _load(injector)).length;

  @override
  Future<List<SitemapEntry>> slice(
    Injector injector,
    int offset,
    int limit,
  ) async {
    final all = await _load(injector);
    if (offset >= all.length) return const [];
    final end = offset + limit > all.length ? all.length : offset + limit;
    return all.sublist(offset, end);
  }
}
