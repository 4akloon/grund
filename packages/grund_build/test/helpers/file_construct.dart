import 'package:grund_generator/grund_generator.dart';

/// A [Construct] that generates one file of its own, `openapi.json`, like
/// the OpenAPI construct of v1.1 will.
final class FileConstruct implements Construct {
  /// Creates the construct.
  const FileConstruct();

  @override
  Iterable<Diagnostic> validate(PackageModel package) => const [];

  @override
  Iterable<GeneratedUnit> generate(PackageModel package) => const [
    FileUnit(
      path: 'openapi.json',
      contentType: ContentType.json,
      content: '{}',
    ),
  ];
}
