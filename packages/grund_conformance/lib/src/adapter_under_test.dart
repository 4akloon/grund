import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';

/// Creates the adapter under test; [onError] receives the failures the
/// adapter reports itself (a throwing handler, a failing body stream), and
/// [closeTimeout] is the adapter's limit for a graceful close (`null`: no
/// limit).
typedef AdapterFactory =
    AdapterUnderTest Function(ErrorLogger onError, Duration? closeTimeout);

/// The module of an adapter for the conformance suite and how to read the
/// port it bound; the suite always listens on port 0.
final class AdapterUnderTest {
  /// Wraps [module]; [portOf] reads the port from the adapter the module
  /// binds, once `listen` completed.
  const AdapterUnderTest(this.module, {required this.portOf});

  /// Wraps [module], which binds an adapter of type [A]; [port] reads its
  /// port.
  static AdapterUnderTest of<A extends HttpAdapter>(
    Module module, {
    required int Function(A adapter) port,
  }) => AdapterUnderTest(
    module,
    portOf: (adapter) => switch (adapter) {
      final A typed => port(typed),
      _ => throw StateError('The module bound $adapter, not an $A.'),
    },
  );

  /// The global module that binds the `HttpAdapter`.
  final Module module;

  /// The port the adapter listens on.
  final int Function(HttpAdapter adapter) portOf;
}
