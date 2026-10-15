import 'package:pub_semver/pub_semver.dart';

import 'extension_model.dart';
import 'injectable_model.dart';
import 'module_model.dart';
import 'provides_model.dart';
import 'unsupported_use.dart';

/// Everything the generator collected from one package: the input of every
/// `Construct`.
final class PackageModel {
  /// Creates the model.
  const PackageModel({
    required this.packageName,
    required this.languageVersion,
    this.modules = const [],
    this.injectables = const [],
    this.strayProvides = const [],
    this.unsupportedUses = const [],
    this.extensions = const [],
  });

  /// The package name; the output is a `X.module.g.dart` per source library
  /// with modules and whatever other files the constructs write.
  final String packageName;

  /// The package's language version, used to format the output.
  final Version languageVersion;

  /// Classes annotated with `@Module`, in library-URI order, then source
  /// order within a library.
  final List<ModuleModel> modules;

  /// Classes annotated with `@Injectable` or with an annotation a construct
  /// marks injectable (`ConstructAnnotations.injectable`), each once, in
  /// library-URI order, then source order within a library.
  final List<InjectableModel> injectables;

  /// `@Provides` methods of classes that are not annotated with `@Module`.
  final List<ProvidesModel> strayProvides;

  /// Annotations the generator cannot honour, in library-URI order, then
  /// source order; the checks report each as `unsupported_use`.
  final List<UnsupportedUse> unsupportedUses;

  /// What the constructs collected for themselves (`Construct.collect`), in
  /// construct order.
  final List<ExtensionModel> extensions;

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
