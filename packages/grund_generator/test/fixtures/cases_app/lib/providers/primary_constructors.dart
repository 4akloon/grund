// Injectables declared with Dart 3.13 primary constructors and with a private
// named parameter.
import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;

/// A database.
@Injectable()
final class PrimaryConstructorDb {}

/// A repository with a primary constructor.
@Injectable()
final class PrimaryConstructorRepo(final PrimaryConstructorDb _db) {
  /// The database.
  PrimaryConstructorDb get db => _db;
}

/// A greeter with a private named parameter.
@Injectable()
final class PrivateNamedGreeter {
  /// Creates it.
  PrivateNamedGreeter({required this._repo});

  final PrimaryConstructorRepo _repo;

  /// The repository.
  PrimaryConstructorRepo get repo => _repo;
}

/// Provides the classes above.
@Module(
  providers: [
    PrimaryConstructorDb,
    PrimaryConstructorRepo,
    PrivateNamedGreeter,
  ],
)
final class PrimaryConstructorsModule extends grund.Module {
  /// Creates the module.
  const PrimaryConstructorsModule();
}
