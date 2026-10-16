## 0.2.0

- `HttpResponse.mergeHeaders` adds every `set-cookie` of the merged headers
  before the response's own instead of dropping them when the response has
  one: a cookie a hook or `Sessions.start` set on `c.response` and the
  cookie of a returned `HttpResponse` both reach the client.
- `await c.form()` reads an `application/x-www-form-urlencoded` body into
  `Params` (`ParamLocation.form`, pointer `/body/<name>`); a bad escape or
  UTF-8 sequence is a 400 `body_invalid`, a body over the limit a 413.
  `ParamLocation` gained the value `form`: an exhaustive `switch` over it
  needs a case for it.
- `StatusCode.seeOther` (303), the redirect after a form `POST`.

## 0.1.0

Initial release.

- `HttpModule` binds the `HttpServer` (a `Runner` named `http`) and the
  `HttpConfig` (`address`, `port`, `maxBodyBytes`, `debug`, `accessLog`);
  it takes global hooks, middleware and response codecs. The server needs
  an `HttpAdapter` from `grund_io` or `grund_shelf`.
- `HttpApi` and `Route`: routes with typed readers for path, query, header,
  cookie and body (`c.path.integer('id')`, `await c.body(T.fromJson)`),
  matched with percent-decoded segments (a malformed percent-encoding is a
  400). `HttpHook` (`before`, `after`, `onError`), named by `HookRef` or,
  in annotations, written as a hook class or a const hook instance
  (`use: [ApiKeyHook, RolesHook(Role.editor)]`), and `Middleware`.
- Errors are `application/problem+json` (RFC 9457) with a stable `code`.
  `HttpException` and its subclasses carry `cause` and `causeStackTrace`
  (forwarded by every built-in subclass), which keep the error a hook or
  handler replaced; the responder logs such an exception on `grund.http`
  (`SEVERE` from status 500, else `FINE`) and never sends the cause to the
  client; the hook chain logs an `onError` that replaces an error as `FINE`.
- Logging on `package:logging`: an unhandled error is `SEVERE` on
  `grund.http` (error and stack trace); routes, the listener and shutdown
  are logged, and `HttpConfig.accessLog` (default `true`) logs each
  request on `grund.access`. The response is still produced when a
  listener throws, but the listener's failure is reported to its own zone:
  without `runZonedGuarded` it is an uncaught asynchronous error that ends
  the isolate, so listeners must not throw.
- The HTTP annotations (`@Api`, `Get`, `Post`, `Put`, `Patch`, `Delete`,
  `Path`, `Query`, `Header`, `Cookie`, `Body`, `Range`, `Length`, `Pattern`,
  `OneOf`) in `package:grund_http/annotations.dart`.
- `TestClient` in `package:grund_http/testing.dart`; the building blocks for
  adapters in `package:grund_http/adapter.dart`.
