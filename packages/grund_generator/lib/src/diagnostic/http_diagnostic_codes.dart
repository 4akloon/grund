import 'diagnostic_code.dart';

/// The codes of the diagnostics of `@Api` classes, their routes and
/// parameters.
///
/// A flat catalog without logic; changing an id is a breaking change.
abstract final class HttpDiagnosticCodes {
  /// An `@Api` class cannot be created once per module.
  static const invalidApi = DiagnosticCode('invalid_api');

  /// An `@Api` class is provided by more than one module.
  static const duplicateApi = DiagnosticCode('duplicate_api');

  /// An entry of `use:` is not a `HookRef`.
  static const invalidHook = DiagnosticCode('invalid_hook');

  /// A route annotation is on a method that cannot handle requests.
  static const invalidRouteHandler = DiagnosticCode('invalid_route_handler');

  /// A route annotation is outside of an `@Api` class.
  static const routeOutsideApi = DiagnosticCode('route_outside_api');

  /// A handler parameter cannot be bound to the request.
  static const invalidHandlerParameter = DiagnosticCode(
    'invalid_handler_parameter',
  );

  /// A handler parameter has neither a source annotation nor a call scope
  /// class type.
  static const parameterWithoutSource = DiagnosticCode(
    'parameter_without_source',
  );

  /// A `@Body()` type has no `fromJson` and is not read directly.
  static const missingFromJson = DiagnosticCode('missing_from_json');

  /// A `@Path` name is not a parameter of the route path.
  static const unknownPathParameter = DiagnosticCode('unknown_path_parameter');

  /// A `@Range`, `@Length`, `@Pattern` or `@OneOf` does not fit the
  /// parameter or its own arguments.
  static const invalidValidator = DiagnosticCode('invalid_validator');

  /// A route `status` is not an HTTP status code.
  static const invalidStatus = DiagnosticCode('invalid_status');

  /// A handler returns a type the response serializer cannot take.
  static const unsupportedReturnType = DiagnosticCode(
    'unsupported_return_type',
  );

  /// A handler returns a `Stream<T>` of something but bytes; reserved for
  /// `grund_sse`.
  static const streamReturnReserved = DiagnosticCode('stream_return_reserved');

  /// Two routes have the same method and path.
  static const duplicateRoute = DiagnosticCode('duplicate_route');
}
