import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_io/grund_io.dart';
import 'package:test/test.dart';

/// An application served by the real [IoAdapter] on an ephemeral loopback
/// port, for requests that `TestClient` and `HttpClient` would normalize.
final class RealServer {
  RealServer._(this._adapter);

  /// Starts [modules] with the HTTP server on port 0; closed after the test.
  static Future<RealServer> start(List<Module> modules) async {
    final app = App(root: _Root(modules));
    await app.start();
    addTearDown(app.close);
    return RealServer._(app.container.root<HttpAdapter>() as IoAdapter);
  }

  final IoAdapter _adapter;

  /// Sends `GET [target]` exactly as written (no normalization) and returns
  /// the status line, and the body as text.
  Future<({int status, String body})> get(String target) async {
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      _adapter.port,
    );
    final received = BytesBuilder(copy: false);
    try {
      socket.add(
        latin1.encode(
          'GET $target HTTP/1.1\r\nHost: 127.0.0.1\r\n'
          'Connection: close\r\n\r\n',
        ),
      );
      await socket.flush();
      await socket
          .listen(received.add, cancelOnError: true)
          .asFuture<void>()
          .timeout(const Duration(seconds: 10));
    } finally {
      socket.destroy();
    }
    final text = latin1.decode(received.takeBytes());
    final status = int.parse(text.split(' ')[1]);
    return (status: status, body: text.substring(text.indexOf('\r\n\r\n')));
  }
}

final class _Root extends Module {
  _Root(this._modules);

  final List<Module> _modules;

  @override
  List<Module> get imports => [
    const HttpModule(config: HttpConfig(address: '127.0.0.1', port: 0)),
    const IoAdapterModule(),
    ..._modules,
  ];
}
