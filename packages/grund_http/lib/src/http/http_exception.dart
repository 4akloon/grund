/// [HttpException] and the built-in subclasses the framework throws itself.
///
/// The subclasses are one family with their base and share this file, like
/// the error families in the core; the base stays open (not sealed) so that
/// applications can add their own statuses.
library;

import 'status_code.dart';

/// An error that `ProblemResponder` turns into an `application/problem+json`
/// response (RFC 9457) with the same status.
///
/// Throw it from hooks and handlers. Extend it for statuses that have no
/// built-in subclass:
///
/// ```dart
/// class PaymentRequiredException extends HttpException {
///   const PaymentRequiredException() : super(402);
/// }
/// ```
class HttpException implements Exception {
  /// Creates an exception for [status]; `message` defaults to the reason
  /// phrase of [status].
  const HttpException(
    this.status, {
    this._message,
    this.code,
    this.pointer,
    this.details,
    this.headers = const {},
    this.cause,
    this.causeStackTrace,
  });

  /// HTTP status code of the response.
  final int status;

  final String? _message;

  /// Human-readable message sent to the client as `detail`.
  String get message => _message ?? StatusCode.reasonPhrase(status);

  /// Stable machine-readable identifier of the failure (`parameter_invalid`),
  /// sent as `code`; clients switch on it, never on [message].
  final String? code;

  /// JSON pointer to the offending input (`/query/page`, `/body/title`),
  /// sent as an entry of `errors`.
  final String? pointer;

  /// Extra data sent as `details`: a JSON value (`Map`, `List`, `String`,
  /// `num`, `bool`), any other object as its `toString()`. A list of
  /// `ProblemError`s is sent as `errors` instead.
  final Object? details;

  /// Headers added to the error response (for example `allow` or
  /// `www-authenticate`).
  final Map<String, String> headers;

  /// The error this exception replaces (what a hook or handler caught before
  /// it chose this response), kept for the logs: never sent to the client.
  final Object? cause;

  /// The stack trace of [cause].
  final StackTrace? causeStackTrace;

  @override
  String toString() => '$runtimeType($status): $message';
}

/// 400: the request is malformed (bad JSON, a parameter of the wrong type).
class BadRequestException extends HttpException {
  /// Creates the exception.
  const BadRequestException({
    super.message,
    super.code,
    super.pointer,
    super.details,
    super.cause,
    super.causeStackTrace,
  }) : super(StatusCode.badRequest);
}

/// 401: the request lacks valid credentials.
class UnauthorizedException extends HttpException {
  /// Creates the exception.
  const UnauthorizedException({
    super.message,
    super.code,
    super.details,
    super.headers,
    super.cause,
    super.causeStackTrace,
  }) : super(StatusCode.unauthorized);
}

/// 403: the credentials are valid but not sufficient.
class ForbiddenException extends HttpException {
  /// Creates the exception.
  const ForbiddenException({
    super.message,
    super.code,
    super.details,
    super.cause,
    super.causeStackTrace,
  }) : super(StatusCode.forbidden);
}

/// 404: no route matches the path, or the requested entity does not exist.
class NotFoundException extends HttpException {
  /// Creates the exception.
  const NotFoundException({
    super.message,
    super.code,
    super.details,
    super.cause,
    super.causeStackTrace,
  }) : super(StatusCode.notFound);
}

/// 405: a route matches the path but not the method; [allowed] is sent in
/// the `allow` header.
class MethodNotAllowedException extends HttpException {
  /// Creates the exception for the [allowed] methods.
  MethodNotAllowedException(
    this.allowed, {
    super.message,
    super.code,
    super.cause,
    super.causeStackTrace,
  }) : super(
         StatusCode.methodNotAllowed,
         headers: {'allow': allowed.join(', ')},
       );

  /// Methods the matched path accepts, sorted.
  final List<String> allowed;
}

/// 413: the request body is larger than the configured limit.
class PayloadTooLargeException extends HttpException {
  /// Creates the exception.
  const PayloadTooLargeException({
    super.message,
    super.code,
    super.details,
    super.cause,
    super.causeStackTrace,
  }) : super(StatusCode.payloadTooLarge);
}

/// 422: the request is well-formed but its content is not acceptable (a
/// business rule, a failed validation of the body).
class UnprocessableContentException extends HttpException {
  /// Creates the exception.
  const UnprocessableContentException({
    super.message,
    super.code,
    super.pointer,
    super.details,
    super.cause,
    super.causeStackTrace,
  }) : super(StatusCode.unprocessableContent);
}

/// 503: the application is shutting down or temporarily unable to serve.
class ServiceUnavailableException extends HttpException {
  /// Creates the exception.
  const ServiceUnavailableException({
    super.message,
    super.code,
    super.details,
    super.cause,
    super.causeStackTrace,
  }) : super(StatusCode.serviceUnavailable);
}
