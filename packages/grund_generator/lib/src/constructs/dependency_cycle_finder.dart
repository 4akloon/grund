import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../model/module_model.dart';
import 'module_scope.dart';
import 'scoped_binding.dart';

/// Finds cycles in the dependencies between the bindings of a package.
final class DependencyCycleFinder {
  /// Creates the finder over the bindings of [modules], resolved by [scope].
  DependencyCycleFinder(this._scope, this._modules);

  final ModuleScope _scope;

  final List<ModuleModel> _modules;

  final Set<ScopedBinding> _done = {};

  final List<ScopedBinding> _path = [];

  /// One diagnostic per cycle found.
  List<Diagnostic> find() {
    final found = <Diagnostic>[];
    for (final module in _modules) {
      for (final binding in _scope.bindingsOf(module)) {
        _visit((owner: module, binding: binding), found);
      }
    }
    return found;
  }

  void _visit(ScopedBinding node, List<Diagnostic> found) {
    final index = _path.indexOf(node);
    if (index >= 0) {
      found.add(_report(_path.sublist(index)));
      return;
    }
    if (_done.contains(node)) return;
    _path.add(node);
    final visible = _scope.visibleIn(node.owner);
    for (final dependency in node.binding.dependencies) {
      if (visible[dependency.key] case final next?) _visit(next, found);
    }
    _path.removeLast();
    _done.add(node);
  }

  Diagnostic _report(List<ScopedBinding> cycle) {
    final names = [...cycle, cycle.first].map((node) => node.binding.key);
    return Diagnostic(
      DiagnosticCode.circularDependency,
      cycle.first.binding.location,
      'Circular dependency: ${names.join(' -> ')}.',
    );
  }
}
