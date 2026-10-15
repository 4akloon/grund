import 'binding_key.dart';
import 'type_model.dart';

/// One entry of `@Module(exports: ...)`.
sealed class ModuleExport {
  /// Creates the export.
  const ModuleExport();
}

/// An exported binding: a type or a `Key<T>('name')`.
final class KeyExport extends ModuleExport {
  /// Creates the export.
  const KeyExport(this.key);

  /// The exported key.
  final BindingKey key;
}

/// A re-exported imported module, written as its type.
final class ModuleReexport extends ModuleExport {
  /// Creates the export.
  const ModuleReexport(this.type);

  /// The class of the re-exported module.
  final TypeModel type;
}
