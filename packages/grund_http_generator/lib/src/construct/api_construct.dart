import 'package:grund_generator/grund_generator.dart';

import '../collector/api_collector.dart';
import '../collector/route_reader.dart';
import '../model/api_model.dart';
import '../model/api_names.dart';
import '../model/http_package_model.dart';
import 'api_check.dart';
import 'route_conflict_check.dart';

/// Collects and validates the `@Api` classes of a package and their
/// routes, and claims an `@Api` class listed in a module's `providers`.
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
    final injectable = provider.injectable;
    final api = _model(
      package,
    ).apis.where((api) => api.type == injectable.type).firstOrNull;
    if (api == null) return null;
    return ProviderClaim([
      BindingModel(
        key: provider.key,
        lifetime: injectable.lifetime,
        dependencies: injectable.constructor.dependencies,
        location: injectable.location,
        lookups: _hookLookups(api),
      ),
      _routesBinding(api, provider),
    ]);
  }

  static List<BindingLookup> _hookLookups(ApiModel api) => [
    for (final hook in [
      ...api.use,
      for (final route in api.routes) ...route.use,
    ])
      if (!hook.isInstance) BindingLookup(BindingKey(hook.type), api.location),
  ];

  // The routes share the api's lifetime, so a non-singleton api is reported
  // once, as invalid_api, and not also as a captive dependency.
  static BindingModel _routesBinding(ApiModel api, ProviderModel provider) =>
      BindingModel(
        key: BindingKey(
          TypeModel(
            name: ApiNames.routes(api.type.name),
            kind: TypeKind.interface,
            libraryUri: api.type.libraryUri,
          ),
        ),
        lifetime: provider.injectable.lifetime,
        dependencies: [
          DependencyModel.injected(
            name: 'api',
            isNamed: false,
            location: api.location,
            key: provider.key,
          ),
        ],
        location: api.location,
      );

  @override
  Iterable<Diagnostic> validate(PackageModel package, ProviderClaims claims) {
    final model = _model(package);
    return [
      ...ApiCheck.check(package, model),
      ...RouteConflictCheck.check(model),
    ];
  }

  @override
  Iterable<GeneratedUnit> generate(
    PackageModel package,
    ProviderClaims claims,
  ) => const [];

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
