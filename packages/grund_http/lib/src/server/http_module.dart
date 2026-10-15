import 'package:grund/grund.dart';

import '../adapter/http_adapter.dart';
import '../hook/hook_ref.dart';
import '../hook/http_hook.dart';
import '../hook/middleware.dart';
import '../http/error_log.dart';
import '../http/print_error_log.dart';
import '../serialize/response_codec.dart';
import 'http_config.dart';
import 'http_server.dart';

/// The HTTP server of the application.
///
/// Import it from the root module together with a module that provides the
/// `HttpAdapter` (`IoAdapterModule`, `ShelfAdapterModule`):
///
/// ```dart
/// final class AppModule extends Module {
///   const AppModule();
///   @override List<Module> get imports => const [
///     HttpModule(use: [HookRef<RequestIdHook>.type()]),
///     IoAdapterModule(),
///     TasksModule(),
///   ];
/// }
/// ```
///
/// It binds the `HttpServer` (a `Runner` named `http`), the `HttpConfig` and
/// the `ErrorLog`, and exports all three; replace the config or the log with
/// an override of the same key. Without an adapter the application does not
/// start: `HttpAdapter` is missing.
final class HttpModule extends Module {
  /// Creates the module.
  ///
  /// [use] are hooks that wrap every route, outermost first; [middleware]
  /// run around the whole request before routing; [codecs] teach the
  /// response serializer types without `toJson()`.
  const HttpModule({
    this.use = const [],
    this.middleware = const [],
    this.codecs = const [],
    this.config = const HttpConfig(),
  });

  /// Hooks that wrap every route.
  final List<HookRef<HttpHook>> use;

  /// Middleware, outermost first.
  final List<Middleware> middleware;

  /// Codecs for the response serializer.
  final List<ResponseCodec<Object>> codecs;

  /// The default configuration.
  final HttpConfig config;

  @override
  List<Binding<Object>> get bindings => [
    Singleton<ErrorLog>((i) => const PrintErrorLog(), dependsOn: const []),
    Singleton<HttpConfig>((i) => config, dependsOn: const []),
    Singleton<HttpServer>(
      (i) => HttpServer(
        this,
        adapter: i<HttpAdapter>(),
        config: i<HttpConfig>(),
        log: i<ErrorLog>(),
      ),
      dependsOn: const [Key<HttpAdapter>(), Key<HttpConfig>(), Key<ErrorLog>()],
    ),
  ];

  // The runner is stopped by App.close only when it was started; an
  // application started with `only: const {}` (tests, shelfHandler) is
  // stopped here, before any value is disposed.
  @override
  Future<void> onShutdown(Injector injector) => injector<HttpServer>().stop();

  @override
  List<Object> get exports => const [
    Key<HttpServer>(),
    Key<HttpConfig>(),
    Key<ErrorLog>(),
  ];
}
