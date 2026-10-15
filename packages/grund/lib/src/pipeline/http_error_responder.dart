import 'dart:convert';

import '../http/header_map.dart';
import '../http/http_exception.dart';
import '../http/http_response.dart';
import '../http/response_body.dart';
import '../http/status_code.dart';

/// Receives errors that become 500 responses, with their stack traces.
///
/// It must not throw: a throwing logger makes `Application.handle` fail.
typedef ErrorLogger = void Function(Object error, StackTrace stackTrace);

/// The default exception filter: turns any error into a JSON error response
/// and never throws.
///
/// - [HttpException] → its status and headers, body
///   `{"statusCode", "error", "message"}` plus `"details"` when present.
/// - Anything else → logged through [log], then 500 with
///   `"message": "Internal server error"`; with [debug] the message is the
///   error's `toString()` and `"stack"` holds the stack trace.
final class HttpErrorResponder {
  /// Creates the responder.
  const HttpErrorResponder({required this.debug, required this.log});

  /// Whether 500 responses reveal the error and its stack trace.
  final bool debug;

  /// Where unexpected errors are reported.
  final ErrorLogger log;

  /// The response for [error].
  HttpResponse respond(Object error, StackTrace stackTrace) {
    if (error is HttpException) {
      return _json(error.status, HeaderMap.of(error.headers), {
        'statusCode': error.status,
        'error': StatusCode.reasonPhrase(error.status),
        'message': error.message,
        if (error.details != null) 'details': error.details,
      });
    }
    log(error, stackTrace);
    return _json(StatusCode.internalServerError, HeaderMap(), {
      'statusCode': StatusCode.internalServerError,
      'error': StatusCode.reasonPhrase(StatusCode.internalServerError),
      'message': debug ? '$error' : 'Internal server error',
      if (debug) 'stack': '$stackTrace',
    });
  }

  /// The default [ErrorLogger]: prints the error and stack trace.
  static void printError(Object error, StackTrace stackTrace) {
    print('grund: unhandled error: $error\n$stackTrace');
  }

  static HttpResponse _json(
    int status,
    HeaderMap headers,
    Map<String, Object?> body,
  ) {
    headers.set('content-type', 'application/json; charset=utf-8');
    final text = _encode(body);
    return HttpResponse(
      status,
      headers: headers,
      body: BytesBody(utf8.encode(text)),
    );
  }

  static String _encode(Map<String, Object?> body) {
    // Anything that is not a JSON value is sent as its toString(), so
    // building an error response cannot fail on odd details.
    String encode(Map<String, Object?> value) =>
        jsonEncode(value, toEncodable: (Object? value) => '$value');
    // HttpErrorResponder boundary: a cyclic details value makes the encoder
    // throw this SDK Error; the body is then sent without details.
    try {
      return encode(body);
    } on JsonUnsupportedObjectError {
      return encode({...body}..remove('details'));
    }
  }
}
