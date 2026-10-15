// A class named like an annotation of grund, declared in this package.

/// Not the annotation of `package:grund`.
final class Module {
  /// Creates it.
  const Module();
}

/// Carries the look-alike; the generator must not read it as a module.
@Module()
class NotOurs {}
