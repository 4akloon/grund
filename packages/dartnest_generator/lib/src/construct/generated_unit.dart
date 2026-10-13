import 'package:code_builder/code_builder.dart';

import '../diagnostic/source_location.dart';
import 'content_type.dart';

/// A piece of generator output: a Dart declaration of the package's
/// generated library, or a file of its own.
sealed class GeneratedUnit {
  /// Creates the unit.
  const GeneratedUnit();
}

/// A top-level declaration [name] of `lib/<package>.dartnest.dart`,
/// generated for the declaration at [origin].
final class DartUnit extends GeneratedUnit {
  /// Creates the unit.
  const DartUnit({
    required this.name,
    required this.spec,
    required this.origin,
  });

  /// The declared name; two units must not share it.
  final String name;

  /// The declaration.
  final Spec spec;

  /// The user declaration it is generated from.
  final SourceLocation origin;
}

/// A file the driver writes as is, at [path] relative to the package root.
final class FileUnit extends GeneratedUnit {
  /// Creates the unit.
  const FileUnit({
    required this.path,
    required this.contentType,
    required this.content,
  });

  /// The path relative to the package root, with `/` separators.
  final String path;

  /// The kind of [content].
  final ContentType contentType;

  /// The file content.
  final String content;
}
