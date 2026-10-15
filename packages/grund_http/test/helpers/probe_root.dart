import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';

import 'adapter_module.dart';
import 'probe_api.dart';

/// A root module that serves `bindings` through [adapter].
final class ProbeRoot extends Module {
  ProbeRoot(
    HttpAdapter adapter,
    List<Binding<Object>> bindings, {
    HttpModule http = const HttpModule(config: HttpConfig(port: 0)),
  }) : _imports = [http, AdapterModule(adapter), ProbeModule(bindings)];

  final List<Module> _imports;

  @override
  List<Module> get imports => _imports;
}

/// The only `HttpServer` of a started [app].
HttpServer serverOf(App app) => app.container.all<HttpServer>().single;
