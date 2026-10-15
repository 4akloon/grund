import 'constant_value.dart';
import 'type_model.dart';

/// What a provider is looked up by: a type or a `Token`.
sealed class ProviderKey {
  /// Creates the key.
  const ProviderKey();

  /// The key as grund prints it: `UsersService` or
  /// `Token<String>(db.url)`.
  String get display;

  @override
  bool operator ==(Object other) =>
      other is ProviderKey &&
      other.runtimeType == runtimeType &&
      other._identity == _identity;

  @override
  int get hashCode => _identity.hashCode;

  Object get _identity;

  @override
  String toString() => display;
}

/// A provider keyed by its [type].
final class TypeKey extends ProviderKey {
  /// Creates the key.
  const TypeKey(this.type);

  /// The provided type.
  final TypeModel type;

  @override
  String get display => type.display;

  @override
  Object get _identity => type;
}

/// A provider keyed by a `Token<T>`; tokens are equal by [valueType] and
/// [name], like `Token` itself.
final class TokenKey extends ProviderKey {
  /// Creates the key.
  const TokenKey({
    required this.valueType,
    required this.name,
    required this.expression,
  });

  /// The `T` of `Token<T>`.
  final TypeModel valueType;

  /// The token name.
  final String name;

  /// How to write the token in code (a reference or a `Token(...)` call).
  final ConstantValue expression;

  @override
  String get display => 'Token<${valueType.display}>($name)';

  @override
  Object get _identity => (valueType, name);
}
