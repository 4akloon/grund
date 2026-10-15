import 'dart:convert';

import 'package:logging/logging.dart';

import 'header_map.dart';
import 'http_exception.dart';
import 'http_response.dart';
import 'problem.dart';
import 'problem_error.dart';
import 'response_body.dart';
import 'status_code.dart';

/// Turns any error into an `application/problem+json` response and never
/// throws.
///
/// - [HttpException]: its status and headers; `detail` is its message, `code`
///   and `pointer` (as an entry of `errors`) are kept, `details` becomes the
///   extension `details` (a list of [ProblemError]s becomes `errors`).
/// - anything else: logged as `SEVERE` on the logger `grund.http` with the
///   error and its stack trace (a throwing record listener is user code and
///   fails on its own, outside this call), then 500 with `detail` `Internal
///   server error`; with [debug] the detail is the error's `toString()` and
///   the extension `stack` holds the stack trace.
final class ProblemResponder {
  /// Creates the responder.
  const ProblemResponder({required this.debug});

  /// Whether 500 responses reveal the error and its stack trace.
  final bool debug;

  static final Logger _logger = Logger('grund.http');

  /// Logs [error], which no response could carry, as `SEVERE` on
  /// `grund.http` with its [stackTrace].
  void report(Object error, StackTrace stackTrace) =>
      _logger.severe('Unhandled error', error, stackTrace);

  /// The response for [error]; [instance] identifies the failed request.
  HttpResponse respond(
    Object error,
    StackTrace stackTrace, {
    String? instance,
  }) {
    if (error is! HttpException) {
      report(error, stackTrace);
      return _response(
        500,
        HeaderMap(),
        _internal(error, stackTrace, instance),
      );
    }
    final headers = HeaderMap.of(error.headers);
    final full = _fromException(error, instance, withDetails: true);
    // A details value the encoder rejects (a cycle) must not turn a 400 into
    // a failure of the responder: it is dropped and the rest is sent.
    return _response(
      error.status,
      headers,
      full,
      fallback: _fromException(error, instance, withDetails: false),
    );
  }

  Problem _fromException(
    HttpException error,
    String? instance, {
    required bool withDetails,
  }) {
    final (listed, extra) = switch (error.details) {
      final List<Object?> list
          when list.every((item) => item is ProblemError) =>
        (list.cast<ProblemError>(), null),
      final other => (const <ProblemError>[], other),
    };
    return Problem(
      title: StatusCode.reasonPhrase(error.status),
      status: error.status,
      detail: error.message,
      instance: instance,
      code: error.code,
      errors: [
        if (error.pointer != null)
          ProblemError(
            detail: error.message,
            pointer: error.pointer,
            code: error.code,
          ),
        ...listed,
      ],
      extensions: {if (withDetails && extra != null) 'details': extra},
    );
  }

  Problem _internal(Object error, StackTrace stackTrace, String? instance) =>
      Problem(
        title: StatusCode.reasonPhrase(StatusCode.internalServerError),
        status: StatusCode.internalServerError,
        detail: debug ? '$error' : 'Internal server error',
        instance: instance,
        extensions: {if (debug) 'stack': '$stackTrace'},
      );

  static HttpResponse _response(
    int status,
    HeaderMap headers,
    Problem problem, {
    Problem? fallback,
  }) {
    headers.set('content-type', 'application/problem+json');
    return HttpResponse(
      status,
      headers: headers,
      body: BytesBody(utf8.encode(_encode(problem, fallback))),
    );
  }

  static String _encode(Problem problem, Problem? fallback) {
    // Anything that is not a JSON value is sent as its toString(), so
    // building an error response cannot fail on odd details.
    String encode(Problem value) =>
        jsonEncode(value.toJson(), toEncodable: (Object? v) => '$v');
    // ProblemResponder boundary: a cyclic details value makes the encoder
    // throw this SDK Error; the problem is then sent without details.
    try {
      return encode(problem);
    } on JsonUnsupportedObjectError {
      return encode(fallback ?? problem);
    }
  }
}
