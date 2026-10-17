import 'package:grund/grund.dart';

import 'sitemap_entry.dart';

/// The source of the addresses of a parameterised page in the sitemap.
abstract interface class SitemapEntries {
  /// Entries that [load] returns in one list; counting and slicing happen
  /// on that list.
  factory SitemapEntries.all(
    Future<List<SitemapEntry>> Function(Injector injector) load,
  ) => _AllEntries(load);

  /// Entries that are counted and loaded page by page, for sources too big
  /// to load at once.
  factory SitemapEntries.paged({
    required Future<int> Function(Injector injector) count,
    required Future<List<SitemapEntry>> Function(
      Injector injector,
      int offset,
      int limit,
    )
    load,
  }) => _PagedEntries(count, load);

  /// The number of entries.
  Future<int> count(Injector injector);

  /// At most [limit] entries starting at [offset].
  Future<List<SitemapEntry>> slice(Injector injector, int offset, int limit);
}

final class _AllEntries implements SitemapEntries {
  const _AllEntries(this._load);

  final Future<List<SitemapEntry>> Function(Injector injector) _load;

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

final class _PagedEntries implements SitemapEntries {
  const _PagedEntries(this._count, this._load);

  final Future<int> Function(Injector injector) _count;
  final Future<List<SitemapEntry>> Function(
    Injector injector,
    int offset,
    int limit,
  )
  _load;

  @override
  Future<int> count(Injector injector) => _count(injector);

  @override
  Future<List<SitemapEntry>> slice(Injector injector, int offset, int limit) =>
      _load(injector, offset, limit);
}
