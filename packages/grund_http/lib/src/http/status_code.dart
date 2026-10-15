/// HTTP status codes that grund itself produces or documents, and their
/// reason phrases. A flat catalog.
abstract final class StatusCode {
  /// 200 OK.
  static const ok = 200;

  /// 201 Created.
  static const created = 201;

  /// 204 No Content.
  static const noContent = 204;

  /// 302 Found.
  static const found = 302;

  /// 400 Bad Request.
  static const badRequest = 400;

  /// 401 Unauthorized.
  static const unauthorized = 401;

  /// 403 Forbidden.
  static const forbidden = 403;

  /// 404 Not Found.
  static const notFound = 404;

  /// 405 Method Not Allowed.
  static const methodNotAllowed = 405;

  /// 409 Conflict.
  static const conflict = 409;

  /// 413 Content Too Large.
  static const payloadTooLarge = 413;

  /// 422 Unprocessable Content.
  static const unprocessableContent = 422;

  /// 500 Internal Server Error.
  static const internalServerError = 500;

  /// 503 Service Unavailable.
  static const serviceUnavailable = 503;

  /// The reason phrase of [code], or `'Unknown Status'`.
  static String reasonPhrase(int code) => switch (code) {
    200 => 'OK',
    201 => 'Created',
    202 => 'Accepted',
    204 => 'No Content',
    301 => 'Moved Permanently',
    302 => 'Found',
    303 => 'See Other',
    304 => 'Not Modified',
    307 => 'Temporary Redirect',
    308 => 'Permanent Redirect',
    400 => 'Bad Request',
    401 => 'Unauthorized',
    403 => 'Forbidden',
    404 => 'Not Found',
    405 => 'Method Not Allowed',
    409 => 'Conflict',
    410 => 'Gone',
    413 => 'Content Too Large',
    415 => 'Unsupported Media Type',
    422 => 'Unprocessable Content',
    429 => 'Too Many Requests',
    500 => 'Internal Server Error',
    501 => 'Not Implemented',
    502 => 'Bad Gateway',
    503 => 'Service Unavailable',
    504 => 'Gateway Timeout',
    _ => 'Unknown Status',
  };
}
