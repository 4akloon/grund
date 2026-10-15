import 'module_reference.dart';
import 'provider_key.dart';

/// One entry of `@Module(exports: ...)`.
sealed class ModuleExport {
  /// Creates the export.
  const ModuleExport();
}

/// An exported provider key.
final class KeyExport extends ModuleExport {
  /// Creates the export.
  const KeyExport(this.key);

  /// The exported key.
  final ProviderKey key;
}

/// A re-exported imported module.
final class ModuleReexport extends ModuleExport {
  /// Creates the export.
  const ModuleReexport(this.module);

  /// The re-exported module.
  final ModuleReference module;
}
