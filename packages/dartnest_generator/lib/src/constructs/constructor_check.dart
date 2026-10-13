import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../diagnostic/source_location.dart';
import '../model/constructor_model.dart';
import '../model/dependency_model.dart';
import '../model/provider_key.dart';
import '../model/type_model.dart';

/// Reports why dependency injection cannot call a constructor; shared by
/// providers and controllers.
abstract final class ConstructorCheck {
  /// The problems of [constructor] of [type] declared at [location].
  static Iterable<Diagnostic> check(
    TypeModel type,
    ConstructorModel constructor,
    SourceLocation location,
  ) sync* {
    if (constructor.problem case final problem?) {
      yield Diagnostic(DiagnosticCode.invalidConstructor, location, problem);
    }
    for (final dependency in constructor.dependencies) {
      yield* _dependency(type, dependency);
    }
  }

  static Iterable<Diagnostic> _dependency(
    TypeModel type,
    DependencyModel dependency,
  ) sync* {
    if (dependency.problem case final problem?) {
      yield Diagnostic(
        DiagnosticCode.invalidDependency,
        dependency.location,
        problem,
      );
    }
    if (dependency.key case TokenKey(:final expression)) {
      if (expression.unsupported case final unsupported?) {
        yield Diagnostic(
          DiagnosticCode.unsupportedConstant,
          dependency.location,
          'The token of parameter ${dependency.name} of $type cannot be '
          'written in generated code: ${unsupported.reason}. Use a public '
          'constant token.',
        );
      }
    }
  }
}
