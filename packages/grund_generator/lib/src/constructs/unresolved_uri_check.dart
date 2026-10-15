import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../model/package_model.dart';

/// Reports the directives whose URI does not resolve: without the library
/// they name, annotations may be unreadable, and the generated outputs of
/// the library would be dropped without a word.
abstract final class UnresolvedUriCheck {
  /// One diagnostic per unresolved directive of [package].
  static Iterable<Diagnostic> check(PackageModel package) => [
    for (final uri in package.unresolvedUris)
      Diagnostic(
        DiagnosticCode.unresolvedUri,
        uri.location,
        "The ${uri.directive} of '${uri.uri}' does not resolve; fix the URI "
        "or the package's dependencies, otherwise the outputs generated "
        'for this library would be dropped.',
      ),
  ];
}
