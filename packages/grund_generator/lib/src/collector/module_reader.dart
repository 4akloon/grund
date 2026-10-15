import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';

import '../construct/construct_annotations.dart';
import '../model/module_model.dart';
import '../model/module_reference.dart';
import 'annotations.dart';
import 'entry_read.dart';
import 'export_entry_reader.dart';
import 'injectable_reader.dart';
import 'module_reference_reader.dart';
import 'provider_entry_reader.dart';
import 'provides_reader.dart';
import 'source_locations.dart';
import 'type_reader.dart';

/// Reads a `@Module` class into a [ModuleModel]. Entries it cannot read go
/// to [ModuleModel.invalidEntries]; the module construct reports them.
final class ModuleReader {
  /// Creates the reader for package [packageName]; the injectable
  /// annotations of [annotations] make a provider class injectable.
  ModuleReader(
    this.packageName,
    this.locations,
    ConstructAnnotations annotations,
  ) : _references = ModuleReferenceReader(packageName),
      _providers = ProviderEntryReader(
        InjectableReader(locations, annotations),
      ),
      _provides = ProvidesReader(locations);

  /// The package being generated.
  final String packageName;

  /// Locations of declarations.
  final SourceLocations locations;

  final ModuleReferenceReader _references;

  final ProviderEntryReader _providers;

  final ProvidesReader _provides;

  /// The module declared by [element], whose `@Module` is [annotation].
  ModuleModel read(ClassElement element, DartObject annotation) {
    final imports = [for (final e in _list(annotation, 'imports')) _import(e)];
    final providers = [
      for (final e in _list(annotation, 'providers')) _providers.read(e),
    ];
    final exports = [
      for (final e in _list(annotation, 'exports')) ExportEntryReader.read(e),
    ];
    return ModuleModel(
      type: TypeReader.read(element.thisType),
      location: locations.of(element),
      imports: EntryRead.values(imports),
      providers: EntryRead.values(providers),
      provides: _provides.read(element),
      exports: EntryRead.values(exports),
      isGlobal: Annotations.field(annotation, 'global')?.toBoolValue() ?? false,
      extendsModule: TypeReader.extendsCoreModule(element),
      invalidEntries: EntryRead.problems([
        ...imports,
        ...providers,
        ...exports,
      ]),
      documentation: element.documentationComment,
    );
  }

  EntryRead<ModuleReference> _import(DartObject entry) =>
      switch (_references.read(entry)) {
        final reference? => ReadEntry(reference),
        null => InvalidEntry(
          'imports: ${Annotations.describe(entry)} is not a const instance '
          'of a Module.',
        ),
      };

  static List<DartObject> _list(DartObject annotation, String name) =>
      Annotations.field(annotation, name)?.toListValue() ?? const [];
}
