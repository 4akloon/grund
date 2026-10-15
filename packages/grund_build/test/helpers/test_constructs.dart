import 'package:grund_generator/grund_generator.dart';

/// A [Construct] that generates one file of its own, `openapi.json`, like
/// the OpenAPI construct of a later version could.
final class FileConstruct extends Construct {
  /// Creates the construct.
  const FileConstruct();

  @override
  String get name => 'file';

  @override
  Iterable<Diagnostic> validate(PackageModel package, ProviderClaims claims) =>
      const [];

  @override
  Iterable<GeneratedUnit> generate(
    PackageModel package,
    ProviderClaims claims,
  ) => const [
    FileUnit(
      path: 'openapi.json',
      contentType: ContentType.json,
      content: '{}',
    ),
  ];
}

/// A [Construct] that reports a problem in [path] once the package has two
/// modules: a problem that only a library reaching both modules produces.
final class TwoModulesConstruct extends Construct {
  /// Creates the construct reporting at [path].
  const TwoModulesConstruct(this.path);

  /// The file the problem is located in.
  final String path;

  @override
  String get name => 'two_modules';

  @override
  Iterable<Diagnostic> validate(PackageModel package, ProviderClaims claims) =>
      package.modules.length < 2
      ? const []
      : [
          Diagnostic(
            const DiagnosticCode('two_modules'),
            SourceLocation(path, 1, 1),
            'two modules',
          ),
        ];

  @override
  Iterable<GeneratedUnit> generate(
    PackageModel package,
    ProviderClaims claims,
  ) => const [];
}
