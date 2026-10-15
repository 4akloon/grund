import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

/// A loopback server that behaves like a hung VM service: it accepts
/// connections and never answers; closed when the test ends.
final class HungVmService {
  HungVmService._(this._server, this.isWebSocket);

  /// Starts the server; with [webSocket] it completes the WebSocket
  /// handshake (the connection opens, the requests hang), otherwise it
  /// does not answer the handshake at all.
  static Future<HungVmService> start({required bool webSocket}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final service = HungVmService._(server, webSocket);
    addTearDown(service._close);
    service._serve();
    return service;
  }

  final HttpServer _server;

  /// Whether the handshake is completed.
  final bool isWebSocket;
  final _sockets = <WebSocket>[];

  /// The banner-style URI of the service, ending with `/`.
  Uri get uri => Uri.parse('http://127.0.0.1:${_server.port}/token=/');

  void _serve() {
    _server.listen((request) async {
      if (!isWebSocket) return;
      _sockets.add(await WebSocketTransformer.upgrade(request));
    });
  }

  Future<void> _close() async {
    for (final socket in _sockets) {
      unawaited(socket.close().timeout(Duration.zero, onTimeout: () {}));
    }
    await _server.close(force: true);
  }
}

/// A loopback port nobody listens on.
Future<int> deadPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}
