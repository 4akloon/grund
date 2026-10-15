/// Root of every error that grund throws on its own.
///
/// Packages add their own families by extending it; the class name is the
/// stable identifier of a failure.
abstract base class GrundError implements Exception {
  /// Creates the error.
  const GrundError();

  /// Human-readable description, with a hint where one exists.
  String get message;

  @override
  String toString() => '$runtimeType: $message';
}
