import 'package:analyzer/dart/element/element.dart';
import 'package:pub_semver/pub_semver.dart';

import '../construct/construct.dart';
import '../construct/construct_annotations.dart';
import '../emit/library_writer.dart';
import '../model/extension_model.dart';
import '../model/generated_names.dart';
import '../model/injectable_model.dart';
import '../model/module_in_part.dart';
import '../model/module_model.dart';
import '../model/package_model.dart';
import '../model/provides_model.dart';
import '../model/unresolved_uri.dart';
import '../model/unsupported_use.dart';
import 'annotations.dart';
import 'collection_context.dart';
import 'injectable_reader.dart';
import 'module_reader.dart';
import 'provides_reader.dart';
import 'source_locations.dart';
import 'unresolved_uri_reader.dart';
import 'unsupported_use_reader.dart';

/// Builds the [PackageModel] of one package from its resolved libraries.
///
/// The driver resolves every library of `lib/` (the CLI with an
/// `AnalysisContextCollection`, build_runner with its resolver) and passes
/// them here; the generator's own outputs (`*.g.dart` libraries with the
/// generator header) are skipped, so a re-run never reads its previous
/// output. The collector reads modules, injectables and `@Provides` itself,
/// and lets each of [constructs] read its own annotations
/// ([Construct.collect]).
final class PackageCollector {
  /// Creates the collector of package [packageName] rooted at
  /// [packageRoot] (an absolute path; locations are relative to it).
  PackageCollector(
    this.packageName,
    String packageRoot, {
    this.constructs = const [],
  }) : _locations = SourceLocations(packageRoot);

  /// The annotations the collector reads itself.
  static final coreAnnotations = ConstructAnnotations(
    libraries: {Annotations.coreLibrary},
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

  /// Whether [library] is a file this generator wrote: the name alone is not
  /// enough (json_serializable or freezed may own a `foo.g.dart`), so the
  /// header decides.
  static bool _isGeneratorOutput(LibraryElement library) =>
      '${library.uri}'.endsWith(GeneratedNames.outputSuffix) &&
      library.firstFragment.source.contents.data.startsWith(
        LibraryWriter.header,
      );

  /// The model of [libraries], in library URI order whatever the input
  /// order.
  PackageModel collect(Iterable<LibraryElement> libraries) {
    final sorted = [
      for (final library in libraries)
        if (!_isGeneratorOutput(library)) library,
    ]..sort((a, b) => '${a.uri}'.compareTo('${b.uri}'));
    final annotations = constructs.fold(
      coreAnnotations,
      (all, construct) => all.union(construct.annotations),
    );
    final parts = _Parts();
    final read = _Readers(packageName, _locations, annotations);
    for (final library in sorted) {
      parts.unsupported.addAll(read.unsupported.read(library));
      parts.unresolved.addAll(read.unresolved.read(library));
      for (final element in library.classes) {
        _collectClass(library, element, read, parts);
      }
    }
    return PackageModel(
      packageName: packageName,
      languageVersion: _languageVersion(sorted),
      modules: parts.modules,
      modulesInParts: parts.modulesInParts,
      injectables: parts.injectables,
      strayProvides: parts.strayProvides,
      unsupportedUses: parts.unsupported,
      unresolvedUris: parts.unresolved,
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
    LibraryElement library,
    ClassElement element,
    _Readers readers,
    _Parts parts,
  ) {
    if (readers.source.find(element, 'Module') case final module?) {
      if (_isInPart(library, element)) {
        parts.modulesInParts.add(
          ModuleInPart(
            element: element.displayName,
            location: readers.locations.of(element),
          ),
        );
        return;
      }
      parts.modules.add(readers.modules.read(element, module));
    } else {
      parts.strayProvides.addAll(readers.provides.read(element));
    }
    if (readers.source.all(element, readers.injectable).isNotEmpty) {
      parts.injectables.add(readers.injectables.read(element));
    }
  }

  static bool _isInPart(LibraryElement library, ClassElement element) =>
      element.firstFragment.libraryFragment != library.firstFragment;

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
      locations = locations,
      source = Annotations(annotations.libraries),
      injectables = InjectableReader(locations, annotations),
      modules = ModuleReader(packageName, locations, annotations),
      provides = ProvidesReader(locations),
      unsupported = UnsupportedUseReader(locations, annotations),
      unresolved = UnresolvedUriReader(locations);

  final SourceLocations locations;
  final Set<String> injectable;
  final Annotations source;
  final InjectableReader injectables;
  final ModuleReader modules;
  final ProvidesReader provides;
  final UnsupportedUseReader unsupported;
  final UnresolvedUriReader unresolved;
}

/// What [PackageCollector] accumulates while it walks the classes.
final class _Parts {
  final modules = <ModuleModel>[];
  final modulesInParts = <ModuleInPart>[];
  final injectables = <InjectableModel>[];
  final strayProvides = <ProvidesModel>[];
  final unsupported = <UnsupportedUse>[];
  final unresolved = <UnresolvedUri>[];
}
