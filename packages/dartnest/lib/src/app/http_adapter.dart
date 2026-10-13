import '../http/http_request.dart';
import '../http/http_response.dart';

/// Answers one request; `Application.handle` is the implementation.
typedef RequestHandler = Future<HttpResponse> Function(HttpRequest request);

/// Connects an HTTP server library to an `Application`.
///
/// Implemented outside this package (`dartnest_io`, `dartnest_shelf`).
/// Contract:
///
/// - [listen] is called at most once, by `Application.listen`, and completes
///   when the server accepts connections. For every native request the
///   adapter builds an [HttpRequest] (upper-cased method; `uri` with path and
///   query; every header value, multi-valued headers included; the body as
///   an unread stream; `connectionInfo` when known), awaits `handler`, and
///   writes the response status, every header value and the body (bytes, or
///   the stream chunk by chunk). It writes no body for `HEAD` requests.
///   `handler` answers every request, errors included; if it ever throws,
///   the adapter answers 500 without a body and keeps serving.
/// - [address] is adapter-specific (a host name or an address object); a
///   [port] of 0 asks for an ephemeral port.
/// - [close] stops accepting connections. With `force: false` it completes
///   after the responses in progress are written; with `force: true` it
///   drops open connections. It is idempotent and completes at once if
///   [listen] was never called. `Application.close` calls it before waiting
///   for in-flight requests.
abstract interface class HttpAdapter {
  /// Starts serving [handler] on [address] and [port].
  Future<void> listen(
    RequestHandler handler, {
    required Object address,
    required int port,
  });

  /// Stops serving; see the class documentation.
  Future<void> close({bool force = false});
}
