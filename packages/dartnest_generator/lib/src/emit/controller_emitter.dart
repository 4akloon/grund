import 'package:code_builder/code_builder.dart';

import '../model/controller_model.dart';
import '../model/generated_names.dart';
import 'constant_emitter.dart';
import 'dart_string.dart';
import 'enhancers_emitter.dart';
import 'import_allocator.dart';
import 'injection_emitter.dart';
import 'route_emitter.dart';
import 'type_emitter.dart';

/// Writes a [ControllerModel] as a function returning the core
/// `Controller<T>`.
abstract final class ControllerEmitter {
  /// `Controller<UsersController> usersController() => Controller(...)`.
  static Method function(ControllerModel controller) {
    final type = TypeReference(
      (b) => b
        ..symbol = 'Controller'
        ..url = ImportAllocator.dartnest
        ..types.add(TypeEmitter.reference(controller.type)),
    );
    final enhancers = EnhancersEmitter.enhancers(controller.enhancers);
    return Method(
      (b) => b
        ..docs.add('/// The controller of `${controller.type.name}`.')
        ..name = GeneratedNames.controller(controller.type.name)
        ..returns = type
        ..lambda = true
        ..body = type.newInstance(const [], {
          if (controller.path.isNotEmpty)
            'path': CodeExpression(Code(DartString.literal(controller.path))),
          'create': _create(controller),
          if (enhancers != null) 'enhancers': enhancers,
          if (controller.metadata.isNotEmpty)
            'metadata': ConstantEmitter.list(controller.metadata),
          'routes': literalList(controller.routes.map(RouteEmitter.route)),
        }).code,
    );
  }

  static Expression _create(ControllerModel controller) => Method(
    (b) => b
      ..requiredParameters.add(
        Parameter(
          (p) =>
              p..name = controller.constructor.dependencies.isEmpty ? '_' : 'i',
        ),
      )
      ..lambda = true
      ..body = InjectionEmitter.create(
        controller.type,
        controller.constructor,
      ).code,
  ).closure;
}
