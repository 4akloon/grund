import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/dto_field.dart';
import '../model/dto_model.dart';
import 'body_kind_reader.dart';
import 'type_reader.dart';

/// Collects the data classes that travel as request bodies and handler
/// results, for the documentation constructs of later versions.
abstract final class DtoReader {
  static const _containers = {'Future', 'FutureOr', 'List', 'Iterable', 'Set'};

  /// The data classes reachable from [roots] (body and return types), each
  /// once, following `Future`, `FutureOr`, `List`, `Iterable`, `Set` and
  /// field types; sorted by library URI and name.
  static List<DtoModel> read(Iterable<DartType> roots) {
    final seen = <InterfaceElement>{};
    final pending = [
      for (final root in roots)
        if (_dataClass(root) case final element?) element,
    ];
    final dtos = <DtoModel>[];
    while (pending.isNotEmpty) {
      final element = pending.removeLast();
      if (!seen.add(element)) continue;
      dtos.add(_dto(element));
      for (final field in _fields(element)) {
        if (_dataClass(field.type) case final nested?) pending.add(nested);
      }
    }
    return dtos..sort(
      (a, b) => '${a.type.libraryUri}#${a.type.name}'.compareTo(
        '${b.type.libraryUri}#${b.type.name}',
      ),
    );
  }

  static InterfaceElement? _dataClass(DartType type) {
    if (type is! InterfaceType) return null;
    final element = type.element;
    if (_containers.contains(element.name) && element.library.isInSdk) {
      return type.typeArguments.isEmpty
          ? null
          : _dataClass(type.typeArguments.single);
    }
    final uri = '${element.library.uri}';
    final isData =
        element is ClassElement &&
        element.typeParameters.isEmpty &&
        !element.library.isInSdk &&
        !uri.startsWith('package:grund/');
    return isData ? element : null;
  }

  static DtoModel _dto(InterfaceElement element) => DtoModel(
    type: TypeReader.read(element.thisType),
    fields: [
      for (final field in _fields(element))
        DtoField(
          name: field.displayName,
          jsonName: _jsonName(field) ?? field.displayName,
          type: TypeReader.read(field.type),
          defaultValue: _defaultValue(element, field.displayName),
          documentation: field.documentationComment,
        ),
    ],
    hasFromJson: BodyKindReader.hasFromJson(element),
    documentation: element.documentationComment,
  );

  static List<FieldElement> _fields(InterfaceElement element) => [
    for (final field in element.fields)
      if (!field.isStatic && field.isPublic && field.nonSynthetic == field)
        field,
  ];

  static String? _jsonName(FieldElement field) {
    for (final annotation in field.metadata.annotations) {
      final value = annotation.computeConstantValue();
      if (value?.type?.element?.name == 'JsonKey') {
        return value?.getField('name')?.toStringValue();
      }
    }
    return null;
  }

  static String? _defaultValue(InterfaceElement element, String name) => element
      .unnamedConstructor
      ?.formalParameters
      .where((parameter) => parameter.displayName == name)
      .firstOrNull
      ?.defaultValueCode;
}
