import 'type_model.dart';

/// What a binding is looked up by: a type and an optional name, like the
/// core `Key<T>([name])`.
final class BindingKey implements Comparable<BindingKey> {
  /// Creates the key of [type], qualified by [name] when several bindings
  /// share the type.
  const BindingKey(this.type, [this.name]);

  /// The type of the bound value.
  final TypeModel type;

  /// The qualifier (`@Named`), or `null`.
  final String? name;

  /// The key as grund prints it: `UsersService` or `Database('primary')`.
  String get display => name == null ? '$type' : "$type('$name')";

  /// Orders keys by type name, then qualifier, then declaring library, so
  /// a sorted list never depends on the order of collection.
  @override
  int compareTo(BindingKey other) {
    final byDisplay = display.compareTo(other.display);
    if (byDisplay != 0) return byDisplay;
    return '${type.libraryUri}'.compareTo('${other.type.libraryUri}');
  }

  @override
  bool operator ==(Object other) =>
      other is BindingKey && other.type == type && other.name == name;

  @override
  int get hashCode => Object.hash(type, name);

  @override
  String toString() => display;
}
