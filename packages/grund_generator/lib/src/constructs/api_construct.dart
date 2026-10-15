import '../collector/api_collector.dart';
import '../collector/collection_context.dart';
import '../collector/route_reader.dart';
import '../construct/construct.dart';
import '../construct/construct_annotations.dart';
import '../construct/generated_unit.dart';
import '../construct/provider_claims.dart';
import '../diagnostic/diagnostic.dart';
import '../model/binding_key.dart';
import '../model/binding_lookup.dart';
import '../model/binding_model.dart';
import '../model/http_package_model.dart';
import '../model/package_model.dart';
import '../model/provider_model.dart';
import 'api_check.dart';
import 'route_conflict_check.dart';

/// Collects and validates the `@Api` classes of a package and their
/// routes, and claims an `@Api` class listed in a module's `providers`.
final class ApiConstruct extends Construct {
  /// Creates the construct.
  const ApiConstruct();

  @override
  ConstructAnnotations get annotations => const ConstructAnnotations(
    classes: {'Api': RouteReader.annotations},
    injectable: {'Api'},
  );

  @override
  HttpPackageModel collect(CollectionContext context) =>
      ApiCollector.collect(context);

  /// The binding of an `@Api` provider: made by its constructor, and
  /// looking up the hooks its `use:` lists by type.
  @override
  BindingModel? claimProvider(ProviderModel provider, PackageModel package) {
    final injectable = provider.injectable;
    final api = _model(
      package,
    ).apis.where((api) => api.type == injectable.type).firstOrNull;
    if (api == null) return null;
    return BindingModel(
      key: provider.key,
      lifetime: injectable.lifetime,
      dependencies: injectable.constructor.dependencies,
      location: injectable.location,
      lookups: [
        for (final hook in [
          ...api.use,
          for (final route in api.routes) ...route.use,
        ])
          if (!hook.isInstance)
            BindingLookup(BindingKey(hook.type), api.location),
      ],
    );
  }

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

  static HttpPackageModel _model(PackageModel package) =>
      package.extensionModel<HttpPackageModel>() ?? const HttpPackageModel();
}
