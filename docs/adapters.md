# Adapters: dart:io and shelf

`grund_http` has no server of its own. `HttpModule` provides the
`HttpServer` (a `Runner` named `http`), which answers an `HttpRequest`; an
adapter module connects it to a real HTTP server by providing the
`HttpAdapter`. Import exactly one:

```dart
final class AppModule extends Module {
  const AppModule();

  @override
  List<Module> get imports => const [
    HttpModule(config: HttpConfig(port: 8080)),
    IoAdapterModule(),          // or ShelfAdapterModule()
  ];
}

Future<void> main(List<String> args) =>
    App(root: const AppModule()).run(only: Runners.fromArgs(args));
```

`App.run` starts the runners, waits for Ctrl+C or `SIGTERM` and closes. The
address and port come from `HttpConfig` (`address: 'localhost'` and `port:
8080` by default).

| | `IoAdapterModule` (`grund_io`) | `ShelfAdapterModule` (`grund_shelf`) |
| --- | --- | --- |
| Server | `dart:io` `HttpServer` | `shelf_io` |
| HTTPS | `IoAdapterModule(securityContext: ...)` | through your own shelf server |
| Extra dependencies | none | `shelf` |
| Embed in an existing server | no | `shelfHandler(app)` |
| Default headers | none (the `dart:io` defaults are cleared) | `date` (added by `shelf_io`) |

Both stream bodies in both directions, answer `HEAD` without a body, route
on the request target only (never on `Host` or `X-Forwarded-*`), and close
gracefully: `app.close()` stops accepting connections and waits for the
requests in flight for up to `closeTimeout` (30 seconds by default), then
drops what is left. Failures that can no longer become a response (a client
that went away, a body stream that fails halfway) go to the adapter's
`onError`, by default stderr. The body readers of `HttpCtx` enforce
`HttpConfig.maxBodyBytes` (1 MiB by default, 413 above it); a handler that
reads `c.request.body` as a stream decides for itself.

Both pass the same conformance suite on real sockets
(`packages/grund_conformance`), so an application behaves the same on either;
the example's end-to-end tests run on both.

## Choosing

- Start with `IoAdapterModule`: no dependencies, and it serves HTTPS itself.
- Use `ShelfAdapterModule` when you want shelf's ecosystem around the
  application, and `shelfHandler(app)` when the application is one part of a
  shelf server you already have:

```dart
final app = App(root: const AppModule());      // imports HttpModule and ShelfAdapterModule
await app.start(only: const {});               // builds the graph, opens no port
final handler = const shelf.Pipeline()
    .addMiddleware(shelf.logRequests())
    .addHandler(shelfHandler(app));
await shelf_io.serve(handler, 'localhost', 8080);
```

Mounted under a prefix (a `shelf_router` mount, for example), the
application sees paths relative to it. Closing your server does not close
the application; call `app.close()` yourself. The `HttpServer` needs the
`HttpAdapter` binding, which is why `ShelfAdapterModule` stays in the graph;
it is never started. A request after `app.close()` gets a 503.

## Ports and addresses

- `HttpConfig(port: 0)` asks for an ephemeral port; read it from the adapter
  after `app.start()`: `(app.container.root<HttpAdapter>() as IoAdapter).port`
  (`ShelfAdapter` has the same getter). Tests use this (see
  `example/test/helpers/loopback_server.dart`).
- `address` is `'localhost'` by default. Inside a container listen on
  `InternetAddress.anyIPv4` to be reachable from outside.
- A start that fails to bind (the port is in use) throws and the application
  is closed again.

To read the port from the environment, replace the `HttpConfig` binding with
an override: `App(root: ..., overrides: [Singleton<HttpConfig>((_) =>
HttpConfig(port: port), dependsOn: const [])])`.

## Shutting down

`App.run` closes the application on Ctrl+C and `SIGTERM`. In your own
entry point call `await app.close()`; it is safe to call more than once.
Requests that arrive while the server stops get a 503.

## Headers you set

`HeaderMap` does not reject CR or LF in a header value. Both adapters hand
values to `dart:io`, which refuses such a value when the response is written:
the client gets no response (the connection is closed), the `FormatException`
goes to the adapter's `onError`, and no header is injected. Never put
unchecked user input into a header; see [faq.md](faq.md#known-limitations).

## Writing an adapter

Implement `HttpAdapter` from `package:grund_http/grund_http.dart` (`listen` and
`close`; the class documentation states the contract; helpers for it are in
`package:grund_http/adapter.dart`), provide it from a
module the way `IoAdapterModule` does, and run `AdapterConformance.run` from
`grund_conformance` against it, as
`packages/grund_io/test/io_adapter_conformance_test.dart` does.
`grund_conformance` is not published; depend on it by path or git.
