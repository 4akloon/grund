import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The server-sent events endpoint of `dev` that makes open pages reload:
/// it sends `event: reload` after every successful hot reload and once a
/// restarted application serves again.
///
/// It listens on 127.0.0.1 and an ephemeral port, outlives restarts of the
/// application and closes with `dev`. Every request gets the event stream,
/// with `access-control-allow-origin: *` (the page comes from the
/// application's origin) and a comment every [keepAlive] so that proxies
/// and browsers keep the connection open.
final class LiveReloadHub {
  LiveReloadHub._(this._server, this.url, Duration keepAlive) {
    _keepAlive = Timer.periodic(keepAlive, (_) => _send(': keep-alive\n\n'));
  }

  /// The variable that passes [url] to the application.
  static const environmentVariable = 'GRUND_LIVE_RELOAD_URL';

  /// Starts the endpoint; [keepAlive] is for tests.
  static Future<LiveReloadHub> start({
    Duration keepAlive = const Duration(seconds: 15),
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final hub = LiveReloadHub._(
      server,
      Uri.parse('http://127.0.0.1:${server.port}/'),
      keepAlive,
    );
    server.listen(hub._accept);
    return hub;
  }

  final HttpServer _server;
  final _clients = <HttpResponse>{};
  late final Timer _keepAlive; // Set in the constructor body.

  /// Where pages connect.
  final Uri url;

  /// The environment of the application process: [environmentVariable]
  /// with [url].
  Map<String, String> get environment => {environmentVariable: '$url'};

  /// Tells every connected page to reload; nothing happens without one.
  void broadcastReload() => _send('event: reload\ndata: \n\n');

  /// Ends every stream and stops listening.
  Future<void> close() async {
    _keepAlive.cancel();
    final clients = List.of(_clients);
    _clients.clear();
    // Each stream ends cleanly; a page that is gone or does not read is
    // cut off by the forced close below.
    await Future.wait([
      for (final client in clients)
        client.close().catchError(
          (Object _) {},
          test: (error) => error is IOException,
        ),
    ]).timeout(const Duration(seconds: 1), onTimeout: () => const []);
    await _server.close(force: true);
  }

  void _accept(HttpRequest request) {
    final response = request.response
      ..bufferOutput = false
      ..headers.set('content-type', 'text/event-stream')
      ..headers.set('cache-control', 'no-cache')
      ..headers.set('access-control-allow-origin', '*');
    _clients.add(response);
    response.add(utf8.encode(': connected\n\n'));
    // A page that went away ends its response with an I/O error; it is
    // simply no longer a client.
    response.done
        .catchError((Object _) {}, test: (error) => error is IOException)
        .whenComplete(() => _clients.remove(response));
  }

  void _send(String event) {
    final bytes = utf8.encode(event);
    for (final client in _clients) {
      client.add(bytes);
    }
  }
}
