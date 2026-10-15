import 'dart:convert';
import 'dart:io';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_shelf/grund_shelf.dart';

/// Answers `GET /ping` with text and `GET /count` with a streamed body.
final class PingApi extends HttpApi {
  /// Creates the API.
  PingApi(super.injector);

  @override
  List<Route> get routes => [
    Route.get('/ping', (_) => 'pong'),
    Route.get(
      '/count',
      // One chunk per line, sent without buffering.
      (_) => Stream.fromIterable([1, 2, 3]).map((n) => utf8.encode('$n\n')),
    ),
  ];
}

/// The root module: the HTTP server on [port], the shelf adapter and
/// [PingApi].
final class AppModule extends Module {
  /// Creates the module; port 0 picks a free port.
  const AppModule({this.port = 8080});

  /// The port the server listens on.
  final int port;

  @override
  List<Module> get imports => [
    HttpModule(
      config: HttpConfig(address: InternetAddress.loopbackIPv4, port: port),
    ),
    const ShelfAdapterModule(),
  ];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<PingApi>(PingApi.new, dependsOn: const []),
  ];
}

/// Serves [AppModule] on an ephemeral loopback port, calls it once over
/// HTTP and closes it; returns the response body.
///
/// A real server is `App(root: AppModule()).run()`: it stops on SIGINT and
/// SIGTERM.
Future<String> run() async {
  final app = App(root: const AppModule(port: 0));
  await app.start();
  final client = HttpClient();
  try {
    final port = switch (app.container.root<HttpAdapter>()) {
      ShelfAdapter(:final port) => port,
      final other => throw StateError('Unexpected adapter $other.'),
    };
    final uri = Uri.http('127.0.0.1:$port', '/count');
    final response = await (await client.getUrl(uri)).close();
    return await utf8.decodeStream(response);
  } finally {
    client.close();
    await app.close();
  }
}

/// Prints what [run] received.
Future<void> main() async => stdout.write(await run());
