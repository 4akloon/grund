import 'package:meta/meta.dart';

/// Typed identifier for a provider whose value is not uniquely identified by
/// its Dart type: primitives (`String`, `int`), or several implementations of
/// one interface.
///
/// ```dart
/// const dbUrl = Token<String>('db.url');
/// Provider.value('postgres://...', token: dbUrl);
/// injector.get(dbUrl); // String
/// ```
///
/// Two tokens are equal when they have the same [name] and the same type
/// parameter [T]. String tokens without a type do not exist on purpose.
@immutable
final class Token<T extends Object> {
  /// Creates a token named [name] for values of type [T].
  const Token(this.name);

  /// Human-readable name, used in diagnostics and for equality.
  final String name;

  /// The value type this token identifies.
  Type get type => T;

  @override
  bool operator ==(Object other) => other is Token<T> && other.name == name;

  @override
  int get hashCode => Object.hash(T, name);

  @override
  String toString() => 'Token<$T>($name)';
}
