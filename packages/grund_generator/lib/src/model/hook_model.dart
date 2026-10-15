import 'constant_value.dart';
import 'type_model.dart';

/// One entry of `use:` on `@Api` or a route annotation: a `HookRef`.
final class HookModel {
  /// Creates the model.
  const HookModel({
    required this.type,
    required this.isInstance,
    required this.expression,
  });

  /// The hook class: the `T` of `HookRef<T>`.
  final TypeModel type;

  /// Whether the hook is a given instance (`HookRef<T>.instance(...)`);
  /// otherwise (`HookRef<T>.type()`) it is a binding of the module.
  final bool isInstance;

  /// The `HookRef` as written in the annotation.
  final ConstantValue expression;
}
