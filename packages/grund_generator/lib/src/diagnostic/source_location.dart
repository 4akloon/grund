/// A position in a source file, printed as `path:line:column`.
///
/// [path] is relative to the package root (`lib/users.dart`) for files of
/// the generated package, and the library URI for anything else.
final class SourceLocation implements Comparable<SourceLocation> {
  /// Creates a location; [line] and [column] start at 1.
  const SourceLocation(this.path, this.line, this.column);

  /// File path relative to the package root, or a library URI.
  final String path;

  /// One-based line.
  final int line;

  /// One-based column.
  final int column;

  @override
  int compareTo(SourceLocation other) {
    final byPath = path.compareTo(other.path);
    if (byPath != 0) return byPath;
    final byLine = line.compareTo(other.line);
    return byLine != 0 ? byLine : column.compareTo(other.column);
  }

  @override
  bool operator ==(Object other) =>
      other is SourceLocation &&
      other.path == path &&
      other.line == line &&
      other.column == column;

  @override
  int get hashCode => Object.hash(path, line, column);

  @override
  String toString() => '$path:$line:$column';
}
