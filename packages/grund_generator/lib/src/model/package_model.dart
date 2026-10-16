import 'package:pub_semver/pub_semver.dart';

import 'extension_model.dart';
import 'injectable_model.dart';
import 'module_in_part.dart';
import 'module_model.dart';
import 'provides_model.dart';
import 'public_imports.dart';
import 'unresolved_uri.dart';
import 'unsupported_use.dart';

/// Everything the generator collected from one package: the input of every
/// `Construct`.
final class PackageModel {
  /// Creates the model.
  const PackageModel({
    required this.packageName,
    required this.languageVersion,
    this.modules = const [],
    this.modulesInParts = const [],
    this.injectables = const [],
    this.strayProvides = const [],
    this.unsupportedUses = const [],
    this.unresolvedUris = const [],
    this.extensions = const [],
    this.libraryPaths = const [],
    this.publicImports = const {},
  });

  /// The package name; the output is an `X.g.dart` per source library
  /// with modules and whatever other files the constructs write.
  final String packageName;

  /// The package's language version, used to format the output.
  final Version languageVersion;

  /// Classes annotated with `@Module`, in library-URI order, then source
  /// order within a library.
  final List<ModuleModel> modules;

  /// Classes annotated with `@Module` that are declared in part files; the
  /// checks report each as `module_in_part`, and nothing is generated for
  /// them.
  final List<ModuleInPart> modulesInParts;

  /// Classes annotated with `@Injectable` or with an annotation a construct
  /// marks injectable (`ConstructAnnotations.injectable`), each once, in
  /// library-URI order, then source order within a library.
  final List<InjectableModel> injectables;

  /// `@Provides` methods of classes that are not annotated with `@Module`.
  final List<ProvidesModel> strayProvides;

  /// Annotations the generator cannot honour, in library-URI order, then
  /// source order; the checks report each as `unsupported_use`.
  final List<UnsupportedUse> unsupportedUses;

  /// Directives of the source libraries whose URI does not resolve, in
  /// library-URI order; the checks report each as `unresolved_uri`.
  final List<UnresolvedUri> unresolvedUris;

  /// What the constructs collected for themselves (`Construct.collect`), in
  /// construct order.
  final List<ExtensionModel> extensions;

  /// The package-relative paths of the source libraries (generated outputs
  /// excluded), in library-URI order: where a generated `part` may attach.
  final List<String> libraryPaths;

  /// For each source library (by its path in [libraryPaths]), the public
  /// libraries to import for declarations of other packages' `src/`.
  final Map<String, PublicImports> publicImports;

  /// The extension model of type [T], or `null` when no construct collected
  /// one.
  T? extensionModel<T extends ExtensionModel>() =>
      extensions.whereType<T>().firstOrNull;

  /// Whether the package has no modules, no injectables and no extension
  /// with content: there is nothing to generate, and a driver removes a
  /// library it generated before.
  bool get isEmpty =>
      modules.isEmpty &&
      injectables.isEmpty &&
      extensions.every((extension) => extension.isEmpty);
}
