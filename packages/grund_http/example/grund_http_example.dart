import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';

/// Answers `GET /greetings/:name` with JSON and `POST /greetings` with a
/// 201 and the echoed body.
final class GreetingApi extends HttpApi {
  /// Creates the API.
  GreetingApi(super.injector);

  @override
  String get path => '/greetings';

  @override
  List<Route> get routes => [
    Route.get(
      '/:name',
      (c) => {'greeting': 'Hello, ${c.path.string('name')}!'},
    ),
    Route.post('/', (c) async => c.body(_Greeting.fromJson), status: 201),
  ];
}

final class _Greeting {
  const _Greeting(this.name);

  factory _Greeting.fromJson(Map<String, Object?> json) =>
      _Greeting(json['name']! as String);

  final String name;

  Map<String, Object?> toJson() => {'name': name};
}

/// An adapter that never listens: the in-process client calls the server
/// directly. A real application imports `IoAdapterModule` (`grund_io`) or
/// `ShelfAdapterModule` (`grund_shelf`) instead.
final class _NoSocketAdapter implements HttpAdapter {
  @override
  Future<void> listen(
    RequestHandler handler, {
    required Object address,
    required int port,
  }) async {}

  @override
  Future<void> close({bool force = false}) async {}
}

/// Provides the adapter to every module, like `IoAdapterModule` does.
final class NoSocketAdapterModule extends Module {
  /// Creates the module.
  const NoSocketAdapterModule();

  @override
  bool get global => true;

  @override
  List<Binding<Object>> get bindings => [
    Singleton<HttpAdapter>((i) => _NoSocketAdapter(), dependsOn: const []),
  ];

  @override
  List<Object> get exports => const [Key<HttpAdapter>()];
}

/// The root module: [HttpModule], the adapter and [GreetingApi].
final class AppModule extends Module {
  /// Creates the module.
  const AppModule();

  @override
  List<Module> get imports => const [HttpModule(), NoSocketAdapterModule()];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<GreetingApi>(GreetingApi.new, dependsOn: const []),
  ];
}

/// Calls the API in process and returns one line per response.
Future<List<String>> callApi() async {
  final app = await TestApp.start(root: const AppModule());
  try {
    final client = TestClient.of(app);
    final greeted = await client.get('/greetings/grund');
    final created = await client.post('/greetings', json: {'name': 'Ann'});
    final missing = await client.get('/nowhere');
    return [
      'GET /greetings/grund -> ${greeted.status} ${greeted.text}',
      'POST /greetings -> ${created.status} ${created.text}',
      'GET /nowhere -> ${missing.status}',
    ];
  } finally {
    await app.close();
  }
}

Future<void> main() async {
  (await callApi()).forEach(print);
}
