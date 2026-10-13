import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/handler_parameter.dart';
import '../model/parameter_binding.dart';
import 'annotations.dart';
import 'body_kind_reader.dart';
import 'source_locations.dart';
import 'type_reader.dart';

/// Reads how a handler parameter is filled from the request.
final class HandlerParameterReader {
  /// Creates the reader.
  HandlerParameterReader(this.locations);

  /// Locations of parameters.
  final SourceLocations locations;

  static const _arguments = {'Param', 'Query', 'Header', 'Body'};

  static const _scalars = {
    'String',
    'int',
    'double',
    'num',
    'bool',
    'DateTime',
  };

  /// The model of [parameter].
  HandlerParameter read(FormalParameterElement parameter) => HandlerParameter(
    name: parameter.displayName,
    type: TypeReader.read(parameter.type),
    binding: _binding(parameter),
    isNamed: parameter.isNamed,
    location: locations.of(parameter),
  );

  ParameterBinding _binding(FormalParameterElement parameter) {
    final type = parameter.type;
    final annotations = Annotations.all(parameter, _arguments);
    final shown = '${parameter.displayName} (${type.getDisplayString()})';
    if (annotations.length > 1) {
      return InvalidBinding(
        'Parameter $shown has more than one of @Param, '
        '@Query, @Header and @Body.',
      );
    }
    if (annotations.isEmpty) return _unannotated(type, shown);
    final annotation = annotations.single;
    final name = Annotations.field(annotation, 'name')?.toStringValue() ?? '';
    return switch (annotation.type?.element?.name) {
      'Param' when _isScalar(type) => PathBinding(name),
      'Query' when _isScalar(type) => QueryBinding(name),
      'Header' when type.isDartCoreString => HeaderBinding(name),
      'Header' => InvalidBinding(
        'Parameter $shown: a @Header parameter is String or String?.',
      ),
      'Body' => BodyBinding(BodyKindReader.read(type)),
      _ => _unsupportedScalar(annotation, shown),
    };
  }

  static ParameterBinding _unannotated(DartType type, String shown) {
    if (TypeReader.isDartnest(type, 'ExecutionContext')) {
      return const ContextBinding();
    }
    if (TypeReader.isDartnest(type, 'HttpRequest')) {
      return const RequestBinding();
    }
    return InvalidBinding(
      'Parameter $shown needs @Param, @Query, @Header or @Body, or the type '
      'ExecutionContext or HttpRequest.',
    );
  }

  static bool _isScalar(DartType type) =>
      type is InterfaceType &&
      (type.element is EnumElement ||
          (type.element.library.isDartCore &&
              _scalars.contains(type.element.name)));

  static ParameterBinding _unsupportedScalar(
    DartObject annotation,
    String shown,
  ) => InvalidBinding(
    'Parameter $shown: @${annotation.type?.element?.name} supports String, '
    'int, double, num, bool, DateTime and enums, nullable or not.',
  );
}
