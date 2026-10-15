import '../construct/construct.dart';
import '../construct/generated_unit.dart';
import '../construct/provider_claims.dart';
import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../emit/module_emitter.dart';
import '../construct/library_unit.dart';
import '../model/generated_names.dart';
import '../model/package_model.dart';
import 'binding_check.dart';
import 'dependency_check.dart';
import 'module_structure_check.dart';
import 'private_declaration_check.dart';
import 'unsupported_use_check.dart';

/// Validates the modules of a package and their bindings, and writes the
/// mixin of each module into the `X.module.g.dart` next to its library.
final class ModuleConstruct extends Construct {
  /// Creates the construct.
  const ModuleConstruct();

  @override
  String get name => 'module';

  @override
  Iterable<Diagnostic> validate(PackageModel package, ProviderClaims claims) {
    final structure = ModuleStructureCheck.check(
      package.modules,
      claims,
    ).toList();
    final own = [
      ...structure,
      ...BindingCheck.check(package),
      ...PrivateDeclarationCheck.check(package),
      ...UnsupportedUseCheck.check(package),
    ];
    return structure.any(_breaksGraphWalk)
        ? own
        : [...own, ...DependencyCheck.check(package, claims)];
  }

  // The visibility walk follows imports and re-exports, so it needs an
  // acyclic import graph and exports that name real imports.
  static bool _breaksGraphWalk(Diagnostic diagnostic) =>
      diagnostic.code == DiagnosticCode.circularModuleImport ||
      diagnostic.code == DiagnosticCode.invalidExport;

  @override
  Iterable<GeneratedUnit> generate(
    PackageModel package,
    ProviderClaims claims,
  ) => [
    for (final module in package.modules)
      LibraryUnit(
        path: GeneratedNames.moduleLibraryPath(module.location.path),
        name: GeneratedNames.module(module.type.name),
        spec: ModuleEmitter.emit(module, claims),
        origin: module.location,
      ),
  ];
}
