/// What kind of problem a `Diagnostic` is, with a stable [id] that tools
/// and tests may rely on.
///
/// The codes of the core constructs are the constants of this class; a
/// package that adds constructs declares its own codes the same way, as
/// `const DiagnosticCode('...')` constants of a class of its own. Two codes
/// are equal when their ids are. A flat catalog without logic: renaming a
/// Dart identifier here is fine, changing an [id] is a breaking change.
final class DiagnosticCode {
  /// Creates the code [id]; ids are `snake_case` and unique across
  /// packages.
  const DiagnosticCode(this.id);

  /// The stable identifier printed with the message.
  final String id;

  /// Modules import each other in a cycle.
  static const circularModuleImport = DiagnosticCode('circular_module_import');

  /// A module binds the same key twice.
  static const duplicateBinding = DiagnosticCode('duplicate_binding');

  /// A module exports a key it does not bind or a module it does not
  /// import.
  static const invalidExport = DiagnosticCode('invalid_export');

  /// An entry of `@Module` the generator cannot use.
  static const invalidModuleEntry = DiagnosticCode('invalid_module_entry');

  /// A `@Module` class does not extend `Module` of `package:grund`.
  static const invalidModuleClass = DiagnosticCode('invalid_module_class');

  /// A `@Named` name is empty.
  static const invalidName = DiagnosticCode('invalid_name');

  /// A dependency is not visible in the module that needs it.
  static const missingProvider = DiagnosticCode('missing_provider');

  /// Bindings depend on each other in a cycle.
  static const circularDependency = DiagnosticCode('circular_dependency');

  /// A singleton depends, directly or through transients, on a call-scoped
  /// binding.
  static const captiveDependency = DiagnosticCode('captive_dependency');

  /// A provider class is not annotated with `@Injectable()`.
  static const notInjectable = DiagnosticCode('not_injectable');

  /// A provider class cannot be created through its unnamed constructor.
  static const invalidConstructor = DiagnosticCode('invalid_constructor');

  /// A constructor or `@Provides` parameter cannot be injected.
  static const invalidDependency = DiagnosticCode('invalid_dependency');

  /// A `@Provides` method cannot be called by generated code, or is not in
  /// a module.
  static const invalidProvides = DiagnosticCode('invalid_provides');

  /// The `scope` of an `@Injectable` is not a constant `Scope` value.
  static const invalidScope = DiagnosticCode('invalid_scope');

  /// A `Bind<I, C>()` entry binds a key that is almost certainly a mistake.
  static const invalidBind = DiagnosticCode('invalid_bind');

  /// A constant (a module instance, a key, an annotation argument) cannot be
  /// written as Dart code.
  static const unsupportedConstant = DiagnosticCode('unsupported_constant');

  /// An annotation or member the generator ignores, so it would silently do
  /// nothing.
  static const unsupportedUse = DiagnosticCode('unsupported_use');

  /// Two generated declarations would have the same name.
  static const duplicateGeneratedName = DiagnosticCode(
    'duplicate_generated_name',
  );

  /// More than one construct claims the same provider of a module.
  static const conflictingProviderClaim = DiagnosticCode(
    'conflicting_provider_claim',
  );

  /// A module names a private class; the code generated into another
  /// library cannot reach it.
  static const privateDeclaration = DiagnosticCode('private_declaration');

  /// Every code of this catalog, in declaration order.
  static const values = <DiagnosticCode>[
    circularModuleImport,
    duplicateBinding,
    invalidExport,
    invalidModuleEntry,
    invalidModuleClass,
    invalidName,
    missingProvider,
    circularDependency,
    captiveDependency,
    notInjectable,
    invalidConstructor,
    invalidDependency,
    invalidProvides,
    invalidScope,
    invalidBind,
    unsupportedConstant,
    unsupportedUse,
    duplicateGeneratedName,
    conflictingProviderClaim,
    privateDeclaration,
  ];

  @override
  bool operator ==(Object other) => other is DiagnosticCode && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => id;
}
