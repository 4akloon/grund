/// Every problem the generator reports, with a stable [id] that tools and
/// tests may rely on.
///
/// A flat catalog without logic. Renaming a Dart identifier here is fine;
/// changing an [id] is a breaking change.
enum DiagnosticCode {
  /// Two modules of the package have the same id.
  duplicateModuleId('duplicate_module_id'),

  /// Modules import each other in a cycle.
  circularModuleImport('circular_module_import'),

  /// A module declares the same provider key twice.
  duplicateProvider('duplicate_provider'),

  /// A module exports a key it does not provide or a module it does not
  /// import.
  invalidExport('invalid_export'),

  /// An entry of `@Module` the generator cannot use.
  invalidModuleEntry('invalid_module_entry'),

  /// A dependency is not visible in the module that needs it.
  missingProvider('missing_provider'),

  /// Providers depend on each other in a cycle.
  circularDependency('circular_dependency'),

  /// A class provider is not annotated with `@Injectable()`.
  notInjectable('not_injectable'),

  /// A provider or `@Api` class cannot be created through its unnamed
  /// constructor.
  invalidConstructor('invalid_constructor'),

  /// A constructor parameter cannot be injected.
  invalidDependency('invalid_dependency'),

  /// A `@UseGuards`, `@UseInterceptors`, `@UsePipes` or `@UseFilters` type
  /// is not a component of that kind.
  invalidComponent('invalid_component'),

  /// A constant (metadata, `Value`, token) cannot be written as Dart code.
  unsupportedConstant('unsupported_constant'),

  /// A route annotation is on a method that cannot handle requests.
  invalidRouteHandler('invalid_route_handler'),

  /// A handler parameter cannot be bound to the request.
  invalidHandlerParameter('invalid_handler_parameter'),

  /// A `@Body()` type has no `fromJson` and is not read directly.
  missingFromJson('missing_from_json'),

  /// A `@Param` name is not a parameter of the route path.
  unknownPathParameter('unknown_path_parameter'),

  /// Two routes have the same method and path, or an `@Api` class is listed
  /// by more than one module (its routes would be registered twice).
  duplicateRoute('duplicate_route'),

  /// Two generated declarations would have the same name.
  duplicateGeneratedName('duplicate_generated_name'),

  /// An annotation sits where the generator does not read it (inherited or
  /// mixed-in members, mixins, enums, extensions) or has an argument it
  /// cannot evaluate.
  unsupportedUse('unsupported_use');

  const DiagnosticCode(this.id);

  /// The stable identifier printed with the message.
  final String id;
}
