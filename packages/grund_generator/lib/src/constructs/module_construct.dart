import '../construct/construct.dart';
import '../construct/generated_unit.dart';
import '../construct/provider_claims.dart';
import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../model/package_model.dart';
import 'binding_check.dart';
import 'dependency_check.dart';
import 'module_structure_check.dart';
import 'unsupported_use_check.dart';

/// Validates the modules of a package and their bindings.
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
  ) => const [];
}
