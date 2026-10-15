import 'constant_value.dart';
import 'type_model.dart';

/// A module listed in `@Module(imports: ...)`: a `const` instance.
sealed class ModuleReference {
  /// Creates the reference.
  const ModuleReference(this.type, this.instance);

  /// The module class.
  final TypeModel type;

  /// The instance as written in the annotation; the generated mixin writes
  /// the same constructor call.
  final ConstantValue instance;

  /// The reference as written in the annotation, for messages.
  String get display => type.display;
}

/// An instance of a class annotated with `@Module` in the generated package:
/// the generator knows its imports, bindings and exports.
final class LocalModuleReference extends ModuleReference {
  /// Creates the reference.
  const LocalModuleReference(super.type, super.instance);
}

/// An instance of any other `Module`: another package's module, or one
/// written with the explicit API. The generator cannot see its bindings, so
/// the graph check is partial for it; the core checks the rest at startup.
final class OpaqueModuleReference extends ModuleReference {
  /// Creates the reference.
  const OpaqueModuleReference(super.type, super.instance);
}
