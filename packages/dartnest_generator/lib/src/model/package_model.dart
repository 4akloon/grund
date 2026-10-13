import 'package:pub_semver/pub_semver.dart';

import 'controller_model.dart';
import 'dto_model.dart';
import 'injectable_model.dart';
import 'module_model.dart';

/// Everything the generator collected from one package: the input of every
/// `Construct`.
final class PackageModel {
  /// Creates the model.
  const PackageModel({
    required this.packageName,
    required this.languageVersion,
    this.modules = const [],
    this.injectables = const [],
    this.controllers = const [],
    this.dtos = const [],
  });

  /// The package name; the output is `lib/<packageName>.dartnest.dart`.
  final String packageName;

  /// The package's language version, used to format the output.
  final Version languageVersion;

  /// Classes annotated with `@Module`, in library-URI order, then source
  /// order within a library.
  final List<ModuleModel> modules;

  /// Classes provided through their constructor, each once, in library-URI
  /// order, then source order within a library.
  final List<InjectableModel> injectables;

  /// Classes annotated with `@Controller`, in library-URI order, then source
  /// order within a library.
  final List<ControllerModel> controllers;

  /// Request bodies and handler results, sorted by library URI, then name.
  final List<DtoModel> dtos;
}
