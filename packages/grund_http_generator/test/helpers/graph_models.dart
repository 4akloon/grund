import 'package:grund_generator/grund_generator.dart';
import 'package:grund_http_generator/grund_http_generator.dart';
import 'package:pub_semver/pub_semver.dart';

import 'fixture_package.dart';

/// Builders of small hand-made packages with modules and apis for the
/// check tests.
abstract final class GraphModels {
  /// A class type named [name].
  static TypeModel type(String name) => TypeModel(
    name: name,
    kind: TypeKind.interface,
    libraryUri: 'package:app/app.dart',
  );

  /// A class provider of [name].
  static ProviderModel provider(
    String name, {
    Lifetime lifetime = Lifetime.singleton,
  }) => ProviderModel(
    BindingKey(type(name)),
    InjectableModel(
      type: type(name),
      lifetime: lifetime,
      isAnnotated: true,
      location: SourceLocation('lib/app.dart', 1, name.length),
      constructor: const ConstructorModel([]),
    ),
  );

  /// A module named [name] with [providers].
  static ModuleModel module(
    String name, {
    List<ProviderModel> providers = const [],
  }) => ModuleModel(
    type: type(name),
    location: SourceLocation('lib/app.dart', 3, name.length),
    providers: providers,
  );

  /// A package of [modules] and [apis].
  static PackageModel package(
    List<ModuleModel> modules, {
    List<ApiModel> apis = const [],
    List<InjectableModel> injectables = const [],
  }) => PackageModel(
    packageName: 'app',
    languageVersion: Version(3, 8, 0),
    modules: modules,
    injectables: injectables,
    extensions: [HttpPackageModel(apis: apis)],
  );

  /// The diagnostic codes of the module and api constructs over
  /// [package], sorted by location.
  static List<String> codes(PackageModel package) => [
    for (final d in const GrundGenerator(
      FixturePackage.constructs,
    ).generate(package).diagnostics)
      d.code.id,
  ];

  /// An api class [name] at [path].
  static ApiModel api(String name, {List<HookModel> use = const []}) =>
      ApiModel(
        type: type(name),
        path: '/',
        location: const SourceLocation('lib/app.dart', 9, 1),
        use: use,
      );
}
