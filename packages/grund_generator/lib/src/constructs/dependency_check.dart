import '../construct/provider_claims.dart';
import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../diagnostic/source_location.dart';
import '../model/binding_key.dart';
import '../model/module_export.dart';
import '../model/module_model.dart';
import '../model/module_reference.dart';
import '../model/package_model.dart';
import 'captive_finder.dart';
import 'dependency_cycle_finder.dart';
import 'module_scope.dart';

/// Checks that every dependency and lookup of a binding is visible in its
/// module and that the bindings form no cycle and no captive dependency.
final class DependencyCheck {
  DependencyCheck._(this._scope, List<ModuleModel> modules)
    : _isPartial = _hasOpaqueReference(modules);

  final ModuleScope _scope;

  // A module from another package may export what looks missing, so then
  // only keys that a module of this package binds are reported.
  final bool _isPartial;

  /// The dependency problems of the modules of [package], whose bindings
  /// are as [claims] say.
  ///
  /// The import graph must be acyclic.
  static List<Diagnostic> check(PackageModel package, ProviderClaims claims) {
    final modules = package.modules;
    final check = DependencyCheck._(ModuleScope(modules, claims), modules);
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
    bool isMissing(BindingKey key) =>
        !visible.containsKey(key) && !_isUnknowable(key);
    for (final binding in _scope.bindingsOf(module)) {
      for (final dependency in binding.dependencies) {
        final key = dependency.key;
        if (key == null || !isMissing(key)) continue;
        yield _diagnostic(module, key, binding.key, dependency.location);
      }
      for (final lookup in binding.lookups) {
        if (!isMissing(lookup.key)) continue;
        yield _diagnostic(module, lookup.key, binding.key, lookup.location);
      }
    }
  }

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
