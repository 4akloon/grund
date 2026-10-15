import '../collector/package_collector.dart';
import '../constructs/module_construct.dart';
import '../model/package_model.dart';
import 'construct.dart';
import 'generation_result.dart';
import 'output_assembler.dart';
import 'provider_claims.dart';

/// Runs a set of [Construct]s over a [PackageModel].
///
/// The constructs claim providers first (two claims of one provider are a
/// `conflicting_provider_claim`), then every construct validates; any
/// diagnostic stops generation, so a package with an error never gets a
/// half-generated file. Declarations of one file that share a name are a
/// `duplicate_generated_name`.
final class GrundGenerator {
  /// Creates the generator; [constructs] run in order.
  const GrundGenerator(this.constructs);

  /// The core constructs: modules with their bindings. A driver that
  /// generates more adds the constructs of other packages with the
  /// unnamed constructor.
  const GrundGenerator.core() : constructs = const [ModuleConstruct()];

  /// The constructs.
  final List<Construct> constructs;

  /// The collector of package [packageName] rooted at [packageRoot] that
  /// lets these [constructs] collect, so the model [generate] gets has what
  /// each of them needs.
  PackageCollector collector(String packageName, String packageRoot) =>
      PackageCollector(packageName, packageRoot, constructs: constructs);

  /// Validates and generates [package].
  GenerationResult generate(PackageModel package) {
    final claims = ProviderClaims.collect(package, constructs);
    final diagnostics = {
      ...claims.conflicts,
      for (final construct in constructs)
        ...construct.validate(package, claims),
    }.toList()..sort();
    if (diagnostics.isNotEmpty) return GenerationResult.failed(diagnostics);
    final output = OutputAssembler(package).assemble([
      for (final construct in constructs)
        ...construct.generate(package, claims),
    ]);
    return output.duplicates.isEmpty
        ? GenerationResult.generated(output.files)
        : GenerationResult.failed(output.duplicates);
  }
}
