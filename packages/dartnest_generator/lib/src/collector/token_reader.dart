import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/provider_key.dart';
import 'constant_reader.dart';
import 'type_reader.dart';

/// Reads `Token` constants of `package:dartnest`.
abstract final class TokenReader {
  /// The key of [object] and its `T`, or `null` when [object] is not a
  /// `Token`.
  static (TokenKey, DartType)? read(DartObject? object) {
    final type = object?.type;
    final name = object?.getField('name')?.toStringValue();
    if (object == null ||
        name == null ||
        type is! InterfaceType ||
        !TypeReader.isDartnest(type, 'Token')) {
      return null;
    }
    final valueType = type.typeArguments.single;
    final key = TokenKey(
      valueType: TypeReader.read(valueType),
      name: name,
      expression: ConstantReader.read(object),
    );
    return (key, valueType);
  }
}
