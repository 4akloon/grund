import 'dart:io' as io;

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';

import 'io_adapter.dart';

/// Provides an [IoAdapter] to the application: import it next to
/// `HttpModule` and the HTTP server listens through `dart:io`.
///
/// The module is global and exports `Key<HttpAdapter>()`, so every module
/// of the graph can resolve the adapter without importing this one. The
/// parameters are those of the [IoAdapter] constructor.
///
/// ```dart
/// final class AppModule extends Module {
///   @override
///   List<Module> get imports => const [HttpModule(), IoAdapterModule()];
/// }
/// ```
final class IoAdapterModule extends Module {
  /// Creates the module; see [IoAdapter] for the parameters.
  const IoAdapterModule({
    this.securityContext,
    this.closeTimeout = IoAdapter.defaultCloseTimeout,
    this.onError,
  });

  /// TLS configuration; `null` serves plain HTTP.
  final io.SecurityContext? securityContext;

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
      (_) => IoAdapter(
        securityContext: securityContext,
        closeTimeout: closeTimeout,
        onError: onError,
      ),
      dependsOn: const [],
    ),
  ];

  @override
  List<Object> get exports => const [Key<HttpAdapter>()];
}
