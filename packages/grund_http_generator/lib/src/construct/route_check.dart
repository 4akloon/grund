import 'package:grund_generator/grund_generator.dart';

import '../diagnostic/http_diagnostic_codes.dart';
import '../model/hook_model.dart';
import '../model/return_kind.dart';
import '../model/route_model.dart';
import 'param_check.dart';

/// Checks one route handler: its annotation, status, result, hooks and
/// parameters.
abstract final class RouteCheck {
  /// The problems of [route] whose full path is [path].
  static Iterable<Diagnostic> check(RouteModel route, String path) sync* {
    final where = '${route.handlerName} ($path)';
    if (route.problem case final problem?) {
      yield Diagnostic(
        HttpDiagnosticCodes.invalidRouteHandler,
        route.location,
        problem,
      );
      return;
    }
    yield* _status(route, where);
    yield* _result(route, where);
    yield* _hooks(route);
    yield* ParamCheck.check(route, path);
  }

  static Iterable<Diagnostic> _status(RouteModel route, String where) sync* {
    final status = route.status;
    if (status == null || (status >= 100 && status <= 599)) return;
    yield Diagnostic(
      HttpDiagnosticCodes.invalidStatus,
      route.location,
      'Route $where has status $status, which is not an HTTP status code '
      '(100 to 599).',
    );
  }

  static Iterable<Diagnostic> _result(RouteModel route, String where) sync* {
    switch (route.returnKind) {
      case ReturnKind.unsupported:
        yield Diagnostic(
          HttpDiagnosticCodes.unsupportedReturnType,
          route.location,
          'Route $where returns ${route.returnType}, which cannot be sent: '
          'return a value, void, or a Stream<List<int>>.',
        );
      case ReturnKind.stream:
        yield Diagnostic(
          HttpDiagnosticCodes.streamReturnReserved,
          route.location,
          'Route $where returns ${route.returnType}; streams of events are '
          'reserved for grund_sse. Return a Stream<List<int>> for bytes.',
        );
      case ReturnKind.value || ReturnKind.none || ReturnKind.byteStream:
        break;
    }
  }

  static Iterable<Diagnostic> _hooks(RouteModel route) sync* {
    for (final problem in route.invalidEntries) {
      yield Diagnostic(
        HttpDiagnosticCodes.invalidHook,
        route.location,
        'Route ${route.handlerName}: $problem',
      );
    }
    yield* hookConstants(route.use, route.location, route.handlerName);
  }

  /// The hooks of [hooks] that cannot be written in generated code, found in
  /// [owner] at [location].
  static Iterable<Diagnostic> hookConstants(
    List<HookModel> hooks,
    SourceLocation location,
    String owner,
  ) sync* {
    for (final hook in hooks) {
      if (hook.expression.unsupported case final unsupported?) {
        yield Diagnostic(
          DiagnosticCode.unsupportedConstant,
          location,
          '$owner: the hook ${hook.type} cannot be written in generated '
          'code: ${unsupported.reason}. Use public constants and const '
          'constructors of public classes.',
        );
      }
    }
  }
}
