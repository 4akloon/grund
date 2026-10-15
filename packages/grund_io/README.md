# grund_io

Serves a grund application on a `dart:io` `HttpServer`.

```dart
import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_io/grund_io.dart';

final class AppModule extends Module {
  const AppModule();

  @override
  List<Module> get imports => const [HttpModule(), IoAdapterModule()];
}

Future<void> main() => App(root: const AppModule()).run();
```

`IoAdapterModule` is global and binds the `HttpAdapter` that `HttpModule`
needs. The port and address come from `HttpModule(config: HttpConfig(...))`;
read the bound port with `app.container.root<HttpAdapter>()` (an `IoAdapter`).

For HTTPS pass a context:
`IoAdapterModule(securityContext: SecurityContext()..useCertificateChain('cert.pem')..usePrivateKey('key.pem'))`
(`SecurityContext` is from `dart:io`).

Rules:

- The response has no `x-powered-by` and no `dart:io` default headers
  (`content-type: text/plain`, `x-frame-options`, `x-content-type-options`,
  `x-xss-protection` are cleared); add security headers with middleware.
- Bodies stream both ways. A byte body is sent with `content-length`; a
  stream is sent unbuffered, each chunk as soon as the stream emits it.
  A `transfer-encoding` header from the application is not copied; framing
  is the adapter's job.
- `HEAD` gets the status and headers of the handler's response and no
  body; a stream body is cancelled unread. As for `GET`, only a byte body
  (or a `content-length` the application sets) has a `content-length`.
- Routing uses the request target only, never `Host`.
- `adapter.port` is the bound port (useful with `port: 0`); it throws a
  `StateError` before `listen` completes and after `close`.
- `listen` can be called once; a second call after it succeeded, or a call
  after `close`, throws a `StateError`. A `listen` that failed to bind (port
  in use) can be retried, e.g. on another port.
- `app.close()` stops accepting connections, waits for the requests in
  flight (responses still being written included) and then closes the
  application. The wait is bounded by `IoAdapterModule(closeTimeout: ...)`, 30
  seconds by default: when it expires, the remaining connections are
  dropped as with `force: true` and `app.close()` still completes
  normally. `closeTimeout: null` waits without a limit (an endless stream
  then keeps `close` waiting). `app.close(force: true)` drops the
  connections at once; when a graceful `app.close()` is already waiting, a
  later `app.close(force: true)` does not end it (the application returns
  the first close), only `adapter.close(force: true)` does.
- Failures that can no longer become a response (a body stream that fails
  mid-response, a broken connection, a response head that cannot be
  written) go to `IoAdapterModule(onError: ...)`. It is
  optional and defaults to printing to stderr. If `onError` itself throws,
  the server keeps running and that failure goes to stderr.
- There is no request body size limit: the handler reads the body as a
  stream and decides how much to accept.
