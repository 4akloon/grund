/// Every problem the generator reports, with a stable [id] that tools and
/// tests may rely on.
///
/// A flat catalog without logic. Renaming a Dart identifier here is fine;
/// changing an [id] is a breaking change.
enum DiagnosticCode {
  /// Modules import each other in a cycle.
  circularModuleImport('circular_module_import'),

  /// A module binds the same key twice.
  duplicateBinding('duplicate_binding'),

  /// A module exports a key it does not bind or a module it does not
  /// import.
  invalidExport('invalid_export'),

  /// An entry of `@Module` the generator cannot use.
  invalidModuleEntry('invalid_module_entry'),

  /// A `@Module` class does not extend `Module` of `package:grund`.
  invalidModuleClass('invalid_module_class'),

  /// A `@Named` name is empty.
  invalidName('invalid_name'),

  /// A dependency is not visible in the module that needs it.
  missingProvider('missing_provider'),

  /// Bindings depend on each other in a cycle.
  circularDependency('circular_dependency'),

  /// A singleton depends, directly or through transients, on a call-scoped
  /// binding.
  captiveDependency('captive_dependency'),

  /// A provider class is not annotated with `@Injectable()`.
  notInjectable('not_injectable'),

  /// A provider or API class cannot be created through its unnamed
  /// constructor.
  invalidConstructor('invalid_constructor'),

  /// A constructor or `@Provides` parameter cannot be injected.
  invalidDependency('invalid_dependency'),

  /// A `@Provides` method cannot be called by generated code, or is not in
  /// a module.
  invalidProvides('invalid_provides'),

  /// The `scope` of an `@Injectable` is not a constant `Scope` value.
  invalidScope('invalid_scope'),

  /// A `Bind<I, C>()` entry binds a key that is almost certainly a mistake.
  invalidBind('invalid_bind'),

  /// A constant (module instance, key, hook) cannot be written as Dart
  /// code.
  unsupportedConstant('unsupported_constant'),

  /// An annotation or member the generator ignores, so it would silently do
  /// nothing.
  unsupportedUse('unsupported_use'),

  /// An `@Api` class cannot be created once per module.
  invalidApi('invalid_api'),

  /// An `@Api` class is provided by more than one module.
  duplicateApi('duplicate_api'),

  /// An entry of `use:` is not a `HookRef`.
  invalidHook('invalid_hook'),

  /// A route annotation is on a method that cannot handle requests.
  invalidRouteHandler('invalid_route_handler'),

  /// A route annotation is outside of an `@Api` class.
  routeOutsideApi('route_outside_api'),

  /// A handler parameter cannot be bound to the request.
  invalidHandlerParameter('invalid_handler_parameter'),

  /// A handler parameter has neither a source annotation nor a call scope
  /// class type.
  parameterWithoutSource('parameter_without_source'),

  /// A `@Body()` type has no `fromJson` and is not read directly.
  missingFromJson('missing_from_json'),

  /// A `@Path` name is not a parameter of the route path.
  unknownPathParameter('unknown_path_parameter'),

  /// A `@Range`, `@Length`, `@Pattern` or `@OneOf` does not fit the
  /// parameter or its own arguments.
  invalidValidator('invalid_validator'),

  /// A route `status` is not an HTTP status code.
  invalidStatus('invalid_status'),

  /// A handler returns a type the response serializer cannot take.
  unsupportedReturnType('unsupported_return_type'),

  /// A handler returns a `Stream<T>` of something but bytes; reserved for
  /// `grund_sse`.
  streamReturnReserved('stream_return_reserved'),

  /// Two routes have the same method and path.
  duplicateRoute('duplicate_route'),

  /// Two generated declarations would have the same name.
  duplicateGeneratedName('duplicate_generated_name');

  const DiagnosticCode(this.id);

  /// The stable identifier printed with the message.
  final String id;
}
