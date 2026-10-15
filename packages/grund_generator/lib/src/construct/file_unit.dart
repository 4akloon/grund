import 'content_type.dart';
import 'generated_unit.dart';

/// A file the driver writes as is, at [path] relative to the package root.
final class FileUnit extends GeneratedUnit {
  /// Creates the unit.
  const FileUnit({
    required this.path,
    required this.contentType,
    required this.content,
  });

  @override
  final String path;

  /// The kind of [content].
  final ContentType contentType;

  /// The file content.
  final String content;
}
