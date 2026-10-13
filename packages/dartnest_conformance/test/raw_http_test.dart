import 'dart:io';
import 'dart:typed_data';

import 'package:dartnest_conformance/dartnest_conformance.dart';
import 'package:test/test.dart';

/// Serves [answer] with a bare `dart:io` server on a loopback port.
Future<HttpServer> serve(Future<void> Function(HttpRequest) answer) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(answer);
  addTearDown(() => server.close(force: true));
  return server;
}

void main() {
  group('RawHttp', () {
    test('builds a request head with Host and Connection: close', () {
      expect(
        RawHttp.head('GET', '/a?b'),
        'GET /a?b HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n',
      );
    });

    test('reads a content-length response', () async {
      // Written by hand: dart:io frames even a short body as chunked. A
      // second pipelined response follows, so only content-length tells
      // where the first body ends.
      final server = await serve((request) async {
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.write('HTTP/1.1 200 OK\r\ncontent-length: 5\r\n\r\nhello');
        socket.write('HTTP/1.1 200 OK\r\ncontent-length: 2\r\n\r\nno');
        await socket.flush();
        socket.destroy();
      });

      final response = await RawHttp.exchange(
        server.port,
        RawHttp.head('GET', '/'),
      );

      expect(response.status, 200);
      expect(response.headers['content-length'], '5');
      expect((response.text, response.isComplete), ('hello', true));
    });

    test('de-chunks a chunked response', () async {
      final server = await serve((request) async {
        request.response
          ..write('ab')
          ..write('cd');
        await request.response.close();
      });

      final response = await RawHttp.exchange(
        server.port,
        RawHttp.head('GET', '/'),
      );

      expect(response.headers['transfer-encoding'], 'chunked');
      expect((response.text, response.isComplete), ('abcd', true));
    });

    test('marks a chunked body cut short as incomplete', () async {
      final server = await serve((request) async {
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.write('HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\n\r\n');
        socket.write('4\r\nab');
        await socket.flush();
        socket.destroy();
      });

      final response = await RawHttp.exchange(
        server.port,
        RawHttp.head('GET', '/'),
      );

      expect((response.status, response.isComplete), (200, false));
    });

    test('marks a response without a complete head as incomplete', () {
      final response = RawResponse.parse(
        Uint8List.fromList('HTTP/1.1 200'.codeUnits),
      );

      expect((response.status, response.isComplete), (0, false));
    });
  });
}
