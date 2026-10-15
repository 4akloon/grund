import '../construct/construct.dart';
import '../construct/generated_unit.dart';
import '../diagnostic/diagnostic.dart';
import '../model/package_model.dart';
import 'binding_check.dart';
import 'dependency_check.dart';
import 'module_structure_check.dart';
import 'unsupported_use_check.dart';

/// Validates the modules of a package and their bindings.
final class ModuleConstruct implements Construct {
  /// Creates the construct.
  const ModuleConstruct();

  @override
  Iterable<Diagnostic> validate(PackageModel package) {
    final own = [
      ...ModuleStructureCheck.check(package.modules),
      ...BindingCheck.check(package),
      ...UnsupportedUseCheck.check(package),
    ];
    return own.isEmpty ? DependencyCheck.check(package) : own;
  }

  @override
  Iterable<GeneratedUnit> generate(PackageModel package) => const [];
}
