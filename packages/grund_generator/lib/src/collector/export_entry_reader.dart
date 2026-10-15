import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/binding_key.dart';
import '../model/module_export.dart';
import 'annotations.dart';
import 'entry_read.dart';
import 'module_reference_reader.dart';
import 'type_reader.dart';

/// Reads one entry of `@Module(exports: [...])`: a type, a
/// `Key<T>('name')`, or the type of an imported module.
abstract final class ExportEntryReader {
  /// The export [entry] declares.
  static EntryRead<ModuleExport> read(DartObject entry) {
    if (entry.toTypeValue() case final InterfaceType type) {
      return ReadEntry(
        ModuleReferenceReader.isModuleClass(type)
            ? ModuleReexport(TypeReader.read(type))
            : KeyExport(
                BindingKey(
                  TypeReader.read(type),
                  Annotations.core.named(type.element),
                ),
              ),
      );
    }
    final type = entry.type;
    if (type is InterfaceType && TypeReader.isGrund(type, 'Key')) {
      final name = Annotations.field(entry, 'name')?.toStringValue();
      return ReadEntry(
        KeyExport(BindingKey(TypeReader.read(type.typeArguments.single), name)),
      );
    }
    return InvalidEntry(
      'exports: ${Annotations.describe(entry)} is not a class, a Key<T>() '
      'or an imported module.',
    );
  }
}
