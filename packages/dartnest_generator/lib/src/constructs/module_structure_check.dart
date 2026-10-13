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
    final finder = _ImportCycleFinder({for (final m in modules) m.type: m});
    final reported = <ModuleModel>{};
    for (final cycle in finder.find(modules)) {
      if (cycle.any(reported.contains)) continue;
      reported.addAll(cycle);
      yield Diagnostic(
        DiagnosticCode.circularModuleImport,
        cycle.first.location,
        'Module imports form a cycle: '
        '${[...cycle, cycle.first].map((m) => m.id).join(' -> ')}. Move the '
        'shared providers into a third module imported by both.',
      );
    }
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

/// Finds import cycles with a depth-first search that marks each module
/// once (grey on the current path, black when done), so a dense module graph
/// costs one visit per module and import, not one per path.
final class _ImportCycleFinder {
  _ImportCycleFinder(this._byType);

  final Map<Object, ModuleModel> _byType;

  final Set<ModuleModel> _done = {};

  final List<ModuleModel> _path = [];

  /// Every cycle a back edge closes, each starting at the module where the
  /// search entered it.
  List<List<ModuleModel>> find(List<ModuleModel> modules) {
    final found = <List<ModuleModel>>[];
    for (final module in modules) {
      _visit(module, found);
    }
    return found;
  }

  void _visit(ModuleModel module, List<List<ModuleModel>> found) {
    final index = _path.indexOf(module);
    if (index >= 0) {
      found.add(_path.sublist(index));
      return;
    }
    if (_done.contains(module)) return;
    _path.add(module);
    for (final reference in module.imports) {
      if (reference is! LocalModuleReference) continue;
      if (_byType[reference.type] case final next?) _visit(next, found);
    }
    _path.removeLast();
    _done.add(module);
  }
}
