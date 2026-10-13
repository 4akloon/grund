import 'package:dartnest/dartnest.dart';

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

/// The root module of the example application.
final appModule = Module(id: 'app', imports: [greetingModule]);

/// Starts the container and prints a greeting.
Future<void> main() async {
  final container = await Container.create(appModule);
  print(container.root.get<Greeter>().greet('dartnest'));
}
