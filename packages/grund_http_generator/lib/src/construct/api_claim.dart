import 'package:code_builder/code_builder.dart';
import 'package:grund_generator/grund_generator.dart';

import '../model/api_model.dart';
import '../model/api_names.dart';

/// The bindings a module gets for a provider that is an `@Api` class: the
/// class itself and its `XRoutes`.
abstract final class ApiClaim {
  /// The claim of [provider], the provider of [api].
  static ProviderClaim of(ProviderModel provider, ApiModel api) {
    final injectable = provider.injectable;
    return ProviderClaim([
      BindingModel(
        key: provider.key,
        lifetime: injectable.lifetime,
        dependencies: injectable.constructor.dependencies,
        location: injectable.location,
        lookups: _hookLookups(api),
        emission: BindingEmitter.provider(provider),
      ),
      _routes(provider, api),
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
  // once, as invalid_api, and not also as a captive dependency. The routes
  // class lives in a part of the api's library, so the module file reaches
  // it through the import of that library.
  static BindingModel _routes(ProviderModel provider, ApiModel api) {
    final routes = TypeModel(
      name: ApiNames.routes(api.type.name),
      kind: TypeKind.interface,
      libraryUri: api.type.libraryUri,
    );
    final key = BindingKey(routes);
    final dependencies = [
      DependencyModel.injected(
        name: 'api',
        isNamed: false,
        location: api.location,
        key: provider.key,
      ),
    ];
    final lifetime = provider.injectable.lifetime;
    return BindingModel(
      key: key,
      lifetime: lifetime,
      dependencies: dependencies,
      location: api.location,
      emission: BindingEmitter.binding(
        key: key,
        lifetime: lifetime,
        dependencies: dependencies,
        create: TypeEmitter.reference(routes)
            .newInstance([refer('i'), BindingEmitter.inject(provider.key)]),
      ),
    );
  }
}
