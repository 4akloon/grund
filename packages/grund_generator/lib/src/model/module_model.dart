import '../diagnostic/source_location.dart';
import 'binding_model.dart';
import 'module_export.dart';
import 'module_reference.dart';
import 'provider_model.dart';
import 'provides_model.dart';
import 'type_model.dart';

/// A class annotated with `@Module`.
final class ModuleModel {
  /// Creates the model.
  const ModuleModel({
    required this.type,
    required this.location,
    this.imports = const [],
    this.providers = const [],
    this.provides = const [],
    this.exports = const [],
    this.isGlobal = false,
    this.extendsModule = true,
    this.invalidEntries = const [],
    this.documentation,
  });

  /// The module class.
  final TypeModel type;

  /// Where the class is declared.
  final SourceLocation location;

  /// Imported modules, in order.
  final List<ModuleReference> imports;

  /// Classes and `Bind`s, in order.
  final List<ProviderModel> providers;

  /// The `@Provides` methods, in declaration order.
  final List<ProvidesModel> provides;

  /// Exports, in order.
  final List<ModuleExport> exports;

  /// Whether the module is global.
  final bool isGlobal;

  /// Whether the class extends the core `Module`.
  final bool extendsModule;

  /// One sentence per annotation entry the generator cannot use.
  final List<String> invalidEntries;

  /// The `///` comment of the class, if any.
  final String? documentation;

  /// The bindings the module owns when no construct claims a provider, in
  /// the order the mixin writes them: providers first, then [provides].
  /// The checks use `ProviderClaims.bindingsOf`, which honours claims.
  List<BindingModel> get bindings => [
    for (final provider in providers) provider.binding,
    ...providedBindings,
  ];

  /// The bindings of the `@Provides` methods, in declaration order. A
  /// method with a problem has no key and is left out; the module construct
  /// reports it.
  List<BindingModel> get providedBindings => [
    for (final provided in provides)
      if (provided.key case final key?)
        BindingModel(
          key: key,
          lifetime: provided.lifetime,
          dependencies: provided.dependencies,
          location: provided.location,
        ),
  ];
}
