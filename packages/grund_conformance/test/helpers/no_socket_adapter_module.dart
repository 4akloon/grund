import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';

/// Binds an `HttpAdapter` that never opens a socket: for tests that start
/// the application with `only: const {}` and call the server directly.
final class NoSocketAdapterModule extends Module {
  /// Creates the module.
  const NoSocketAdapterModule();

  @override
  bool get global => true;

  @override
  List<Binding<Object>> get bindings => [
    Singleton<HttpAdapter>((_) => _NoSocketAdapter(), dependsOn: const []),
  ];

  @override
  List<Object> get exports => const [Key<HttpAdapter>()];
}

final class _NoSocketAdapter implements HttpAdapter {
  @override
  Future<void> listen(
    RequestHandler handler, {
    required Object address,
    required int port,
  }) => throw StateError('This adapter opens no socket.');

  @override
  Future<void> close({bool force = false}) async {}
}
