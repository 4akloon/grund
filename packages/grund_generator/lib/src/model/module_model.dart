import '../diagnostic/source_location.dart';
import 'module_export.dart';
import 'module_reference.dart';
import 'provider_model.dart';
import 'type_model.dart';

/// A class annotated with `@Module`.
final class ModuleModel {
  /// Creates the model.
  const ModuleModel({
    required this.type,
    required this.id,
    required this.location,
    this.imports = const [],
    this.providers = const [],
    this.controllers = const [],
    this.exports = const [],
    this.isGlobal = false,
    this.invalidEntries = const [],
    this.documentation,
  });

  /// The module class.
  final TypeModel type;

  /// The module id: `@Module(id:)` or the class name.
  final String id;

  /// Where the class is declared.
  final SourceLocation location;

  /// Imported modules, in order.
  final List<ModuleReference> imports;

  /// Providers, in order.
  final List<ProviderModel> providers;

  /// Controller classes (annotated with `@Controller`), in order.
  final List<TypeModel> controllers;

  /// Exports, in order.
  final List<ModuleExport> exports;

  /// Whether the module is global.
  final bool isGlobal;

  /// One sentence per annotation entry the generator cannot use.
  final List<String> invalidEntries;

  /// The `///` comment of the class, if any.
  final String? documentation;
}
