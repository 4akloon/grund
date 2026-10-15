import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:grund_generator/grund_generator.dart';

import '../model/hook_model.dart';

/// Reads the `use:` list of `@Api` and of the route annotations.
///
/// An entry is a hook class (`ApiKeyHook`), a constant hook instance
/// (`RolesHook(Role.editor)`) or a `HookRef` constant; all three are turned
/// into the same `HookRef` expression, so the generated code does not depend
/// on how the entry was written.
abstract final class HookReader {
  static const _httpPackage = 'package:grund_http/';

  /// A library of `package:grund_http` that declares `HookRef`; the emitter
  /// only needs the package to write the reference with its prefix.
  static const _hookRefLibrary = '${_httpPackage}src/hook/hook_ref.dart';

  static const _acceptedForms =
      'a hook class (`ApiKeyHook`), a const hook instance '
      '(`RolesHook(Role.editor)`) or a `HookRef` constant';

  /// The hooks of the `use` field of [annotation], in order.
  static List<EntryRead<HookModel>> read(DartObject annotation) => [
    for (final entry
        in Annotations.field(annotation, 'use')?.toListValue() ??
            const <DartObject>[])
      _hook(entry),
  ];

  static EntryRead<HookModel> _hook(DartObject entry) {
    final typeValue = entry.toTypeValue();
    if (typeValue != null) return _hookClass(entry, typeValue);
    final type = entry.type;
    if (type is InterfaceType &&
        TypeReader.isFrom(type, 'HookRef', _httpPackage)) {
      return _hookRef(entry, type);
    }
    if (type is InterfaceType && _isHook(type)) return _instance(entry, type);
    return _invalid(entry);
  }

  static EntryRead<HookModel> _hookClass(DartObject entry, DartType hook) {
    if (hook is! InterfaceType || !_isHook(hook)) return _invalid(entry);
    final model = TypeReader.read(hook);
    return ReadEntry(
      HookModel(
        type: model,
        isInstance: false,
        expression: _privateName(model) ?? _hookRefOf(model, 'type', const []),
      ),
    );
  }

  static EntryRead<HookModel> _instance(DartObject entry, InterfaceType hook) {
    final model = TypeReader.read(hook);
    return ReadEntry(
      HookModel(
        type: model,
        isInstance: true,
        expression:
            _privateName(model) ??
            _hookRefOf(model, 'instance', [ConstantReader.read(entry)]),
      ),
    );
  }

  static EntryRead<HookModel> _hookRef(DartObject entry, InterfaceType type) =>
      ReadEntry(
        HookModel(
          type: TypeReader.read(type.typeArguments.single),
          isInstance:
              entry.constructorInvocation?.constructor.name == 'instance',
          expression: ConstantReader.read(entry),
        ),
      );

  /// Names a hook class that no other library can write down.
  static UnsupportedConstant? _privateName(TypeModel hook) =>
      hook.name.startsWith('_')
      ? UnsupportedConstant('${hook.name} is private')
      : null;

  static ObjectConstant _hookRefOf(
    TypeModel hook,
    String constructorName,
    List<ConstantValue> positional,
  ) => ObjectConstant(
    type: TypeModel(
      name: 'HookRef',
      kind: TypeKind.interface,
      libraryUri: _hookRefLibrary,
      typeArguments: [hook],
    ),
    constructorName: constructorName,
    positional: positional,
  );

  static bool _isHook(InterfaceType type) => [
    type,
    ...type.element.allSupertypes,
  ].any((t) => TypeReader.isFrom(t, 'HttpHook', _httpPackage));

  static InvalidEntry<HookModel> _invalid(DartObject entry) => InvalidEntry(
    'use: ${Annotations.describe(entry)} is not a hook; write $_acceptedForms.',
  );
}
