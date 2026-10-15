import 'package:code_builder/code_builder.dart';

import '../model/type_model.dart';

/// Writes [TypeModel]s as `code_builder` references.
abstract final class TypeEmitter {
  /// [type] with its type arguments and nullability.
  static TypeReference reference(TypeModel type) => TypeReference(
    (b) => b
      ..symbol = type.name
      ..url = type.libraryUri
      ..isNullable = type.isNullable
      ..types.addAll(type.typeArguments.map(reference)),
  );
}
