import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../model/binding_key.dart';
import '../model/module_export.dart';
import '../model/module_model.dart';
import 'import_cycle_finder.dart';

/// Checks what a module declares without looking at other modules'
/// bindings: its class, entries, duplicates, exports and constants.
abstract final class ModuleStructureCheck {
  /// The structural problems of [modules].
  static Iterable<Diagnostic> check(List<ModuleModel> modules) sync* {
    yield* _importCycles(modules);
    for (final module in modules) {
      yield* _moduleClass(module);
      yield* _entries(module);
      yield* _duplicateBindings(module);
      yield* _exports(module);
      yield* _constants(module);
    }
  }

  static Iterable<Diagnostic> _importCycles(List<ModuleModel> modules) sync* {
    final reported = <ModuleModel>{};
    for (final cycle in ImportCycleFinder(modules).find()) {
      if (cycle.any(reported.contains)) continue;
      reported.addAll(cycle);
      yield Diagnostic(
        DiagnosticCode.circularModuleImport,
        cycle.first.location,
        'Module imports form a cycle: '
        '${[...cycle, cycle.first].map((m) => m.type).join(' -> ')}. Move '
        'the shared providers into a third module imported by both.',
      );
    }
  }

  static Iterable<Diagnostic> _moduleClass(ModuleModel module) sync* {
    if (module.extendsModule) return;
    yield Diagnostic(
      DiagnosticCode.invalidModuleClass,
      module.location,
      '${module.type} is annotated with @Module but does not extend Module '
      'of package:grund/grund.dart. Write "final class ${module.type} '
      'extends Module with \$${module.type}".',
    );
  }

  static Iterable<Diagnostic> _entries(ModuleModel module) => [
    for (final problem in module.invalidEntries)
      Diagnostic(
        DiagnosticCode.invalidModuleEntry,
        module.location,
        'Module ${module.type}: $problem',
      ),
  ];

  static Iterable<Diagnostic> _duplicateBindings(ModuleModel module) sync* {
    final seen = <BindingKey>{};
    for (final binding in module.bindings) {
      if (seen.add(binding.key)) continue;
      yield Diagnostic(
        DiagnosticCode.duplicateBinding,
        binding.location,
        'Module ${module.type} binds ${binding.key} more than once.',
      );
    }
  }

  static Iterable<Diagnostic> _exports(ModuleModel module) sync* {
    final keys = {for (final binding in module.bindings) binding.key};
    final imported = {for (final reference in module.imports) reference.type};
    for (final export in module.exports) {
      final (isValid, what) = switch (export) {
        KeyExport(:final key) => (keys.contains(key), '$key'),
        ModuleReexport(:final type) => (
          imported.contains(type),
          'module $type',
        ),
      };
      if (isValid) continue;
      yield Diagnostic(
        DiagnosticCode.invalidExport,
        module.location,
        'Module ${module.type} exports $what, which is neither one of its '
        'bindings nor one of its imports.',
      );
    }
  }

  static Iterable<Diagnostic> _constants(ModuleModel module) sync* {
    for (final reference in module.imports) {
      if (reference.instance.unsupported case final unsupported?) {
        yield Diagnostic(
          DiagnosticCode.unsupportedConstant,
          module.location,
          'Module ${module.type}: the import ${reference.display} cannot be '
          'written in generated code: ${unsupported.reason}. Use public '
          'constants and const constructors of public classes.',
        );
      }
    }
  }
}
