import '../construct/construct.dart';
import '../construct/generated_unit.dart';
import '../diagnostic/diagnostic.dart';
import '../emit/module_emitter.dart';
import '../model/generated_names.dart';
import '../model/package_model.dart';
import 'dependency_check.dart';
import 'module_structure_check.dart';

/// Checks the module graph the way `Application.create` would and
/// generates one function per `@Module` class.
final class ModuleConstruct implements Construct {
  /// Creates the construct.
  const ModuleConstruct();

  /// Dependencies are resolved only in a structurally valid graph, so one
  /// mistake is not reported again as missing providers.
  @override
  Iterable<Diagnostic> validate(PackageModel package) {
    final structure = ModuleStructureCheck.check(package.modules).toList();
    return structure.isEmpty ? DependencyCheck.check(package) : structure;
  }

  @override
  Iterable<GeneratedUnit> generate(PackageModel package) => [
    for (final module in package.modules)
      DartUnit(
        name: GeneratedNames.module(module.type.name),
        spec: ModuleEmitter.function(module),
        origin: module.location,
      ),
  ];
}
