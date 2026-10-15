import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';

import 'shelf_adapter.dart';

/// Provides a [ShelfAdapter] to the application: import it next to
/// `HttpModule` and the HTTP server listens through `shelf_io`.
///
/// The module is global and exports `Key<HttpAdapter>()`, so every module
/// of the graph can resolve the adapter without importing this one. The
/// parameters are those of the [ShelfAdapter] constructor.
///
/// ```dart
/// final class AppModule extends Module {
///   @override
///   List<Module> get imports => const [HttpModule(), ShelfAdapterModule()];
/// }
/// ```
final class ShelfAdapterModule extends Module {
  /// Creates the module; see [ShelfAdapter] for the parameters.
  const ShelfAdapterModule({
    this.closeTimeout = ShelfAdapter.defaultCloseTimeout,
    this.onError,
  });

  /// How long a graceful close waits for the requests in flight; `null`
  /// waits without a limit.
  final Duration? closeTimeout;

  /// Where the adapter reports failures; `null` prints them to stderr.
  final ErrorLogger? onError;

  @override
  bool get global => true;

  @override
  List<Binding<Object>> get bindings => [
    Singleton<HttpAdapter>(
      (_) => ShelfAdapter(closeTimeout: closeTimeout, onError: onError),
      dependsOn: const [],
    ),
  ];

  @override
  List<Object> get exports => const [Key<HttpAdapter>()];
}
