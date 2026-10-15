// An HttpAdapter that never opens a socket, and the module that provides it.
import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';

/// Accepts `listen` and `close` without doing anything: the tests drive the
/// server through `TestClient`.
final class FakeAdapter implements HttpAdapter {
  @override
  Future<void> listen(
    RequestHandler handler, {
    required Object address,
    required int port,
  }) async {}

  @override
  Future<void> close({bool force = false}) async {}
}

/// The application root of a test: HTTP, the fake adapter and [app].
final class TestRoot extends Module {
  /// Creates the root over the application module [app].
  TestRoot(this.app);

  /// The module under test.
  final Module app;

  @override
  List<Module> get imports => [const HttpModule(), _AdapterModule(), app];
}

final class _AdapterModule extends Module {
  @override
  bool get global => true;

  @override
  List<Binding<Object>> get bindings => [
    Singleton<HttpAdapter>((i) => FakeAdapter(), dependsOn: const []),
  ];

  @override
  List<Object> get exports => const [Key<HttpAdapter>()];
}
