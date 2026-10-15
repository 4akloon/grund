# Adapters: dart:io and shelf

`package:grund` has no server. An application answers an `HttpRequest`
with `app.handle(request)`; an adapter connects that to a real HTTP server.

```dart
final app = await Application.create(appModule, adapter: IoAdapter());
await app.listen(port: 8080);                  // address: 'localhost' by default
// ...
await app.close();                             // graceful; close(force: true) drops connections
```

| | `IoAdapter` (`grund_io`) | `ShelfAdapter` (`grund_shelf`) |
| --- | --- | --- |
| Server | `dart:io` `HttpServer` | `shelf_io` |
| HTTPS | `IoAdapter(securityContext: ...)` | through your own shelf server |
| Extra dependencies | none | `shelf` |
| Embed in an existing server | no | `shelfHandler(app)` |
| Default headers | none (`dart:io` defaults are cleared) | `date` (added by `shelf_io`) |

Both stream bodies in both directions, answer `HEAD` without a body, route
on the request target only (never on `Host` or `X-Forwarded-*`), have no
request body size limit (the handler reads the body as a stream), and
close gracefully: `app.close()` stops accepting connections and waits for
the requests in flight for up to `closeTimeout` (30 seconds by default),
then drops what is left. Failures that can no longer become a response (a
client that went away, a body stream that fails halfway) go to the
adapter's `onError`, by default stderr.

Both pass the same conformance suite on real sockets
(`packages/grund_conformance`), so an application behaves the same on
either; the example's end-to-end tests run on both.

## Choosing

- Start with `IoAdapter`: it has no dependencies and serves HTTPS itself.
- Use `ShelfAdapter` when you want shelf's ecosystem around the
  application, and `shelfHandler(app)` when the application is one part of
  a shelf server you already have:

```dart
final app = await Application.create(appModule);    // no adapter
final handler = const shelf.Pipeline()
    .addMiddleware(shelf.logRequests())
    .addHandler(shelfHandler(app));
await shelf_io.serve(handler, 'localhost', 8080);
```

Mounted under a prefix (a `shelf_router` mount, for example), the
application sees paths relative to it. Closing your server does not close
the application; call `app.close()` yourself.

## Ports and addresses

- `port: 0` asks for an ephemeral port; read it from `adapter.port` after
  `listen`. Tests use this (see `example/test/helpers/loopback_server.dart`).
- `address` is `'localhost'` by default. Inside a container, listen on
  `InternetAddress.anyIPv4` (or `'0.0.0.0'`) to be reachable from outside.
- A `listen` that fails to bind (the port is in use) throws and can be
  retried.

## Shutting down

```dart
await ProcessSignal.sigint.watch().first;
await app.close();
```

`close` is safe to call more than once. Requests that arrive while the
application closes get a 503.

## Headers you set

`HeaderMap` does not reject CR or LF in a header value. Both adapters hand
values to `dart:io`, which refuses such a value when the response is
written: the client gets no response (the connection is closed), the
`FormatException` goes to the adapter's `onError`, and no header is
injected. Never put unchecked user input into a header; see
[faq.md](faq.md#known-limitations).

## Writing an adapter

Implement `HttpAdapter` from `package:grund` (`listen` and `close`; the
class documentation states the contract) and run
`AdapterConformance.run` from `grund_conformance` against it, as
`packages/grund_io/test/io_adapter_conformance_test.dart` does.
`grund_conformance` is not published; depend on it by path or git.
