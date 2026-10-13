# dartnest_io

Serves a dartnest application on a `dart:io` `HttpServer`.

```dart
import 'package:dartnest/dartnest.dart';
import 'package:dartnest_io/dartnest_io.dart';

Future<void> main() async {
  final adapter = IoAdapter();
  // appModule: your root module, `Module appModule() => Module(...)`.
  final app = await Application.create(appModule, adapter: adapter);
  await app.listen(port: 8080);
  print('Listening on http://localhost:${adapter.port}');
}
```

For HTTPS pass a context:
`IoAdapter(securityContext: SecurityContext()..useCertificateChain('cert.pem')..usePrivateKey('key.pem'))`
(`SecurityContext` is from `dart:io`).

Rules:

- The response has no `x-powered-by` and no `dart:io` default headers
  (`content-type: text/plain`, `x-frame-options`, `x-content-type-options`,
  `x-xss-protection` are cleared); add security headers with middleware.
- Bodies stream both ways. A byte body is sent with `content-length`; a
  stream is sent unbuffered, each chunk as soon as the stream emits it.
  A `transfer-encoding` header from the application is not copied; framing
  is the adapter's job.
- `HEAD` gets the headers of `GET` and no body; a stream body is cancelled
  unread.
- Routing uses the request target only, never `Host`.
- `adapter.port` is the bound port (useful with `port: 0`); it throws a
  `StateError` before `listen` completes and after `close`.
- `listen` can be called once; a second call, or a call after `close`,
  throws a `StateError`.
- `app.close()` stops accepting connections, waits for the requests in
  flight (responses still being written included) and then closes the
  application. The wait is bounded by `IoAdapter(closeTimeout: ...)`, 30
  seconds by default: when it expires, the remaining connections are
  dropped as with `force: true` and `app.close()` still completes
  normally. `closeTimeout: null` waits without a limit (an endless stream
  then keeps `close` waiting). `app.close(force: true)` drops the
  connections at once, also when a graceful close is already waiting.
- Failures that can no longer become a response (a body stream that fails
  mid-response, a broken connection) go to `IoAdapter(onError: ...)`. It is
  optional and defaults to printing to stderr. If `onError` itself throws,
  the server keeps running and that failure goes to stderr.
- There is no request body size limit: the handler reads the body as a
  stream and decides how much to accept.
