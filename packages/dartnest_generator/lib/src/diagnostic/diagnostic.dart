import 'diagnostic_code.dart';
import 'source_location.dart';

/// A problem found in the annotated sources; generation does not write
/// code while any diagnostic exists.
///
/// Printed as `path:line:column: error: message [code]`.
final class Diagnostic implements Comparable<Diagnostic> {
  /// Creates a diagnostic.
  const Diagnostic(this.code, this.location, this.message);

  /// What kind of problem this is.
  final DiagnosticCode code;

  /// Where the problem is.
  final SourceLocation location;

  /// One or more sentences describing the problem and its fix.
  final String message;

  /// Orders by location, then by code and message, so output is stable.
  @override
  int compareTo(Diagnostic other) {
    final byLocation = location.compareTo(other.location);
    if (byLocation != 0) return byLocation;
    final byCode = code.id.compareTo(other.code.id);
    return byCode != 0 ? byCode : message.compareTo(other.message);
  }

  @override
  bool operator ==(Object other) =>
      other is Diagnostic &&
      other.code == code &&
      other.location == location &&
      other.message == message;

  @override
  int get hashCode => Object.hash(code, location, message);

  @override
  String toString() => '$location: error: $message [${code.id}]';
}
