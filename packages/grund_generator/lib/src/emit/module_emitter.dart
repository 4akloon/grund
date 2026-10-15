import 'package:code_builder/code_builder.dart';

import '../construct/provider_claims.dart';
import '../model/generated_names.dart';
import '../model/module_export.dart';
import '../model/module_model.dart';
import 'binding_emitter.dart';
import 'constant_emitter.dart';
import 'core_references.dart';
import 'override_getter.dart';
import 'type_emitter.dart';

/// Writes the mixin `$X on Module` that gives a `@Module` class X its
/// `imports`, `bindings`, `exports` and `global`.
abstract final class ModuleEmitter {
  /// The mixin of [module]; [claims] say which providers a construct wrote
  /// the bindings of.
  static Mixin emit(ModuleModel module, ProviderClaims claims) {
    final bindings = _bindings(module, claims);
    final moduleType = CoreReferences.grund('Module');
    return Mixin(
      (b) => b
        ..name = GeneratedNames.module(module.type.name)
        ..docs.add('/// The generated declarations of `${module.type.name}`.')
        ..on = moduleType
        ..methods.addAll([
          if (module.imports.isNotEmpty)
            OverrideGetter.build(
              'imports',
              OverrideGetter.listOf(moduleType),
              literalList([
                for (final import in module.imports)
                  ConstantEmitter.instance(import.instance),
              ]),
            ),
          if (bindings.isNotEmpty)
            OverrideGetter.build(
              'bindings',
              OverrideGetter.listOf(_bindingType),
              literalList(bindings),
            ),
          if (module.exports.isNotEmpty)
            OverrideGetter.build(
              'exports',
              OverrideGetter.listOf(refer('Object')),
              _exports(module),
            ),
          if (module.isGlobal)
            OverrideGetter.build('global', refer('bool'), literalTrue),
        ]),
    );
  }

  static TypeReference get _bindingType => TypeReference(
    (b) => b
      ..symbol = 'Binding'
      ..url = CoreReferences.grund('Binding').url
      ..types.add(refer('Object')),
  );

  // Providers in annotation order, a claimed one as the bindings its
  // construct gave, then the `@Provides` methods in declaration order.
  static List<Expression> _bindings(
    ModuleModel module,
    ProviderClaims claims,
  ) => [
    for (final provider in module.providers)
      if (claims.claimed(provider) case final claim?)
        for (final binding in claim.bindings)
          binding.emission ??
              (throw StateError(
                'The construct that claimed ${provider.injectable.type} gave '
                'the binding ${binding.key} no emission.',
              ))
      else
        BindingEmitter.provider(provider),
    for (final provided in module.provides)
      if (provided.key case final key?) BindingEmitter.provides(provided, key),
  ];

  static Expression _exports(ModuleModel module) {
    final keys = [
      for (final export in module.exports)
        if (export case KeyExport(:final key)) key,
    ]..sort();
    final modules = [
      for (final export in module.exports)
        if (export case ModuleReexport(:final type)) type,
    ]..sort((a, b) => a.display.compareTo(b.display));
    // The core accepts a re-exported module only as an instance (like an
    // entry of `imports`), and the module classes may have no const
    // constructor, so a list with a module is not const.
    final values = [
      for (final key in keys)
        CoreReferences.key(TypeEmitter.reference(key.type), key.name),
      for (final type in modules) TypeEmitter.reference(type).newInstance([]),
    ];
    return modules.isEmpty ? literalConstList(values) : literalList(values);
  }
}
