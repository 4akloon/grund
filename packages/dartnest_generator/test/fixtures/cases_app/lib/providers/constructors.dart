// Classes whose constructors dependency injection cannot or can call.
import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

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
final class Named {
  /// Creates it.
  Named.create();
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

/// Tokens that do not fit.
@Injectable()
final class BadTokens {
  /// Creates it.
  BadTokens(@Inject(dbUrl) this.port, @Inject('db.url') this.url);

  /// Declared int, but the token is a String.
  final int port;

  /// Not a token.
  final String url;
}

/// A token of a subtype fits a supertype parameter.
const portToken = Token<int>('port');

/// Injects through every accepted form.
@Injectable()
final class Fine {
  /// Creates it.
  Fine(this.clock, @Inject(portToken) this.port, {required this.repo});

  /// The clock.
  final Clock clock;

  /// The port, as a num.
  final num port;

  /// The repository.
  final Repo repo;
}
