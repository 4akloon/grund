import '../diagnostic/diagnostic.dart';
import '../model/package_model.dart';
import 'generated_unit.dart';

/// One generation step over the whole [PackageModel]: it checks what it
/// generates and produces it.
///
/// v1 has `ModuleConstruct`, `ProviderConstruct` and `ControllerConstruct`;
/// later packages add their own (OpenAPI, GraphQL), and the CLI compiles
/// the set in statically.
abstract interface class Construct {
  /// The problems that make [package] impossible to generate.
  Iterable<Diagnostic> validate(PackageModel package);

  /// The output for [package]; called only when no construct reported a
  /// diagnostic.
  Iterable<GeneratedUnit> generate(PackageModel package);
}
