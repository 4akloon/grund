import 'package:dartnest_generator/src/diagnostic/source_location.dart';
import 'package:dartnest_generator/src/model/constructor_model.dart';
import 'package:dartnest_generator/src/model/dependency_model.dart';
import 'package:dartnest_generator/src/model/injectable_model.dart';
import 'package:dartnest_generator/src/model/module_export.dart';
import 'package:dartnest_generator/src/model/module_model.dart';
import 'package:dartnest_generator/src/model/module_reference.dart';
import 'package:dartnest_generator/src/model/package_model.dart';
import 'package:dartnest_generator/src/model/provider_key.dart';
import 'package:dartnest_generator/src/model/provider_model.dart';
import 'package:dartnest_generator/src/model/type_kind.dart';
import 'package:dartnest_generator/src/model/type_model.dart';
import 'package:pub_semver/pub_semver.dart';

/// Builders of small hand-made module graphs for the dependency tests.
abstract final class GraphModels {
  /// A class type named [name].
  static TypeModel type(String name) => TypeModel(
    name: name,
    kind: TypeKind.interface,
    libraryUri: 'package:app/app.dart',
  );

  /// The key of the class [name].
  static ProviderKey key(String name) => TypeKey(type(name));

  /// A class provider of [name] that needs the classes [needs].
  static ClassProvider provider(String name, [List<String> needs = const []]) =>
      ClassProvider(
        key(name),
        InjectableModel(
          type: type(name),
          isAnnotated: true,
          location: SourceLocation('lib/app.dart', 1, name.length),
          constructor: ConstructorModel([
            for (final need in needs)
              DependencyModel.injected(
                name: need.toLowerCase(),
                isNamed: false,
                location: SourceLocation('lib/app.dart', 2, need.length),
                key: key(need),
              ),
          ]),
        ),
      );

  /// A module named [name].
  static ModuleModel module(
    String name, {
    List<ModuleReference> imports = const [],
    List<ProviderModel> providers = const [],
    List<ModuleExport> exports = const [],
    bool isGlobal = false,
  }) => ModuleModel(
    type: type(name),
    id: name,
    location: SourceLocation('lib/app.dart', 3, name.length),
    imports: imports,
    providers: providers,
    exports: exports,
    isGlobal: isGlobal,
  );

  /// A reference to the module [name].
  static LocalModuleReference reference(String name) =>
      LocalModuleReference(type(name));

  /// A package of [modules].
  static PackageModel package(List<ModuleModel> modules) => PackageModel(
    packageName: 'app',
    languageVersion: Version(3, 8, 0),
    modules: modules,
  );
}
