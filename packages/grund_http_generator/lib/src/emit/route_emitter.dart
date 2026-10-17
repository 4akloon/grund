import 'package:code_builder/code_builder.dart';
import 'package:grund_generator/grund_generator.dart';

import '../model/return_kind.dart';
import '../model/route_model.dart';
import 'http_references.dart';
import 'param_emitter.dart';

/// Writes one `http.Route.get(...)` (or `post`, `put`, `patch`, `delete`)
/// of a generated `HttpApi`, whose handler calls the method of the user's
/// API class held in the field `_api`.
abstract final class RouteEmitter {
  /// The route expression of [route].
  static Expression emit(RouteModel route) =>
      HttpReferences.of('Route')
          .property(route.method.toLowerCase())
          .call(
            [DartString.expression(route.path), _handler(route)],
            {
              if (route.status case final status?) 'status': literalNum(status),
              if (route.use.isNotEmpty)
                'use': ConstantEmitter.list([
                  for (final hook in route.use)
                    HttpReferences.prefixed(hook.expression),
                ]),
            },
          );

  static Expression _handler(RouteModel route) {
    final parameters = route.parameters;
    final call = refer('_api')
        .property(route.handlerName)
        .call(
          [
            for (final param in parameters)
              if (!param.isNamed) ParamEmitter.argument(param),
          ],
          {
            for (final param in parameters)
              if (param.isNamed) param.name: ParamEmitter.argument(param),
          },
        );
    final awaitsBody = parameters.any(ParamEmitter.awaits);
    // `FutureOr` is awaited too: the declared type does not say which it is.
    final returnsFuture = const {
      'Future',
      'FutureOr',
    }.contains(route.returnType.name);
    return switch (route.returnKind) {
      ReturnKind.value || ReturnKind.byteStream => _closure(
        call.code,
        isAsync: awaitsBody,
        isLambda: true,
      ),
      ReturnKind.none => _closure(
        Block.of([
          (returnsFuture ? call.awaited : call).statement,
          literalNull.returned.statement,
        ]),
        isAsync: awaitsBody || returnsFuture,
        isLambda: false,
      ),
      ReturnKind.stream || ReturnKind.unsupported => throw StateError(
        'Route ${route.handlerName} has an unsupported result.',
      ),
    };
  }

  static Expression _closure(
    Code body, {
    required bool isAsync,
    required bool isLambda,
  }) => Method(
    (b) => b
      ..requiredParameters.add(Parameter((p) => p..name = 'c'))
      ..modifier = isAsync ? MethodModifier.async : null
      ..lambda = isLambda
      ..body = body,
  ).closure;
}
