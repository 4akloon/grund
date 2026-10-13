import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../model/constant_value.dart';
import '../model/module_export.dart';
import '../model/module_model.dart';
import '../model/module_reference.dart';
import '../model/provider_key.dart';
import '../model/provider_model.dart';

/// The startup checks of the module graph that need no dependency
/// resolution: ids, import cycles, duplicate providers, exports, unreadable
/// entries and constants generated code cannot write.
abstract final class ModuleStructureCheck {
  /// The structural problems of [modules].
  static Iterable<Diagnostic> check(List<ModuleModel> modules) sync* {
    yield* _duplicateIds(modules);
    yield* _importCycles(modules);
    for (final module in modules) {
      yield* _entries(module);
      yield* _duplicateProviders(module);
      yield* _exports(module);
      yield* _constants(module);
    }
  }

  /// One diagnostic for every module whose id an earlier module already
  /// has, at that later module.
  static Iterable<Diagnostic> _duplicateIds(List<ModuleModel> modules) sync* {
    final first = <String, ModuleModel>{};
    for (final module in modules) {
      final other = first.putIfAbsent(module.id, () => module);
      if (other != module) {
        yield Diagnostic(
          DiagnosticCode.duplicateModuleId,
          module.location,
          'Modules ${other.type} and ${module.type} share the id '
          '"${module.id}". Give each @Module its own id.',
        );
      }
    }
  }

  static Iterable<Diagnostic> _importCycles(List<ModuleModel> modules) sync* {
    final byType = {for (final m in modules) m.type: m};
    final reported = <ModuleModel>{};
    for (final start in modules) {
      final cycle = _cycleFrom(start, byType, [start]);
      if (cycle == null || cycle.any(reported.contains)) continue;
      reported.addAll(cycle);
      yield Diagnostic(
        DiagnosticCode.circularModuleImport,
        start.location,
        'Module imports form a cycle: '
        '${[...cycle, start].map((m) => m.id).join(' -> ')}. Move the '
        'shared providers into a third module imported by both.',
      );
    }
  }

  /// The import path from [start] back to itself, if any.
  static List<ModuleModel>? _cycleFrom(
    ModuleModel start,
    Map<Object, ModuleModel> byType,
    List<ModuleModel> path,
  ) {
    for (final reference in path.last.imports) {
      if (reference is! LocalModuleReference) continue;
      final next = byType[reference.type];
      if (next == null || (next != start && path.contains(next))) continue;
      if (next == start) return path;
      if (_cycleFrom(start, byType, [...path, next]) case final cycle?) {
        return cycle;
      }
    }
    return null;
  }

  static Iterable<Diagnostic> _entries(ModuleModel module) => [
    for (final problem in module.invalidEntries)
      Diagnostic(
        DiagnosticCode.invalidModuleEntry,
        module.location,
        'Module "${module.id}": $problem',
      ),
  ];

  static Iterable<Diagnostic> _duplicateProviders(ModuleModel module) sync* {
    final seen = <ProviderKey>{};
    for (final provider in module.providers) {
      if (!seen.add(provider.key)) {
        yield Diagnostic(
          DiagnosticCode.duplicateProvider,
          module.location,
          'Module "${module.id}" declares ${provider.key} more than once.',
        );
      }
    }
  }

  static Iterable<Diagnostic> _exports(ModuleModel module) sync* {
    final keys = {for (final p in module.providers) p.key};
    for (final export in module.exports) {
      final (isValid, what) = switch (export) {
        KeyExport(:final key) => (keys.contains(key), '$key'),
        ModuleReexport(module: final reexported) => (
          module.imports.contains(reexported),
          'module ${reexported.display}',
        ),
      };
      if (!isValid) {
        yield Diagnostic(
          DiagnosticCode.invalidExport,
          module.location,
          'Module "${module.id}" exports $what, which is neither one of its '
          'providers nor one of its imports.',
        );
      }
    }
  }

  static Iterable<Diagnostic> _constants(ModuleModel module) => [
    for (final (what, value) in _constantsOf(module))
      if (value.unsupported case final unsupported?)
        Diagnostic(
          DiagnosticCode.unsupportedConstant,
          module.location,
          'Module "${module.id}": $what cannot be written in generated '
          'code: ${unsupported.reason}. Use public constants and const '
          'constructors of public classes.',
        ),
  ];

  /// Every constant a module's generated function writes, with what it is.
  static Iterable<(String, ConstantValue)> _constantsOf(
    ModuleModel module,
  ) sync* {
    for (final provider in module.providers) {
      if (provider case ValueProvider(:final value)) {
        yield ('the value of ${provider.key}', value);
      }
      if (provider.key case final TokenKey key) {
        yield ('the token $key', key.expression);
      }
    }
    for (final export in module.exports) {
      if (export case KeyExport(key: final TokenKey key)) {
        yield ('the token $key', key.expression);
      }
    }
  }
}
