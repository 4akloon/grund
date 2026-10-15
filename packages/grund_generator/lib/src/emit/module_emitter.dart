import 'package:code_builder/code_builder.dart';

import '../model/generated_names.dart';
import '../model/module_export.dart';
import '../model/module_model.dart';
import '../model/module_reference.dart';
import '../model/provider_key.dart';
import '../model/provider_model.dart';
import 'constant_emitter.dart';
import 'dart_string.dart';
import 'import_allocator.dart';
import 'type_emitter.dart';

/// Writes a [ModuleModel] as a function returning the core `Module`.
abstract final class ModuleEmitter {
  /// `Module usersModule() => Module(id: 'users', ...)`; empty lists and
  /// `global: false` are left out. A module listed twice in `imports`, and
  /// an export listed twice, is written once, at its first position.
  static Method function(ModuleModel module) {
    final imports = module.imports.toSet();
    final exports = _distinct(module.exports);
    return Method(
      (b) => b
        ..docs.add('/// The module of `${module.type.name}`.')
        ..name = GeneratedNames.module(module.type.name)
        ..returns = _core('Module')
        ..lambda = true
        ..body = _core('Module').newInstance(const [], {
          'id': CodeExpression(Code(DartString.literal(module.id))),
          if (imports.isNotEmpty)
            'imports': literalList(imports.map(reference)),
          if (module.providers.isNotEmpty)
            'providers': literalList(module.providers.map(_provider)),
          if (module.controllers.isNotEmpty)
            'controllers': literalList([
              for (final type in module.controllers)
                refer(GeneratedNames.controller(type.name)).call(const []),
            ]),
          if (exports.isNotEmpty) 'exports': literalList(exports.map(_export)),
          if (module.isGlobal) 'global': literalTrue,
        }).code,
    );
  }

  /// The call that builds the module [reference] points to.
  static Expression reference(ModuleReference reference) => switch (reference) {
    LocalModuleReference(:final type) => refer(
      GeneratedNames.module(type.name),
    ).call(const []),
    OpaqueModuleReference(
      :final name,
      :final libraryUri,
      :final enclosingName?,
    ) =>
      refer(enclosingName, libraryUri).property(name).call(const []),
    OpaqueModuleReference(:final name, :final libraryUri) => refer(
      name,
      libraryUri,
    ).call(const []),
  };

  static Expression _provider(ProviderModel provider) {
    final (type, token) = switch (provider.key) {
      TypeKey(:final type) => (type, null),
      TokenKey(:final valueType, :final expression) => (
        valueType,
        ConstantEmitter.expression(expression),
      ),
    };
    final generic = TypeReference(
      (b) => b
        ..symbol = 'Provider'
        ..url = ImportAllocator.grund
        ..types.add(TypeEmitter.reference(type)),
    );
    final named = {if (token != null) 'token': token};
    return switch (provider) {
      ClassProvider(:final injectable) => generic.newInstance([
        refer(GeneratedNames.factory(injectable.type.name)),
      ], named),
      ValueProvider(:final value) => generic.newInstanceNamed('value', [
        ConstantEmitter.expression(value),
      ], named),
    };
  }

  static List<ModuleExport> _distinct(List<ModuleExport> exports) {
    final seen = <Object>{};
    return [
      for (final export in exports)
        if (seen.add(switch (export) {
          KeyExport(:final key) => key,
          ModuleReexport(:final module) => module,
        }))
          export,
    ];
  }

  static Expression _export(ModuleExport export) => switch (export) {
    KeyExport(key: TypeKey(:final type)) => TypeEmitter.reference(type),
    KeyExport(key: TokenKey(:final expression)) => ConstantEmitter.expression(
      expression,
    ),
    ModuleReexport(:final module) => reference(module),
  };

  static Reference _core(String name) => refer(name, ImportAllocator.grund);
}
