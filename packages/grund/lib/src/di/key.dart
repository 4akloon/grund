import 'package:meta/meta.dart';

/// Identifies a binding: its type plus an optional [name].
@immutable
final class Key<T extends Object> {
  /// Creates the key of type [T], qualified by [name] when several bindings
  /// share the type.
  const Key([this.name]);

  /// Qualifier of the binding, or `null`.
  final String? name;

  /// The type argument, as a runtime value.
  Type get type => T;

  @override
  bool operator ==(Object other) =>
      other is Key<Object> && other.type == type && other.name == name;

  @override
  int get hashCode => Object.hash(T, name);

  @override
  String toString() => name == null ? '$T' : "$T('$name')";
}
