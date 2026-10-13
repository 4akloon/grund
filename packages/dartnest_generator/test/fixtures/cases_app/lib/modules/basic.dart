// A valid global module: class, Bind and Value providers and a token.
import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

/// The database URL.
const dbUrl = Token<String>('db.url');

/// Application settings.
final class AppConfig {
  /// Creates the settings.
  const AppConfig(this.name);

  /// The application name.
  final String name;
}

/// The settings value.
const appConfig = AppConfig('demo');

/// A clock.
abstract interface class Clock {
  /// The current time.
  DateTime now();
}

/// The system clock.
@Injectable()
final class SystemClock implements Clock {
  @override
  DateTime now() => DateTime.now();
}

/// A repository.
@Injectable()
final class Repo {
  /// Creates the repository.
  Repo(this.clock, @Inject(dbUrl) this.url, {required this.config});

  /// The clock.
  final Clock clock;

  /// The database URL.
  final String url;

  /// The settings.
  final AppConfig config;
}

/// Database access.
@Module(
  id: 'db',
  providers: [
    Repo,
    Bind<Clock, SystemClock>(),
    Value('postgres://localhost', token: dbUrl),
    Value(appConfig),
  ],
  exports: [Repo, dbUrl],
  global: true,
)
class DbModule {}
