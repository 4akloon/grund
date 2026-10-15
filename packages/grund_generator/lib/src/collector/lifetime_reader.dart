import 'package:analyzer/dart/constant/value.dart';

import '../model/lifetime.dart';
import 'annotations.dart';

/// Reads the `scope` of `@Injectable` and `@Provides`.
abstract final class LifetimeReader {
  /// The lifetime of [annotation] and the problem with its `scope`, if any.
  ///
  /// A missing annotation or `Scope.singleton` is [Lifetime.singleton]; a
  /// `scope` that is not a `Scope` constant is a problem, not a default.
  static ({Lifetime lifetime, String? problem}) read(DartObject? annotation) {
    final scope = annotation == null
        ? null
        : Annotations.field(annotation, 'scope');
    if (scope == null) return (lifetime: Lifetime.singleton, problem: null);
    return switch (scope.getField('_name')?.toStringValue()) {
      'singleton' => (lifetime: Lifetime.singleton, problem: null),
      'call' => (lifetime: Lifetime.scoped, problem: null),
      'transient' => (lifetime: Lifetime.transient, problem: null),
      _ => (
        lifetime: Lifetime.singleton,
        problem: 'The scope is not a constant Scope value.',
      ),
    };
  }
}
