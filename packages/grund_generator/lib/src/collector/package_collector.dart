import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:pub_semver/pub_semver.dart';

import '../model/api_model.dart';
import '../model/injectable_model.dart';
import '../model/module_model.dart';
import '../model/package_model.dart';
import '../model/provides_model.dart';
import '../model/route_model.dart';
import '../model/unsupported_use.dart';
import 'annotations.dart';
import 'api_reader.dart';
import 'dto_reader.dart';
import 'injectable_reader.dart';
import 'module_reader.dart';
import 'provides_reader.dart';
import 'route_reader.dart';
import 'source_locations.dart';
import 'unsupported_use_reader.dart';

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
    final routes = RouteReader(_locations);
    final readers = _Readers(
      ModuleReader(packageName, _locations),
      InjectableReader(_locations),
      ApiReader(_locations, routes),
      ProvidesReader(_locations),
      routes,
    );
    final parts = _Parts();
    for (final library in sorted) {
      parts.unsupported.addAll(UnsupportedUseReader(_locations).read(library));
      for (final element in library.classes) {
        _collectClass(element, readers, parts);
      }
    }
    return PackageModel(
      packageName: packageName,
      languageVersion: _languageVersion(sorted),
      modules: parts.modules,
      injectables: parts.injectables,
      apis: parts.apis,
      strayProvides: parts.strayProvides,
      strayRoutes: parts.strayRoutes,
      dtos: DtoReader.read(parts.dtoRoots),
      unsupportedUses: parts.unsupported,
    );
  }

  static void _collectClass(
    ClassElement element,
    _Readers readers,
    _Parts parts,
  ) {
    final module = Annotations.find(element, 'Module');
    final api = Annotations.find(element, 'Api');
    if (module != null) {
      parts.modules.add(readers.modules.read(element, module));
    } else {
      parts.strayProvides.addAll(readers.provides.read(element));
    }
    if (api != null) {
      parts.apis.add(readers.apis.read(element, api));
      parts.dtoRoots.addAll(_dtoRoots(element));
    } else {
      parts.strayRoutes.addAll(readers.routes.read(element));
    }
    if (Annotations.all(element, const {'Injectable', 'Api'}).isNotEmpty) {
      parts.injectables.add(readers.injectables.read(element));
    }
  }

  static List<DartType> _dtoRoots(ClassElement api) => [
    for (final method in api.methods)
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

/// The readers [PackageCollector] applies to every class.
final class _Readers {
  _Readers(
    this.modules,
    this.injectables,
    this.apis,
    this.provides,
    this.routes,
  );

  final ModuleReader modules;
  final InjectableReader injectables;
  final ApiReader apis;
  final ProvidesReader provides;
  final RouteReader routes;
}

/// What [PackageCollector] accumulates while it walks the classes.
final class _Parts {
  final modules = <ModuleModel>[];
  final injectables = <InjectableModel>[];
  final apis = <ApiModel>[];
  final strayProvides = <ProvidesModel>[];
  final strayRoutes = <RouteModel>[];
  final dtoRoots = <DartType>[];
  final unsupported = <UnsupportedUse>[];
}
