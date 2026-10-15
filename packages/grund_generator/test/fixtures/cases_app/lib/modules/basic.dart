// Valid modules: class, Bind and Provides bindings, scopes and names.
import 'package:grund/grund.dart' as grund;
import 'package:grund_annotations/grund_annotations.dart';

/// Application settings.
final class AppConfig {
  /// Creates the settings.
  const AppConfig(this.name);

  /// The application name.
  final String name;
}

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

/// A named binding.
@Injectable()
@Named('primary')
final class PrimaryDb {}

/// Lives as long as a call.
@Injectable(scope: Scope.call)
final class Tx {}

/// A repository.
@Injectable()
final class Repo {
  /// Creates the repository.
  Repo(this.clock, @Named('primary') this.db, {required this.config});

  /// The clock.
  final Clock clock;

  /// The database.
  final PrimaryDb db;

  /// The settings.
  final AppConfig config;
}

/// A session opened asynchronously.
final class Session {
  /// Creates the session.
  const Session();
}

/// Database access.
@Module(
  providers: [Repo, Bind<Clock, SystemClock>(), PrimaryDb, Tx],
  exports: [Repo, PrimaryDb, grund.Key<Clock>(), grund.Key<Session>('main')],
  global: true,
)
final class DbModule extends grund.Module {
  /// Creates the module.
  const DbModule();

  /// The settings.
  @Provides()
  static AppConfig config() => const AppConfig('demo');

  /// A session per call.
  @Provides(scope: Scope.call)
  @Named('main')
  static Future<Session> session(Clock clock) async => const Session();

  /// Not static.
  @Provides()
  Repo notStatic() => throw UnimplementedError();

  /// Returns nothing.
  @Provides()
  static void nothing() {}
}

/// Re-exports the database module.
@Module(
  imports: [
    DbModule(),
    ExplicitModule(name: 'x'),
  ],
  exports: [DbModule],
)
final class AppModule extends grund.Module {
  /// Creates the module.
  const AppModule();
}

/// A module written with the explicit API.
final class ExplicitModule extends grund.Module {
  /// Creates the module.
  const ExplicitModule({this.name});

  /// Tells instances apart.
  final String? name;

  @override
  Object? get qualifier => name;
}
