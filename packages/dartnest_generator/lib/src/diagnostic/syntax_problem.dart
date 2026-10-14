import 'source_location.dart';

/// A syntax error in a source file of `lib/`; a driver does not run the
/// generator while one exists.
///
/// Printed like a `Diagnostic`:
/// `path:line:column: error: message [syntax_error]`. The CLI and the
/// build_runner builder both report syntax errors with it, so they print
/// them the same way.
final class SyntaxProblem implements Comparable<SyntaxProblem> {
  /// Creates the problem.
  const SyntaxProblem(this.location, this.message);

  /// The code printed after the message.
  static const code = 'syntax_error';

  /// Where the error is; the path is relative to the package root.
  final SourceLocation location;

  /// The parser's message.
  final String message;

  /// Orders by location, then by message, so output is stable.
  @override
  int compareTo(SyntaxProblem other) {
    final byLocation = location.compareTo(other.location);
    return byLocation != 0 ? byLocation : message.compareTo(other.message);
  }

  @override
  String toString() => '$location: error: $message [$code]';
}
