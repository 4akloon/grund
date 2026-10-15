import 'binding.dart';
import 'key.dart';
import 'module_identity.dart';

/// What a module declares, compared when one identity is imported twice.
///
/// Factories are never compared: two instances may carry different
/// configuration as long as they declare the same keys.
final class ModuleShape {
  /// Creates the shape.
  const ModuleShape({
    required this.imports,
    required this.bindings,
    required this.exports,
    required this.global,
  });

  /// Identities of the imports.
  final Set<ModuleIdentity> imports;

  /// Keys of the bindings with their scope.
  final Set<(Key<Object>, BindingScope)> bindings;

  /// Exported keys and re-exported module identities.
  final Set<Object> exports;

  /// Whether the module is global.
  final bool global;

  @override
  bool operator ==(Object other) =>
      other is ModuleShape &&
      other.global == global &&
      _sameSet(other.imports, imports) &&
      _sameSet(other.bindings, bindings) &&
      _sameSet(other.exports, exports);

  @override
  int get hashCode => Object.hash(global, imports.length, bindings.length);

  static bool _sameSet(Set<Object> a, Set<Object> b) =>
      a.length == b.length && a.containsAll(b);
}
