import 'type_kind.dart';

/// A Dart type as the generator needs it: enough to emit a reference to it
/// and to compare it with other types, without analyzer objects.
final class TypeModel {
  /// Creates the description of a named type.
  const TypeModel({
    required this.name,
    required this.kind,
    this.libraryUri,
    this.typeArguments = const [],
    this.isNullable = false,
  });

  /// The `void` type.
  static const voidType = TypeModel(name: 'void', kind: TypeKind.voidType);

  /// The class or enum name; the display string for [TypeKind.unsupported].
  final String name;

  /// What kind of type this is.
  final TypeKind kind;

  /// URI of the declaring library (`dart:core`, `package:a/a.dart`);
  /// `null` for `void`, `dynamic` and unsupported types.
  final String? libraryUri;

  /// Type arguments, in order.
  final List<TypeModel> typeArguments;

  /// Whether the type is nullable (`String?`).
  final bool isNullable;

  /// The type as written in Dart, for messages: `List<int>?`.
  String get display {
    final arguments = typeArguments.isEmpty
        ? ''
        : '<${typeArguments.map((t) => t.display).join(', ')}>';
    return '$name$arguments${isNullable ? '?' : ''}';
  }

  /// The same type without `?`.
  TypeModel get nonNullable => TypeModel(
    name: name,
    kind: kind,
    libraryUri: libraryUri,
    typeArguments: typeArguments,
  );

  /// Whether this is the type [name] declared in [libraryUri], ignoring
  /// type arguments and nullability.
  bool isDeclaredAs(String name, String libraryUri) =>
      this.name == name && this.libraryUri == libraryUri;

  String get _identity =>
      '$libraryUri#$name<${typeArguments.map((t) => t._identity).join(',')}>'
      '${isNullable ? '?' : ''}';

  @override
  bool operator ==(Object other) =>
      other is TypeModel && other._identity == _identity;

  @override
  int get hashCode => _identity.hashCode;

  @override
  String toString() => display;
}
