import 'package:grund_generator/grund_generator.dart';

/// A [Construct] that fails with a plain exception, to see how commands
/// end when a generation run fails.
final class ExplodingConstruct extends Construct {
  /// Creates the construct.
  const ExplodingConstruct();

  @override
  String get name => 'exploding';

  @override
  Iterable<Diagnostic> validate(PackageModel package, ProviderClaims claims) =>
      throw const FormatException('boom');

  @override
  Iterable<GeneratedUnit> generate(
    PackageModel package,
    ProviderClaims claims,
  ) => const [];
}
