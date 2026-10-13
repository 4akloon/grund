import '../http/http_request.dart';
import '../http/response_head.dart';

/// The protocol an `ExecutionContext` serves. Sealed: HTTP now, GraphQL
/// later.
sealed class Transport {
  /// Creates a transport.
  const Transport();
}

/// The HTTP view of a request: the request, the response head handlers may
/// change, and the matched path parameters.
final class HttpContext extends Transport {
  /// Creates the HTTP view.
  HttpContext({
    required this.request,
    required this.response,
    this.pathParameters = const {},
  });

  /// The incoming request.
  final HttpRequest request;

  /// Status and headers for the response.
  final ResponseHead response;

  /// Matched path parameters, percent-decoded; the wildcard is `*`.
  final Map<String, String> pathParameters;
}
