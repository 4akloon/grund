import 'package:pub_semver/pub_semver.dart';

import 'api_model.dart';
import 'dto_model.dart';
import 'injectable_model.dart';
import 'module_model.dart';
import 'provides_model.dart';
import 'route_model.dart';

/// Everything the generator collected from one package: the input of every
/// `Construct`.
final class PackageModel {
  /// Creates the model.
  const PackageModel({
    required this.packageName,
    required this.languageVersion,
    this.modules = const [],
    this.injectables = const [],
    this.apis = const [],
    this.strayProvides = const [],
    this.strayRoutes = const [],
    this.dtos = const [],
  });

  /// The package name; the output is `lib/<packageName>.grund.dart`.
  final String packageName;

  /// The package's language version, used to format the output.
  final Version languageVersion;

  /// Classes annotated with `@Module`, in library-URI order, then source
  /// order within a library.
  final List<ModuleModel> modules;

  /// Classes annotated with `@Injectable` or `@Api`, each once, in
  /// library-URI order, then source order within a library.
  final List<InjectableModel> injectables;

  /// Classes annotated with `@Api`, in the same order.
  final List<ApiModel> apis;

  /// `@Provides` methods of classes that are not annotated with `@Module`.
  final List<ProvidesModel> strayProvides;

  /// Route methods of classes that are not annotated with `@Api`.
  final List<RouteModel> strayRoutes;

  /// Request bodies and handler results, sorted by library URI, then name.
  final List<DtoModel> dtos;

  /// Whether the package has no modules, injectables or APIs: there is
  /// nothing to generate, and a driver removes a library it generated
  /// before.
  bool get isEmpty => modules.isEmpty && injectables.isEmpty && apis.isEmpty;
}
