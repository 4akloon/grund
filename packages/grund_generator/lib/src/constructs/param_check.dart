import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../diagnostic/http_diagnostic_codes.dart';
import '../model/body_kind.dart';
import '../model/param_location.dart';
import '../model/invalid_source_reason.dart';
import '../model/param_model.dart';
import '../model/param_source.dart';
import '../model/route_model.dart';
import 'route_paths.dart';
import 'validator_check.dart';

/// Checks the parameters of one route handler.
abstract final class ParamCheck {
  /// The problems of the parameters of [route] whose full path is [path].
  static Iterable<Diagnostic> check(RouteModel route, String path) sync* {
    final known = RoutePaths.parameters(path);
    var bodies = 0;
    for (final param in route.parameters) {
      if (param.source is BodySource && ++bodies > 1) {
        yield _diagnostic(
          HttpDiagnosticCodes.invalidHandlerParameter,
          param,
          'Parameter ${param.name} is a second @Body; a request has one body.',
        );
      }
      yield* _source(param, known, path);
      yield* ValidatorCheck.check(param);
    }
  }

  static Iterable<Diagnostic> _source(
    ParamModel param,
    List<String> known,
    String path,
  ) sync* {
    switch (param.source) {
      case InvalidSource(:final reason, :final problem):
        yield _diagnostic(
          reason == InvalidSourceReason.missing
              ? HttpDiagnosticCodes.parameterWithoutSource
              : HttpDiagnosticCodes.invalidHandlerParameter,
          param,
          problem,
        );
      case BodySource(kind: BodyKind.unsupported):
        yield _diagnostic(
          HttpDiagnosticCodes.missingFromJson,
          param,
          'The @Body parameter ${param.name} has type ${param.type}, which '
          'cannot be read: use a class with a fromJson(Map<String, Object?>) '
          'factory, a List of one, Map<String, Object?> or Uint8List.',
        );
      case ValueSource(location: ParamLocation.path, :final name):
        yield* _pathParameter(param, name, known, path);
      case _:
        break;
    }
  }

  static Iterable<Diagnostic> _pathParameter(
    ParamModel param,
    String name,
    List<String> known,
    String path,
  ) sync* {
    if (!known.contains(name)) {
      yield _diagnostic(
        HttpDiagnosticCodes.unknownPathParameter,
        param,
        'The path $path has no parameter :$name for ${param.name}; its '
        'parameters are [${known.join(', ')}].',
      );
    }
    if (param.type.isNullable) {
      yield _diagnostic(
        HttpDiagnosticCodes.invalidHandlerParameter,
        param,
        'The path parameter ${param.name} cannot be nullable: a path always '
        'has its parameters.',
      );
    }
  }

  static Diagnostic _diagnostic(
    DiagnosticCode code,
    ParamModel param,
    String message,
  ) => Diagnostic(code, param.location, message);
}
