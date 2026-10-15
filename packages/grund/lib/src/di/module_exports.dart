import 'key.dart';
import 'module_identity.dart';

/// What a module offers to the modules that import it.
final class ModuleExports {
  /// Creates the exports from [keys] and [modules].
  const ModuleExports({required this.keys, required this.modules});

  /// Keys of the module's own bindings that importers may use.
  final List<Key<Object>> keys;

  /// Imported modules whose exports are passed on.
  final List<ModuleIdentity> modules;
}
