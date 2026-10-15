import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';

import 'conformance_module.dart';
import 'conformance_probe.dart';

/// The root module of the conformance application: `HttpModule` on a
/// loopback ([port], by default an ephemeral one), the [adapter] under test and the
/// [ConformanceModule].
final class ConformanceRoot extends Module {
  /// Creates the root around [probe]; [adapter] is the module of the
  /// adapter under test (`HttpModule` needs one, even when the application
  /// is only started with `only: const {}`).
  const ConformanceRoot(this.probe, {required this.adapter, this.port = 0});

  /// The probe of this server's fixture.
  final ConformanceProbe probe;

  /// The module that binds the `HttpAdapter` under test.
  final Module adapter;

  /// The port `HttpModule` listens on; 0 picks a free one.
  final int port;

  @override
  List<Module> get imports => [
    HttpModule(
      config: HttpConfig(address: '127.0.0.1', port: port),
    ),
    adapter,
    ConformanceModule(probe),
  ];
}
