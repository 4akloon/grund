import 'dart:convert';
import 'dart:io';

import 'package:grund/grund.dart';
import 'package:grund_io/grund_io.dart';

/// Answers `GET /ping` with text and `GET /count` with a streamed body.
final class PingController {
  /// Returns `pong`, sent as `text/plain`.
  String ping() => 'pong';

  /// Streams `1\n2\n3\n`, one chunk per line, without buffering.
  Stream<List<int>> count() =>
      Stream.fromIterable([1, 2, 3]).map((n) => utf8.encode('$n\n'));
}

/// The root module: one controller, no providers.
Module appModule() => Module(
  id: 'app',
  controllers: [
    Controller<PingController>(
      path: '/',
      create: (i) => PingController(),
      routes: [
        Route.get('/ping', (c, ctx) async => c.ping()),
        Route.get('/count', (c, ctx) async => c.count()),
      ],
    ),
  ],
);

/// Serves [appModule] on an ephemeral loopback port, calls it once over
/// HTTP and closes it; returns the response body.
///
/// A real server calls `app.listen(port: 8080)` and closes the application
/// on a signal instead.
Future<String> run() async {
  final adapter = IoAdapter();
  final app = await Application.create(appModule, adapter: adapter);
  await app.listen(port: 0, address: InternetAddress.loopbackIPv4);
  final client = HttpClient();
  try {
    final uri = Uri.http('127.0.0.1:${adapter.port}', '/count');
    final response = await (await client.getUrl(uri)).close();
    return await utf8.decodeStream(response);
  } finally {
    client.close();
    await app.close();
  }
}

/// Prints what [run] received.
Future<void> main() async => stdout.write(await run());
