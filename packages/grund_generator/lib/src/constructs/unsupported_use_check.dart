import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../model/package_model.dart';

/// Reports the annotations and members the collector saw but the generator
/// does not read, so that none of them silently does nothing.
abstract final class UnsupportedUseCheck {
  /// One diagnostic per unsupported use of [package].
  static Iterable<Diagnostic> check(PackageModel package) => [
    for (final use in package.unsupportedUses)
      Diagnostic(DiagnosticCode.unsupportedUse, use.location, use.reason),
  ];
}
