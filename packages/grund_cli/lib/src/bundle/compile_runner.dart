import 'compile_outcome.dart';

/// Compiles a Dart entry point to JavaScript.
abstract interface class CompileRunner {
  /// Compiles [entry] to the file [output], running in [workingDirectory].
  ///
  /// [release] selects the production flags (`-O2
  /// -Djaspr.flags.release=true`); otherwise the development ones (`-O1`,
  /// with source maps).
  Future<CompileOutcome> compileJs({
    required String entry,
    required String output,
    required bool release,
    required String workingDirectory,
  });
}
