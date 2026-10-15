import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../diagnostic/source_location.dart';
import '../model/api_model.dart';
import '../model/binding_key.dart';
import '../model/module_export.dart';
import '../model/module_model.dart';
import '../model/module_reference.dart';
import '../model/package_model.dart';
import '../model/type_model.dart';
import 'captive_finder.dart';
import 'dependency_cycle_finder.dart';
import 'module_scope.dart';

/// Checks that every dependency of a binding is visible in its module and
/// that the bindings form no cycle and no captive dependency.
final class DependencyCheck {
  DependencyCheck._(this._package, this._scope)
    : _isPartial = _hasOpaqueReference(_package.modules);

  final PackageModel _package;

  final ModuleScope _scope;

  // A module from another package may export what looks missing, so then
  // only keys that a module of this package binds are reported.
  final bool _isPartial;

  /// The dependency problems of the modules of [package].
  ///
  /// The import graph must be acyclic.
  static List<Diagnostic> check(PackageModel package) {
    final modules = package.modules;
    final check = DependencyCheck._(package, ModuleScope(modules));
    return [
      for (final module in modules) ...check._missing(module),
      ...DependencyCycleFinder(check._scope, modules).find(),
      ...CaptiveFinder(check._scope, modules).find(),
    ];
  }

  static bool _hasOpaqueReference(List<ModuleModel> modules) {
    final local = {for (final module in modules) module.type};
    return modules.any(
      (module) =>
          module.imports.any((i) => i is OpaqueModuleReference) ||
          module.exports.any(
            (e) => e is ModuleReexport && !local.contains(e.type),
          ),
    );
  }

  Iterable<Diagnostic> _missing(ModuleModel module) sync* {
    final visible = _scope.visibleIn(module);
    for (final binding in module.bindings) {
      for (final dependency in binding.dependencies) {
        final key = dependency.key;
        if (key == null || visible.containsKey(key)) continue;
        if (_isUnknowable(key)) continue;
        yield _diagnostic(module, key, binding.key, dependency.location);
      }
    }
    yield* _hooks(module, visible.containsKey);
  }

  Iterable<Diagnostic> _hooks(
    ModuleModel module,
    bool Function(BindingKey) isVisible,
  ) sync* {
    for (final provider in module.providers) {
      final api = _apiOf(provider.injectable.type);
      if (api == null) continue;
      for (final hook in [
        ...api.use,
        for (final route in api.routes) ...route.use,
      ]) {
        final key = BindingKey(hook.type);
        if (hook.isInstance || isVisible(key) || _isUnknowable(key)) continue;
        yield _diagnostic(module, key, provider.key, api.location);
      }
    }
  }

  ApiModel? _apiOf(TypeModel type) =>
      _package.apis.where((api) => api.type == type).firstOrNull;

  bool _isUnknowable(BindingKey key) =>
      _isPartial && _scope.declaring(key).isEmpty;

  Diagnostic _diagnostic(
    ModuleModel module,
    BindingKey key,
    BindingKey owner,
    SourceLocation location,
  ) {
    final declaring = _scope.declaring(key);
    final hint = declaring.isEmpty
        ? ''
        : ' It is bound in module(s) [${declaring.join(', ')}]; export it '
              'there and import that module into ${module.type}.';
    return Diagnostic(
      DiagnosticCode.missingProvider,
      location,
      'No provider for $key in module ${module.type} (needed by $owner).'
      '$hint',
    );
  }
}
