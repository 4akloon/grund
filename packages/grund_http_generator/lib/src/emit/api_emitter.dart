import 'package:code_builder/code_builder.dart';
import 'package:grund_generator/grund_generator.dart';

import '../model/api_model.dart';
import '../model/api_names.dart';
import 'http_references.dart';
import 'route_emitter.dart';

/// Writes the class `XRoutes extends http.HttpApi` that serves the routes
/// of an `@Api` class X by calling its methods.
///
/// The class lives in a part of X's library, so it names the user's types
/// as they are named there.
abstract final class ApiEmitter {
  /// The routes class of [api].
  static Class emit(ApiModel api) => Class(
    (b) => b
      ..name = ApiNames.routes(api.type.name)
      ..modifier = ClassModifier.final$
      ..docs.add('/// The routes of [${api.type.name}].')
      ..extend = HttpReferences.of('HttpApi')
      ..fields.add(
        Field(
          (f) => f
            ..name = '_api'
            ..modifier = FieldModifier.final$
            ..type = TypeEmitter.reference(api.type),
        ),
      )
      ..constructors.add(_constructor())
      ..methods.addAll(_getters(api)),
  );

  static Constructor _constructor() => Constructor(
    (c) => c
      ..docs.add('/// Creates the routes over an instance of the API.')
      ..requiredParameters.addAll([
        Parameter(
          (p) => p
            ..name = 'injector'
            ..toSuper = true,
        ),
        Parameter(
          (p) => p
            ..name = '_api'
            ..toThis = true,
        ),
      ]),
  );

  static List<Method> _getters(ApiModel api) => [
    OverrideGetter.build(
      'path',
      refer('String'),
      DartString.expression(api.path),
    ),
    if (api.use.isNotEmpty)
      OverrideGetter.build(
        'use',
        OverrideGetter.listOf(HttpReferences.hookRef),
        ConstantEmitter.list([
          for (final hook in api.use) HttpReferences.prefixed(hook.expression),
        ]),
      ),
    OverrideGetter.build(
      'routes',
      OverrideGetter.listOf(HttpReferences.of('Route')),
      literalList([for (final route in api.routes) RouteEmitter.emit(route)]),
    ),
  ];
}
