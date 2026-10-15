import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../model/binding_key.dart';
import '../model/lifetime.dart';
import '../model/module_model.dart';
import 'module_scope.dart';
import 'scoped_binding.dart';

/// Finds singletons that keep a call-scoped binding alive.
final class CaptiveFinder {
  /// Creates the finder over the bindings of [modules], resolved by [scope].
  CaptiveFinder(this._scope, this._modules);

  final ModuleScope _scope;

  final List<ModuleModel> _modules;

  /// One diagnostic per singleton that reaches a call-scoped binding
  /// directly or through transient ones.
  List<Diagnostic> find() => [
    for (final module in _modules)
      for (final binding in _scope.bindingsOf(module))
        if (binding.lifetime == Lifetime.singleton)
          ..._captive((owner: module, binding: binding)),
  ];

  Iterable<Diagnostic> _captive(ScopedBinding singleton) sync* {
    final path = _pathToScoped(singleton, {singleton}, [singleton.binding.key]);
    if (path == null) return;
    yield Diagnostic(
      DiagnosticCode.captiveDependency,
      singleton.binding.location,
      'Singleton ${path.first} depends on the call-scoped ${path.last} '
      '(${path.join(' -> ')}); a singleton outlives every call. Make '
      '${path.first} call-scoped or transient, or ${path.last} a singleton.',
    );
  }

  List<BindingKey>? _pathToScoped(
    ScopedBinding from,
    Set<ScopedBinding> seen,
    List<BindingKey> path,
  ) {
    final visible = _scope.visibleIn(from.owner);
    for (final dependency in from.binding.dependencies) {
      final next = visible[dependency.key];
      if (next == null || !seen.add(next)) continue;
      final trail = [...path, next.binding.key];
      switch (next.binding.lifetime) {
        case Lifetime.scoped:
          return trail;
        case Lifetime.transient:
          if (_pathToScoped(next, seen, trail) case final found?) return found;
        case Lifetime.singleton:
          break;
      }
    }
    return null;
  }
}
