import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/module_reference.dart';
import 'annotations.dart';
import 'constant_reader.dart';
import 'type_reader.dart';

/// Reads an entry of `@Module(imports: ...)`: a `const` instance of a class
/// that extends the core `Module`.
final class ModuleReferenceReader {
  /// Creates the reader for package [packageName].
  ModuleReferenceReader(this.packageName);

  /// The package being generated.
  final String packageName;

  /// The reference [entry] denotes, or `null` when it is not a module
  /// instance.
  ModuleReference? read(DartObject entry) {
    final type = entry.type;
    if (type is! InterfaceType || !isModuleClass(type)) return null;
    final model = TypeReader.read(type);
    final instance = ConstantReader.read(entry);
    return _isLocal(type)
        ? LocalModuleReference(model, instance)
        : OpaqueModuleReference(model, instance);
  }

  /// Whether [type] extends the core `Module`.
  static bool isModuleClass(InterfaceType type) =>
      TypeReader.hasSupertype(type.element, 'Module', 'package:grund/');

  bool _isLocal(InterfaceType type) =>
      Annotations.find(type.element, 'Module') != null &&
      '${type.element.library.uri}'.startsWith('package:$packageName/');
}
