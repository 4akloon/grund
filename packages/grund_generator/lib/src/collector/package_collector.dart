import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:pub_semver/pub_semver.dart';

import '../model/controller_model.dart';
import '../model/injectable_model.dart';
import '../model/module_model.dart';
import '../model/package_model.dart';
import 'annotations.dart';
import 'controller_reader.dart';
import 'dto_reader.dart';
import 'injectable_reader.dart';
import 'module_reader.dart';
import 'route_reader.dart';
import 'source_locations.dart';

/// Builds the [PackageModel] of one package from its resolved libraries.
///
/// The driver resolves every library of `lib/` (the CLI with an
/// `AnalysisContextCollection`, build_runner with its resolver) and passes
/// them here; the generated `*.grund.dart` is skipped.
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
        if (!'${library.uri}'.endsWith('.grund.dart')) library,
    ]..sort((a, b) => '${a.uri}'.compareTo('${b.uri}'));
    final modules = ModuleReader(packageName, _locations);
    final injectables = InjectableReader(_locations);
    final controllers = ControllerReader(_locations);
    final moduleModels = <ModuleModel>[];
    final injectableModels = <InjectableModel>[];
    final controllerModels = <ControllerModel>[];
    final dtoRoots = <DartType>[];
    for (final element in [for (final l in sorted) ...l.classes]) {
      if (Annotations.find(element, 'Module') case final annotation?) {
        moduleModels.add(modules.read(element, annotation));
      }
      if (Annotations.find(element, 'Injectable') != null) {
        injectableModels.add(injectables.read(element));
      }
      if (Annotations.find(element, 'Controller') case final annotation?) {
        controllerModels.add(controllers.read(element, annotation));
        dtoRoots.addAll(_dtoRoots(element));
      }
    }
    return PackageModel(
      packageName: packageName,
      languageVersion: _languageVersion(sorted),
      modules: moduleModels,
      injectables: injectableModels,
      controllers: controllerModels,
      dtos: DtoReader.read(dtoRoots),
    );
  }

  static List<DartType> _dtoRoots(ClassElement controller) => [
    for (final method in controller.methods)
      if (Annotations.all(method, RouteReader.annotations).isNotEmpty) ...[
        method.returnType,
        for (final parameter in method.formalParameters)
          if (Annotations.find(parameter, 'Body') != null) parameter.type,
      ],
  ];

  static Version _languageVersion(List<LibraryElement> libraries) {
    final version = libraries.firstOrNull?.languageVersion.package;
    return version == null
        ? Version(3, 8, 0)
        : Version(version.major, version.minor, 0);
  }
}
