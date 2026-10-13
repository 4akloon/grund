import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../diagnostic/source_location.dart';
import '../model/constructor_model.dart';
import '../model/controller_model.dart';
import '../model/module_export.dart';
import '../model/module_model.dart';
import '../model/module_reference.dart';
import '../model/package_model.dart';
import '../model/provider_key.dart';
import '../model/provider_model.dart';
import '../model/type_model.dart';
import 'module_scope.dart';
import 'scoped_provider.dart';

/// The startup checks that resolve dependencies: a missing provider and a
/// circular dependency, for provider classes, controllers and the pipeline
/// components controllers use.
///
/// One module built by a function (an explicit module or another package's)
/// can provide and export anything, so a package that imports or re-exports
/// one is not checked here at all: no module can be proven to lack a
/// provider. `Application.create` still checks it at startup.
///
/// Two limits follow from reading only `@Module` classes:
/// - the opaque test looks at imports and re-exports of `@Module` classes
///   only. An explicit global `Module` that only an explicit root imports is
///   invisible to the scope, so a dependency it satisfies can be reported as
///   `missing_provider` wrongly.
/// - a global `@Module` of this package that nothing imports is treated as
///   global, although at startup it is absent unless something imports it;
///   a real `missing_provider` can be hidden.
final class DependencyCheck {
  DependencyCheck._(this._package, this._scope);

  final PackageModel _package;

  final ModuleScope _scope;

  /// The dependency problems of [package], or none when it has an opaque
  /// module reference.
  static List<Diagnostic> check(PackageModel package) {
    if (package.modules.any(_hasOpaqueReference)) return const [];
    final check = DependencyCheck._(package, ModuleScope(package.modules));
    return [
      for (final module in package.modules) ...[
        ...check._missingInProviders(module),
        ...check._missingInControllers(module),
      ],
      ..._CycleFinder(check._scope).find(package.modules),
    ];
  }

  static bool _hasOpaqueReference(ModuleModel module) => [
    ...module.imports,
    for (final export in module.exports)
      if (export is ModuleReexport) export.module,
  ].any((reference) => reference is OpaqueModuleReference);

  Iterable<Diagnostic> _missingInProviders(ModuleModel module) sync* {
    for (final provider in module.providers) {
      if (provider is ClassProvider) {
        final injectable = provider.injectable;
        yield* _missing(module, injectable.type, injectable.constructor);
      }
    }
  }

  Iterable<Diagnostic> _missingInControllers(ModuleModel module) sync* {
    for (final type in module.controllers) {
      final controller = _package.controllers
          .where((controller) => controller.type == type)
          .firstOrNull;
      // Invariant: every listed controller class is annotated with
      // `@Controller` and collected into the package, so this skip is only a
      // guard for a controller declared outside the analysed libraries; the
      // core checks it at startup.
      if (controller == null) continue;
      yield* _missing(module, type, controller.constructor);
      yield* _missingComponents(module, controller);
    }
  }

  Iterable<Diagnostic> _missingComponents(
    ModuleModel module,
    ControllerModel controller,
  ) sync* {
    final visible = _scope.visibleIn(module);
    for (final component in _components(controller)) {
      final key = TypeKey(component);
      if (!visible.containsKey(key)) {
        yield _diagnostic(module, key, controller.type, controller.location);
      }
    }
  }

  /// The components of [controller] and its routes, each type once.
  static Set<TypeModel> _components(ControllerModel controller) => {
    for (final component in [
      ...controller.enhancers.all,
      for (final route in controller.routes) ...route.enhancers.all,
    ])
      if (component.isValid) component.type,
  };

  Iterable<Diagnostic> _missing(
    ModuleModel module,
    TypeModel owner,
    ConstructorModel constructor,
  ) sync* {
    final visible = _scope.visibleIn(module);
    for (final dependency in constructor.dependencies) {
      final key = dependency.key;
      if (key != null && !visible.containsKey(key)) {
        yield _diagnostic(module, key, owner, dependency.location);
      }
    }
  }

  Diagnostic _diagnostic(
    ModuleModel module,
    ProviderKey key,
    TypeModel owner,
    SourceLocation location,
  ) {
    final declaring = _scope.declaring(key);
    final hint = declaring.isEmpty
        ? ''
        : ' It is declared in module(s) [${declaring.join(', ')}]; export it '
              'there and import that module into "${module.id}".';
    return Diagnostic(
      DiagnosticCode.missingProvider,
      location,
      'No provider for $key in module "${module.id}" (resolving: $owner).'
      '$hint',
    );
  }
}

/// Finds dependency cycles with a depth-first search that marks each
/// provider once (white, grey on the current path, black when done), so a
/// dense graph costs one visit per provider and dependency, not one per
/// path.
final class _CycleFinder {
  _CycleFinder(this._scope);

  final ModuleScope _scope;

  final Set<ScopedProvider> _done = {};

  final List<ScopedProvider> _path = [];

  /// One diagnostic per cycle, at the class where the search entered it.
  List<Diagnostic> find(List<ModuleModel> modules) {
    final found = <Diagnostic>[];
    for (final module in modules) {
      for (final provider in module.providers) {
        _visit((owner: module, provider: provider), found);
      }
    }
    return found;
  }

  void _visit(ScopedProvider node, List<Diagnostic> found) {
    final provider = node.provider;
    if (provider is! ClassProvider) return;
    final index = _path.indexOf(node);
    if (index >= 0) {
      found.add(_report(_path.sublist(index)));
      return;
    }
    if (_done.contains(node)) return;
    _path.add(node);
    final visible = _scope.visibleIn(node.owner);
    for (final dependency in provider.injectable.constructor.dependencies) {
      final next = visible[dependency.key];
      if (next != null) _visit(next, found);
    }
    _path.removeLast();
    _done.add(node);
  }

  Diagnostic _report(List<ScopedProvider> cycle) {
    final names = [...cycle, cycle.first].map((node) => node.provider.key);
    return Diagnostic(
      DiagnosticCode.circularDependency,
      (cycle.first.provider as ClassProvider).injectable.location,
      'Circular dependency: ${names.join(' -> ')}.',
    );
  }
}
