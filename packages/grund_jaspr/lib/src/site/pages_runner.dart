import 'package:grund/grund.dart';

import 'page_registry.dart';
import 'page_snapshot.dart';
import 'pages_api.dart';
import 'page_site.dart';
import 'site_api.dart';
import 'site_validator.dart';

/// Builds the [PageSnapshot] from the fresh root injector and validates it.
///
/// A runner, not a singleton, because after a hot reload an adopted
/// singleton keeps its old injector: only [prepare] and [reassemble]
/// receive the new one.
final class PagesRunner extends Runner {
  /// Creates the runner that fills [_registry] after [_validator] accepts
  /// the snapshot.
  PagesRunner(this._registry, this._validator);

  final PageRegistry _registry;
  final SiteValidator _validator;

  @override
  String get name => 'pages';

  @override
  Future<void> prepare(Injector injector) async => _refresh(injector);

  @override
  Future<ReassembleReport> reassemble(Injector injector) async {
    _refresh(injector);
    return ReassembleReport.none;
  }

  @override
  Future<void> start(Injector injector) async {}

  @override
  Future<void> stop() async {}

  // The registry keeps its snapshot when the new one is invalid.
  void _refresh(Injector injector) {
    final snapshot = PageSnapshot(
      sites: injector.all<SiteApi<PageSite>>(),
      pages: injector.all<PagesApi<PageSite>>(),
    );
    _validator.check(snapshot);
    _registry.replace(snapshot);
  }
}
