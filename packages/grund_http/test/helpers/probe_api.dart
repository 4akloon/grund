import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';

/// An [HttpApi] whose routes a test writes inline.
final class ProbeApi extends HttpApi {
  ProbeApi(
    super.injector,
    this._routes, {
    this.apiPath = '',
    this.apiUse = const [],
  });

  /// A singleton binding of a probe API; [name] keeps several apart.
  static Binding<Object> binding(
    String name,
    List<Route> routes, {
    String path = '',
    List<HookRef<HttpHook>> use = const [],
    List<Key<Object>> dependsOn = const [],
  }) => Singleton<ProbeApi>(
    (i) => ProbeApi(i, routes, apiPath: path, apiUse: use),
    name: name,
    dependsOn: dependsOn,
  );

  final List<Route> _routes;
  final String apiPath;
  final List<HookRef<HttpHook>> apiUse;

  @override
  String get path => apiPath;

  @override
  List<HookRef<HttpHook>> get use => apiUse;

  @override
  List<Route> get routes => _routes;
}

/// A module that binds exactly [bindings].
final class ProbeModule extends Module {
  ProbeModule(this.bindings);

  @override
  final List<Binding<Object>> bindings;
}
