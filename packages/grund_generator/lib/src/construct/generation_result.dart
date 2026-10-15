import 'dart:collection';

import '../diagnostic/diagnostic.dart';

/// The outcome of one generation: either diagnostics, or the generated
/// files.
final class GenerationResult {
  /// A failed generation; [diagnostics] is not empty.
  GenerationResult.failed(this.diagnostics)
    : assert(diagnostics.isNotEmpty),
      files = const {};

  /// A successful generation of [files] (path → content).
  GenerationResult.generated(Map<String, String> files)
    : files = UnmodifiableMapView(SplayTreeMap.of(files)),
      diagnostics = const [];

  /// The problems, sorted by location; empty on success.
  final List<Diagnostic> diagnostics;

  /// The content of every generated file by its path relative to the
  /// package root, iterated in path order; empty on failure.
  final Map<String, String> files;

  /// Whether generation succeeded.
  bool get isSuccess => diagnostics.isEmpty;
}
