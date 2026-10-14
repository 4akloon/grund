import 'package:dartnest_generator/dartnest_generator.dart';

/// A syntax error in a source file of `lib/`; nothing is generated while
/// one exists.
///
/// Printed like a generator `Diagnostic`:
/// `path:line:column: error: message [syntax_error]`.
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
