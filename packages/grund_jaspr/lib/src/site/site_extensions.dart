import '../catalog/snapshot_index.dart';
import '../page/page_extension.dart';
import 'page_registry.dart';

/// The extensions of the pages of a site, read from the current snapshot.
///
/// The snapshot is the source, not the live module: a hot reload adopts
/// singletons that still hold the injector they were created with.
final class SiteExtensions {
  /// Reads the snapshot held by [_registry] through [_index].
  SiteExtensions(this._registry, this._index);

  final PageRegistry _registry;
  final SnapshotIndex _index;

  /// The extensions of the pages of the site of exactly the type
  /// [siteType] that have no `hooks.use` of their own, each once, in the
  /// order they were first declared; empty before the pages runner has built
  /// a snapshot.
  List<PageExtension> of(Type siteType) {
    final snapshot = _registry.current;
    if (snapshot == null) return const [];
    final unique = <PageExtension>{};
    for (final page in _index.pagesOf(snapshot, siteType)) {
      // A page with hooks of its own is guarded beyond the site: `claim`
      // has no page match to apply them to, so the page is not asked.
      if (page.page.hooks.use.isNotEmpty) continue;
      unique.addAll(page.page.extensions);
    }
    return unique.toList(growable: false);
  }
}
