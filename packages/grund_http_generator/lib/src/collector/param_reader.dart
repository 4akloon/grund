import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:grund_generator/grund_generator.dart';

import '../model/param_location.dart';
import '../model/param_model.dart';
import '../model/invalid_source_reason.dart';
import '../model/param_source.dart';
import '../model/value_kind.dart';
import 'body_kind_reader.dart';
import 'validator_reader.dart';
import 'value_kind_reader.dart';

/// Reads where a parameter of a route handler gets its value from.
final class ParamReader {
  /// Creates the reader.
  ParamReader(this.locations);

  /// Locations of parameters.
  final SourceLocations locations;

  static const _sources = {'Path', 'Query', 'Header', 'Cookie', 'Body'};

  static const _locations = {
    'Path': ParamLocation.path,
    'Query': ParamLocation.query,
    'Header': ParamLocation.header,
    'Cookie': ParamLocation.cookie,
  };

  /// The model of [parameter].
  ParamModel read(FormalParameterElement parameter) => ParamModel(
    name: parameter.displayName,
    type: TypeReader.read(parameter.type),
    source: _source(parameter),
    isNamed: parameter.isNamed,
    location: locations.of(parameter),
    validators: ValidatorReader.read(parameter),
    defaultValue: _default(parameter),
  );

  ParamSource _source(FormalParameterElement parameter) {
    final type = parameter.type;
    final annotations = Annotations.all(parameter, _sources);
    final shown = '${parameter.displayName} (${type.getDisplayString()})';
    if (annotations.length > 1) {
      return InvalidSource(
        InvalidSourceReason.ambiguous,
        'Parameter $shown has more than one of @Path, @Query, @Header, '
        '@Cookie and @Body.',
      );
    }
    if (annotations.isEmpty) return _unannotated(parameter, shown);
    final annotation = annotations.single;
    final name = annotation.type?.element?.name;
    final location = _locations[name];
    if (location == null) return BodySource(BodyKindReader.read(type));
    return _value(annotation, location, parameter, shown);
  }

  static ParamSource _value(
    DartObject annotation,
    ParamLocation location,
    FormalParameterElement parameter,
    String shown,
  ) {
    final kind = ValueKindReader.read(parameter.type);
    final isList = kind == ValueKind.stringList;
    if (kind == ValueKind.unsupported ||
        (isList && location == ParamLocation.path)) {
      return InvalidSource(
        InvalidSourceReason.unsupportedType,
        'Parameter $shown: @${annotation.type?.element?.name} supports '
        'String, int, double, bool, DateTime, Uri and enums, and '
        'List<String> except for @Path.',
      );
    }
    final name =
        Annotations.field(annotation, 'name')?.toStringValue() ??
        parameter.displayName;
    return ValueSource(location, name, kind);
  }

  static ParamSource _unannotated(
    FormalParameterElement parameter,
    String shown,
  ) {
    final type = parameter.type;
    if (TypeReader.isFrom(type, 'HttpCtx', 'package:grund_http/')) {
      return const ContextSource();
    }
    if (type is InterfaceType &&
        type.element is ClassElement &&
        !type.element.library.isInSdk) {
      return CallScopeSource(
        BindingKey(
          TypeReader.read(type).nonNullable,
          Annotations.named(parameter),
        ),
      );
    }
    return InvalidSource(
      InvalidSourceReason.missing,
      'Parameter $shown has no source: annotate it with @Path, @Query, '
      '@Header, @Cookie or @Body, or give it the class type of a value of '
      'the call scope.',
    );
  }

  static ConstantValue? _default(FormalParameterElement parameter) =>
      parameter.hasDefaultValue
      ? ConstantReader.read(parameter.computeConstantValue())
      : null;
}
