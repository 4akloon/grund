import 'package:code_builder/code_builder.dart';

import '../diagnostic/source_location.dart';
import 'generated_unit.dart';

/// A top-level declaration [name] of the generated library at [path].
///
/// The units of one path form one library with its own imports: every
/// `refer(name, url)` in [spec] is imported by that file's allocator.
final class LibraryUnit extends GeneratedUnit {
  /// Creates the unit.
  const LibraryUnit({
    required this.path,
    required this.name,
    required this.spec,
    required this.origin,
  });

  @override
  final String path;

  /// The declared name; two units of one file must not share it.
  final String name;

  /// The declaration.
  final Spec spec;

  /// The user declaration it is generated from.
  final SourceLocation origin;
}
