// Classes whose constructors dependency injection cannot or can call.
import 'package:grund_annotations/grund_annotations.dart';

import '../modules/basic.dart';

/// Not annotated.
final class Plain {}

/// Abstract.
@Injectable()
abstract class Shape {}

/// Generic.
@Injectable()
final class Box<T> {}

/// Only a named constructor.
@Injectable()
final class OnlyNamed {
  /// Creates it.
  OnlyNamed.create();
}

/// An optional parameter.
@Injectable()
final class Optional {
  /// Creates it.
  Optional([this.clock]);

  /// The clock.
  final Clock? clock;
}

/// A nullable required parameter and a function parameter.
@Injectable()
final class Odd {
  /// Creates it.
  Odd(this.clock, this.callback);

  /// The clock.
  final Clock? clock;

  /// A callback.
  final void Function() callback;
}

/// Private classes cannot be created from the generated library.
@Injectable()
// ignore: unused_element, read by the collector only.
final class _Hidden {}

/// An abstract class with a factory can be created.
@Injectable()
abstract class Service {
  /// Creates the default service.
  factory Service() => _DefaultService();
}

final class _DefaultService implements Service {}

/// An `Object` parameter says nothing about what to inject.
@Injectable()
final class Loose {
  /// Creates it.
  Loose(this.anything);

  /// Anything.
  final Object anything;
}

/// Injects through every accepted form.
@Injectable(scope: Scope.transient)
final class Fine {
  /// Creates it.
  Fine(this.clock, @Named('primary') this.db, {required this.repo});

  /// The clock.
  final Clock clock;

  /// The database.
  final PrimaryDb db;

  /// The repository.
  final Repo repo;
}

/// A class with `@Provides` that is not a module.
final class NotAModule {
  /// Provided from the wrong place.
  @Provides()
  static Plain plain() => Plain();
}
