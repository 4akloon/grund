import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/hook_model.dart';
import 'annotations.dart';
import 'constant_reader.dart';
import 'entry_read.dart';
import 'type_reader.dart';

/// Reads the `use:` list of `@Api` and of the route annotations.
abstract final class HookReader {
  /// The hooks of the `use` field of [annotation], in order.
  static List<EntryRead<HookModel>> read(DartObject annotation) => [
    for (final entry
        in Annotations.field(annotation, 'use')?.toListValue() ??
            const <DartObject>[])
      _hook(entry),
  ];

  static EntryRead<HookModel> _hook(DartObject entry) {
    final type = entry.type;
    if (type is! InterfaceType ||
        !TypeReader.isFrom(type, 'HookRef', 'package:grund_http/')) {
      return InvalidEntry(
        'use: ${Annotations.describe(entry)} is not a HookRef.',
      );
    }
    return ReadEntry(
      HookModel(
        type: TypeReader.read(type.typeArguments.single),
        isInstance: entry.constructorInvocation?.constructor.name == 'instance',
        expression: ConstantReader.read(entry),
      ),
    );
  }
}
