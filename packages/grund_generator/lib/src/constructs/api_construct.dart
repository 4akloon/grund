import '../construct/construct.dart';
import '../construct/generated_unit.dart';
import '../diagnostic/diagnostic.dart';
import '../model/package_model.dart';
import 'api_check.dart';
import 'route_conflict_check.dart';

/// Validates the `@Api` classes of a package and their routes.
final class ApiConstruct implements Construct {
  /// Creates the construct.
  const ApiConstruct();

  @override
  Iterable<Diagnostic> validate(PackageModel package) => [
    ...ApiCheck.check(package),
    ...RouteConflictCheck.check(package),
  ];

  @override
  Iterable<GeneratedUnit> generate(PackageModel package) => const [];
}
