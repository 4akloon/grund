// Valid modules that exercise every binding form the emitter writes.
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

/// A name that needs escaping in generated code.
@Injectable()
@Named(r"a'b$c")
final class OddName {}

/// Lives as long as a call.
@Injectable(scope: Scope.call)
final class Tx {
  /// Creates the transaction.
  Tx(this.clock);

  /// The clock.
  final Clock clock;
}

/// Created on every request for it.
@Injectable(scope: Scope.transient)
final class Counter {}

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

/// A handle per call.
final class Handle {
  /// Creates the handle.
  const Handle();
}

/// Database access.
@Module(
  providers: [
    Repo,
    Bind<Clock, SystemClock>(),
    PrimaryDb,
    Tx,
    Counter,
    OddName,
  ],
  exports: [Repo, PrimaryDb, grund.Key<Session>('main'), grund.Key<Clock>()],
  global: true,
)
final class EmitDbModule extends grund.Module {
  /// Creates the module.
  const EmitDbModule();

  /// The settings.
  @Provides()
  static AppConfig config() => const AppConfig('it\'s demo');

  /// A session opened asynchronously.
  @Provides()
  @Named('main')
  static Future<Session> session(Clock clock, @Named('primary') PrimaryDb db) =>
      Future.value(const Session());

  /// A handle per call.
  @Provides(scope: Scope.call)
  @Named('call')
  static Handle handle(Clock clock) => const Handle();
}

/// Re-exports the database module.
@Module(
  imports: [
    EmitDbModule(),
    EmitExplicitModule(name: 'x'),
  ],
  exports: [EmitDbModule],
)
final class EmitAppModule extends grund.Module {
  /// Creates the module.
  const EmitAppModule();
}

/// A module written with the explicit API.
final class EmitExplicitModule extends grund.Module {
  /// Creates the module.
  const EmitExplicitModule({this.name});

  /// Tells instances apart.
  final String? name;

  @override
  Object? get qualifier => name;
}
