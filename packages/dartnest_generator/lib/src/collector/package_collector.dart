import 'package:analyzer/dart/element/element.dart';
import 'package:pub_semver/pub_semver.dart';

import '../model/injectable_model.dart';
import '../model/module_model.dart';
import '../model/package_model.dart';
import 'annotations.dart';
import 'injectable_reader.dart';
import 'module_reader.dart';
import 'source_locations.dart';

/// Builds the [PackageModel] of one package from its resolved libraries.
///
/// The driver resolves every library of `lib/` (the CLI with an
/// `AnalysisContextCollection`, build_runner with its resolver) and passes
/// them here; the generated `*.dartnest.dart` is skipped.
final class PackageCollector {
  /// Creates the collector of package [packageName] rooted at
  /// [packageRoot] (an absolute path; locations are relative to it).
  PackageCollector(this.packageName, String packageRoot)
    : _locations = SourceLocations(packageRoot);

  /// The package being generated.
  final String packageName;

  final SourceLocations _locations;

  /// The model of [libraries], in library URI order whatever the input
  /// order.
  PackageModel collect(Iterable<LibraryElement> libraries) {
    final sorted = [
      for (final library in libraries)
        if (!'${library.uri}'.endsWith('.dartnest.dart')) library,
    ]..sort((a, b) => '${a.uri}'.compareTo('${b.uri}'));
    final modules = ModuleReader(packageName, _locations);
    final injectables = InjectableReader(_locations);
    final moduleModels = <ModuleModel>[];
    final injectableModels = <InjectableModel>[];
    for (final library in sorted) {
      for (final element in library.classes) {
        if (Annotations.find(element, 'Module') case final annotation?) {
          moduleModels.add(modules.read(element, annotation));
        }
        if (Annotations.find(element, 'Injectable') != null) {
          injectableModels.add(injectables.read(element));
        }
      }
    }
    return PackageModel(
      packageName: packageName,
      languageVersion: _languageVersion(sorted),
      modules: moduleModels,
      injectables: injectableModels,
    );
  }

  static Version _languageVersion(List<LibraryElement> libraries) {
    final version = libraries.firstOrNull?.languageVersion.package;
    return version == null
        ? Version(3, 8, 0)
        : Version(version.major, version.minor, 0);
  }
}
