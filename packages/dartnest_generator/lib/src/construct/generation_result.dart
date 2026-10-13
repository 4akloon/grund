import '../diagnostic/diagnostic.dart';
import 'generated_unit.dart';

/// The outcome of one generation: either diagnostics, or the generated
/// library source and the other files.
final class GenerationResult {
  /// A failed generation.
  const GenerationResult.failed(this.diagnostics)
    : library = null,
      files = const [];

  /// A successful generation.
  const GenerationResult.generated({
    required String this.library,
    this.files = const [],
  }) : diagnostics = const [];

  /// The problems, sorted by location; empty on success.
  final List<Diagnostic> diagnostics;

  /// The source of `lib/<package>.dartnest.dart`, or `null` on failure.
  final String? library;

  /// The other files, in construct order.
  final List<FileUnit> files;

  /// Whether generation succeeded.
  bool get isSuccess => library != null;
}
