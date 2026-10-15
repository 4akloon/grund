import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';

/// Provides [adapter] as the `HttpAdapter` of the graph, the way the real
/// adapter modules do: global, exported.
final class AdapterModule extends Module {
  AdapterModule(this.adapter);

  /// The adapter that is bound.
  final HttpAdapter adapter;

  @override
  bool get global => true;

  @override
  List<Binding<Object>> get bindings => [
    Singleton<HttpAdapter>((i) => adapter, dependsOn: const []),
  ];

  @override
  List<Object> get exports => const [Key<HttpAdapter>()];
}
