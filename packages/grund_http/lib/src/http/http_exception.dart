/// [HttpException] and the built-in subclasses the framework throws itself.
///
/// The subclasses are one family with their base and share this file, like
/// the error families in `errors.dart`; the base stays open (not sealed) so
/// that applications can add their own statuses.
library;

import 'status_code.dart';

/// An error that the default exception filter turns into an HTTP error
/// response: `{"statusCode": status, "error": reason phrase,
/// "message": message}`, plus `"details"` when given.
///
/// Throw it from guards, interceptors, pipes, handlers and filters. Extend it
/// for statuses that have no built-in subclass:
///
/// ```dart
/// class PaymentRequiredException extends HttpException {
///   const PaymentRequiredException() : super(402);
/// }
/// ```
class HttpException implements Exception {
  /// Creates an exception for [status]; [message] defaults to the reason
  /// phrase of [status].
  const HttpException(
    this.status, {
    String? message,
    this.details,
    this.headers = const {},
  }) : _message = message;

  /// HTTP status code of the response.
  final int status;

  final String? _message;

  /// Human-readable message sent to the client.
  String get message => _message ?? StatusCode.reasonPhrase(status);

  /// Extra data sent as `"details"`: a JSON value (`Map`, `List`, `String`,
  /// `num`, `bool`); any other object is sent as its `toString()`.
  final Object? details;

  /// Headers added to the error response (for example `allow` or
  /// `www-authenticate`).
  final Map<String, String> headers;

  @override
  String toString() => '$runtimeType($status): $message';
}

/// 400: the request is malformed (bad JSON, a parameter of the wrong type).
class BadRequestException extends HttpException {
  /// Creates the exception.
  const BadRequestException({super.message, super.details})
    : super(StatusCode.badRequest);
}

/// 401: the request lacks valid credentials.
class UnauthorizedException extends HttpException {
  /// Creates the exception.
  const UnauthorizedException({super.message, super.details, super.headers})
    : super(StatusCode.unauthorized);
}

/// 403: the credentials are valid but not sufficient; also thrown when a
/// guard returns `false`.
class ForbiddenException extends HttpException {
  /// Creates the exception.
  const ForbiddenException({super.message, super.details})
    : super(StatusCode.forbidden);
}

/// 404: no route matches the path, or the requested entity does not exist.
class NotFoundException extends HttpException {
  /// Creates the exception.
  const NotFoundException({super.message, super.details})
    : super(StatusCode.notFound);
}

/// 405: a route matches the path but not the method; [allowed] is sent in
/// the `allow` header.
class MethodNotAllowedException extends HttpException {
  /// Creates the exception for the [allowed] methods.
  MethodNotAllowedException(this.allowed, {super.message})
    : super(
        StatusCode.methodNotAllowed,
        headers: {'allow': allowed.join(', ')},
      );

  /// Methods the matched path accepts, sorted.
  final List<String> allowed;
}

/// 503: the application is shutting down or temporarily unable to serve.
class ServiceUnavailableException extends HttpException {
  /// Creates the exception.
  const ServiceUnavailableException({super.message, super.details})
    : super(StatusCode.serviceUnavailable);
}
