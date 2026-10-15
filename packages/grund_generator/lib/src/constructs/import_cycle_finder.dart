import '../model/module_model.dart';
import '../model/module_reference.dart';
import '../model/type_model.dart';

/// Finds cycles in the import graph of the modules of one package.
final class ImportCycleFinder {
  /// Creates the finder over [modules].
  ImportCycleFinder(List<ModuleModel> modules)
    : _modules = modules,
      _byType = {for (final module in modules) module.type: module};

  final List<ModuleModel> _modules;

  final Map<TypeModel, ModuleModel> _byType;

  final Set<ModuleModel> _done = {};

  final List<ModuleModel> _path = [];

  /// Every cycle found, each starting at its first module in package order.
  List<List<ModuleModel>> find() {
    final found = <List<ModuleModel>>[];
    for (final module in _modules) {
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
