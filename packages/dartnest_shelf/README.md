# dartnest_shelf

Serves a dartnest application through [shelf](https://pub.dev/packages/shelf),
or embeds it in a shelf pipeline you already have.

Let dartnest run shelf on the wire:

```dart
import 'package:dartnest/dartnest.dart';
import 'package:dartnest_shelf/dartnest_shelf.dart';

Future<void> main() async {
  // appModule: your root module, `Module appModule() => Module(...)`.
  final app = await Application.create(appModule, adapter: ShelfAdapter());
  await app.listen(port: 8080);
}
```

Or keep your own server and middleware:

```dart
import 'package:dartnest/dartnest.dart';
import 'package:dartnest_shelf/dartnest_shelf.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  // appModule: your root module, `Module appModule() => Module(...)`.
  final app = await Application.create(appModule);
  final handler = const shelf.Pipeline()
      .addMiddleware(shelf.logRequests())
      .addHandler(shelfHandler(app));
  await shelf_io.serve(handler, 'localhost', 8080);
}
```

`shelfHandler(app)`:

- Changes nothing around it. The application sees the path relative to the
  shelf `handlerPath`, so it can be mounted under a prefix.
- Does not close the application with your server; after `app.close()` the
  handler answers 503.
- Reports a failure of `app.handle` (only possible when the application's
  own error logger throws) to its optional `onError` and answers 500
  without a body. If `onError` itself throws, that failure goes to stderr.

`ShelfAdapter`:

- Adds no `x-powered-by` and no `dart:io` default headers; `shelf_io`
  itself adds a `date` header. Add security headers with middleware.
- Sends byte bodies with `content-length`, streams unbuffered, and `HEAD`
  without a body. A `transfer-encoding` header from the application is
  dropped; framing is not left to the application.
- Routes like `shelf_io`: on the URI built from `Host` and the request
  target (`IoAdapter` from `dartnest_io` routes on the target only).
  `shelf_io` itself answers 400 to invalid percent-encoding.
- `adapter.port` is the bound port (useful with `port: 0`); it throws a
  `StateError` before `listen` completes and after `close`. `listen` can be
  called once; a second call, or a call after `close`, throws a
  `StateError`.
- `app.close()` stops accepting connections, waits for the requests in
  flight (responses still being written included) and then closes the
  application, for at most `ShelfAdapter(closeTimeout: ...)`, 30 seconds by
  default; after that the remaining connections are dropped and
  `app.close()` still completes normally. `closeTimeout: null` waits
  without a limit. `app.close(force: true)` drops the connections at once,
  also when a graceful close is already waiting.
- Failures that can no longer become a response go to the optional
  `onError` of `ShelfAdapter` (default: stderr). If `onError` throws, the
  server keeps running and that failure goes to stderr.

There is no request body size limit: the handler reads the body as a
stream and decides how much to accept.
