import 'package:grund_generator/grund_generator.dart';

import '../collector/api_collector.dart';
import '../collector/route_reader.dart';
import '../emit/api_emitter.dart';
import '../model/api_names.dart';
import '../model/http_package_model.dart';
import 'api_check.dart';
import 'api_claim.dart';
import 'api_host_check.dart';
import 'route_conflict_check.dart';

/// Collects and validates the `@Api` classes of a package and their
/// routes, claims an `@Api` class listed in a module's `providers`, and
/// writes the routes of every `@Api` class into the part `X.api.g.dart` of
/// its library.
final class ApiConstruct extends Construct {
  /// Creates the construct.
  const ApiConstruct();

  @override
  String get name => 'api';

  @override
  ConstructAnnotations get annotations => const ConstructAnnotations(
    classes: {'Api': RouteReader.annotations},
    injectable: {'Api'},
  );

  @override
  HttpPackageModel collect(CollectionContext context) =>
      ApiCollector.collect(context);

  /// The bindings of an `@Api` provider: the class, made by its
  /// constructor and looking up the hooks its `use:` lists by type, and its
  /// `XRoutes`, which depends on the class.
  @override
  ProviderClaim? claimProvider(ProviderModel provider, PackageModel package) {
    final api = _model(
      package,
    ).apis.where((api) => api.type == provider.injectable.type).firstOrNull;
    return api == null ? null : ApiClaim.of(provider, api);
  }

  @override
  Iterable<Diagnostic> validate(PackageModel package, ProviderClaims claims) {
    final model = _model(package);
    return [
      ...ApiCheck.check(package, model),
      ...RouteConflictCheck.check(model),
      ...ApiHostCheck.check(model),
    ];
  }

  @override
  Iterable<GeneratedUnit> generate(
    PackageModel package,
    ProviderClaims claims,
  ) => [
    for (final api in _model(package).apis)
      PartUnit(
        path: ApiNames.partPath(api.libraryPath),
        hostPath: api.libraryPath,
        name: ApiNames.routes(api.type.name),
        spec: ApiEmitter.emit(api),
        origin: api.location,
      ),
  ];

  /// The model [collect] added to [package].
  ///
  /// Throws [StateError] when it is missing: [package] was collected
  /// without this construct, so every api would silently be skipped.
  static HttpPackageModel _model(PackageModel package) =>
      switch (package.extensionModel<HttpPackageModel>()) {
        final model? => model,
        null => throw StateError(
          'The package ${package.packageName} was collected without the api '
          'construct; collect it with GrundGenerator.collector of a generator '
          'that lists ApiConstruct.',
        ),
      };
}
