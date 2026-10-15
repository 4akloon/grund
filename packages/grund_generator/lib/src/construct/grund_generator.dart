import 'package:code_builder/code_builder.dart';

import '../constructs/module_construct.dart';
import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../emit/library_writer.dart';
import '../model/package_model.dart';
import 'construct.dart';
import 'generated_unit.dart';
import 'generation_result.dart';
import 'provider_claims.dart';

/// Runs a set of [Construct]s over a [PackageModel].
///
/// The constructs claim providers first, then every construct validates;
/// any diagnostic stops generation, so a package with an error never gets
/// a half-generated library.
final class GrundGenerator {
  /// Creates the generator; [constructs] run in order.
  const GrundGenerator(this.constructs);

  /// The core constructs: modules with their bindings. A driver that
  /// generates more adds the constructs of other packages with the
  /// unnamed constructor.
  const GrundGenerator.core() : constructs = const [ModuleConstruct()];

  /// The constructs.
  final List<Construct> constructs;

  /// Validates and generates [package].
  GenerationResult generate(PackageModel package) {
    final claims = ProviderClaims.collect(package, constructs);
    final diagnostics = {
      ...claims.conflicts,
      for (final construct in constructs)
        ...construct.validate(package, claims),
    }.toList()..sort();
    if (diagnostics.isNotEmpty) return GenerationResult.failed(diagnostics);
    final units = [
      for (final construct in constructs)
        ...construct.generate(package, claims),
    ];
    final dartUnits = units.whereType<DartUnit>().toList();
    final duplicates = _duplicateNames(dartUnits);
    if (duplicates.isNotEmpty) return GenerationResult.failed(duplicates);
    return GenerationResult.generated(
      library: LibraryWriter.write(
        packageName: package.packageName,
        languageVersion: package.languageVersion,
        declarations: <Spec>[for (final unit in dartUnits) unit.spec],
      ),
      files: units.whereType<FileUnit>().toList(),
    );
  }

  static List<Diagnostic> _duplicateNames(List<DartUnit> units) {
    final first = <String, DartUnit>{};
    return [
      for (final unit in units)
        if (first.putIfAbsent(unit.name, () => unit) case final other
            when other != unit)
          Diagnostic(
            DiagnosticCode.duplicateGeneratedName,
            unit.origin,
            'Generated name ${unit.name} is used twice: for the declaration '
            'at ${other.origin} and for this one. Rename one of them.',
          ),
    ]..sort();
  }
}
