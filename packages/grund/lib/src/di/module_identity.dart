import 'package:meta/meta.dart';

import 'module.dart';

/// What makes two module instances the same module: the class and the
/// qualifier.
@immutable
final class ModuleIdentity {
  /// Creates the identity of the module class [type] with [qualifier].
  const ModuleIdentity(this.type, [this.qualifier]);

  /// The identity of [module].
  factory ModuleIdentity.of(Module module) =>
      ModuleIdentity(module.runtimeType, module.qualifier);

  /// The module class.
  final Type type;

  /// The qualifier, or `null`.
  final Object? qualifier;

  @override
  bool operator ==(Object other) =>
      other is ModuleIdentity &&
      other.type == type &&
      other.qualifier == qualifier;

  @override
  int get hashCode => Object.hash(type, qualifier);

  @override
  String toString() => qualifier == null ? '$type' : "$type('$qualifier')";
}
