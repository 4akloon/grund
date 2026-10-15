import 'package:grund_generator/src/construct/grund_generator.dart';
import 'package:grund_generator/src/diagnostic/source_location.dart';
import 'package:grund_generator/src/model/api_model.dart';
import 'package:grund_generator/src/model/hook_model.dart';
import 'package:grund_generator/src/model/binding_key.dart';
import 'package:grund_generator/src/model/constant_value.dart';
import 'package:grund_generator/src/model/constructor_model.dart';
import 'package:grund_generator/src/model/dependency_model.dart';
import 'package:grund_generator/src/model/injectable_model.dart';
import 'package:grund_generator/src/model/lifetime.dart';
import 'package:grund_generator/src/model/module_export.dart';
import 'package:grund_generator/src/model/module_model.dart';
import 'package:grund_generator/src/model/module_reference.dart';
import 'package:grund_generator/src/model/package_model.dart';
import 'package:grund_generator/src/model/provider_model.dart';
import 'package:grund_generator/src/model/provides_model.dart';
import 'package:grund_generator/src/model/type_kind.dart';
import 'package:grund_generator/src/model/type_model.dart';
import 'package:pub_semver/pub_semver.dart';

/// Builders of small hand-made module graphs for the check tests.
abstract final class GraphModels {
  /// A class type named [name].
  static TypeModel type(String name) => TypeModel(
    name: name,
    kind: TypeKind.interface,
    libraryUri: 'package:app/app.dart',
  );

  /// The key of the class [name], qualified by [qualifier].
  static BindingKey key(String name, [String? qualifier]) =>
      BindingKey(type(name), qualifier);

  /// A dependency on [need] (`Name` or `Name('qualifier')` is not parsed;
  /// pass the key).
  static DependencyModel need(BindingKey need) => DependencyModel.injected(
    name: need.type.name.toLowerCase(),
    isNamed: false,
    location: SourceLocation('lib/app.dart', 2, need.type.name.length),
    key: need,
  );

  /// A class provider of [name] that needs the classes [needs].
  static ProviderModel provider(
    String name, {
    List<String> needs = const [],
    Lifetime lifetime = Lifetime.singleton,
  }) => ProviderModel(
    key(name),
    InjectableModel(
      type: type(name),
      lifetime: lifetime,
      isAnnotated: true,
      location: SourceLocation('lib/app.dart', 1, name.length),
      constructor: ConstructorModel([for (final n in needs) need(key(n))]),
    ),
  );

  /// A `@Provides` method of [owner] that provides [name].
  static ProvidesModel provides(
    String owner,
    String name, {
    List<String> needs = const [],
    Lifetime lifetime = Lifetime.singleton,
    String? problem,
  }) => ProvidesModel(
    owner: type(owner),
    methodName: name.toLowerCase(),
    location: SourceLocation('lib/app.dart', 6, name.length),
    key: problem == null ? key(name) : null,
    lifetime: lifetime,
    dependencies: [for (final n in needs) need(key(n))],
    problem: problem,
  );

  /// A module named [name].
  static ModuleModel module(
    String name, {
    List<ModuleReference> imports = const [],
    List<ProviderModel> providers = const [],
    List<ProvidesModel> provides = const [],
    List<ModuleExport> exports = const [],
    bool isGlobal = false,
    bool extendsModule = true,
    List<String> invalidEntries = const [],
  }) => ModuleModel(
    type: type(name),
    location: SourceLocation('lib/app.dart', 3, name.length),
    imports: imports,
    providers: providers,
    provides: provides,
    exports: exports,
    isGlobal: isGlobal,
    extendsModule: extendsModule,
    invalidEntries: invalidEntries,
  );

  /// A reference to the module [name] from this package.
  static LocalModuleReference reference(String name) =>
      LocalModuleReference(type(name), _instance(name));

  /// A reference to the module [name] from elsewhere.
  static OpaqueModuleReference opaque(String name) =>
      OpaqueModuleReference(type(name), _instance(name));

  /// An export of the class [name].
  static KeyExport export(String name, [String? qualifier]) =>
      KeyExport(key(name, qualifier));

  /// A package of [modules] and [apis].
  static PackageModel package(
    List<ModuleModel> modules, {
    List<ApiModel> apis = const [],
    List<InjectableModel> injectables = const [],
  }) => PackageModel(
    packageName: 'app',
    languageVersion: Version(3, 8, 0),
    modules: modules,
    apis: apis,
    injectables: injectables,
  );

  /// The diagnostic codes of the core constructs over [package], sorted by
  /// location.
  static List<String> codes(PackageModel package) => [
    for (final d in const GrundGenerator.core().generate(package).diagnostics)
      d.code.id,
  ];

  /// A reference to the module [name] whose constant cannot be written.
  static LocalModuleReference unwritable(String name) => LocalModuleReference(
    type(name),
    const UnsupportedConstant('it calls a private constructor'),
  );

  /// An api class [name] at [path].
  static ApiModel api(String name, {List<HookModel> use = const []}) =>
      ApiModel(
        type: type(name),
        path: '/',
        location: const SourceLocation('lib/app.dart', 9, 1),
        use: use,
      );

  static ObjectConstant _instance(String name) =>
      ObjectConstant(type: type(name), constructorName: '');
}
