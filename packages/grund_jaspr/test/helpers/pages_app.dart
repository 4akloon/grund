import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:grund_io/grund_io.dart';
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
