import 'package:code_builder/code_builder.dart';

import '../diagnostic/source_location.dart';
import 'generated_unit.dart';

/// A top-level declaration [name] of the part file [path] of the library
/// [hostPath].
///
/// A part has no imports: [spec] uses the names in scope of the host, and
/// a `refer(name, url)` is written as the bare name.
final class PartUnit extends GeneratedUnit {
  /// Creates the unit.
  const PartUnit({
    required this.path,
    required this.hostPath,
    required this.name,
    required this.spec,
    required this.origin,
  });

  @override
  final String path;

  /// The library the part belongs to, relative to the package root.
  final String hostPath;

  /// The declared name; two units of one file must not share it.
  final String name;

  /// The declaration.
  final Spec spec;

  /// The user declaration it is generated from.
  final SourceLocation origin;
}
