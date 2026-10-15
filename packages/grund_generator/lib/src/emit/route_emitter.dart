import 'package:code_builder/code_builder.dart';

import '../model/route_model.dart';
import '../model/type_kind.dart';
import 'argument_emitter.dart';
import 'constant_emitter.dart';
import 'dart_string.dart';
import 'enhancers_emitter.dart';
import 'import_allocator.dart';

/// Writes a [RouteModel] as `Route.get(path, (c, ctx) => ..., name: ...)`.
abstract final class RouteEmitter {
  /// The route of [route].
  static Expression route(RouteModel route) {
    final enhancers = EnhancersEmitter.enhancers(route.enhancers);
    return refer('Route', ImportAllocator.grund)
        .property(route.method.toLowerCase())
        .call(
          [
            CodeExpression(Code(DartString.literal(route.path))),
            _handler(route),
          ],
          {
            'name': CodeExpression(Code(DartString.literal(route.handlerName))),
            if (enhancers != null) 'enhancers': enhancers,
            if (route.metadata.isNotEmpty)
              'metadata': ConstantEmitter.list(route.metadata),
          },
        );
  }

  /// `(c, ctx) async => c.find(await ctx.param<int>('id'))`; a `void`
  /// handler gets a block that returns `null` (204).
  static Expression _handler(RouteModel route) {
    final positional = <Expression>[];
    final named = <String, Expression>{};
    for (final parameter in route.parameters) {
      final argument = ArgumentEmitter.argument(parameter);
      if (parameter.isNamed) {
        named[parameter.name] = argument;
      } else {
        positional.add(argument);
      }
    }
    final call = refer('c').property(route.handlerName).call(positional, named);
    final returnsVoid = route.returnType.kind == TypeKind.voidType;
    final returnsFutureVoid = _isFutureOfVoid(route);
    final isAsync =
        returnsFutureVoid || route.parameters.any(ArgumentEmitter.awaits);
    return Method(
      (b) => b
        ..requiredParameters.addAll([
          Parameter((p) => p..name = 'c'),
          Parameter((p) => p..name = route.parameters.isEmpty ? '_' : 'ctx'),
        ])
        ..modifier = isAsync ? MethodModifier.async : null
        ..lambda = !(returnsVoid || returnsFutureVoid)
        ..body = returnsVoid || returnsFutureVoid
            ? Block.of([
                (returnsFutureVoid ? call.awaited : call).statement,
                literalNull.returned.statement,
              ])
            : call.code,
    ).closure;
  }

  static bool _isFutureOfVoid(RouteModel route) {
    final type = route.returnType;
    return (type.name == 'Future' || type.name == 'FutureOr') &&
        type.libraryUri == 'dart:async' &&
        type.typeArguments.singleOrNull?.kind == TypeKind.voidType;
  }
}
