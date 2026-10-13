import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../diagnostic/source_location.dart';
import '../model/body_kind.dart';
import '../model/constant_value.dart';
import '../model/controller_model.dart';
import '../model/enhancers_model.dart';
import '../model/handler_parameter.dart';
import '../model/parameter_binding.dart';
import '../model/route_model.dart';
import 'constructor_check.dart';

/// The checks of one controller: its constructor, components, metadata,
/// handlers and their parameters.
abstract final class ControllerCheck {
  /// The problems of [controller].
  static Iterable<Diagnostic> check(ControllerModel controller) sync* {
    final name = controller.type.name;
    yield* ConstructorCheck.check(
      controller.type,
      controller.constructor,
      controller.location,
    );
    yield* _components(controller.enhancers, name, controller.location);
    yield* _metadata(controller.metadata, name, controller.location);
    for (final route in controller.routes) {
      final handler = '$name.${route.handlerName}';
      if (route.problem case final problem?) {
        yield Diagnostic(
          DiagnosticCode.invalidRouteHandler,
          route.location,
          problem,
        );
        continue;
      }
      yield* _components(route.enhancers, handler, route.location);
      yield* _metadata(route.metadata, handler, route.location);
      final declared = fullPath(controller, route).pathParameters;
      for (final parameter in route.parameters) {
        yield* _parameter(parameter, handler, declared);
      }
    }
  }

  /// [route] with the controller path in front.
  static RouteModel fullPath(
    ControllerModel controller,
    RouteModel route,
  ) => RouteModel(
    method: route.method,
    path:
        '/${[for (final segment in '${controller.path}/${route.path}'.split('/'))
          if (segment.isNotEmpty) segment].join('/')}',
    handlerName: route.handlerName,
    returnType: route.returnType,
    location: route.location,
  );

  static Iterable<Diagnostic> _components(
    EnhancersModel enhancers,
    String owner,
    SourceLocation location,
  ) {
    final kinds = {
      'UseGuards': (enhancers.guards, 'Guard'),
      'UseInterceptors': (enhancers.interceptors, 'Interceptor'),
      'UsePipes': (enhancers.pipes, 'Pipe'),
      'UseFilters': (enhancers.filters, 'ExceptionFilter'),
    };
    return [
      for (final MapEntry(key: annotation, value: (list, kind))
          in kinds.entries)
        for (final component in list)
          if (!component.isValid)
            Diagnostic(
              DiagnosticCode.invalidComponent,
              location,
              '${component.type.name} in @$annotation of $owner is not a '
              '$kind.',
            ),
    ];
  }

  static Iterable<Diagnostic> _metadata(
    List<ConstantValue> metadata,
    String owner,
    SourceLocation location,
  ) => [
    for (final value in metadata)
      if (value.unsupported case final unsupported?)
        Diagnostic(
          DiagnosticCode.unsupportedConstant,
          location,
          'Metadata of $owner cannot be written in generated code: '
          '${unsupported.reason}. Use public constants and const constructors '
          'of public classes.',
        ),
  ];

  static Iterable<Diagnostic> _parameter(
    HandlerParameter parameter,
    String handler,
    List<String> declared,
  ) sync* {
    switch (parameter.binding) {
      case InvalidBinding(:final problem):
        yield Diagnostic(
          DiagnosticCode.invalidHandlerParameter,
          parameter.location,
          '$handler: $problem',
        );
      case BodyBinding(kind: BodyKind.unsupported):
        yield Diagnostic(
          DiagnosticCode.missingFromJson,
          parameter.location,
          '@Body parameter ${parameter.name} of $handler has type '
          '${parameter.type}; @Body needs a class with a '
          'fromJson(Map<String, Object?>) constructor or static method, '
          'Map<String, Object?>, String or List<int>.',
        );
      case PathBinding(:final name) when !declared.contains(name):
        yield Diagnostic(
          DiagnosticCode.unknownPathParameter,
          parameter.location,
          "@Param('$name') of $handler is not in the route path; it declares "
          '${declared.isEmpty ? 'no parameters' : declared.join(', ')}.',
        );
      default:
        break;
    }
  }
}
