## 0.1.0

- Initial release.
- `HttpException.cause` and `causeStackTrace` (forwarded by every built-in
  subclass) keep the error a hook or handler replaced. The responder logs
  such an exception on `grund.http` (`SEVERE` from status 500, else `FINE`)
  and never sends the cause to the client; the hook chain logs an `onError`
  that replaces an error as `FINE`.
- Logging: an unhandled error is logged as `SEVERE` on `grund.http` (error and
  stack trace); subscribe to `Logger.root.onRecord` to forward it. The
  response is still produced when a listener throws, but the listener's
  failure is reported to its own zone: without `runZonedGuarded` it is an
  uncaught asynchronous error that ends the isolate, so listeners must not
  throw. Routes, the listener and shutdown are logged, and
  `HttpConfig.accessLog` (default `true`) logs each request on
  `grund.access`.
- The HTTP annotations (`@Api`, `Get`, `Post`, `Put`, `Patch`, `Delete`,
  `Path`, `Query`, `Header`, `Cookie`, `Body`, `Range`, `Length`, `Pattern`,
  `OneOf`) in `package:grund_http/annotations.dart`.
