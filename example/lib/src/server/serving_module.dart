import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_io/grund_io.dart';
import 'package:grund_shelf/grund_shelf.dart';

import '../common/request_id_middleware.dart';
import '../common/timing_hook.dart';
import 'adapter_kind.dart';

/// Serves [application] over HTTP: the same wrapper for both module forms
/// and both adapters, so the application itself does not know how it is
/// served.
final class ServingModule extends Module {
  /// Serves [application] with the adapter [kind] on [address] and [port].
  ServingModule(
    this.application,
    this.kind, {
    this.address = 'localhost',
    this.port = 8080,
    this.onError,
  });

  /// The application module, `AppModule` or `ExplicitAppModule`.
  final Module application;

  /// Which adapter serves.
  final AdapterKind kind;

  /// The address to listen on.
  final Object address;

  /// The port to listen on; 0 picks a free one.
  final int port;

  /// Receives failures an adapter cannot turn into a response.
  final ErrorLogger? onError;

  @override
  List<Module> get imports => [
    application,
    switch (kind) {
      AdapterKind.io => IoAdapterModule(onError: onError),
      AdapterKind.shelf => ShelfAdapterModule(onError: onError),
    },
    HttpModule(
      use: const [HookRef<TimingHook>.instance(TimingHook())],
      middleware: [RequestIdMiddleware()],
      config: HttpConfig(address: address, port: port),
    ),
  ];
}
