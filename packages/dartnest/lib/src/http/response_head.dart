import 'header_map.dart';

/// Status and headers that a guard, interceptor or handler sets for the
/// response dartnest builds from the handler's result.
///
/// Reach it through `context.switchToHttp().response`.
///
/// - [status] replaces the default status of a serialized result (200, or
///   204 for `null`). It is ignored when the handler returns an
///   `HttpResponse`.
/// - [headers] are added to every response of the request, error responses
///   included. For a serialized result they replace the defaults (so a
///   handler can set `content-type`); a returned `HttpResponse` keeps its own
///   values for names it sets.
final class ResponseHead {
  /// Creates an empty head.
  ResponseHead();

  /// Status for a serialized result; `null` keeps the default.
  int? status;

  /// Headers for the response.
  final HeaderMap headers = HeaderMap();
}
