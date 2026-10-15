import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../model/package_model.dart';

/// Reports the modules declared in part files, for which nothing is
/// generated.
abstract final class ModuleInPartCheck {
  /// One diagnostic per module declared in a part of [package].
  static Iterable<Diagnostic> check(PackageModel package) => [
    for (final module in package.modulesInParts)
      Diagnostic(
        DiagnosticCode.moduleInPart,
        module.location,
        'Module ${module.element} is declared in a part file; declare '
        'modules in a library file, not in a part.',
      ),
  ];
}
