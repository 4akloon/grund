import 'package:analyzer/dart/constant/value.dart';

import '../model/lifetime.dart';
import 'annotations.dart';

/// Reads the `scope` of `@Injectable` and `@Provides`.
abstract final class LifetimeReader {
  /// The lifetime of [annotation]; a missing annotation or `Scope.singleton`
  /// is [Lifetime.singleton].
  static Lifetime read(DartObject? annotation) {
    final scope = annotation == null
        ? null
        : Annotations.field(annotation, 'scope');
    return switch (scope?.variable?.name) {
      'call' => Lifetime.scoped,
      'transient' => Lifetime.transient,
      _ => Lifetime.singleton,
    };
  }
}
