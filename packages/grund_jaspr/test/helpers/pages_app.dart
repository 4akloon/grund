import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:grund_io/grund_io.dart';
import 'package:grund_jaspr/src/site/page_snapshot.dart';
import 'package:grund_jaspr/src/site/pages_runner.dart';
import 'package:grund_jaspr/src/site/site_validator.dart';
import 'package:test/test.dart';

/// Starts an application of [modules] with the HTTP server ([use] as its
/// global hooks) and returns an in-process client; nothing listens.
abstract final class PagesApp {
  /// The client of the started application, closed after the test.
  static Future<TestClient> start(
    List<Module> modules, {
    List<HookRef<HttpHook>> use = const [],
  }) async {
    final app = await TestApp.start(root: _Root(modules, use));
    addTearDown(app.close);
    return TestClient.of(app);
  }
}

final class _Root extends Module {
  _Root(this._modules, this._use);

  final List<Module> _modules;
  final List<HookRef<HttpHook>> _use;

  @override
  List<Module> get imports => [
    HttpModule(use: _use),
    const IoAdapterModule(),
    ..._modules,
  ];
}

/// Starts [modules] like [PagesApp.start] and returns the started
/// application, for tests that read its injector.
abstract final class StartedPagesApp {
  /// The started application, closed after the test.
  static Future<TestApp> start(List<Module> modules) async {
    final app = await TestApp.start(root: _Root(modules, const []));
    addTearDown(app.close);
    return app;
  }

  /// Like [start] with the global site rules switched off, so a test can
  /// hand an invalid graph to a [PagesRunner] itself.
  static Future<TestApp> startUnchecked(List<Module> modules) async {
    final app = await TestApp.start(
      root: _Root(modules, const []),
      overrides: [
        Singleton<SiteValidator>((_) => const _NoRules(), dependsOn: const []),
      ],
    );
    addTearDown(app.close);
    return app;
  }
}

final class _NoRules extends SiteValidator {
  const _NoRules();

  @override
  void check(PageSnapshot snapshot) {}
}
