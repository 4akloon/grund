import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/module_export.dart';
import '../model/module_model.dart';
import '../model/module_reference.dart';
import '../model/provider_key.dart';
import '../model/type_model.dart';
import 'annotations.dart';
import 'entry_read.dart';
import 'injectable_reader.dart';
import 'module_reference_reader.dart';
import 'provider_entry_reader.dart';
import 'source_locations.dart';
import 'token_reader.dart';
import 'type_reader.dart';

/// Reads a `@Module` class into a [ModuleModel]. Entries it cannot read go
/// to [ModuleModel.invalidEntries]; the module construct reports them.
final class ModuleReader {
  /// Creates the reader for package [packageName].
  ModuleReader(this.packageName, this.locations)
    : _references = ModuleReferenceReader(packageName),
      _injectables = InjectableReader(locations);

  /// The package being generated.
  final String packageName;

  /// Locations of declarations.
  final SourceLocations locations;

  final ModuleReferenceReader _references;

  final InjectableReader _injectables;

  /// The module declared by [element], whose `@Module` is [annotation].
  ModuleModel read(ClassElement element, DartObject annotation) {
    final providerReader = ProviderEntryReader(
      _injectables,
      element.library.typeSystem,
    );
    final imports = [for (final e in _list(annotation, 'imports')) _import(e)];
    final providers = [
      for (final e in _list(annotation, 'providers')) providerReader.read(e),
    ];
    final controllers = [
      for (final e in _list(annotation, 'controllers')) _controller(e),
    ];
    final exports = [for (final e in _list(annotation, 'exports')) _export(e)];
    return ModuleModel(
      type: TypeReader.read(element.thisType),
      id:
          Annotations.field(annotation, 'id')?.toStringValue() ??
          element.displayName,
      location: locations.of(element),
      imports: EntryRead.values(imports),
      providers: EntryRead.values(providers),
      controllers: EntryRead.values(controllers),
      exports: EntryRead.values(exports),
      isGlobal: Annotations.field(annotation, 'global')?.toBoolValue() ?? false,
      invalidEntries: EntryRead.problems([
        ...imports,
        ...providers,
        ...controllers,
        ...exports,
      ]),
      documentation: element.documentationComment,
    );
  }

  EntryRead<ModuleReference> _import(DartObject entry) =>
      switch (_references.read(entry)) {
        final reference? => ReadEntry(reference),
        null => _invalid('imports', entry, 'is not a module'),
      };

  EntryRead<TypeModel> _controller(DartObject entry) {
    final type = entry.toTypeValue();
    final local =
        type is InterfaceType &&
        Annotations.find(type.element, 'Controller') != null &&
        '${type.element.library.uri}'.startsWith('package:$packageName/');
    return local
        ? ReadEntry(TypeReader.read(type))
        : _invalid(
            'controllers',
            entry,
            'is not a @Controller class of this package',
          );
  }

  EntryRead<ModuleExport> _export(DartObject entry) {
    if (_references.read(entry) case final reference?) {
      return ReadEntry(ModuleReexport(reference));
    }
    if (entry.toTypeValue() case final InterfaceType type) {
      return ReadEntry(KeyExport(TypeKey(TypeReader.read(type))));
    }
    if (TokenReader.read(entry) case (final key, _)) {
      return ReadEntry(KeyExport(key));
    }
    return _invalid('exports', entry, 'is not a class, token or module');
  }

  static List<DartObject> _list(DartObject annotation, String name) =>
      Annotations.field(annotation, name)?.toListValue() ?? const [];

  static InvalidEntry<T> _invalid<T>(
    String field,
    DartObject entry,
    String what,
  ) => InvalidEntry('$field: ${Annotations.describe(entry)} $what.');
}
