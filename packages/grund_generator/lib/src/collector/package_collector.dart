import 'package:analyzer/dart/element/element.dart';
import 'package:pub_semver/pub_semver.dart';

import '../construct/construct.dart';
import '../construct/construct_annotations.dart';
import '../model/extension_model.dart';
import '../model/injectable_model.dart';
import '../model/module_model.dart';
import '../model/package_model.dart';
import '../model/provides_model.dart';
import '../model/unsupported_use.dart';
import 'annotations.dart';
import 'collection_context.dart';
import 'injectable_reader.dart';
import 'module_reader.dart';
import 'provides_reader.dart';
import 'source_locations.dart';
import 'unsupported_use_reader.dart';

/// Builds the [PackageModel] of one package from its resolved libraries.
///
/// The driver resolves every library of `lib/` (the CLI with an
/// `AnalysisContextCollection`, build_runner with its resolver) and passes
/// them here; the generator's own outputs (`*.module.g.dart`,
/// `*.api.g.dart`) are skipped, so a re-run never reads its previous output. The collector reads
/// modules, injectables and `@Provides` itself, and lets each of
/// [constructs] read its own annotations ([Construct.collect]).
final class PackageCollector {
  /// Creates the collector of package [packageName] rooted at
  /// [packageRoot] (an absolute path; locations are relative to it).
  PackageCollector(
    this.packageName,
    String packageRoot, {
    this.constructs = const [],
  }) : _locations = SourceLocations(packageRoot);

  /// The annotations the collector reads itself.
  static const coreAnnotations = ConstructAnnotations(
    classes: {
      'Injectable': {},
      'Module': {'Provides'},
    },
    injectable: {'Injectable'},
  );

  /// The package being generated.
  final String packageName;

  /// The constructs whose annotations are collected too.
  final List<Construct> constructs;

  final SourceLocations _locations;

  static const _outputSuffixes = ['.module.g.dart', '.api.g.dart'];

  static bool _isGeneratorOutput(String uri) =>
      _outputSuffixes.any(uri.endsWith);

  /// The model of [libraries], in library URI order whatever the input
  /// order.
  PackageModel collect(Iterable<LibraryElement> libraries) {
    final sorted = [
      for (final library in libraries)
        if (!_isGeneratorOutput('${library.uri}')) library,
    ]..sort((a, b) => '${a.uri}'.compareTo('${b.uri}'));
    final annotations = constructs.fold(
      coreAnnotations,
      (all, construct) => all.union(construct.annotations),
    );
    final parts = _Parts();
    final read = _Readers(packageName, _locations, annotations);
    for (final library in sorted) {
      parts.unsupported.addAll(read.unsupported.read(library));
      for (final element in library.classes) {
        _collectClass(element, read, parts);
      }
    }
    return PackageModel(
      packageName: packageName,
      languageVersion: _languageVersion(sorted),
      modules: parts.modules,
      injectables: parts.injectables,
      strayProvides: parts.strayProvides,
      unsupportedUses: parts.unsupported,
      extensions: _extensions(sorted),
      libraryPaths: [for (final library in sorted) _locations.pathOf(library)],
    );
  }

  List<ExtensionModel> _extensions(List<LibraryElement> libraries) {
    final context = CollectionContext(
      packageName: packageName,
      libraries: libraries,
      locations: _locations,
    );
    return [
      for (final construct in constructs)
        if (construct.collect(context) case final model?) model,
    ];
  }

  static void _collectClass(
    ClassElement element,
    _Readers readers,
    _Parts parts,
  ) {
    if (Annotations.find(element, 'Module') case final module?) {
      parts.modules.add(readers.modules.read(element, module));
    } else {
      parts.strayProvides.addAll(readers.provides.read(element));
    }
    if (Annotations.all(element, readers.injectable).isNotEmpty) {
      parts.injectables.add(readers.injectables.read(element));
    }
  }

  static Version _languageVersion(List<LibraryElement> libraries) {
    final version = libraries.firstOrNull?.languageVersion.package;
    return version == null
        ? Version(3, 8, 0)
        : Version(version.major, version.minor, 0);
  }
}

/// The readers [PackageCollector] applies to every library and class.
final class _Readers {
  _Readers(
    String packageName,
    SourceLocations locations,
    ConstructAnnotations annotations,
  ) : injectable = annotations.injectable,
      injectables = InjectableReader(locations, annotations.injectable),
      modules = ModuleReader(packageName, locations, annotations.injectable),
      provides = ProvidesReader(locations),
      unsupported = UnsupportedUseReader(locations, annotations);

  final Set<String> injectable;
  final InjectableReader injectables;
  final ModuleReader modules;
  final ProvidesReader provides;
  final UnsupportedUseReader unsupported;
}

/// What [PackageCollector] accumulates while it walks the classes.
final class _Parts {
  final modules = <ModuleModel>[];
  final injectables = <InjectableModel>[];
  final strayProvides = <ProvidesModel>[];
  final unsupported = <UnsupportedUse>[];
}
