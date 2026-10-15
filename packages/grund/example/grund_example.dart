import 'package:grund/grund.dart';
import 'package:grund/testing.dart';

/// A typed token for a primitive value.
const dbUrl = Token<String>('db.url');

/// A dynamic module: a plain function returning a Module.
Module databaseModule({required String url}) => Module(
  id: 'database',
  providers: [
    Provider.value(url, token: dbUrl),
    Provider.async((i) async => Db.connect(i.get(dbUrl))),
  ],
  exports: [Db],
);

/// A fake database connection.
class Db {
  Db._(this.url);

  /// The URL this connection was opened with.
  final String url;

  /// Opens a connection to [url].
  static Future<Db> connect(String url) async => Db._(url);
}

/// A service that depends on [Db].
class Greeter {
  /// Creates a greeter backed by [db].
  Greeter(this.db);

  /// The database this greeter reports in its greeting.
  final Db db;

  /// Returns a greeting for [name] that mentions the database URL.
  String greet(String name) => 'Hello, $name! (via ${db.url})';
}

/// Provides [Greeter] and imports the database.
final greetingModule = Module(
  id: 'greeting',
  imports: [databaseModule(url: 'pg://localhost')],
  providers: [Provider((i) => Greeter(i.get()))],
  exports: [Greeter],
);

/// The root module of the dependency injection example.
final appModule = Module(id: 'app', imports: [greetingModule]);

/// Serves `GET /hello?name=...` with a [Greeter].
final helloController = Controller<Greeter>(
  path: '/hello',
  create: (i) => i.get(),
  routes: [
    Route.get(
      '/',
      (greeter, ctx) async => {
        'message': greeter.greet(await ctx.query<String>('name')),
      },
    ),
  ],
);

/// The root module of the HTTP example: [greetingModule] plus a controller.
Module httpModule() => Module(
  id: 'http',
  imports: [greetingModule],
  controllers: [helloController],
);

/// Resolves a service from a container, then answers one request in memory.
///
/// To serve over a socket, pass `IoAdapter()` from `grund_io` or
/// `ShelfAdapter()` from `grund_shelf` to `Application.create` and call
/// `app.listen(port: 8080)`.
Future<void> main() async {
  final container = await Container.create(appModule);
  print(container.root.get<Greeter>().greet('grund'));
  await container.close();

  final app = await Application.create(httpModule);
  final response = await TestClient(app).get('/hello?name=you');
  print('${response.status} ${response.text}');
  await app.close();
}
