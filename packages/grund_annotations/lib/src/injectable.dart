import 'scope.dart';

/// Marks a class that dependency injection creates through its unnamed
/// constructor; list it in `Module.providers`.
///
/// Every constructor parameter is resolved by its type, or by its `Named`
/// annotation. Named parameters must be `required`. The class stays an
/// ordinary class: a test can create it by hand.
///
/// ```dart
/// @Injectable()
/// final class UsersService {
///   UsersService(this.repo, @Named('primary') this.db);
///   final UsersRepo repo;
///   final Database db;
/// }
/// ```
final class Injectable {
  /// Creates the annotation with the [scope] of the binding.
  const Injectable({this.scope = Scope.singleton});

  /// How long the instances live.
  final Scope scope;
}
