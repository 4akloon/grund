import 'package:grund_generator/grund_generator.dart';

/// A library that declares `@Api` classes, and what it must contain for the
/// generated part to compile: the `part` directive and the prefixed import
/// of `package:grund_http`.
final class ApiHost {
  /// Creates the model.
  const ApiHost({
    required this.path,
    required this.location,
    required this.hasPartDirective,
    required this.hasHttpImport,
    required this.declaresModule,
  });

  /// The package-relative path of the library.
  final String path;

  /// The first `@Api` class of the library: where its diagnostics point.
  final SourceLocation location;

  /// Whether the library has `part 'X.g.dart';` for its own part.
  final bool hasPartDirective;

  /// Whether the library also declares a `@Module` class: its one output
  /// file then conflicts with the part, so a missing part is not reported.
  final bool declaresModule;

  /// Whether the library imports `package:grund_http` with the prefix the
  /// generated code uses.
  final bool hasHttpImport;
}
