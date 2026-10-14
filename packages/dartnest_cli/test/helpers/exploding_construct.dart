import 'package:dartnest_generator/dartnest_generator.dart';

/// A [Construct] that fails with a plain exception, to see how commands
/// end when a generation run fails.
final class ExplodingConstruct implements Construct {
  /// Creates the construct.
  const ExplodingConstruct();

  @override
  Iterable<Diagnostic> validate(PackageModel package) =>
      throw const FormatException('boom');

  @override
  Iterable<GeneratedUnit> generate(PackageModel package) => const [];
}
